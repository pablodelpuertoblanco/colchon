import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/forecast.dart';
import '../../domain/models.dart';
import '../../domain/recurrence.dart';
import '../database.dart';
import 'transaction_repository.dart';

/// Regla recurrente con los datos de su categoría y su próxima fecha.
class RuleView {
  const RuleView({
    required this.rule,
    required this.categoryName,
    required this.categoryEmoji,
    required this.categoryColor,
    required this.nextDate,
  });
  final RecurringRuleRow rule;
  final String categoryName;
  final String categoryEmoji;
  final int categoryColor;
  final DateTime? nextDate;

  String get title => rule.description.trim().isEmpty ? categoryName : rule.description;
}

/// Datos del formulario de una regla recurrente.
class RuleDraft {
  const RuleDraft({
    required this.type,
    required this.amountCents,
    required this.description,
    required this.categoryId,
    required this.frequency,
    required this.everyN,
    required this.startDate,
    required this.mode,
    this.paymentMethodId,
    this.endDate,
    this.notes,
  });
  final TxType type;
  final int amountCents;
  final String description;
  final String categoryId;
  final String? paymentMethodId;
  final Frequency frequency;
  final int everyN;
  final DateTime startDate;
  final DateTime? endDate;
  final RecurringMode mode;
  final String? notes;
}

/// Gastos e ingresos que se repiten y el motor que los genera.
class RecurringRepository {
  RecurringRepository(this.db);
  final AppDatabase db;

  DateTime? _nextOf(RecurringRuleRow r, DateTime today) {
    if (!r.isActive) return null;
    return Recurrence.nextFrom(
      start: Dates.parseKey(r.startDate),
      frequency: r.frequency,
      everyN: r.everyN,
      from: today,
      end: r.endDate == null ? null : Dates.parseKey(r.endDate!),
    );
  }

  Stream<List<RuleView>> watchAll() {
    return db
        .customSelect(
          'SELECT r.*, c.name AS category_name, c.emoji AS category_emoji, c.color AS category_color '
          'FROM recurring_rules r JOIN categories c ON c.id = r.category_id '
          'WHERE r.deleted_at IS NULL ORDER BY r.is_active DESC, r.description',
          readsFrom: {db.recurringRules, db.categories},
        )
        .watch()
        .map((rows) {
      final today = Dates.today();
      return rows.map((row) {
        final rule = db.recurringRules.map(row.data);
        return RuleView(
          rule: rule,
          categoryName: row.read<String>('category_name'),
          categoryEmoji: row.read<String>('category_emoji'),
          categoryColor: row.read<int>('category_color'),
          nextDate: _nextOf(rule, today),
        );
      }).toList();
    });
  }

  Future<RecurringRuleRow?> getById(String id) =>
      (db.select(db.recurringRules)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<String> create(RuleDraft d) async {
    final now = Dates.nowIso();
    final id = newId();
    await db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          type: d.type,
          amountCents: d.amountCents,
          description: d.description.trim(),
          categoryId: d.categoryId,
          paymentMethodId: Value(d.paymentMethodId),
          frequency: d.frequency,
          everyN: Value(d.everyN),
          startDate: Dates.key(d.startDate),
          endDate: Value(d.endDate == null ? null : Dates.key(d.endDate!)),
          mode: d.mode,
          notes: Value(d.notes),
        ));
    return id;
  }

  /// Los cambios solo afectan a las ocurrencias futuras: las ya generadas
  /// son movimientos normales del historial.
  Future<void> update(String id, RuleDraft d) {
    return (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(RecurringRulesCompanion(
      type: Value(d.type),
      amountCents: Value(d.amountCents),
      description: Value(d.description.trim()),
      categoryId: Value(d.categoryId),
      paymentMethodId: Value(d.paymentMethodId),
      frequency: Value(d.frequency),
      everyN: Value(d.everyN),
      startDate: Value(Dates.key(d.startDate)),
      endDate: Value(d.endDate == null ? null : Dates.key(d.endDate!)),
      mode: Value(d.mode),
      notes: Value(d.notes),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> setActive(String id, bool active) {
    return (db.update(db.recurringRules)..where((r) => r.id.equals(id)))
        .write(RecurringRulesCompanion(isActive: Value(active), updatedAt: Value(Dates.nowIso())));
  }

  Future<void> softDelete(String id) {
    final now = Dates.nowIso();
    return (db.update(db.recurringRules)..where((r) => r.id.equals(id)))
        .write(RecurringRulesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  /// Crea los movimientos pendientes de todas las reglas activas hasta hoy.
  ///
  /// Es idempotente: se puede llamar cada vez que se abre la app. El índice
  /// único (regla, fecha) + INSERT OR IGNORE impide duplicados, y como los
  /// borrados son lógicos, un movimiento recurrente borrado no "resucita".
  Future<int> generateDue({DateTime? today}) async {
    final t = Dates.dateOnly(today ?? DateTime.now());
    final rules = await (db.select(db.recurringRules)
          ..where((r) => r.deletedAt.isNull() & r.isActive.equals(true)))
        .get();
    var created = 0;
    for (final rule in rules) {
      final lastRow = await db.customSelect(
        'SELECT MAX(occurrence_date) AS last FROM transactions WHERE recurring_rule_id = ?',
        variables: [Variable.withString(rule.id)],
      ).getSingle();
      final last = lastRow.readNullable<String>('last');
      final start = Dates.parseKey(rule.startDate);
      var from = start;
      if (last != null) {
        final afterLast = Dates.addDays(Dates.parseKey(last), 1);
        if (afterLast.isAfter(from)) from = afterLast;
      }
      final dates = Recurrence.between(
        start: start,
        frequency: rule.frequency,
        everyN: rule.everyN,
        from: from,
        to: t,
        end: rule.endDate == null ? null : Dates.parseKey(rule.endDate!),
      );
      if (dates.isEmpty) continue;

      await db.transaction(() async {
        for (final d in dates) {
          final draft = TxDraft(
            type: rule.type,
            amountCents: rule.amountCents,
            categoryId: rule.categoryId,
            date: d,
            description: rule.description,
            paymentMethodId: rule.paymentMethodId,
            notes: rule.notes,
            status: rule.mode == RecurringMode.auto ? TxStatus.confirmed : TxStatus.pending,
          );
          await db.into(db.transactions).insert(
                newTransactionCompanion(draft, recurringRuleId: rule.id, occurrenceDate: Dates.key(d)),
                mode: InsertMode.insertOrIgnore,
              );
          created++;
        }
      });
    }
    return created;
  }

  /// Reglas activas con la fecha de su última ocurrencia generada, para la
  /// previsión de saldo. Se actualiza al generar o borrar movimientos.
  Stream<List<ForecastRule>> watchForecastRules() {
    return db
        .customSelect(
          'SELECT r.*, c.name AS category_name, c.emoji AS category_emoji, '
          '(SELECT MAX(t.occurrence_date) FROM transactions t WHERE t.recurring_rule_id = r.id) AS last_occurrence '
          'FROM recurring_rules r JOIN categories c ON c.id = r.category_id '
          'WHERE r.deleted_at IS NULL AND r.is_active = 1',
          readsFrom: {db.recurringRules, db.categories, db.transactions},
        )
        .watch()
        .map((rows) => rows.map((row) {
              final r = db.recurringRules.map(row.data);
              final last = row.readNullable<String>('last_occurrence');
              return ForecastRule(
                id: r.id,
                type: r.type,
                amountCents: r.amountCents,
                categoryId: r.categoryId,
                label: r.description.trim().isEmpty ? row.read<String>('category_name') : r.description,
                emoji: row.read<String>('category_emoji'),
                start: Dates.parseKey(r.startDate),
                frequency: r.frequency,
                everyN: r.everyN,
                end: r.endDate == null ? null : Dates.parseKey(r.endDate!),
                lastGenerated: last == null ? null : Dates.parseKey(last),
              );
            }).toList());
  }

  /// Cargos de los próximos [days] días (a partir de mañana).
  Stream<List<UpcomingCharge>> watchUpcoming(int days) {
    return watchAll().map((views) {
      final today = Dates.today();
      final from = Dates.addDays(today, 1);
      final to = Dates.addDays(today, days);
      final result = <UpcomingCharge>[];
      for (final v in views) {
        final r = v.rule;
        if (!r.isActive) continue;
        final dates = Recurrence.between(
          start: Dates.parseKey(r.startDate),
          frequency: r.frequency,
          everyN: r.everyN,
          from: from,
          to: to,
          end: r.endDate == null ? null : Dates.parseKey(r.endDate!),
        );
        for (final d in dates) {
          result.add(UpcomingCharge(
            ruleId: r.id,
            date: d,
            type: r.type,
            amountCents: r.amountCents,
            description: v.title,
            emoji: v.categoryEmoji,
            mode: r.mode,
          ));
        }
      }
      result.sort((a, b) => a.date.compareTo(b.date));
      return result;
    });
  }
}
