import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/models.dart';
import '../database.dart';

/// Categorías de gasto, ingreso y producto.
class CategoryRepository {
  CategoryRepository(this.db);
  final AppDatabase db;

  /// Todas las categorías (no borradas) de un tipo, en el orden del usuario.
  Stream<List<CategoryRow>> watchAll({CategoryKind? kind, bool includeArchived = true}) {
    final q = db.select(db.categories)..where((c) => c.deletedAt.isNull());
    if (kind != null) q.where((c) => c.kind.equalsValue(kind));
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    q.orderBy([
      (c) => OrderingTerm(expression: c.sortOrder),
      (c) => OrderingTerm(expression: c.name),
    ]);
    return q.watch();
  }

  /// Categorías que se pueden elegir al registrar: no archivadas, que no sean
  /// grupos y ordenadas por uso (las más usadas primero).
  Stream<List<CategoryRow>> watchSelectable(CategoryKind kind) {
    return db
        .customSelect(
          'SELECT c.*, '
          '(SELECT COUNT(*) FROM transactions t WHERE t.category_id = c.id AND t.deleted_at IS NULL) AS uses '
          'FROM categories c '
          'WHERE c.kind = ? AND c.deleted_at IS NULL AND c.is_archived = 0 '
          'AND NOT EXISTS (SELECT 1 FROM categories ch WHERE ch.parent_id = c.id AND ch.deleted_at IS NULL) '
          'ORDER BY uses DESC, c.sort_order, c.name',
          variables: [Variable.withString(kind.name)],
          readsFrom: {db.categories, db.transactions},
        )
        .watch()
        .map((rows) => rows.map((r) => db.categories.map(r.data)).toList());
  }

  Future<CategoryRow?> getById(String id) =>
      (db.select(db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<String> create({
    required CategoryKind kind,
    required String name,
    required String emoji,
    required int color,
    String? parentId,
    BudgetGroup? group,
    bool isSavings = false,
    int? expectedDay,
  }) async {
    final now = Dates.nowIso();
    final id = newId();
    final order = await db
        .customSelect(
          'SELECT COALESCE(MAX(sort_order), 0) AS m FROM categories WHERE kind = ?',
          variables: [Variable.withString(kind.name)],
        )
        .getSingle();
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          kind: kind,
          name: name.trim(),
          emoji: emoji,
          color: color,
          parentId: Value(parentId),
          sortOrder: Value(order.read<int>('m') + 1),
          budgetGroup: Value(group),
          isSavings: Value(isSavings),
          expectedDay: Value(expectedDay),
        ));
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required String emoji,
    required int color,
    String? parentId,
    BudgetGroup? group,
    bool isSavings = false,
    int? expectedDay,
  }) {
    return (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
      name: Value(name.trim()),
      emoji: Value(emoji),
      color: Value(color),
      parentId: Value(parentId),
      budgetGroup: Value(group),
      isSavings: Value(isSavings),
      expectedDay: Value(expectedDay),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  /// Día del mes en que suele cargarse o cobrarse (null = sin día fijo).
  Future<void> setExpectedDay(String id, int? day) {
    return (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
      expectedDay: Value(day),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> setArchived(String id, bool archived) {
    return (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
      isArchived: Value(archived),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  /// Mueve una categoría de sitio en el plan: a otro bloque de gastos o de
  /// ingreso a gasto (o al revés).
  ///
  /// Si cambia de tipo, todo va con ella para que las cuentas cuadren: sus
  /// subcategorías, y sus movimientos y recurrentes pasan de ingreso a gasto
  /// (o al revés). Deja el grupo en el que estaba (era del otro tipo) y, si
  /// pasa a ser ingreso, sus presupuestos de gasto se borran.
  Future<void> move(String id, {required CategoryKind kind, BudgetGroup? group}) {
    assert(kind != CategoryKind.product);
    return db.transaction(() async {
      final c = await getById(id);
      if (c == null) return;
      final now = Dates.nowIso();
      final newGroup = kind == CategoryKind.income ? null : group;
      if (c.kind == kind) {
        await (db.update(db.categories)..where((x) => x.id.equals(id))).write(CategoriesCompanion(
          budgetGroup: Value(newGroup),
          isSavings: newGroup == BudgetGroup.savings ? const Value(true) : const Value.absent(),
          updatedAt: Value(now),
        ));
        return;
      }

      final children = await (db.select(db.categories)
            ..where((x) => x.parentId.equals(id) & x.deletedAt.isNull()))
          .get();
      final ids = [id, ...children.map((ch) => ch.id)];
      await (db.update(db.categories)..where((x) => x.id.equals(id))).write(CategoriesCompanion(
        kind: Value(kind),
        budgetGroup: Value(newGroup),
        parentId: const Value(null),
        // "Cuenta como ahorro" (gasto) y "Sale de tus ahorros" (ingreso) no son lo mismo.
        isSavings: Value(newGroup == BudgetGroup.savings),
        updatedAt: Value(now),
      ));
      if (children.isNotEmpty) {
        // Las subcategorías siguen en el grupo y toman su bloque.
        await (db.update(db.categories)..where((x) => x.parentId.equals(id))).write(CategoriesCompanion(
          kind: Value(kind),
          budgetGroup: const Value(null),
          isSavings: const Value(false),
          updatedAt: Value(now),
        ));
      }

      final type = kind == CategoryKind.income ? TxType.income : TxType.expense;
      await (db.update(db.transactions)..where((t) => t.categoryId.isIn(ids)))
          .write(TransactionsCompanion(type: Value(type), updatedAt: Value(now)));
      await (db.update(db.recurringRules)..where((r) => r.categoryId.isIn(ids)))
          .write(RecurringRulesCompanion(type: Value(type), updatedAt: Value(now)));
      if (kind == CategoryKind.income) {
        await (db.update(db.budgets)..where((b) => b.categoryId.isIn(ids) & b.deletedAt.isNull()))
            .write(BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      }
    });
  }

  /// Movimientos (no borrados) que usan la categoría y sus subcategorías.
  Future<int> countTransactionsWithChildren(String id) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL AND (category_id = ? '
      'OR category_id IN (SELECT id FROM categories WHERE parent_id = ? AND deleted_at IS NULL))',
      variables: [Variable.withString(id), Variable.withString(id)],
    ).getSingle();
    return row.read<int>('n');
  }

  /// Movimientos (no borrados) que usan la categoría.
  Future<int> countTransactions(String id) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM transactions WHERE category_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(id)],
    ).getSingle();
    return row.read<int>('n');
  }

  /// Elimina la categoría (borrado lógico). Si se indica [reassignTo], sus
  /// movimientos y reglas recurrentes pasan a esa otra categoría.
  Future<void> delete(String id, {String? reassignTo}) {
    return db.transaction(() async {
      final now = Dates.nowIso();
      if (reassignTo != null) {
        await (db.update(db.transactions)..where((t) => t.categoryId.equals(id)))
            .write(TransactionsCompanion(categoryId: Value(reassignTo), updatedAt: Value(now)));
        await (db.update(db.recurringRules)..where((r) => r.categoryId.equals(id)))
            .write(RecurringRulesCompanion(categoryId: Value(reassignTo), updatedAt: Value(now)));
      }
      // Sus presupuestos y su plan dejan de tener sentido.
      await (db.update(db.budgets)..where((b) => b.categoryId.equals(id)))
          .write(BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (db.update(db.planEntries)..where((e) => e.categoryId.equals(id) & e.deletedAt.isNull()))
          .write(PlanEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      // Productos de la compra quedan sin categoría.
      await (db.update(db.shoppingItems)..where((i) => i.categoryId.equals(id)))
          .write(ShoppingItemsCompanion(categoryId: const Value(null), updatedAt: Value(now)));
      // Las subcategorías dejan de estar agrupadas.
      await (db.update(db.categories)..where((c) => c.parentId.equals(id)))
          .write(CategoriesCompanion(parentId: const Value(null), updatedAt: Value(now)));
      await (db.update(db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    });
  }

  /// Guarda el nuevo orden tras arrastrar en la lista.
  Future<void> reorder(List<String> orderedIds) {
    final now = Dates.nowIso();
    return db.batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          db.categories,
          CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(now)),
          where: (c) => c.id.equals(orderedIds[i]),
        );
      }
    });
  }
}

/// Métodos de pago (efectivo, tarjeta, Bizum...).
class PaymentMethodRepository {
  PaymentMethodRepository(this.db);
  final AppDatabase db;

  Stream<List<PaymentMethodRow>> watchAll({bool includeArchived = true}) {
    final q = db.select(db.paymentMethods)..where((m) => m.deletedAt.isNull());
    if (!includeArchived) q.where((m) => m.isArchived.equals(false));
    q.orderBy([(m) => OrderingTerm(expression: m.sortOrder), (m) => OrderingTerm(expression: m.name)]);
    return q.watch();
  }

  Future<String> create({required String name, required String emoji}) async {
    final now = Dates.nowIso();
    final id = newId();
    final order = await db.customSelect('SELECT COALESCE(MAX(sort_order), 0) AS m FROM payment_methods').getSingle();
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          name: name.trim(),
          emoji: emoji,
          sortOrder: Value(order.read<int>('m') + 1),
        ));
    return id;
  }

  Future<void> update(String id, {required String name, required String emoji}) {
    return (db.update(db.paymentMethods)..where((m) => m.id.equals(id))).write(PaymentMethodsCompanion(
      name: Value(name.trim()),
      emoji: Value(emoji),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> setArchived(String id, bool archived) {
    return (db.update(db.paymentMethods)..where((m) => m.id.equals(id))).write(PaymentMethodsCompanion(
      isArchived: Value(archived),
      updatedAt: Value(Dates.nowIso()),
    ));
  }
}
