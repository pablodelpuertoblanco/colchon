import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/core/text.dart';
import 'package:hogar_en_cifras/domain/budget_math.dart';
import 'package:hogar_en_cifras/domain/period.dart';

void main() {
  group('Dates', () {
    test('clave de día ida y vuelta', () {
      expect(Dates.key(DateTime(2026, 3, 7)), '2026-03-07');
      expect(Dates.parseKey('2026-03-07'), DateTime(2026, 3, 7));
    });

    test('la semana empieza en lunes', () {
      // 14/11/2026 es sábado
      expect(Dates.startOfWeek(DateTime(2026, 11, 14)), DateTime(2026, 11, 9));
      expect(Dates.endOfWeek(DateTime(2026, 11, 14)), DateTime(2026, 11, 15));
    });

    test('sumar meses ajusta el día', () {
      expect(Dates.addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(Dates.addMonthsClamped(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 15));
      expect(Dates.addMonthsClamped(DateTime(2026, 1, 15), -13), DateTime(2024, 12, 15));
    });

    test('días entre fechas a través del cambio de hora', () {
      expect(Dates.daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(Dates.daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  group('Period', () {
    test('mes anterior y siguiente', () {
      final p = Period.month(DateTime(2026, 3, 15));
      expect(p.start, DateTime(2026, 3, 1));
      expect(p.end, DateTime(2026, 3, 31));
      expect(p.previous().start, DateTime(2026, 2, 1));
      expect(p.next().end, DateTime(2026, 4, 30));
    });

    test('tramos: semana 7 días, mes en bloques, año 12 meses', () {
      expect(Period.week(DateTime(2026, 11, 14)).buckets().length, 7);
      final month = Period.month(DateTime(2026, 2, 1)).buckets();
      expect(month.length, 4); // febrero 2026 tiene 28 días
      expect(month.last.end, DateTime(2026, 2, 28));
      expect(Period.year(DateTime(2026, 6, 1)).buckets().length, 12);
    });
  });

  group('BudgetProgress', () {
    test('estados y ritmo diario', () {
      final p = BudgetProgress(
        limitCents: 40000,
        spentCents: 34000,
        alertPct: 80,
        periodEnd: DateTime(2026, 11, 30),
        today: DateTime(2026, 11, 21),
      );
      expect(p.state, BudgetState.warning);
      expect(p.remainingCents, 6000);
      expect(p.daysLeft, 10);
      expect(p.dailyAllowanceCents, 600);
    });

    test('superado', () {
      final p = BudgetProgress(
        limitCents: 10000,
        spentCents: 12000,
        alertPct: 80,
        periodEnd: DateTime(2026, 11, 30),
        today: DateTime(2026, 11, 21),
      );
      expect(p.state, BudgetState.exceeded);
      expect(p.dailyAllowanceCents, isNull);
    });

    test('aviso solo al cruzar el umbral', () {
      // De 70 € a 85 € con límite 100 € y aviso al 80 %: cruza el aviso.
      expect(
        BudgetProgress.crossedBy(limitCents: 10000, alertPct: 80, spentAfterCents: 8500, amountCents: 1500),
        BudgetState.warning,
      );
      // De 85 € a 90 €: ya estaba avisado, no repite.
      expect(BudgetProgress.crossedBy(limitCents: 10000, alertPct: 80, spentAfterCents: 9000, amountCents: 500), isNull);
      // De 90 € a 105 €: supera el límite.
      expect(
        BudgetProgress.crossedBy(limitCents: 10000, alertPct: 80, spentAfterCents: 10500, amountCents: 1500),
        BudgetState.exceeded,
      );
    });
  });

  test('normalizar texto para buscar', () {
    expect(normalizeForSearch('  Cafetería  Ñandú '), 'cafeteria nandu');
  });
}
