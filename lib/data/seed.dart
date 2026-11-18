import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../domain/models.dart';
import 'database.dart';

/// Paleta de colores para categorías (ARGB).
const categoryPalette = <int>[
  0xFF2E9E6B, 0xFFE8590C, 0xFF4C6EF5, 0xFFF0A202, 0xFF1C9CB8, 0xFFE5735C,
  0xFF7048E8, 0xFF6C7A89, 0xFFD6457A, 0xFFA0522D, 0xFF1971C2, 0xFF0B7285,
  0xFF3BC9DB, 0xFFF06595, 0xFF228BE6, 0xFF868E96,
];

/// Id fijo de la categoría donde se registran las compras del súper.
const supermarketCategoryId = 'exp-supermercado';

typedef _Cat = (String id, String name, String emoji, int color, String? parent);

const List<_Cat> _expense = [
  ('exp-supermercado', 'Supermercado', '🛒', 0xFF2E9E6B, null),
  ('exp-restaurantes', 'Restaurantes y comidas', '🍽️', 0xFFE8590C, null),
  ('exp-vivienda', 'Alquiler o hipoteca', '🏠', 0xFF4C6EF5, null),
  ('exp-facturas', 'Facturas', '📄', 0xFFF0A202, null),
  ('exp-luz', 'Luz', '💡', 0xFFF0A202, 'exp-facturas'),
  ('exp-agua', 'Agua', '💧', 0xFF1C9CB8, 'exp-facturas'),
  ('exp-gas', 'Gas', '🔥', 0xFFE5735C, 'exp-facturas'),
  ('exp-internet', 'Internet y teléfono', '🌐', 0xFF7048E8, 'exp-facturas'),
  ('exp-transporte', 'Transporte y gasolina', '🚗', 0xFF6C7A89, null),
  ('exp-salud', 'Salud y farmacia', '🏥', 0xFFD6457A, null),
  ('exp-ocio', 'Ocio y entretenimiento', '🎬', 0xFF7048E8, null),
  ('exp-ropa', 'Ropa', '👕', 0xFFF06595, null),
  ('exp-mascotas', 'Mascotas', '🐶', 0xFFA0522D, null),
  ('exp-educacion', 'Educación', '📚', 0xFF1971C2, null),
  ('exp-impuestos', 'Impuestos', '🧾', 0xFF495057, null),
  ('exp-seguros', 'Seguros', '🛡️', 0xFF0B7285, null),
  ('exp-limpieza', 'Limpieza y hogar', '🧹', 0xFF3BC9DB, null),
  ('exp-regalos', 'Regalos', '🎁', 0xFFF06595, null),
  ('exp-viajes', 'Viajes', '✈️', 0xFF228BE6, null),
  ('exp-otros', 'Otros gastos', '📦', 0xFF868E96, null),
];

const List<_Cat> _income = [
  ('inc-nomina', 'Nómina', '💼', 0xFF2E9E6B, null),
  ('inc-autonomo', 'Trabajo autónomo', '💻', 0xFF1971C2, null),
  ('inc-inversiones', 'Inversiones', '💰', 0xFFF0A202, null),
  ('inc-alquileres', 'Alquileres recibidos', '🏠', 0xFF4C6EF5, null),
  ('inc-regalos', 'Regalos recibidos', '🎁', 0xFFF06595, null),
  ('inc-devoluciones', 'Devoluciones', '💸', 0xFF1C9CB8, null),
  ('inc-intereses', 'Intereses bancarios', '🏦', 0xFF0B7285, null),
  ('inc-otros', 'Otros ingresos', '📦', 0xFF868E96, null),
];

const List<_Cat> _product = [
  ('prod-fruta', 'Frutas y verduras', '🥦', 0xFF2E9E6B, null),
  ('prod-carne', 'Carnicería', '🥩', 0xFFD6457A, null),
  ('prod-pescado', 'Pescadería', '🐟', 0xFF1C9CB8, null),
  ('prod-lacteos', 'Lácteos', '🥛', 0xFF4C6EF5, null),
  ('prod-pan', 'Panadería', '🍞', 0xFFA0522D, null),
  ('prod-conservas', 'Conservas', '🥫', 0xFFE8590C, null),
  ('prod-limpieza', 'Limpieza', '🧽', 0xFF3BC9DB, null),
  ('prod-higiene', 'Higiene', '🧴', 0xFF7048E8, null),
  ('prod-bebidas', 'Bebidas', '🥤', 0xFFF0A202, null),
  ('prod-otros', 'Otros', '🍫', 0xFF868E96, null),
];

const _paymentMethods = [
  ('pm-tarjeta', 'Tarjeta', '💳'),
  ('pm-efectivo', 'Efectivo', '💶'),
  ('pm-bizum', 'Bizum', '📱'),
  ('pm-transferencia', 'Transferencia', '🏦'),
  ('pm-domiciliacion', 'Domiciliación', '🧾'),
];

/// Datos iniciales. Usa ids fijos para que, al sincronizar en el futuro, dos
/// dispositivos no dupliquen las categorías por defecto.
Future<void> seedDatabase(AppDatabase db) async {
  final now = Dates.nowIso();

  CategoriesCompanion cat(_Cat c, CategoryKind kind, int order) => CategoriesCompanion.insert(
        id: c.$1,
        createdAt: now,
        updatedAt: now,
        kind: kind,
        name: c.$2,
        emoji: c.$3,
        color: c.$4,
        parentId: Value(c.$5),
        sortOrder: Value(order),
      );

  await db.batch((b) {
    b.insertAll(db.categories, [
      for (var i = 0; i < _expense.length; i++) cat(_expense[i], CategoryKind.expense, i),
      for (var i = 0; i < _income.length; i++) cat(_income[i], CategoryKind.income, i),
      for (var i = 0; i < _product.length; i++) cat(_product[i], CategoryKind.product, i),
    ]);
    b.insertAll(db.paymentMethods, [
      for (var i = 0; i < _paymentMethods.length; i++)
        PaymentMethodsCompanion.insert(
          id: _paymentMethods[i].$1,
          createdAt: now,
          updatedAt: now,
          name: _paymentMethods[i].$2,
          emoji: _paymentMethods[i].$3,
          sortOrder: Value(i),
        ),
    ]);
    b.insertAll(db.settings, [
      SettingsCompanion.insert(key: 'theme_mode', value: 'system', updatedAt: now),
    ]);
  });
  await assignDefaultGroups(db);
}

/// Bloque de la regla 50/30/20 de las categorías por defecto. "Otros gastos"
/// queda sin clasificar a propósito.
const _defaultGroups = <String, BudgetGroup>{
  'exp-supermercado': BudgetGroup.variable,
  'exp-restaurantes': BudgetGroup.leisure,
  'exp-vivienda': BudgetGroup.fixed,
  'exp-luz': BudgetGroup.variable,
  'exp-agua': BudgetGroup.variable,
  'exp-gas': BudgetGroup.variable,
  'exp-internet': BudgetGroup.fixed,
  'exp-transporte': BudgetGroup.variable,
  'exp-salud': BudgetGroup.variable,
  'exp-ocio': BudgetGroup.leisure,
  'exp-ropa': BudgetGroup.discretionary,
  'exp-mascotas': BudgetGroup.variable,
  'exp-educacion': BudgetGroup.fixed,
  'exp-impuestos': BudgetGroup.fixed,
  'exp-seguros': BudgetGroup.fixed,
  'exp-limpieza': BudgetGroup.variable,
  'exp-regalos': BudgetGroup.discretionary,
  'exp-viajes': BudgetGroup.leisure,
};

/// Categorías por defecto que pasan de "Prescindible" a "Ocio".
const leisureDefaultIds = ['exp-ocio', 'exp-viajes', 'exp-restaurantes'];

/// Clave de ajustes que marca que ya se hizo el paso a "Ocio".
const _leisureDoneKey = 'leisure_defaults_done';

/// Pasa a "Ocio" las categorías de ocio, viajes y restaurantes, pero solo si
/// siguen en su bloque por defecto ("Prescindible"): si el usuario les puso
/// otro, se respeta. Se hace una única vez (la columna es texto, así que no
/// hace falta migración de esquema): si después el usuario las vuelve a
/// poner en "Prescindible", ya no se tocan.
Future<void> assignLeisureDefaults(AppDatabase db) async {
  final done = await (db.select(db.settings)..where((s) => s.key.equals(_leisureDoneKey))).getSingleOrNull();
  if (done != null) return;
  final now = Dates.nowIso();
  await db.transaction(() async {
    await (db.update(db.categories)
          ..where((c) => c.id.isIn(leisureDefaultIds) & c.budgetGroup.equalsValue(BudgetGroup.discretionary)))
        .write(CategoriesCompanion(budgetGroup: const Value(BudgetGroup.leisure), updatedAt: Value(now)));
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: _leisureDoneKey, value: '1', updatedAt: now),
        );
  });
}

/// Asigna su bloque a las categorías por defecto que aún no tienen uno
/// (instalación nueva y migración desde la versión 1).
Future<void> assignDefaultGroups(AppDatabase db) async {
  final now = Dates.nowIso();
  await db.batch((b) {
    for (final e in _defaultGroups.entries) {
      b.update(
        db.categories,
        CategoriesCompanion(budgetGroup: Value(e.value), updatedAt: Value(now)),
        where: (c) => c.id.equals(e.key) & c.budgetGroup.isNull(),
      );
    }
  });
}
