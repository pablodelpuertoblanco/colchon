import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/data/plan_excel.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/plan.dart';

/// Bloque "Ocio": sección propia en el plan, pero dentro del 30 % de la
/// regla 50/30/20 junto a los prescindibles.
void main() {
  const cats = {
    'nomina': PlanCategory(id: 'nomina', kind: CategoryKind.income, name: 'Nómina', emoji: '💼', color: 0),
    'ropa': PlanCategory(
        id: 'ropa', kind: CategoryKind.expense, name: 'Ropa', emoji: '👕', color: 0, group: BudgetGroup.discretionary, sortOrder: 1),
    'cine': PlanCategory(
        id: 'cine', kind: CategoryKind.expense, name: 'Cine', emoji: '🎬', color: 0, group: BudgetGroup.leisure, sortOrder: 2),
    'viajes': PlanCategory(
        id: 'viajes', kind: CategoryKind.expense, name: 'Viajes', emoji: '✈️', color: 0, group: BudgetGroup.leisure, sortOrder: 3),
    'escapadas': PlanCategory(
        id: 'escapadas', kind: CategoryKind.expense, name: 'Escapadas', emoji: '🏕️', color: 0, parentId: 'viajes', sortOrder: 4),
  };

  RealAmount r(String id, String day, int cents, [TxType type = TxType.expense]) =>
      RealAmount(categoryId: id, dayKey: day, cents: cents, type: type);

  test('Ocio cuenta en el bloque de prescindibles de la regla 50/30/20', () {
    expect(BudgetGroup.leisure.bucket, RuleBucket.wants);
    expect(BudgetGroup.discretionary.bucket, RuleBucket.wants);
    expect(PlanSectionKind.leisure.bucket, RuleBucket.wants);
    expect(PlanSectionKind.ofGroup(BudgetGroup.leisure), PlanSectionKind.leisure);
    expect(BudgetGroup.leisure.label, 'Ocio');
    expect(BudgetGroup.leisure.emoji, '🎬');
  });

  test('el plan muestra Ocio como sección propia, tras los prescindibles', () {
    final plan = buildPlanYear(
      year: 2026,
      cycle: MonthCycle.calendar,
      categories: cats,
      planned: const [
        PlannedAmount(categoryId: 'nomina', month: 3, cents: 200000),
        PlannedAmount(categoryId: 'ropa', month: 3, cents: 10000),
        PlannedAmount(categoryId: 'cine', month: 3, cents: 3000),
        PlannedAmount(categoryId: 'viajes', month: 3, cents: 20000),
      ],
      real: [
        r('nomina', '2026-03-01', 200000, TxType.income),
        r('ropa', '2026-03-02', 8000),
        r('cine', '2026-03-03', 2500),
        // Sin bloque propio: hereda "Ocio" del grupo padre.
        r('escapadas', '2026-03-04', 15000),
      ],
    );
    final m = plan.monthAt(3);
    final kinds = m.sections.map((s) => s.kind).toList();
    expect(kinds, [PlanSectionKind.income, PlanSectionKind.discretionary, PlanSectionKind.leisure]);

    final leisure = m.sections.firstWhere((s) => s.kind == PlanSectionKind.leisure);
    expect(leisure.plannedCents, 23000);
    expect(leisure.realCents, 17500);

    final t = m.totals;
    expect(t.sectionCents(PlanSectionKind.discretionary, real: true), 8000);
    expect(t.sectionCents(PlanSectionKind.leisure, real: true), 17500);
    // El 30 % suma prescindibles + ocio.
    expect(t.bucketCents(RuleBucket.wants, real: true), 25500);
    expect(t.bucketCents(RuleBucket.wants, real: false), 33000);
    expect(t.expenseCents(real: true), 25500);
  });

  test('el Excel acepta el bloque Ocio y explica los válidos si no lo conoce', () {
    expect(
      () => PlanExcel.parse(File('test/fixtures/bloque_no_valido.xlsx').readAsBytesSync(), fallbackYear: 2026),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', allOf(contains('Diversión'), contains('Ocio')))),
    );
  });

  test('la plantilla trae Restaurantes y Viajes en el bloque de ocio', () {
    final f = PlanExcel.parse(File('assets/plantilla/plantilla_plan.xlsx').readAsBytesSync(), fallbackYear: 2026);
    expect(f.categories.firstWhere((c) => c.name == 'Restaurantes').group, BudgetGroup.leisure);
    expect(f.categories.firstWhere((c) => c.name == 'Viajes').group, BudgetGroup.leisure);
  });
}
