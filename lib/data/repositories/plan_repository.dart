import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../database.dart';

/// Importes previstos del plan anual (categoría × mes contable).
class PlanRepository {
  PlanRepository(this.db);
  final AppDatabase db;

  /// Lo previsto en el año [year].
  Stream<List<PlannedAmount>> watchYear(int year) {
    final q = db.select(db.planEntries)..where((e) => e.year.equals(year) & e.deletedAt.isNull());
    return q.watch().map((rows) => [
          for (final r in rows) PlannedAmount(categoryId: r.categoryId, month: r.month, cents: r.amountCents),
        ]);
  }

  /// Importes confirmados por categoría y día entre [from] y [to] (claves de día).
  Stream<List<RealAmount>> watchRealByDay(String from, String to) {
    return db
        .customSelect(
          'SELECT category_id, occurred_on, type, SUM(amount_cents) AS total FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'confirmed' AND occurred_on BETWEEN ? AND ? "
          'GROUP BY category_id, occurred_on, type',
          variables: [Variable.withString(from), Variable.withString(to)],
          readsFrom: {db.transactions},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                RealAmount(
                  categoryId: r.read<String>('category_id'),
                  dayKey: r.read<String>('occurred_on'),
                  cents: r.read<int>('total'),
                  type: TxType.values.byName(r.read<String>('type')),
                ),
            ]);
  }

  /// Fija lo previsto de [categoryId] en los [months] de [year]. Con 0 se
  /// quita la partida de esos meses.
  Future<void> setAmount(String categoryId, int year, Iterable<int> months, int cents) {
    return db.transaction(() async {
      for (final m in months) {
        await writeEntry(categoryId, year, m, cents);
      }
    });
  }

  /// Fija lo previsto de varios meses de golpe ({mes: céntimos}).
  Future<void> setMonths(String categoryId, int year, Map<int, int> centsByMonth) {
    return db.transaction(() async {
      for (final e in centsByMonth.entries) {
        await writeEntry(categoryId, year, e.key, e.value);
      }
    });
  }

  /// Escribe una partida. Llamar siempre dentro de una transacción
  /// (`db.transaction`), como hacen [setAmount] y la importación.
  Future<void> writeEntry(String categoryId, int year, int month, int cents) async {
    final now = Dates.nowIso();
    final existing = await (db.select(db.planEntries)
          ..where((e) =>
              e.categoryId.equals(categoryId) & e.year.equals(year) & e.month.equals(month) & e.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) {
      if (existing.amountCents == cents) return;
      await (db.update(db.planEntries)..where((e) => e.id.equals(existing.id))).write(cents == 0
          ? PlanEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now))
          : PlanEntriesCompanion(amountCents: Value(cents), updatedAt: Value(now)));
    } else if (cents > 0) {
      await db.into(db.planEntries).insert(PlanEntriesCompanion.insert(
            id: newId(),
            createdAt: now,
            updatedAt: now,
            categoryId: categoryId,
            year: year,
            month: month,
            amountCents: cents,
          ));
    }
  }

  /// Quita la categoría del plan de [year].
  Future<void> removeFromYear(String categoryId, int year) {
    final now = Dates.nowIso();
    return (db.update(db.planEntries)
          ..where((e) => e.categoryId.equals(categoryId) & e.year.equals(year) & e.deletedAt.isNull()))
        .write(PlanEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  /// ¿Hay algo previsto en [year]?
  Future<bool> hasYear(int year) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM plan_entries WHERE year = ? AND deleted_at IS NULL',
      variables: [Variable.withInt(year)],
    ).getSingle();
    return row.read<int>('n') > 0;
  }

  /// Copia el plan de [from] a [to]. Si [replace], borra antes lo que hubiera
  /// en [to]; si no, solo rellena los huecos. Devuelve las partidas copiadas.
  Future<int> copyYear(int from, int to, {bool replace = false}) {
    return db.transaction(() async {
      final now = Dates.nowIso();
      if (replace) {
        await (db.update(db.planEntries)..where((e) => e.year.equals(to) & e.deletedAt.isNull()))
            .write(PlanEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      }
      final source = await (db.select(db.planEntries)..where((e) => e.year.equals(from) & e.deletedAt.isNull())).get();
      final existing = await (db.select(db.planEntries)..where((e) => e.year.equals(to) & e.deletedAt.isNull())).get();
      final taken = {for (final e in existing) '${e.categoryId}|${e.month}'};
      var copied = 0;
      for (final e in source) {
        if (taken.contains('${e.categoryId}|${e.month}')) continue;
        await db.into(db.planEntries).insert(PlanEntriesCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              categoryId: e.categoryId,
              year: to,
              month: e.month,
              amountCents: e.amountCents,
            ));
        copied++;
      }
      return copied;
    });
  }
}

/// Convierte las categorías de la base de datos al modelo del plan.
Map<String, PlanCategory> planCategoriesOf(Map<String, CategoryRow> rows) => {
      for (final c in rows.values)
        c.id: PlanCategory(
          id: c.id,
          kind: c.kind,
          name: c.name,
          emoji: c.emoji,
          color: c.color,
          parentId: c.parentId,
          group: c.budgetGroup,
          isSavings: c.isSavings,
          sortOrder: c.sortOrder,
          isArchived: c.isArchived,
          expectedDay: c.expectedDay,
        ),
    };
