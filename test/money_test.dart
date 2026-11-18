import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/core/money.dart';

void main() {
  group('Money.parse', () {
    test('acepta coma decimal, punto decimal y miles', () {
      expect(Money.parse('12'), 1200);
      expect(Money.parse('12,5'), 1250);
      expect(Money.parse('12,05'), 1205);
      expect(Money.parse('12.50'), 1250);
      expect(Money.parse('1.234,56'), 123456);
      expect(Money.parse('1.234'), 123400);
      expect(Money.parse(' 7,99 € '), 799);
      expect(Money.parse('0,'), 0);
    });

    test('rechaza entradas no válidas', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1,234'), isNull); // tres decimales
    });
  });

  test('las sumas en céntimos son exactas', () {
    // En double: 0.1 + 0.2 = 0.30000000000000004
    expect(Money.parse('0,10')! + Money.parse('0,20')!, Money.parse('0,30'));
  });

  test('total de línea redondea al céntimo', () {
    expect(Money.lineTotal(1500, 240), 360); // 1,5 kg x 2,40 €
    expect(Money.lineTotal(333, 100), 33); // 0,333 x 1,00 € = 0,333 -> 0,33
    expect(Money.lineTotal(335, 100), 34); // 0,335 -> 0,34
    expect(Money.lineTotal(1000, 199), 199);
  });

  test('toPlain para CSV', () {
    expect(Money.toPlain(123456), '1234,56');
    expect(Money.toPlain(-505), '-5,05');
    expect(Money.toPlain(0), '0,00');
  });

  test('variación porcentual', () {
    expect(Money.percentChange(0, 100), isNull);
    expect(Money.percentChange(100, 150), 50);
    expect(Money.percentChange(200, 100), -50);
  });

  group('Quantity', () {
    test('parse y format', () {
      expect(Quantity.parse('1'), 1000);
      expect(Quantity.parse('1,5'), 1500);
      expect(Quantity.parse('0.25'), 250);
      expect(Quantity.parse('0'), isNull);
      expect(Quantity.parse('x'), isNull);
      expect(Quantity.format(1500), '1,5');
      expect(Quantity.format(2000), '2');
      expect(Quantity.format(250), '0,25');
    });
  });
}
