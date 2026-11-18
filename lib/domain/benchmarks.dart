import '../core/dates.dart';
import '../core/text.dart';
import 'models.dart';
import 'plan.dart';

// ---------------------------------------------------------------------------
// Salud financiera: reglas orientativas por concepto ("vivienda, como mucho
// el 35 % de los ingresos") comparadas con el gasto real, fondo de
// emergencia y medias por categoría.
//
// Son referencias orientativas, no asesoramiento financiero. Todo el cálculo
// vive aquí, sin base de datos, para poder probarlo.
// ---------------------------------------------------------------------------

/// Qué mide una regla.
enum BenchmarkMetric {
  /// Gasto de las categorías elegidas (y sus subcategorías).
  categories,

  /// Ahorro real: saldo + gastos que son ahorro − ingresos que salen de tus
  /// ahorros (como en el plan).
  savings;

  String get label => this == BenchmarkMetric.categories ? 'Gasto en categorías' : 'Ahorro real';
}

/// Estado de una regla frente a sus límites.
enum BenchmarkStatus {
  inside,
  near,
  outside;

  String get label => switch (this) {
        BenchmarkStatus.inside => 'Dentro',
        BenchmarkStatus.near => 'Cerca del límite',
        BenchmarkStatus.outside => 'Fuera',
      };
}

/// Margen relativo para "cerca": a menos del 10 % del límite (con un máximo
/// del 35 %, a partir del 31,5 %; con un mínimo del 20 %, por debajo del 22 %).
const nearMargin = 0.10;

/// Estado de un porcentaje frente a un mínimo y un máximo (null = sin límite).
BenchmarkStatus? statusOf(double? pct, {int? minPct, int? maxPct}) {
  if (pct == null || (minPct == null && maxPct == null)) return null;
  if ((maxPct != null && pct > maxPct) || (minPct != null && pct < minPct)) return BenchmarkStatus.outside;
  if ((maxPct != null && pct > maxPct * (1 - nearMargin)) || (minPct != null && pct < minPct * (1 + nearMargin))) {
    return BenchmarkStatus.near;
  }
  return BenchmarkStatus.inside;
}

/// Una regla orientativa.
class Benchmark {
  const Benchmark({
    required this.id,
    required this.name,
    required this.emoji,
    this.metric = BenchmarkMetric.categories,
    this.minPct,
    this.maxPct,
    this.categoryIds = const {},
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String emoji;
  final BenchmarkMetric metric;
  final int? minPct;
  final int? maxPct;
  final Set<String> categoryIds;
  final int sortOrder;

  /// "máx. 35 %", "mín. 20 %" o "entre 10 y 20 %".
  String get limitLabel {
    if (minPct != null && maxPct != null) return 'entre $minPct y $maxPct %';
    if (maxPct != null) return 'máx. $maxPct %';
    if (minPct != null) return 'mín. $minPct %';
    return 'sin límite';
  }
}

/// Lo que pasó en un mes contable, ya agregado.
class MonthFigures {
  MonthFigures({required this.month});
  final DateTime month;

  int incomeCents = 0;
  int expenseCents = 0;

  /// Ingresos que salen de tus ahorros y gastos que son ahorro.
  int savingsInCents = 0;
  int savingsOutCents = 0;

  /// Gasto en necesarios (fijos y variables), para el fondo de emergencia.
  int needsCents = 0;

  /// Importe por categoría (gasto o ingreso, según la categoría).
  final Map<String, int> byCategory = {};

  /// Ingresos sin contar lo que sale de tus ahorros.
  int get ownIncomeCents => incomeCents - savingsInCents;

  /// Ahorro real (igual que en el plan).
  int get realSavingsCents => incomeCents - expenseCents + savingsOutCents - savingsInCents;

  bool get hasData => incomeCents != 0 || expenseCents != 0;

  /// Suma de las categorías [ids] y de sus subcategorías.
  int centsOf(Set<String> ids, Map<String, PlanCategory> categories) {
    var total = 0;
    byCategory.forEach((id, cents) {
      final parent = categories[id]?.parentId;
      if (ids.contains(id) || (parent != null && ids.contains(parent))) total += cents;
    });
    return total;
  }
}

/// Agrega los importes reales por mes contable. Devuelve un elemento por cada
/// mes de [months], en el mismo orden.
List<MonthFigures> monthFigures({
  required List<DateTime> months,
  required MonthCycle cycle,
  required Map<String, PlanCategory> categories,
  required List<RealAmount> real,
}) {
  final byMonth = {for (final m in months) m: MonthFigures(month: m)};
  for (final r in real) {
    final f = byMonth[cycle.monthOf(Dates.parseKey(r.dayKey))];
    if (f == null) continue;
    final c = categories[r.categoryId];
    final parent = c?.parentId == null ? null : categories[c!.parentId];
    final isSavings = c?.isSavings ?? false;
    f.byCategory[r.categoryId] = (f.byCategory[r.categoryId] ?? 0) + r.cents;
    if (r.type == TxType.income) {
      f.incomeCents += r.cents;
      if (isSavings) f.savingsInCents += r.cents;
    } else {
      f.expenseCents += r.cents;
      if (isSavings) f.savingsOutCents += r.cents;
      if ((c?.group ?? parent?.group)?.bucket == RuleBucket.needs) f.needsCents += r.cents;
    }
  }
  return [for (final m in months) byMonth[m]!];
}

/// Meses contables completos anteriores a [current] (el más reciente
/// primero), sin pasar de [count] ni de antes del primer mes con datos.
List<DateTime> previousMonths(DateTime current, int count, {DateTime? firstDataMonth}) => [
      for (var i = 1; i <= count; i++)
        if (firstDataMonth == null || !Dates.shiftMonth(current, -i).isBefore(firstDataMonth)) Dates.shiftMonth(current, -i),
    ];

/// Resultado de una regla: el mes y la media de los últimos meses.
class BenchmarkResult {
  const BenchmarkResult({
    required this.benchmark,
    required this.monthCents,
    required this.monthPct,
    required this.averageCents,
    required this.averagePct,
    required this.averageMonths,
  });

  final Benchmark benchmark;

  /// Importe y porcentaje de los ingresos propios del mes (null sin ingresos).
  final int monthCents;
  final double? monthPct;

  /// Media mensual de los meses anteriores y porcentaje sobre sus ingresos.
  final int? averageCents;
  final double? averagePct;

  /// Cuántos meses entran en la media (hasta 12).
  final int averageMonths;

  BenchmarkStatus? get monthStatus => statusOf(monthPct, minPct: benchmark.minPct, maxPct: benchmark.maxPct);
  BenchmarkStatus? get averageStatus => statusOf(averagePct, minPct: benchmark.minPct, maxPct: benchmark.maxPct);

  /// El estado que se muestra: el del mes si ya hay ingresos; si no, el de
  /// la media (a principio de mes aún no se ha cobrado).
  BenchmarkStatus? get status => monthStatus ?? averageStatus;

  /// Porcentaje con el que se calcula [status].
  double? get statusPct => monthPct ?? averagePct;
}

int _valueOf(Benchmark b, MonthFigures f, Map<String, PlanCategory> categories) =>
    b.metric == BenchmarkMetric.savings ? f.realSavingsCents : f.centsOf(b.categoryIds, categories);

/// Evalúa [b] en el mes [current] y en la media de [previous]. La media es
/// el total de esos meses entre sus ingresos (no la media de porcentajes),
/// para que un mes con pocos ingresos no pese igual que uno normal.
BenchmarkResult evaluateBenchmark(
  Benchmark b, {
  required MonthFigures current,
  required List<MonthFigures> previous,
  required Map<String, PlanCategory> categories,
}) {
  double? pct(int cents, int income) => income <= 0 ? null : cents / income * 100;
  final monthCents = _valueOf(b, current, categories);
  final withData = previous.where((f) => f.hasData).toList();
  final totalCents = withData.fold(0, (s, f) => s + _valueOf(b, f, categories));
  final totalIncome = withData.fold(0, (s, f) => s + f.ownIncomeCents);
  return BenchmarkResult(
    benchmark: b,
    monthCents: monthCents,
    monthPct: pct(monthCents, current.ownIncomeCents),
    averageCents: withData.isEmpty ? null : totalCents ~/ withData.length,
    averagePct: pct(totalCents, totalIncome),
    averageMonths: withData.length,
  );
}

/// Fondo de emergencia: cuántos meses de gastos necesarios cubre el dinero
/// disponible. Objetivo orientativo: de 3 a 6 meses.
class EmergencyFund {
  const EmergencyFund({required this.availableCents, required this.monthlyNeedsCents, required this.monthsUsed});

  static const minMonths = 3;
  static const maxMonths = 6;

  final int availableCents;

  /// Gasto medio mensual en necesarios (null sin meses con datos).
  final int? monthlyNeedsCents;
  final int monthsUsed;

  double? get months =>
      monthlyNeedsCents == null || monthlyNeedsCents! <= 0 ? null : availableCents / monthlyNeedsCents!;

  BenchmarkStatus? get status => statusOf(months, minPct: minMonths);

  /// Más de 6 meses: bien cubierto; podría convenir invertir parte.
  bool get aboveTarget => (months ?? 0) > maxMonths;
}

EmergencyFund emergencyFund({required int availableCents, required List<MonthFigures> previous}) {
  final withData = previous.where((f) => f.hasData).toList();
  final needs = withData.fold(0, (s, f) => s + f.needsCents);
  return EmergencyFund(
    availableCents: availableCents,
    monthlyNeedsCents: withData.isEmpty ? null : needs ~/ withData.length,
    monthsUsed: withData.length,
  );
}

/// Todas las reglas evaluadas y el fondo de emergencia.
class FinancialHealth {
  const FinancialHealth({required this.month, required this.results, this.fund});
  final DateTime month;
  final List<BenchmarkResult> results;

  /// Null si no hay saldo inicial (no se conoce el dinero disponible).
  final EmergencyFund? fund;

  /// Reglas incumplidas (para el aviso del inicio).
  List<BenchmarkResult> get outside => [for (final r in results) if (r.status == BenchmarkStatus.outside) r];

  bool get fundOutside => fund?.status == BenchmarkStatus.outside;
}

/// Evalúa todas las reglas en [current] frente a los meses [previous].
FinancialHealth buildFinancialHealth({
  required List<Benchmark> benchmarks,
  required MonthFigures current,
  required List<MonthFigures> previous,
  required Map<String, PlanCategory> categories,
  int? availableCents,
}) =>
    FinancialHealth(
      month: current.month,
      results: [
        for (final b in benchmarks) evaluateBenchmark(b, current: current, previous: previous, categories: categories),
      ],
      fund: availableCents == null ? null : emergencyFund(availableCents: availableCents, previous: previous),
    );

/// Media mensual de una categoría en los últimos 3, 6 y 12 meses.
class CategoryAverages {
  const CategoryAverages({required this.currentCents, required this.averages});
  final int currentCents;

  /// {3: media, 6: media, 12: media}; null si no hay meses con datos.
  final Map<int, int?> averages;

  /// Diferencia del mes actual con la media de [months] meses, en %.
  double? changeVs(int months) {
    final avg = averages[months];
    if (avg == null || avg == 0) return null;
    return (currentCents - avg) / avg * 100;
  }
}

/// [previous]: meses anteriores, el más reciente primero (ya recortados al
/// primer mes con datos de la app, para no dividir entre meses sin usarla).
CategoryAverages categoryAverages(
  String categoryId, {
  required MonthFigures current,
  required List<MonthFigures> previous,
  required Map<String, PlanCategory> categories,
}) {
  final ids = {categoryId};
  int? avg(int n) {
    // Los meses sin ningún movimiento (no se usó la app) no cuentan.
    final months = previous.take(n).where((f) => f.hasData).toList();
    if (months.isEmpty) return null;
    return months.fold(0, (s, f) => s + f.centsOf(ids, categories)) ~/ months.length;
  }

  return CategoryAverages(
    currentCents: current.centsOf(ids, categories),
    averages: {3: avg(3), 6: avg(6), 12: avg(12)},
  );
}

// ---------------------------------------------------------------------------
// Reglas iniciales (orientativas; el usuario las revisa y confirma).
// ---------------------------------------------------------------------------

/// Una regla por crear.
class BenchmarkSpec {
  const BenchmarkSpec({
    required this.key,
    required this.name,
    required this.emoji,
    this.metric = BenchmarkMetric.categories,
    this.minPct,
    this.maxPct,
    this.categoryIds = const {},
  });
  final String key;
  final String name;
  final String emoji;
  final BenchmarkMetric metric;
  final int? minPct;
  final int? maxPct;
  final Set<String> categoryIds;
}

/// ¿Contiene el nombre alguna de las [words] como palabra (o frase) completa,
/// en singular o plural? "gas" encaja con "Gas casa" pero no con "Gasolina".
bool _hasAny(String name, List<String> words) {
  final padded = ' ${normalizeForSearch(name).replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  return words.any((w) => padded.contains(' $w ') || padded.contains(' ${w}s ') || padded.contains(' ${w}es '));
}

/// Reglas iniciales con las categorías de gasto que encajan por id o por
/// nombre. Las amortizaciones anticipadas no cuentan: son ahorro voluntario.
List<BenchmarkSpec> defaultBenchmarks(Iterable<PlanCategory> categories) {
  final expenses = categories.where((c) => c.kind == CategoryKind.expense && !c.isArchived).toList();
  Set<String> pick({Set<String> ids = const {}, List<String> words = const [], bool Function(PlanCategory c)? also}) => {
        for (final c in expenses)
          if (!normalizeForSearch(c.name).contains('amortiz') &&
              (ids.contains(c.id) || _hasAny(c.name, words) || (also?.call(c) ?? false)))
            c.id,
      };
  BudgetGroup? groupOf(PlanCategory c) =>
      c.group ?? (c.parentId == null ? null : categories.where((p) => p.id == c.parentId).firstOrNull?.group);

  return [
    BenchmarkSpec(
      key: 'housing',
      name: 'Vivienda',
      emoji: '🏠',
      maxPct: 35,
      categoryIds: pick(
        ids: {'exp-vivienda', 'exp-luz', 'exp-agua', 'exp-gas'},
        words: ['hipoteca', 'alquiler', 'electricidad', 'luz', 'agua', 'gas', 'gasoil', 'comunidad', 'ibi',
            'seguro hogar', 'seguro de hogar', 'basura'],
      ),
    ),
    BenchmarkSpec(
      key: 'food',
      name: 'Alimentación',
      emoji: '🛒',
      maxPct: 15,
      categoryIds: pick(ids: {'exp-supermercado'}, words: ['supermercado', 'alimentacion']),
    ),
    BenchmarkSpec(
      key: 'transport',
      name: 'Transporte',
      emoji: '🚗',
      maxPct: 15,
      categoryIds: pick(ids: {'exp-transporte'}, words: ['transporte', 'gasolina', 'taxi', 'parking', 'coche']),
    ),
    BenchmarkSpec(
      key: 'wants',
      name: 'Ocio y prescindibles',
      emoji: '🎈',
      maxPct: 30,
      categoryIds: pick(also: (c) => groupOf(c)?.bucket == RuleBucket.wants),
    ),
    BenchmarkSpec(
      key: 'debt',
      name: 'Deudas',
      emoji: '🏦',
      maxPct: 35,
      categoryIds: pick(words: ['hipoteca', 'prestamo', 'credito', 'financiacion']),
    ),
    const BenchmarkSpec(key: 'savings', name: 'Ahorro', emoji: '💰', metric: BenchmarkMetric.savings, minPct: 20),
  ];
}
