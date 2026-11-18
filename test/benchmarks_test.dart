import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/domain/benchmarks.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/plan.dart';

void main() {
  const cats = {
    'nomina': PlanCategory(id: 'nomina', kind: CategoryKind.income, name: 'Nómina', emoji: '💼', color: 0),
    'retirada': PlanCategory(
        id: 'retirada', kind: CategoryKind.income, name: 'Desde ahorro', emoji: '🏦', color: 0, isSavings: true),
    'casa': PlanCategory(id: 'casa', kind: CategoryKind.expense, name: 'Vivienda', emoji: '🏠', color: 0, group: BudgetGroup.fixed),
    'hipoteca': PlanCategory(
        id: 'hipoteca', kind: CategoryKind.expense, name: 'Hipoteca', emoji: '🏦', color: 0, parentId: 'casa', isSavings: true),
    'agua': PlanCategory(
        id: 'agua', kind: CategoryKind.expense, name: 'Agua', emoji: '💧', color: 0, parentId: 'casa', group: BudgetGroup.variable),
    'gasolina': PlanCategory(
        id: 'gasolina', kind: CategoryKind.expense, name: 'Gasolina', emoji: '⛽', color: 0, group: BudgetGroup.variable),
    'super': PlanCategory(
        id: 'exp-supermercado', kind: CategoryKind.expense, name: 'Comida', emoji: '🛒', color: 0, group: BudgetGroup.variable),
    'cine': PlanCategory(id: 'cine', kind: CategoryKind.expense, name: 'Cine', emoji: '🎬', color: 0, group: BudgetGroup.leisure),
    'ropa': PlanCategory(
        id: 'ropa', kind: CategoryKind.expense, name: 'Ropa', emoji: '👕', color: 0, group: BudgetGroup.discretionary),
    'amort': PlanCategory(
        id: 'amort',
        kind: CategoryKind.expense,
        name: 'Amortización hipoteca',
        emoji: '🏦',
        color: 0,
        group: BudgetGroup.discretionary),
  };
  final categories = {for (final c in cats.values) c.id: c};

  RealAmount r(String id, String day, int cents, [TxType type = TxType.expense]) =>
      RealAmount(categoryId: id, dayKey: day, cents: cents, type: type);

  List<MonthFigures> figures(List<RealAmount> real, List<DateTime> months) =>
      monthFigures(months: months, cycle: MonthCycle.calendar, categories: categories, real: real);

  group('Estado de una regla', () {
    test('máximo: dentro, cerca (a menos del 10 % del límite) y fuera', () {
      expect(statusOf(20, maxPct: 35), BenchmarkStatus.inside);
      expect(statusOf(32, maxPct: 35), BenchmarkStatus.near);
      expect(statusOf(35, maxPct: 35), BenchmarkStatus.near);
      expect(statusOf(35.5, maxPct: 35), BenchmarkStatus.outside);
    });

    test('mínimo: por debajo es fuera; justo por encima, cerca', () {
      expect(statusOf(25, minPct: 20), BenchmarkStatus.inside);
      expect(statusOf(21, minPct: 20), BenchmarkStatus.near);
      expect(statusOf(19.9, minPct: 20), BenchmarkStatus.outside);
      expect(statusOf(-5, minPct: 20), BenchmarkStatus.outside);
    });

    test('sin datos o sin límites no hay estado', () {
      expect(statusOf(null, maxPct: 35), isNull);
      expect(statusOf(10), isNull);
    });
  });

  group('Cifras por mes', () {
    test('ingresos propios, ahorro real y necesarios', () {
      final f = figures([
        r('nomina', '2026-11-01', 200000, TxType.income),
        r('retirada', '2026-11-02', 50000, TxType.income),
        r('hipoteca', '2026-11-03', 60000),
        r('agua', '2026-11-04', 4000),
        r('cine', '2026-11-05', 3000),
      ], [DateTime(2026, 11, 1)]).single;
      expect(f.ownIncomeCents, 200000);
      // 250000 − 67000 + 60000 (hipoteca es ahorro) − 50000 (sale de ahorros)
      expect(f.realSavingsCents, 193000);
      // Hipoteca hereda "fijo" del grupo Casa; agua es variable; el cine no.
      expect(f.needsCents, 64000);
      // Una regla con el grupo incluye sus subcategorías.
      expect(f.centsOf({'casa'}, categories), 64000);
    });

    test('meses anteriores, sin pasar del primer mes con datos', () {
      expect(previousMonths(DateTime(2026, 11, 1), 3), [DateTime(2026, 10, 1), DateTime(2026, 9, 1), DateTime(2026, 8, 1)]);
      expect(previousMonths(DateTime(2026, 11, 1), 12, firstDataMonth: DateTime(2026, 9, 1)),
          [DateTime(2026, 10, 1), DateTime(2026, 9, 1)]);
      expect(previousMonths(DateTime(2026, 11, 1), 12, firstDataMonth: DateTime(2026, 11, 1)), isEmpty);
    });
  });

  group('Reglas', () {
    const vivienda = Benchmark(id: 'v', name: 'Vivienda', emoji: '🏠', maxPct: 35, categoryIds: {'casa'});
    const ahorro = Benchmark(id: 'a', name: 'Ahorro', emoji: '💰', metric: BenchmarkMetric.savings, minPct: 20);
    final months = [DateTime(2026, 11, 1), DateTime(2026, 10, 1), DateTime(2026, 9, 1)];
    final data = figures([
      // Noviembre (mes actual): 2.000 € de ingresos, 800 € de casa.
      r('nomina', '2026-11-01', 200000, TxType.income),
      r('hipoteca', '2026-11-03', 80000),
      // Octubre: 1.000 € de ingresos, 300 € de casa.
      r('nomina', '2026-10-01', 100000, TxType.income),
      r('agua', '2026-10-04', 30000),
      // Septiembre: 3.000 € de ingresos, 600 € de casa y 2.000 € de cine.
      r('nomina', '2026-09-01', 300000, TxType.income),
      r('hipoteca', '2026-09-03', 60000),
      r('cine', '2026-09-10', 200000),
    ], months);

    test('porcentaje del mes y media (total entre ingresos, no media de porcentajes)', () {
      final res = evaluateBenchmark(vivienda, current: data.first, previous: data.sublist(1), categories: categories);
      expect(res.monthCents, 80000);
      expect(res.monthPct, closeTo(40, 0.001));
      expect(res.monthStatus, BenchmarkStatus.outside);
      // (300 + 600) / (1.000 + 3.000) = 22,5 % (la media de porcentajes daría 25 %).
      expect(res.averagePct, closeTo(22.5, 0.001));
      expect(res.averageCents, 45000);
      expect(res.averageMonths, 2);
      expect(res.averageStatus, BenchmarkStatus.inside);
      expect(res.status, BenchmarkStatus.outside);
    });

    test('ahorro real como regla de mínimo', () {
      final res = evaluateBenchmark(ahorro, current: data.first, previous: data.sublist(1), categories: categories);
      // Noviembre: 2.000 − 800 + 800 (la hipoteca cuenta como ahorro) = 2.000 € → 100 %.
      expect(res.monthPct, closeTo(100, 0.001));
      expect(res.status, BenchmarkStatus.inside);
      // Septiembre: 3.000 − 2.600 + 600 = 1.000 €; octubre: 1.000 − 300 = 700 €. (1.700 / 4.000)
      expect(res.averagePct, closeTo(42.5, 0.001));
    });

    test('a principio de mes, sin ingresos, el estado sale de la media', () {
      final empty = figures([], [DateTime(2026, 12, 1)]).single;
      final res = evaluateBenchmark(vivienda, current: empty, previous: data, categories: categories);
      expect(res.monthPct, isNull);
      expect(res.status, res.averageStatus);
    });

    test('resumen: reglas incumplidas y fondo de emergencia', () {
      final health = buildFinancialHealth(
        benchmarks: const [vivienda, ahorro],
        current: data.first,
        previous: data.sublist(1),
        categories: categories,
        availableCents: 100000,
      );
      expect(health.outside.map((r) => r.benchmark.name), ['Vivienda']);
      // Necesarios: octubre 300 €, septiembre 600 € → 450 €/mes; 1.000 € cubren 2,2 meses.
      expect(health.fund!.monthlyNeedsCents, 45000);
      expect(health.fund!.months, closeTo(2.222, 0.001));
      expect(health.fundOutside, isTrue);
      expect(
        buildFinancialHealth(benchmarks: const [], current: data.first, previous: const [], categories: categories).fund,
        isNull,
      );
    });

    test('fondo de emergencia: de 3 a 6 meses', () {
      EmergencyFund fund(int available) =>
          EmergencyFund(availableCents: available, monthlyNeedsCents: 100000, monthsUsed: 12);
      expect(fund(250000).status, BenchmarkStatus.outside);
      expect(fund(310000).status, BenchmarkStatus.near);
      expect(fund(450000).status, BenchmarkStatus.inside);
      expect(fund(800000).aboveTarget, isTrue);
      expect(const EmergencyFund(availableCents: 1, monthlyNeedsCents: null, monthsUsed: 0).months, isNull);
    });
  });

  test('medias de una categoría a 3, 6 y 12 meses y comparación con el mes actual', () {
    final months = [for (var i = 0; i <= 12; i++) Dates.shiftMonth(DateTime(2026, 11, 1), -i)];
    final real = [
      for (var i = 0; i <= 12; i++) ...[
        // Gasto en súper: 100 € los últimos 3 meses, 200 € antes; este mes 150 €.
        r('exp-supermercado', Dates.key(Dates.shiftMonth(DateTime(2026, 11, 1), -i)), i == 0 ? 15000 : (i <= 3 ? 10000 : 20000)),
      ],
    ];
    final f = figures(real, months);
    final avg = categoryAverages('exp-supermercado', current: f.first, previous: f.sublist(1), categories: categories);
    expect(avg.currentCents, 15000);
    expect(avg.averages[3], 10000);
    expect(avg.averages[6], 15000);
    expect(avg.averages[12], 17500);
    expect(avg.changeVs(3), closeTo(50, 0.001));
    expect(avg.changeVs(6), closeTo(0, 0.001));

    final noHistory = categoryAverages('exp-supermercado', current: f.first, previous: const [], categories: categories);
    expect(noHistory.averages[3], isNull);
    expect(noHistory.changeVs(12), isNull);
  });

  test('reglas iniciales: categorías por id o por palabra completa, sin amortizaciones', () {
    final specs = {for (final s in defaultBenchmarks(cats.values)) s.key: s};
    expect(specs.keys, ['housing', 'food', 'transport', 'wants', 'debt', 'savings']);
    expect(specs['housing']!.maxPct, 35);
    // "Gasolina" no es "gas" de casa; la amortización no cuenta.
    expect(specs['housing']!.categoryIds, {'hipoteca', 'agua'});
    expect(specs['food']!.categoryIds, {'exp-supermercado'});
    expect(specs['transport']!.categoryIds, {'gasolina'});
    expect(specs['wants']!.categoryIds, {'cine', 'ropa'});
    expect(specs['debt']!.categoryIds, {'hipoteca'});
    expect(specs['savings']!.metric, BenchmarkMetric.savings);
    expect(specs['savings']!.minPct, 20);
  });
}
