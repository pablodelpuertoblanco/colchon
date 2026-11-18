import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/budget_math.dart';
import '../../domain/models.dart';
import '../database.dart';

/// Presupuesto con lo gastado en su periodo actual.
class BudgetView {
  const BudgetView({
    required this.budget,
    required this.spentCents,
    required this.progress,
    this.categoryName,
    this.categoryEmoji,
    this.categoryColor,
  });
  final BudgetRow budget;
  final int spentCents;
  final BudgetProgress progress;
  final String? categoryName;
  final String? categoryEmoji;
  final int? categoryColor;

  String get title => categoryName ?? 'Todos los gastos';
  String get emoji => categoryEmoji ?? '💶';
}

/// Aviso a mostrar justo después de guardar un gasto.
class BudgetAlert {
  const BudgetAlert({required this.title, required this.state, required this.view});
  final String title;
  final BudgetState state;
  final BudgetView view;

  String get message => state == BudgetState.exceeded
      ? 'Has superado el presupuesto de $title'
      : 'Has llegado al ${view.budget.alertPct} % del presupuesto de $title';
}

/// Límites de gasto semanales, mensuales o anuales.
class BudgetRepository {
  BudgetRepository(this.db);
  final AppDatabase db;

  // Lo gastado se calcula en SQL para el periodo de cada presupuesto.
  // ?1-?2 semana, ?3-?4 mes, ?5-?6 año. Un presupuesto de un grupo suma
  // también sus subcategorías; uno global (sin categoría) suma todo.
  static const _sql = '''
SELECT b.*, c.name AS category_name, c.emoji AS category_emoji, c.color AS category_color,
  (SELECT COALESCE(SUM(t.amount_cents), 0) FROM transactions t
    WHERE t.deleted_at IS NULL AND t.status = 'confirmed' AND t.type = 'expense'
      AND (b.category_id IS NULL OR t.category_id = b.category_id
           OR t.category_id IN (SELECT ch.id FROM categories ch WHERE ch.parent_id = b.category_id))
      AND t.occurred_on BETWEEN
        (CASE b.period WHEN 'week' THEN ?1 WHEN 'month' THEN ?3 ELSE ?5 END)
        AND (CASE b.period WHEN 'week' THEN ?2 WHEN 'month' THEN ?4 ELSE ?6 END)
  ) AS spent
FROM budgets b LEFT JOIN categories c ON c.id = b.category_id
WHERE b.deleted_at IS NULL
ORDER BY b.category_id IS NOT NULL, c.sort_order
''';

  Selectable<BudgetView> _query(DateTime day, MonthCycle cycle) {
    final vars = <Variable<Object>>[];
    for (final p in BudgetPeriod.values) {
      final (s, e) = p.rangeFor(day, cycle);
      vars.add(Variable.withString(Dates.key(s)));
      vars.add(Variable.withString(Dates.key(e)));
    }
    final today = Dates.today();
    return db
        .customSelect(_sql, variables: vars, readsFrom: {db.budgets, db.transactions, db.categories})
        .map((row) {
      final budget = db.budgets.map(row.data);
      final spent = row.read<int>('spent');
      final (_, end) = budget.period.rangeFor(day, cycle);
      return BudgetView(
        budget: budget,
        spentCents: spent,
        progress: BudgetProgress(
          limitCents: budget.amountCents,
          spentCents: spent,
          alertPct: budget.alertPct,
          periodEnd: end,
          today: today,
        ),
        categoryName: row.readNullable<String>('category_name'),
        categoryEmoji: row.readNullable<String>('category_emoji'),
        categoryColor: row.readNullable<int>('category_color'),
      );
    });
  }

  /// Presupuestos con lo gastado en su periodo actual. Los mensuales y
  /// anuales siguen el mes contable [cycle].
  Stream<List<BudgetView>> watchAll(MonthCycle cycle) => _query(Dates.today(), cycle).watch();

  Future<String> create({String? categoryId, required BudgetPeriod period, required int amountCents, int alertPct = 80}) async {
    final now = Dates.nowIso();
    final id = newId();
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          categoryId: Value(categoryId),
          period: period,
          amountCents: amountCents,
          alertPct: Value(alertPct),
        ));
    return id;
  }

  Future<void> update(String id, {String? categoryId, required BudgetPeriod period, required int amountCents, required int alertPct}) {
    return (db.update(db.budgets)..where((b) => b.id.equals(id))).write(BudgetsCompanion(
      categoryId: Value(categoryId),
      period: Value(period),
      amountCents: Value(amountCents),
      alertPct: Value(alertPct),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> softDelete(String id) {
    final now = Dates.nowIso();
    return (db.update(db.budgets)..where((b) => b.id.equals(id)))
        .write(BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  /// Avisos que provoca un gasto recién creado de [amountCents] en
  /// [categoryId] con fecha [date]. Solo avisa de periodos en curso.
  Future<List<BudgetAlert>> alertsAfterExpense({
    required String categoryId,
    required DateTime date,
    required int amountCents,
    MonthCycle cycle = MonthCycle.calendar,
  }) async {
    final category = await (db.select(db.categories)..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    final parentId = category?.parentId;
    final today = Dates.today();
    final views = await _query(today, cycle).get();
    final alerts = <BudgetAlert>[];
    for (final v in views) {
      final b = v.budget;
      final applies = b.categoryId == null || b.categoryId == categoryId || (parentId != null && b.categoryId == parentId);
      if (!applies) continue;
      final (start, end) = b.period.rangeFor(today, cycle);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final crossed = BudgetProgress.crossedBy(
        limitCents: b.amountCents,
        alertPct: b.alertPct,
        spentAfterCents: v.spentCents,
        amountCents: amountCents,
      );
      if (crossed != null) alerts.add(BudgetAlert(title: v.title, state: crossed, view: v));
    }
    return alerts;
  }
}
