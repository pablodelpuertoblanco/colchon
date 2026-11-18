import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/models.dart';
import '../database.dart';

/// SELECT base para obtener movimientos con su categoría y método de pago.
const txSelectSql = '''
SELECT t.id, t.type, t.amount_cents, t.description, t.category_id, t.payment_method_id,
       t.occurred_on, t.time_of_day, t.notes, t.status, t.recurring_rule_id,
       c.name AS category_name, c.emoji AS category_emoji, c.color AS category_color,
       pm.name AS payment_method_name
FROM transactions t
JOIN categories c ON c.id = t.category_id
LEFT JOIN payment_methods pm ON pm.id = t.payment_method_id
''';

TxView txViewFromRow(QueryRow r) => TxView(
      id: r.read<String>('id'),
      type: TxType.values.byName(r.read<String>('type')),
      amountCents: r.read<int>('amount_cents'),
      description: r.read<String>('description'),
      categoryId: r.read<String>('category_id'),
      categoryName: r.read<String>('category_name'),
      categoryEmoji: r.read<String>('category_emoji'),
      categoryColor: r.read<int>('category_color'),
      paymentMethodId: r.readNullable<String>('payment_method_id'),
      paymentMethodName: r.readNullable<String>('payment_method_name'),
      date: Dates.parseKey(r.read<String>('occurred_on')),
      time: r.readNullable<String>('time_of_day'),
      notes: r.readNullable<String>('notes'),
      status: TxStatus.values.byName(r.read<String>('status')),
      recurringRuleId: r.readNullable<String>('recurring_rule_id'),
    );

String? _nullIfBlank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

String _searchTextFor(TxDraft d) => normalizeForSearch('${d.description} ${d.notes ?? ''}');

/// Companion listo para insertar un movimiento nuevo (también lo usan las
/// reglas recurrentes y la lista de la compra dentro de sus transacciones).
TransactionsCompanion newTransactionCompanion(
  TxDraft d, {
  String? recurringRuleId,
  String? occurrenceDate,
}) {
  final now = Dates.nowIso();
  return TransactionsCompanion.insert(
    id: newId(),
    createdAt: now,
    updatedAt: now,
    type: d.type,
    amountCents: d.amountCents,
    description: Value(d.description.trim()),
    searchText: Value(_searchTextFor(d)),
    categoryId: d.categoryId,
    paymentMethodId: Value(d.paymentMethodId),
    occurredOn: Dates.key(d.date),
    timeOfDay: Value(d.time),
    notes: Value(_nullIfBlank(d.notes)),
    status: Value(d.status),
    recurringRuleId: Value(recurringRuleId),
    occurrenceDate: Value(occurrenceDate),
  );
}

/// Gastos e ingresos: altas, ediciones, búsquedas y totales.
class TransactionRepository {
  TransactionRepository(this.db);
  final AppDatabase db;

  Set<ResultSetImplementation<dynamic, dynamic>> get _reads => {db.transactions, db.categories, db.paymentMethods};

  // ------------------------------------------------------------------ altas

  Future<String> create(TxDraft d, {String? recurringRuleId, String? occurrenceDate}) async {
    final companion = newTransactionCompanion(d, recurringRuleId: recurringRuleId, occurrenceDate: occurrenceDate);
    await db.into(db.transactions).insert(companion);
    return companion.id.value;
  }

  Future<void> update(String id, TxDraft d) {
    return (db.update(db.transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(
      type: Value(d.type),
      amountCents: Value(d.amountCents),
      description: Value(d.description.trim()),
      searchText: Value(_searchTextFor(d)),
      categoryId: Value(d.categoryId),
      paymentMethodId: Value(d.paymentMethodId),
      occurredOn: Value(Dates.key(d.date)),
      timeOfDay: Value(d.time),
      notes: Value(_nullIfBlank(d.notes)),
      status: Value(d.status),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  /// Vincula un movimiento ya creado con una regla recurrente (cuando se
  /// marca "Repetir" al crearlo), para que la regla no lo duplique.
  Future<void> linkToRule(String id, String ruleId, DateTime occurrence) {
    return (db.update(db.transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(
      recurringRuleId: Value(ruleId),
      occurrenceDate: Value(Dates.key(occurrence)),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  /// Borrado lógico (permite deshacer y, en el futuro, sincronizar el borrado).
  Future<void> softDelete(String id) {
    final now = Dates.nowIso();
    return (db.update(db.transactions)..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> restore(String id) {
    return (db.update(db.transactions)..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(deletedAt: const Value(null), updatedAt: Value(Dates.nowIso())));
  }

  // -------------------------------------------------------------- consultas

  Stream<List<TxView>> watchFiltered(TxFilter f) {
    final where = <String>['t.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];

    final q = normalizeForSearch(f.query);
    if (q.isNotEmpty) {
      where.add('(t.search_text LIKE ? OR lower(c.name) LIKE ?)');
      vars.add(Variable.withString('%$q%'));
      vars.add(Variable.withString('%$q%'));
    }
    if (f.type != null) {
      where.add('t.type = ?');
      vars.add(Variable.withString(f.type!.name));
    }
    if (f.categoryIds.isNotEmpty) {
      final marks = List.filled(f.categoryIds.length, '?').join(', ');
      // Incluye las subcategorías si se filtra por un grupo.
      where.add('(t.category_id IN ($marks) OR c.parent_id IN ($marks))');
      vars.addAll(f.categoryIds.map(Variable.withString));
      vars.addAll(f.categoryIds.map(Variable.withString));
    }
    if (f.from != null) {
      where.add('t.occurred_on >= ?');
      vars.add(Variable.withString(Dates.key(f.from!)));
    }
    if (f.to != null) {
      where.add('t.occurred_on <= ?');
      vars.add(Variable.withString(Dates.key(f.to!)));
    }
    if (f.paymentMethodId != null) {
      where.add('t.payment_method_id = ?');
      vars.add(Variable.withString(f.paymentMethodId!));
    }
    final order = switch (f.sort) {
      TxSort.dateDesc => 't.occurred_on DESC, t.time_of_day DESC, t.created_at DESC',
      TxSort.dateAsc => 't.occurred_on ASC, t.time_of_day ASC, t.created_at ASC',
      TxSort.amountDesc => 't.amount_cents DESC, t.occurred_on DESC',
      TxSort.amountAsc => 't.amount_cents ASC, t.occurred_on DESC',
    };
    vars.add(Variable.withInt(f.limit));

    return db
        .customSelect(
          '$txSelectSql WHERE ${where.join(' AND ')} ORDER BY $order LIMIT ?',
          variables: vars,
          readsFrom: _reads,
        )
        .watch()
        .map((rows) => rows.map(txViewFromRow).toList());
  }

  Stream<List<TxView>> watchRecent(int limit) {
    return db
        .customSelect(
          '$txSelectSql WHERE t.deleted_at IS NULL '
          'ORDER BY t.occurred_on DESC, t.time_of_day DESC, t.created_at DESC LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: _reads,
        )
        .watch()
        .map((rows) => rows.map(txViewFromRow).toList());
  }

  Stream<List<TxView>> watchDay(String dayKey) {
    return db
        .customSelect(
          '$txSelectSql WHERE t.deleted_at IS NULL AND t.occurred_on = ? '
          'ORDER BY t.time_of_day DESC, t.created_at DESC',
          variables: [Variable.withString(dayKey)],
          readsFrom: _reads,
        )
        .watch()
        .map((rows) => rows.map(txViewFromRow).toList());
  }

  Stream<List<TxView>> watchPending() {
    return db
        .customSelect(
          "$txSelectSql WHERE t.deleted_at IS NULL AND t.status = 'pending' ORDER BY t.occurred_on ASC",
          readsFrom: _reads,
        )
        .watch()
        .map((rows) => rows.map(txViewFromRow).toList());
  }

  Stream<TxView?> watchById(String id) {
    return db
        .customSelect('$txSelectSql WHERE t.id = ? AND t.deleted_at IS NULL',
            variables: [Variable.withString(id)], readsFrom: _reads)
        .watchSingleOrNull()
        .map((r) => r == null ? null : txViewFromRow(r));
  }

  /// Totales confirmados entre dos días (claves "AAAA-MM-DD", inclusivas).
  Stream<Totals> watchTotals(String from, String to) {
    return db
        .customSelect(
          "SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END), 0) AS income, "
          "COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END), 0) AS expense "
          "FROM transactions WHERE deleted_at IS NULL AND status = 'confirmed' AND occurred_on BETWEEN ? AND ?",
          variables: [Variable.withString(from), Variable.withString(to)],
          readsFrom: {db.transactions},
        )
        .watchSingle()
        .map((r) => Totals(incomeCents: r.read<int>('income'), expenseCents: r.read<int>('expense')));
  }

  /// Día del primer movimiento confirmado (null si no hay ninguno). Sirve
  /// para no contar en las medias los meses anteriores a usar la app.
  Stream<String?> watchFirstDay() {
    return db
        .customSelect(
          "SELECT MIN(occurred_on) AS first FROM transactions WHERE deleted_at IS NULL AND status = 'confirmed'",
          readsFrom: {db.transactions},
        )
        .watchSingle()
        .map((r) => r.readNullable<String>('first'));
  }

  /// Ingresos menos gastos confirmados desde un día (para el dinero disponible).
  Stream<int> watchNetSince(String fromKey) {
    return db
        .customSelect(
          "SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount_cents ELSE -amount_cents END), 0) AS net "
          "FROM transactions WHERE deleted_at IS NULL AND status = 'confirmed' AND occurred_on >= ?",
          variables: [Variable.withString(fromKey)],
          readsFrom: {db.transactions},
        )
        .watchSingle()
        .map((r) => r.read<int>('net'));
  }

  /// Totales por día. Si se indica [categoryId], solo esa categoría (y sus
  /// subcategorías si es un grupo).
  Stream<Map<String, DayTotal>> watchDailyTotals(String from, String to, {String? categoryId}) {
    final vars = <Variable<Object>>[Variable.withString(from), Variable.withString(to)];
    var extra = '';
    if (categoryId != null) {
      extra = ' AND category_id IN (SELECT id FROM categories WHERE id = ? OR parent_id = ?)';
      vars.add(Variable.withString(categoryId));
      vars.add(Variable.withString(categoryId));
    }
    return db
        .customSelect(
          "SELECT occurred_on AS day, "
          "SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END) AS income, "
          "SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END) AS expense "
          "FROM transactions WHERE deleted_at IS NULL AND status = 'confirmed' "
          "AND occurred_on BETWEEN ? AND ?$extra GROUP BY occurred_on",
          variables: vars,
          readsFrom: {db.transactions, db.categories},
        )
        .watch()
        .map((rows) => {
              for (final r in rows)
                r.read<String>('day'): DayTotal(
                  dayKey: r.read<String>('day'),
                  incomeCents: r.read<int>('income'),
                  expenseCents: r.read<int>('expense'),
                ),
            });
  }

  /// Total por categoría en un periodo. Con [grouped], las subcategorías se
  /// suman en su grupo (Luz + Agua + Gas = Facturas).
  Stream<List<CategoryTotal>> watchCategoryTotals(String from, String to, TxType type, {bool grouped = false}) {
    final groupKey = grouped ? 'COALESCE(c.parent_id, c.id)' : 'c.id';
    return db
        .customSelect(
          'SELECT g.id AS id, g.name AS name, g.emoji AS emoji, g.color AS color, '
          'SUM(t.amount_cents) AS total, COUNT(*) AS n '
          'FROM transactions t JOIN categories c ON c.id = t.category_id '
          'JOIN categories g ON g.id = $groupKey '
          "WHERE t.deleted_at IS NULL AND t.status = 'confirmed' AND t.type = ? "
          'AND t.occurred_on BETWEEN ? AND ? '
          'GROUP BY g.id ORDER BY total DESC',
          variables: [Variable.withString(type.name), Variable.withString(from), Variable.withString(to)],
          readsFrom: {db.transactions, db.categories},
        )
        .watch()
        .map((rows) => rows
            .map((r) => CategoryTotal(
                  categoryId: r.read<String>('id'),
                  name: r.read<String>('name'),
                  emoji: r.read<String>('emoji'),
                  color: r.read<int>('color'),
                  totalCents: r.read<int>('total'),
                  count: r.read<int>('n'),
                ))
            .toList());
  }

  // ------------------------------------------------------------ sugerencias

  /// Descripciones usadas antes que empiezan por [prefix].
  Future<List<String>> suggestDescriptions(String prefix, TxType type) async {
    final q = normalizeForSearch(prefix);
    if (q.isEmpty) return const [];
    final rows = await db.customSelect(
      "SELECT description, COUNT(*) AS n FROM transactions "
      "WHERE deleted_at IS NULL AND type = ? AND description <> '' AND search_text LIKE ? "
      'GROUP BY lower(description) ORDER BY n DESC LIMIT 5',
      variables: [Variable.withString(type.name), Variable.withString('$q%')],
    ).get();
    return rows.map((r) => r.read<String>('description')).toList();
  }

  /// Categoría más usada con esa misma descripción ("Mercadona" -> Supermercado).
  Future<String?> suggestCategory(String description, TxType type) async {
    if (description.trim().isEmpty) return null;
    final row = await db.customSelect(
      'SELECT t.category_id AS id, COUNT(*) AS n FROM transactions t '
      'JOIN categories c ON c.id = t.category_id '
      'WHERE t.deleted_at IS NULL AND c.deleted_at IS NULL AND c.is_archived = 0 '
      'AND t.type = ? AND lower(t.description) = lower(?) '
      'GROUP BY t.category_id ORDER BY n DESC LIMIT 1',
      variables: [Variable.withString(type.name), Variable.withString(description.trim())],
    ).getSingleOrNull();
    return row?.read<String>('id');
  }

  /// Último método de pago usado para ese tipo de movimiento.
  Future<String?> lastPaymentMethod(TxType type) async {
    final row = await db.customSelect(
      'SELECT payment_method_id AS id FROM transactions '
      'WHERE deleted_at IS NULL AND payment_method_id IS NOT NULL AND type = ? '
      'ORDER BY created_at DESC LIMIT 1',
      variables: [Variable.withString(type.name)],
    ).getSingleOrNull();
    return row?.read<String>('id');
  }

  /// Lista de la compra que generó este gasto, si la hay: (id, nombre).
  Future<(String, String)?> shoppingListFor(String transactionId) async {
    final row = await db.customSelect(
      'SELECT id, name FROM shopping_lists WHERE transaction_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(transactionId)],
    ).getSingleOrNull();
    return row == null ? null : (row.read<String>('id'), row.read<String>('name'));
  }
}
