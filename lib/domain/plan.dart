import '../core/dates.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Plan anual: importe previsto por categoría y mes frente a lo real.
//
// Es la hoja del Excel de presupuesto: filas = categorías agrupadas en
// ingresos, necesarios variables, necesarios fijos, prescindibles y ahorro;
// columnas = meses con "presupuestado" y "real".
//
// Todo el cálculo vive aquí, sin base de datos, para poder probarlo.
// ---------------------------------------------------------------------------

/// Lo que el plan necesita saber de una categoría.
class PlanCategory {
  const PlanCategory({
    required this.id,
    required this.kind,
    required this.name,
    required this.emoji,
    required this.color,
    this.parentId,
    this.group,
    this.isSavings = false,
    this.sortOrder = 0,
    this.isArchived = false,
    this.expectedDay,
  });

  final String id;
  final CategoryKind kind;
  final String name;
  final String emoji;
  final int color;
  final String? parentId;
  final BudgetGroup? group;
  final bool isSavings;
  final int sortOrder;
  final bool isArchived;

  /// Día del mes (1-31) en que suele cargarse o cobrarse (null = sin día fijo).
  final int? expectedDay;

  bool get isIncome => kind == CategoryKind.income;
}

/// Importe confirmado de una categoría en un día.
class RealAmount {
  const RealAmount({required this.categoryId, required this.dayKey, required this.cents, required this.type});
  final String categoryId;
  final String dayKey;
  final int cents;
  final TxType type;
}

/// Importe previsto de una categoría en un mes (1-12).
class PlannedAmount {
  const PlannedAmount({required this.categoryId, required this.month, required this.cents});
  final String categoryId;
  final int month;
  final int cents;
}

/// Bloques del plan, en el orden del Excel (el ocio va tras los prescindibles).
enum PlanSectionKind {
  income,
  variable,
  fixed,
  discretionary,
  leisure,
  savings,
  unclassified;

  String get label => switch (this) {
        PlanSectionKind.income => 'Ingresos',
        PlanSectionKind.variable => BudgetGroup.variable.pluralLabel,
        PlanSectionKind.fixed => BudgetGroup.fixed.pluralLabel,
        PlanSectionKind.discretionary => BudgetGroup.discretionary.pluralLabel,
        PlanSectionKind.leisure => BudgetGroup.leisure.pluralLabel,
        PlanSectionKind.savings => BudgetGroup.savings.pluralLabel,
        PlanSectionKind.unclassified => 'Sin clasificar',
      };

  String get emoji => switch (this) {
        PlanSectionKind.income => '💶',
        PlanSectionKind.variable => BudgetGroup.variable.emoji,
        PlanSectionKind.fixed => BudgetGroup.fixed.emoji,
        PlanSectionKind.discretionary => BudgetGroup.discretionary.emoji,
        PlanSectionKind.leisure => BudgetGroup.leisure.emoji,
        PlanSectionKind.savings => BudgetGroup.savings.emoji,
        PlanSectionKind.unclassified => '❔',
      };

  bool get isIncome => this == PlanSectionKind.income;

  /// Bloque de la regla 50/30/20 (null para ingresos y sin clasificar).
  RuleBucket? get bucket => switch (this) {
        PlanSectionKind.variable || PlanSectionKind.fixed => RuleBucket.needs,
        PlanSectionKind.discretionary || PlanSectionKind.leisure => RuleBucket.wants,
        PlanSectionKind.savings => RuleBucket.savings,
        _ => null,
      };

  static PlanSectionKind ofGroup(BudgetGroup? g) => switch (g) {
        BudgetGroup.fixed => PlanSectionKind.fixed,
        BudgetGroup.variable => PlanSectionKind.variable,
        BudgetGroup.discretionary => PlanSectionKind.discretionary,
        BudgetGroup.leisure => PlanSectionKind.leisure,
        BudgetGroup.savings => PlanSectionKind.savings,
        null => PlanSectionKind.unclassified,
      };
}

/// Una fila del plan: una categoría con su previsto y su real.
class PlanLine {
  const PlanLine({
    required this.category,
    required this.parent,
    required this.section,
    required this.plannedCents,
    required this.realCents,
  });

  final PlanCategory category;
  final PlanCategory? parent;
  final PlanSectionKind section;
  final int plannedCents;
  final int realCents;

  bool get isIncome => section.isIncome;

  /// Gasto: lo que queda (negativo si te has pasado).
  /// Ingreso: lo que falta por cobrar (negativo si has cobrado de más).
  int get differenceCents => plannedCents - realCents;

  /// Real / previsto (null si no había nada previsto).
  double? get ratio => plannedCents == 0 ? null : realCents / plannedCents;

  /// Gasto por encima de lo previsto.
  bool get isOver => !isIncome && realCents > plannedCents;

  /// Gasto que no estaba en el plan.
  bool get isUnplanned => plannedCents == 0 && realCents > 0;

  /// Cuenta como movimiento de ahorro (para el ahorro real).
  bool get isSavings => category.isSavings;
}

/// Un bloque (ingresos, fijos...) con sus filas.
class PlanSection {
  const PlanSection({required this.kind, required this.lines});
  final PlanSectionKind kind;
  final List<PlanLine> lines;

  int get plannedCents => lines.fold(0, (s, l) => s + l.plannedCents);
  int get realCents => lines.fold(0, (s, l) => s + l.realCents);
}

/// Totales de un mes o de un año del plan.
class PlanTotals {
  PlanTotals(List<PlanSection> sections) {
    for (final s in sections) {
      _planned[s.kind] = s.plannedCents;
      _real[s.kind] = s.realCents;
      for (final l in s.lines) {
        if (!l.isSavings) continue;
        if (l.isIncome) {
          savingsInPlanned += l.plannedCents;
          savingsInReal += l.realCents;
        } else {
          savingsOutPlanned += l.plannedCents;
          savingsOutReal += l.realCents;
        }
      }
    }
  }

  final _planned = <PlanSectionKind, int>{};
  final _real = <PlanSectionKind, int>{};

  /// Gastos que son ahorro o patrimonio (pensiones, hipoteca...).
  int savingsOutPlanned = 0;
  int savingsOutReal = 0;

  /// Ingresos que salen de los propios ahorros (no son ingresos reales).
  int savingsInPlanned = 0;
  int savingsInReal = 0;

  int sectionCents(PlanSectionKind k, {required bool real}) => (real ? _real : _planned)[k] ?? 0;

  int incomeCents({required bool real}) => sectionCents(PlanSectionKind.income, real: real);

  int expenseCents({required bool real}) => PlanSectionKind.values
      .where((k) => !k.isIncome)
      .fold(0, (s, k) => s + sectionCents(k, real: real));

  /// Ingresos − gastos ("saldo del mes" del Excel).
  int balanceCents({required bool real}) => incomeCents(real: real) - expenseCents(real: real);

  /// Ingresos sin contar el dinero que sale de tus ahorros.
  int ownIncomeCents({required bool real}) => incomeCents(real: real) - (real ? savingsInReal : savingsInPlanned);

  /// Ahorro real: lo que te sobra más lo que has destinado a ahorro o
  /// patrimonio, menos lo que has sacado de tus ahorros.
  int realSavingsCents({required bool real}) =>
      balanceCents(real: real) + (real ? savingsOutReal - savingsInReal : savingsOutPlanned - savingsInPlanned);

  /// Gasto de un bloque de la regla 50/30/20.
  int bucketCents(RuleBucket b, {required bool real}) => PlanSectionKind.values
      .where((k) => k.bucket == b)
      .fold(0, (s, k) => s + sectionCents(k, real: real));

  /// Porcentaje de los ingresos propios (null sin ingresos).
  double? shareOfIncome(int cents, {required bool real}) {
    final base = ownIncomeCents(real: real);
    return base <= 0 ? null : cents / base * 100;
  }
}

/// El plan de un mes contable.
class PlanMonth {
  PlanMonth({required this.month, required this.sections}) : totals = PlanTotals(sections);
  final DateTime month;
  final List<PlanSection> sections;
  final PlanTotals totals;

  bool get isEmpty => sections.every((s) => s.lines.isEmpty);

  /// Fila de una categoría (null si no tiene previsto ni movimientos).
  PlanLine? lineOf(String categoryId) {
    for (final s in sections) {
      for (final l in s.lines) {
        if (l.category.id == categoryId) return l;
      }
    }
    return null;
  }
}

/// El plan de un año contable: doce meses y el acumulado.
class PlanYear {
  PlanYear({required this.year, required this.months, required this.annual}) : totals = PlanTotals(annual);
  final int year;
  final List<PlanMonth> months;

  /// Filas con los importes sumados de todo el año.
  final List<PlanSection> annual;
  final PlanTotals totals;

  PlanMonth monthAt(int month) => months[month - 1];

  bool get hasPlan => annual.any((s) => s.plannedCents > 0);
}

/// Construye el plan de [year] a partir de las categorías, lo previsto y los
/// movimientos reales (por día). Los días se asignan a su mes contable.
PlanYear buildPlanYear({
  required int year,
  required MonthCycle cycle,
  required Map<String, PlanCategory> categories,
  required List<PlannedAmount> planned,
  required List<RealAmount> real,
}) {
  final plannedByMonth = List.generate(12, (_) => <String, int>{});
  for (final p in planned) {
    if (p.month < 1 || p.month > 12 || p.cents <= 0) continue;
    final m = plannedByMonth[p.month - 1];
    m[p.categoryId] = (m[p.categoryId] ?? 0) + p.cents;
  }

  final realByMonth = List.generate(12, (_) => <String, int>{});
  final types = <String, TxType>{};
  for (final r in real) {
    final month = cycle.monthOf(Dates.parseKey(r.dayKey));
    if (month.year != year) continue;
    final m = realByMonth[month.month - 1];
    m[r.categoryId] = (m[r.categoryId] ?? 0) + r.cents;
    types[r.categoryId] = r.type;
  }

  Map<String, int> sum(List<Map<String, int>> maps) {
    final out = <String, int>{};
    for (final m in maps) {
      m.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  return PlanYear(
    year: year,
    months: [
      for (var i = 0; i < 12; i++)
        PlanMonth(
          month: DateTime(year, i + 1, 1),
          sections: buildPlanSections(categories, plannedByMonth[i], realByMonth[i], types),
        ),
    ],
    annual: buildPlanSections(categories, sum(plannedByMonth), sum(realByMonth), types),
  );
}

/// Agrupa en bloques lo previsto y lo real de un periodo.
///
/// Si una categoría no tiene previsto pero su grupo padre sí (p. ej. un gasto
/// en "Agua" con el previsto puesto en su grupo "Vivienda"), lo real se suma a
/// la fila del padre. Lo gastado sin previsto aparece igualmente, con
/// previsto 0, para que nada quede fuera de los totales.
List<PlanSection> buildPlanSections(
  Map<String, PlanCategory> categories,
  Map<String, int> planned,
  Map<String, int> real, [
  Map<String, TxType> types = const {},
]) {
  final plannedOf = <String, int>{};
  final realOf = <String, int>{};

  planned.forEach((id, cents) {
    if (cents > 0 && categories.containsKey(id)) plannedOf[id] = (plannedOf[id] ?? 0) + cents;
  });
  real.forEach((id, cents) {
    if (cents == 0) return;
    var target = id;
    final parentId = categories[id]?.parentId;
    if (!plannedOf.containsKey(id) && parentId != null && plannedOf.containsKey(parentId)) target = parentId;
    realOf[target] = (realOf[target] ?? 0) + cents;
  });

  PlanCategory categoryOf(String id) =>
      categories[id] ??
      PlanCategory(
        id: id,
        kind: types[id] == TxType.income ? CategoryKind.income : CategoryKind.expense,
        name: 'Categoría eliminada',
        emoji: '🗑️',
        color: 0xFF868E96,
        sortOrder: 1 << 30,
      );

  final bySection = <PlanSectionKind, List<PlanLine>>{};
  for (final id in {...plannedOf.keys, ...realOf.keys}) {
    final c = categoryOf(id);
    final parent = c.parentId == null ? null : categories[c.parentId];
    final section = c.isIncome ? PlanSectionKind.income : PlanSectionKind.ofGroup(c.group ?? parent?.group);
    bySection.putIfAbsent(section, () => []).add(PlanLine(
          category: c,
          parent: parent,
          section: section,
          plannedCents: plannedOf[id] ?? 0,
          realCents: realOf[id] ?? 0,
        ));
  }

  // Mismo orden que la pantalla de categorías: cada grupo (p. ej.
  // "Vivienda") con sus subcategorías juntas.
  int compare(PlanLine a, PlanLine b) {
    final byGroup = (a.parent ?? a.category).sortOrder.compareTo((b.parent ?? b.category).sortOrder);
    if (byGroup != 0) return byGroup;
    // Dentro del mismo grupo, el propio grupo primero y luego sus hijas.
    final aIsChild = a.parent != null ? 1 : 0;
    final bIsChild = b.parent != null ? 1 : 0;
    if (aIsChild != bIsChild) return aIsChild - bIsChild;
    final byOrder = a.category.sortOrder.compareTo(b.category.sortOrder);
    return byOrder != 0 ? byOrder : a.category.name.compareTo(b.category.name);
  }

  return [
    for (final kind in PlanSectionKind.values)
      if (bySection[kind] != null) PlanSection(kind: kind, lines: bySection[kind]!..sort(compare)),
  ];
}
