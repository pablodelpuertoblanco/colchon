import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/app/providers.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/domain/benchmarks.dart';
import 'package:hogar_en_cifras/domain/forecast.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/plan.dart';
import 'package:hogar_en_cifras/features/forecast/forecast_screen.dart';
import 'package:hogar_en_cifras/features/health/health_screen.dart';

/// Pinta las pantallas nuevas con datos calculados por la lógica de dominio
/// (sin base de datos) para detectar errores de ejecución o de diseño:
/// desbordes en un móvil estrecho, fallos del gráfico...
void main() {
  const cats = {
    'nomina': PlanCategory(id: 'nomina', kind: CategoryKind.income, name: 'Nómina', emoji: '💼', color: 0, expectedDay: 28),
    'hipoteca': PlanCategory(
        id: 'hipoteca', kind: CategoryKind.expense, name: 'Hipoteca', emoji: '🏦', color: 0, group: BudgetGroup.fixed, expectedDay: 5),
    'super': PlanCategory(
        id: 'super', kind: CategoryKind.expense, name: 'Supermercado', emoji: '🛒', color: 0, group: BudgetGroup.variable),
  };
  final today = Dates.today();
  final month = MonthCycle.calendar.monthOf(today);

  Future<void> pump(WidgetTester tester, Widget screen, List overrides) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(home: screen),
    ));
    await tester.pump();
  }

  testWidgets('previsión de saldo: resumen, gráfico, aviso del mínimo y lista', (tester) async {
    final forecast = buildForecast(
      today: today,
      startBalanceCents: 150000,
      cycle: MonthCycle.calendar,
      months: 3,
      categories: cats,
      plannedByYear: {
        for (final y in {month.year, Dates.shiftMonth(month, 2).year})
          y: [
            for (var m = 1; m <= 12; m++) ...[
              PlannedAmount(categoryId: 'nomina', month: m, cents: 200000),
              PlannedAmount(categoryId: 'hipoteca', month: m, cents: 90000),
              PlannedAmount(categoryId: 'super', month: m, cents: 45000),
            ],
          ],
      },
      real: const [],
    );
    await pump(tester, const ForecastScreen(), [
      forecastProvider.overrideWithValue(AsyncData(forecast)),
      forecastMonthsProvider.overrideWithValue(3),
      minBalanceProvider.overrideWithValue(100000),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Saldo previsto'), findsOneWidget);
    expect(find.textContaining('mínimo'), findsWidgets);
    expect(find.text('Próximos cargos e ingresos'), findsOneWidget);
  });

  testWidgets('previsión sin saldo inicial pide configurarlo', (tester) async {
    await pump(tester, const ForecastScreen(), [
      forecastProvider.overrideWithValue(const AsyncData<Forecast?>(null)),
      forecastMonthsProvider.overrideWithValue(3),
      minBalanceProvider.overrideWithValue(null),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Indicar saldo inicial'), findsOneWidget);
  });

  testWidgets('salud financiera: aviso, reglas y fondo de emergencia', (tester) async {
    final categories = {
      ...cats,
      'cine': const PlanCategory(
          id: 'cine', kind: CategoryKind.expense, name: 'Cine', emoji: '🎬', color: 0, group: BudgetGroup.leisure),
    };
    final months = [for (var i = 0; i <= 3; i++) Dates.shiftMonth(month, -i)];
    final figures = monthFigures(
      months: months,
      cycle: MonthCycle.calendar,
      categories: categories,
      real: [
        for (final m in months) ...[
          RealAmount(categoryId: 'nomina', dayKey: Dates.key(m), cents: 200000, type: TxType.income),
          RealAmount(categoryId: 'hipoteca', dayKey: Dates.key(m), cents: 90000, type: TxType.expense),
          RealAmount(categoryId: 'cine', dayKey: Dates.key(m), cents: 70000, type: TxType.expense),
        ],
      ],
    );
    final specs = defaultBenchmarks(categories.values);
    final health = buildFinancialHealth(
      benchmarks: [
        for (final s in specs)
          Benchmark(
            id: s.key,
            name: s.name,
            emoji: s.emoji,
            metric: s.metric,
            minPct: s.minPct,
            maxPct: s.maxPct,
            categoryIds: s.categoryIds,
          ),
      ],
      current: figures.first,
      previous: figures.sublist(1),
      categories: categories,
      availableCents: 120000,
    );
    expect(health.outside.map((r) => r.benchmark.name), containsAll(['Vivienda', 'Ocio y prescindibles', 'Deudas']));

    final overrides = [
      financialHealthProvider.overrideWithValue(AsyncData(health)),
      monthCycleProvider.overrideWithValue(MonthCycle.calendar),
    ];
    await pump(tester, const HealthScreen(), overrides);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('no asesoramiento financiero'), findsOneWidget);
    expect(find.text('Vivienda'), findsOneWidget);

    await pump(tester, const Scaffold(body: HealthSummaryCard()), overrides);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Vivienda: 45 %'), findsOneWidget);
  });
}
