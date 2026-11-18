import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/data/plan_excel.dart';
import 'package:hogar_en_cifras/data/plan_import.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/net_worth.dart';
import 'package:hogar_en_cifras/domain/period.dart';
import 'package:hogar_en_cifras/domain/plan.dart';

void main() {
  group('MonthCycle (mes del 24 al 23)', () {
    const c = MonthCycle(24);

    test('el mes toma el nombre del mes en que termina', () {
      expect(c.monthOf(DateTime(2025, 12, 24)), DateTime(2026, 1, 1));
      expect(c.monthOf(DateTime(2026, 1, 23)), DateTime(2026, 1, 1));
      expect(c.monthOf(DateTime(2026, 1, 24)), DateTime(2026, 2, 1));
      expect(c.monthOf(DateTime(2026, 11, 14)), DateTime(2026, 11, 1));
    });

    test('inicio y fin, también entre años', () {
      expect(c.startOf(DateTime(2026, 1, 1)), DateTime(2025, 12, 24));
      expect(c.endOf(DateTime(2026, 1, 1)), DateTime(2026, 1, 23));
      expect(c.yearRange(2026), (DateTime(2025, 12, 24), DateTime(2026, 12, 23)));
    });

    test('día 1 = mes natural', () {
      expect(MonthCycle.calendar.startOf(DateTime(2026, 2, 1)), DateTime(2026, 2, 1));
      expect(MonthCycle.calendar.endOf(DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
      expect(MonthCycle.parse('99'), MonthCycle.calendar);
      expect(MonthCycle.parse('24').startDay, 24);
    });

    test('periodos de mes y año siguen el ciclo', () {
      final p = Period.month(DateTime(2026, 11, 14), cycle: c);
      expect(p.start, DateTime(2026, 10, 24));
      expect(p.end, DateTime(2026, 11, 23));
      expect(p.label, 'Noviembre 2026');
      expect(p.next().start, DateTime(2026, 11, 24));
      expect(p.previous().end, DateTime(2026, 10, 23));
      final y = Period.year(DateTime(2026, 12, 30), cycle: c);
      expect(y.cycleYear, 2027);
      expect(y.buckets().length, 12);
      expect(BudgetPeriod.month.rangeFor(DateTime(2026, 11, 30), c), (DateTime(2026, 11, 24), DateTime(2026, 12, 23)));
    });
  });

  group('Plan', () {
    const cats = {
      'nomina': PlanCategory(id: 'nomina', kind: CategoryKind.income, name: 'Nómina', emoji: '💼', color: 0, sortOrder: 0),
      'retirada': PlanCategory(
          id: 'retirada', kind: CategoryKind.income, name: 'Desde ahorro', emoji: '🏦', color: 0, isSavings: true, sortOrder: 1),
      'casa': PlanCategory(id: 'casa', kind: CategoryKind.expense, name: 'Casa', emoji: '🏠', color: 0, sortOrder: 2),
      'agua': PlanCategory(
          id: 'agua', kind: CategoryKind.expense, name: 'Agua', emoji: '💧', color: 0, parentId: 'casa', group: BudgetGroup.variable, sortOrder: 3),
      'hipoteca': PlanCategory(
          id: 'hipoteca',
          kind: CategoryKind.expense,
          name: 'Hipoteca',
          emoji: '🏦',
          color: 0,
          parentId: 'casa',
          group: BudgetGroup.fixed,
          isSavings: true,
          sortOrder: 4),
      'suscripciones': PlanCategory(
          id: 'suscripciones', kind: CategoryKind.expense, name: 'Suscripciones', emoji: '📺', color: 0, group: BudgetGroup.discretionary, sortOrder: 5),
      'pensiones': PlanCategory(
          id: 'pensiones',
          kind: CategoryKind.expense,
          name: 'Plan de pensiones',
          emoji: '🧓',
          color: 0,
          group: BudgetGroup.savings,
          isSavings: true,
          sortOrder: 6),
      'otros': PlanCategory(id: 'otros', kind: CategoryKind.expense, name: 'Otros', emoji: '📦', color: 0, sortOrder: 7),
    };

    PlanYear build(List<RealAmount> real) => buildPlanYear(
          year: 2026,
          cycle: const MonthCycle(24),
          categories: cats,
          planned: const [
            PlannedAmount(categoryId: 'nomina', month: 11, cents: 180000),
            PlannedAmount(categoryId: 'agua', month: 11, cents: 3000),
            PlannedAmount(categoryId: 'hipoteca', month: 11, cents: 6000),
            PlannedAmount(categoryId: 'suscripciones', month: 11, cents: 10000),
            PlannedAmount(categoryId: 'pensiones', month: 11, cents: 5000),
            PlannedAmount(categoryId: 'suscripciones', month: 12, cents: 10000),
          ],
          real: real,
        );

    RealAmount r(String id, String day, int cents, [TxType type = TxType.expense]) =>
        RealAmount(categoryId: id, dayKey: day, cents: cents, type: type);

    test('lo real va a su mes contable y a su bloque', () {
      final plan = build([
        r('nomina', '2026-10-24', 180000, TxType.income), // noviembre contable
        r('suscripciones', '2026-11-23', 11300), // noviembre
        r('suscripciones', '2026-11-24', 2000), // ya es diciembre
        r('otros', '2026-11-10', 500), // sin plan ni bloque
      ]);
      final nov = plan.monthAt(11);
      expect(nov.lineOf('suscripciones')!.realCents, 11300);
      expect(nov.lineOf('suscripciones')!.isOver, isTrue);
      expect(plan.monthAt(12).lineOf('suscripciones')!.realCents, 2000);
      expect(nov.lineOf('otros')!.section, PlanSectionKind.unclassified);
      expect(nov.lineOf('otros')!.isUnplanned, isTrue);
      expect(nov.totals.incomeCents(real: true), 180000);
      expect(nov.totals.expenseCents(real: true), 11800);
      expect(nov.totals.expenseCents(real: false), 24000);
      expect(nov.sections.first.kind, PlanSectionKind.income);
    });

    test('ahorro real: saldo + aportaciones − lo sacado de ahorros', () {
      final plan = build([
        r('nomina', '2026-11-01', 180000, TxType.income),
        r('retirada', '2026-11-02', 50000, TxType.income),
        r('hipoteca', '2026-11-03', 6000),
        r('pensiones', '2026-11-04', 5000),
        r('suscripciones', '2026-11-05', 10000),
      ]);
      final t = plan.monthAt(11).totals;
      expect(t.balanceCents(real: true), 230000 - 21000);
      expect(t.ownIncomeCents(real: true), 180000);
      // 209000 + 11000 (hipoteca + pensiones) − 50000 (retirada)
      expect(t.realSavingsCents(real: true), 170000);
      expect(t.bucketCents(RuleBucket.needs, real: true), 6000);
      expect(t.bucketCents(RuleBucket.wants, real: true), 10000);
      expect(t.bucketCents(RuleBucket.savings, real: true), 5000);
      expect(t.shareOfIncome(18000, real: true), closeTo(10, 0.001));
    });

    test('un gasto sin previsto se suma al grupo padre si el padre tiene previsto', () {
      final plan = buildPlanYear(
        year: 2026,
        cycle: MonthCycle.calendar,
        categories: cats,
        planned: const [PlannedAmount(categoryId: 'casa', month: 3, cents: 10000)],
        real: [r('agua', '2026-03-05', 2500), r('casa', '2026-03-06', 1000)],
      );
      final m = plan.monthAt(3);
      expect(m.lineOf('casa')!.realCents, 3500);
      expect(m.lineOf('agua'), isNull);
    });

    test('el año suma los doce meses', () {
      final plan = build([r('suscripciones', '2026-11-05', 10000), r('suscripciones', '2026-12-05', 9000)]);
      expect(plan.totals.sectionCents(PlanSectionKind.discretionary, real: true), 19000);
      expect(plan.totals.sectionCents(PlanSectionKind.discretionary, real: false), 20000);
      expect(plan.hasPlan, isTrue);
    });
  });

  group('Patrimonio', () {
    const assets = [
      AssetInfo(id: 'plan', name: 'Plan', emoji: '🧓', kind: AssetKind.asset),
      AssetInfo(id: 'hip', name: 'Hipoteca', emoji: '🏦', kind: AssetKind.liability),
    ];
    const values = [
      AssetValue(assetId: 'plan', year: 2026, month: 1, cents: 2000000),
      AssetValue(assetId: 'plan', year: 2026, month: 3, cents: 2100000),
      AssetValue(assetId: 'hip', year: 2026, month: 1, cents: 3000000),
      AssetValue(assetId: 'hip', year: 2026, month: 2, cents: 2990000),
    ];

    test('arrastra el último valor y calcula el neto', () {
      final feb = netWorthAt(DateTime(2026, 2, 1), assets, values);
      expect(feb.assetsCents, 2000000);
      expect(feb.liabilitiesCents, 2990000);
      expect(feb.netCents, -990000);
      expect(feb.changeCents, 10000); // la deuda bajó 100 €
      expect(feb.pendingUpdates, 1); // el plan no se anotó en febrero
      final series = netWorthSeries(DateTime(2026, 3, 1), 3, assets, values);
      expect(series, [-1000000, -990000, -890000]);
    });
  });

  group('Importar plan desde Excel', () {
    PlanImportFile read(String path) => PlanExcel.parse(File(path).readAsBytesSync(), fallbackYear: 2026);

    test('la plantilla se lee entera: plan, grupos, ajustes y patrimonio', () {
      final f = read('assets/plantilla/plantilla_plan.xlsx');
      expect(f.year, 2026); // la plantilla no fija el año: se usa el actual
      expect(f.plannedCategories, 15);
      expect(f.plannedTotal(CategoryKind.income), 2535000);
      expect(f.plannedTotal(CategoryKind.expense), 1884000);
      expect(f.hasGroups, isTrue);
      final luz = f.categories.firstWhere((c) => c.name == 'Luz');
      expect(luz.group, BudgetGroup.variable);
      expect(luz.parentKey, 'grupo:expense:vivienda');
      expect(luz.plan!.first, 7000);
      expect(f.categories.firstWhere((c) => c.key == 'grupo:expense:vivienda').plan, isNull);
      expect(f.categories.firstWhere((c) => c.name == 'Plan de pensiones').isSavings, isTrue);
      expect(f.categories.firstWhere((c) => c.name == 'Nómina').plan![6], 360000); // paga extra de julio
      expect(f.monthStartDay, 1);
      expect(f.minBalanceCents, isNull);
      expect(f.targets, const RuleTargets(needs: 50, wants: 30, savings: 20));
      expect(f.assets.length, 2);
      expect(f.assets.last.kind, AssetKind.liability);
      expect(f.assets.first.values.first, (year: 2026, month: 1, cents: 300000));
    });

    test('también lee hojas con títulos de bloque, totales e importes escritos como texto', () {
      final f = read('test/fixtures/plan_por_secciones.xlsx');
      expect(f.year, 2027); // del nombre de la hoja
      expect(f.hasGroups, isFalse);
      expect(f.categories.map((c) => c.name), ['Nómina', 'Alquiler piso', 'Hipoteca', 'Comida', 'Ocio', 'Fondo indexado']);
      final alquiler = f.categories.firstWhere((c) => c.name == 'Alquiler piso');
      expect(alquiler.kind, CategoryKind.income);
      expect(alquiler.plan!.first, 45050); // "450,50 €"
      expect(f.categories.firstWhere((c) => c.name == 'Hipoteca').group, BudgetGroup.fixed);
      expect(f.categories.firstWhere((c) => c.name == 'Comida').plan!.first, 35000); // -300 y 50: se suman en positivo
      expect(f.categories.firstWhere((c) => c.name == 'Ocio').group, BudgetGroup.discretionary);
      expect(f.categories.firstWhere((c) => c.name == 'Fondo indexado').group, BudgetGroup.savings);
      expect(f.plannedTotal(CategoryKind.income), 2940600);
      expect(f.plannedTotal(CategoryKind.expense), 1620000);
    });

    test('un título de bloque que no conoce, tras los ingresos, da paso a los gastos', () {
      // Todo en mayúsculas y con títulos propios ("VIVIENDA", "MASCOTAS").
      final f = read('test/fixtures/plan_titulos_libres.xlsx');
      CategoryKind kindOf(String n) => f.categories.firstWhere((c) => c.name == n).kind;
      expect(f.categories.map((c) => c.name), ['NOMINA', 'OTROS COBROS', 'HIPOTECA', 'ARENA', 'OCIO']);
      expect(kindOf('NOMINA'), CategoryKind.income);
      expect(kindOf('OTROS COBROS'), CategoryKind.income);
      expect(kindOf('HIPOTECA'), CategoryKind.expense);
      expect(kindOf('ARENA'), CategoryKind.expense);
      expect(kindOf('OCIO'), CategoryKind.expense); // con importes es una partida, no un título
      expect(f.plannedTotal(CategoryKind.income), 1900 * 100 * 12);
    });

    test('el bloque puede ir en una columna a la izquierda del nombre', () {
      final f = read('test/fixtures/plan_bloque_a_la_izquierda.xlsx');
      PlanImportCategory cat(String n) => f.categories.firstWhere((c) => c.name == n);
      expect(f.categories.map((c) => c.name), ['Nómina', 'Intereses', 'Alquiler', 'Luz', 'Arena del gato']);
      expect(cat('Intereses').kind, CategoryKind.income);
      expect(cat('Alquiler').kind, CategoryKind.expense);
      expect(cat('Alquiler').group, BudgetGroup.fixed);
      expect(cat('Luz').group, BudgetGroup.fixed);
      expect(cat('Arena del gato').kind, CategoryKind.expense);
      expect(cat('Arena del gato').group, BudgetGroup.variable);
    });

    test('rechaza archivos que no son un Excel', () {
      expect(
        () => PlanExcel.parse(Uint8List.fromList('no es un excel'.codeUnits), fallbackYear: 2026),
        throwsFormatException,
      );
    });
  });
}
