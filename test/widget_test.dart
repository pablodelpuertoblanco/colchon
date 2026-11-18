// Este archivo existe para que `flutter create .` no genere el test de
// ejemplo del contador (que no compilaría con esta app).
import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/domain/models.dart';

void main() {
  test('las etiquetas de tipo están en español', () {
    expect(TxType.expense.label, 'Gasto');
    expect(TxType.income.label, 'Ingreso');
  });
}
