import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/domain/forecast.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/plan.dart';

void main() {
  const cats = {
    'nomina': PlanCategory(id: 'nomina', kind: CategoryKind.income, name: 'Nómina', emoji: '💼', color: 0, expectedDay: 28),
    'hipoteca': PlanCategory(
        id: 'hipoteca', kind: CategoryKind.expense, name: 'Hipoteca', emoji: '🏦', color: 0, group: BudgetGroup.fixed, expectedDay: 5),
    'super': PlanCategory(
        id: 'super', kind: CategoryKind.expense, name: 'Súper', emoji: '🛒', color: 0, group: BudgetGroup.variable),
    'luz': PlanCategory(
        id: 'luz', kind: CategoryKind.expense, name: 'Luz', emoji: '💡', color: 0, group: BudgetGroup.variable, expectedDay: 31),
    'casa': PlanCategory(id: 'casa', kind: CategoryKind.expense, name: 'Casa', emoji: '🏠', color: 0, group: BudgetGroup.fixed),
    'agua': PlanCategory(id: 'agua', kind: CategoryKind.expense, name: 'Agua', emoji: '💧', color: 0, parentId: 'casa'),
  };

  RealAmount real(String id, String day, int cents, [TxType type = TxType.expense]) =>
      RealAmount(categoryId: id, dayKey: day, cents: cents, type: type);

  List<PlannedAmount> monthly(String id, int cents, [List<int> months = const [11, 12]]) =>
      [for (final m in months) PlannedAmount(categoryId: id, month: m, cents: cents)];

  Forecast run({
    DateTime? today,
    int start = 100000,
    MonthCycle cycle = MonthCycle.calendar,
    int months = 1,
    List<PlannedAmount> planned = const [],
    List<RealAmount> realAmounts = const [],
    List<ForecastRule> rules = const [],
    List<ForecastPendingTx> pending = const [],
  }) =>
      buildForecast(
        today: today ?? DateTime(2026, 11, 14),
        startBalanceCents: start,
        cycle: cycle,
        months: months,
        categories: cats,
        plannedByYear: {2026: planned},
        real: realAmounts,
        rules: rules,
        pending: pending,
      );

  ForecastDay dayOf(Forecast f, DateTime d) => f.days.firstWhere((x) => Dates.sameDay(x.date, d));

  group('Fecha esperada dentro del mes contable', () {
    test('mes natural, ajustando al último día', () {
      expect(expectedDateIn(MonthCycle.calendar, DateTime(2026, 2, 1), 31), DateTime(2026, 2, 28));
      expect(expectedDateIn(MonthCycle.calendar, DateTime(2028, 2, 1), 30), DateTime(2028, 2, 29));
      expect(expectedDateIn(MonthCycle.calendar, DateTime(2026, 11, 1), 5), DateTime(2026, 11, 5));
    });

    test('mes del 24 al 23: el 28 cae al principio y el 5 al final', () {
      const c = MonthCycle(24);
      // "Enero" = 24 dic – 23 ene.
      expect(expectedDateIn(c, DateTime(2026, 1, 1), 28), DateTime(2025, 12, 28));
      expect(expectedDateIn(c, DateTime(2026, 1, 1), 5), DateTime(2026, 1, 5));
      // "Marzo" = 24 feb – 23 mar: el 30 de febrero no existe -> 28 feb.
      expect(expectedDateIn(c, DateTime(2026, 3, 1), 30), DateTime(2026, 2, 28));
    });

    test('los meses de la previsión empiezan en el mes contable actual', () {
      expect(forecastMonths(DateTime(2026, 11, 30), const MonthCycle(24), 3),
          [DateTime(2026, 12, 1), DateTime(2027, 1, 1), DateTime(2027, 2, 1)]);
      expect(forecastMonths(DateTime(2026, 11, 14), MonthCycle.calendar, 99).length, maxForecastMonths);
    });
  });

  group('Recurrentes', () {
    final netflix = ForecastRule(
      id: 'r1',
      type: TxType.expense,
      amountCents: 1299,
      categoryId: 'ocio',
      label: 'Netflix',
      emoji: '🎬',
      start: DateTime(2026, 1, 20),
      frequency: Frequency.month,
      lastGenerated: DateTime(2026, 10, 20),
    );

    test('las ocurrencias futuras van en su fecha y lo ya generado no se repite', () {
      final f = run(months: 2, rules: [netflix]);
      final events = f.events.where((e) => e.source == ForecastSource.recurring).toList();
      expect(events.map((e) => e.date), [DateTime(2026, 11, 20), DateTime(2026, 12, 20)]);
      expect(dayOf(f, DateTime(2026, 11, 20)).balanceCents, 100000 - 1299);
      expect(f.endBalanceCents, 100000 - 2 * 1299);
    });

    test('una ocurrencia pasada aún no generada se cuenta hoy', () {
      final rule = ForecastRule(
        id: 'r2',
        type: TxType.expense,
        amountCents: 5000,
        categoryId: 'luz',
        label: 'Luz',
        emoji: '💡',
        start: DateTime(2026, 11, 10),
        frequency: Frequency.month,
      );
      final f = run(rules: [rule]);
      expect(f.days.first.date, DateTime(2026, 11, 14));
      expect(f.days.first.balanceCents, 95000);
    });

    test('los pendientes de confirmar cuentan, y si son de días pasados, hoy', () {
      final f = run(pending: [
        ForecastPendingTx(
            date: DateTime(2026, 11, 2), type: TxType.expense, amountCents: 3000, categoryId: 'luz', label: 'Luz', emoji: '💡'),
      ]);
      expect(f.days.first.balanceCents, 97000);
      expect(f.days.first.events.single.source, ForecastSource.pending);
    });
  });

  group('Partidas del plan', () {
    test('con día fijo: lo que queda va ese día; si ya pasó, hoy', () {
      final f = run(
        planned: [...monthly('hipoteca', 60000), ...monthly('nomina', 200000)],
        realAmounts: [real('hipoteca', '2026-11-05', 20000)],
      );
      // La hipoteca (día 5) ya pasó pero quedan 400 €: van hoy.
      final today = f.days.first;
      expect(today.events.single.cents, 40000);
      expect(today.events.single.source, ForecastSource.plan);
      expect(today.balanceCents, 60000);
      // La nómina el 28.
      expect(dayOf(f, DateTime(2026, 11, 28)).balanceCents, 260000);
    });

    test('día 31 en un mes de 30 cae el 30', () {
      final f = run(planned: monthly('luz', 4000));
      expect(dayOf(f, DateTime(2026, 11, 30)).events.single.cents, 4000);
    });

    test('sin día fijo se reparte a partes iguales entre los días que quedan, sin perder céntimos', () {
      // Del 14 al 30 de noviembre: 17 días; quedan 100 € del súper.
      final f = run(planned: monthly('super', 30000), realAmounts: [real('super', '2026-11-03', 20000)]);
      expect(f.days.length, 17);
      final spread = f.events.where((e) => e.isSpread).toList();
      expect(spread.length, 17);
      expect(spread.fold<int>(0, (s, e) => s + e.cents), 10000);
      expect(spread.first.cents, 589); // 10000 = 17 × 588 + 4
      expect(spread.last.cents, 588);
      expect(f.endBalanceCents, 90000);
    });

    test('si lo real supera lo previsto no queda nada que prever', () {
      final f = run(planned: monthly('super', 30000), realAmounts: [real('super', '2026-11-03', 35000)]);
      expect(f.events, isEmpty);
      expect(f.endBalanceCents, 100000);
    });

    test('un recurrente de la categoría cubre su partida: no se cuenta dos veces', () {
      final rule = ForecastRule(
        id: 'h',
        type: TxType.expense,
        amountCents: 60000,
        categoryId: 'hipoteca',
        label: 'Hipoteca',
        emoji: '🏦',
        start: DateTime(2026, 1, 25),
        frequency: Frequency.month,
        lastGenerated: DateTime(2026, 10, 25),
      );
      final f = run(planned: monthly('hipoteca', 65000), rules: [rule]);
      // 600 € del recurrente el 25 + 50 € que el recurrente no cubre (hoy, el día 5 ya pasó).
      expect(f.events.map((e) => (e.source, e.cents)), [(ForecastSource.plan, 5000), (ForecastSource.recurring, 60000)]);
      expect(f.endBalanceCents, 100000 - 65000);
    });

    test('un pendiente de confirmar también cubre su partida', () {
      final f = run(planned: monthly('luz', 4000), pending: [
        ForecastPendingTx(
            date: DateTime(2026, 11, 10), type: TxType.expense, amountCents: 4500, categoryId: 'luz', label: 'Luz', emoji: '💡'),
      ]);
      expect(f.endBalanceCents, 100000 - 4500);
    });

    test('lo gastado en una subcategoría sin previsto descuenta del grupo', () {
      final f = run(
        planned: monthly('casa', 10000),
        realAmounts: [real('agua', '2026-11-02', 3000)],
      );
      expect(f.endBalanceCents, 100000 - 7000);
    });

    test('al registrar un gasto real baja lo que queda de la partida', () {
      final before = run(planned: monthly('super', 30000));
      final after = run(planned: monthly('super', 30000), realAmounts: [real('super', '2026-11-14', 5000)]);
      // El saldo de hoy ya incluye el gasto (start baja 50 €) y lo previsto baja 50 €.
      final afterWithBalance = run(start: 95000, planned: monthly('super', 30000), realAmounts: [real('super', '2026-11-14', 5000)]);
      expect(before.endBalanceCents, 70000);
      expect(after.endBalanceCents, 75000);
      expect(afterWithBalance.endBalanceCents, 70000);
    });

    test('varios meses: cada mes su partida completa', () {
      final f = run(months: 2, planned: monthly('hipoteca', 60000));
      expect(f.endDate, DateTime(2026, 12, 31));
      expect(dayOf(f, DateTime(2026, 12, 5)).events.single.cents, 60000);
      expect(f.endBalanceCents, 100000 - 120000);
    });
  });

  group('Resumen', () {
    test('punto más bajo y primer día por debajo del mínimo', () {
      final f = run(
        months: 2,
        planned: [...monthly('hipoteca', 60000), ...monthly('nomina', 200000)],
        realAmounts: [real('hipoteca', '2026-11-05', 60000)],
      );
      // Noviembre: nómina el 28 (+2000). Diciembre: hipoteca el 5 (−600), nómina el 28.
      expect(f.lowest!.date, DateTime(2026, 11, 14));
      expect(f.lowest!.balanceCents, 100000);
      expect(f.firstBelow(150000)!.date, DateTime(2026, 11, 14));
      expect(f.firstBelow(50000), isNull);

      final tight = run(months: 2, start: 10000, planned: monthly('hipoteca', 60000));
      expect(tight.lowest!.date, DateTime(2026, 12, 5));
      expect(tight.lowest!.balanceCents, 10000 - 120000);
      expect(tight.firstBelow(0)!.date, DateTime(2026, 11, 14));
    });

    test('el último mes del año contable sigue con el plan del año siguiente', () {
      final f = buildForecast(
        today: DateTime(2026, 12, 20),
        startBalanceCents: 0,
        cycle: const MonthCycle(24),
        months: 2,
        categories: cats,
        plannedByYear: {
          2026: [const PlannedAmount(categoryId: 'hipoteca', month: 12, cents: 100)],
          2027: [const PlannedAmount(categoryId: 'hipoteca', month: 1, cents: 200)],
        },
        real: const [],
      );
      // Diciembre contable acaba el 23; "enero 2027" va del 24 dic al 23 ene.
      expect(f.endDate, DateTime(2027, 1, 23));
      expect(f.events.map((e) => (e.date, e.cents)), [(DateTime(2026, 12, 20), 100), (DateTime(2027, 1, 5), 200)]);
    });
  });
}
