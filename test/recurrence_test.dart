import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/dates.dart';
import 'package:hogar_en_cifras/domain/models.dart';
import 'package:hogar_en_cifras/domain/recurrence.dart';

List<String> keys(List<DateTime> ds) => ds.map(Dates.key).toList();

void main() {
  test('mensual el día 31 se ajusta al último día del mes', () {
    final r = Recurrence.between(
      start: DateTime(2026, 1, 31),
      frequency: Frequency.month,
      everyN: 1,
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 5, 31),
    );
    expect(keys(r), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']);
  });

  test('anual el 29 de febrero cae el 28 en años no bisiestos', () {
    final r = Recurrence.between(
      start: DateTime(2028, 2, 29),
      frequency: Frequency.year,
      everyN: 1,
      from: DateTime(2028, 1, 1),
      to: DateTime(2030, 12, 31),
    );
    expect(keys(r), ['2028-02-29', '2029-02-28', '2030-02-28']);
  });

  test('cada 2 semanas y respeta la fecha de fin', () {
    final r = Recurrence.between(
      start: DateTime(2026, 11, 2),
      frequency: Frequency.week,
      everyN: 2,
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 12, 31),
      end: DateTime(2026, 12, 10),
    );
    expect(keys(r), ['2026-11-02', '2026-11-16', '2026-11-30']);
  });

  test('solo devuelve ocurrencias dentro del rango pedido', () {
    final r = Recurrence.between(
      start: DateTime(2026, 1, 5),
      frequency: Frequency.month,
      everyN: 1,
      from: DateTime(2026, 3, 6),
      to: DateTime(2026, 6, 4),
    );
    expect(keys(r), ['2026-04-05', '2026-05-05']);
  });

  test('próxima ocurrencia', () {
    final next = Recurrence.nextFrom(
      start: DateTime(2026, 1, 1),
      frequency: Frequency.month,
      everyN: 3,
      from: DateTime(2026, 2, 15),
    );
    expect(Dates.key(next!), '2026-04-01');
  });

  test('una regla terminada no tiene próxima ocurrencia', () {
    final next = Recurrence.nextFrom(
      start: DateTime(2026, 1, 1),
      frequency: Frequency.month,
      everyN: 1,
      from: DateTime(2026, 6, 15),
      end: DateTime(2026, 5, 31),
    );
    expect(next, isNull);
  });
}
