import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/benchmarks.dart';
import '../domain/models.dart';
import 'repositories/benchmark_repository.dart';
import 'seed.dart';

// Archivo generado por drift_dev. Se crea con:
//   dart run build_runner build --delete-conflicting-outputs
part 'database.g.dart';

/// Columnas comunes a todas las tablas sincronizables:
/// id UUID, fechas de creación/modificación (UTC) y borrado lógico.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

@DataClassName('CategoryRow')
class Categories extends Table with SyncColumns {
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get emoji => text()();
  IntColumn get color => integer()();

  /// Grupo opcional (p. ej. Luz, Agua y Gas dentro de Facturas).
  TextColumn get parentId => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  // --- v2: plan anual
  /// Bloque del plan (necesario fijo/variable, prescindible, ocio, ahorro). Solo
  /// gastos; si es null se hereda del grupo padre.
  TextColumn get budgetGroup => textEnum<BudgetGroup>().nullable()();

  /// Movimiento de ahorro: en un gasto, dinero que va a ahorro o patrimonio
  /// (plan de pensiones, hipoteca...); en un ingreso, dinero que sale de tus
  /// ahorros (no es un ingreso real). Sirve para calcular el ahorro real.
  BoolColumn get isSavings => boolean().withDefault(const Constant(false))();

  // --- v3: previsión de saldo
  /// Día del mes (1-31) en que suele cargarse o cobrarse. Si el mes es más
  /// corto, se usa su último día. Null = sin día fijo.
  // Así declara drift un CHECK sobre la propia columna (el generador no
  // ejecuta el getter, solo lo lee): el aviso de getter recursivo no aplica.
  // ignore: recursive_getters
  IntColumn get expectedDay => integer().nullable().check(expectedDay.isBetweenValues(1, 31))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get emoji => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecurringRuleRow')
class RecurringRules extends Table with SyncColumns {
  TextColumn get type => textEnum<TxType>()();

  /// Importe fijo (modo auto) o estimado (modo confirm).
  IntColumn get amountCents => integer()();
  TextColumn get description => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get paymentMethodId => text().nullable().references(PaymentMethods, #id)();
  TextColumn get frequency => textEnum<Frequency>()();
  IntColumn get everyN => integer().withDefault(const Constant(1))();

  /// "AAAA-MM-DD"; fija también el día de cobro.
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  TextColumn get mode => textEnum<RecurringMode>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (amount_cents > 0)',
        'CHECK (every_n >= 1)',
      ];
}

@DataClassName('TransactionRow')
class Transactions extends Table with SyncColumns {
  TextColumn get type => textEnum<TxType>()();
  IntColumn get amountCents => integer()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Descripción y notas normalizadas (sin tildes ni mayúsculas) para buscar.
  TextColumn get searchText => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get paymentMethodId => text().nullable().references(PaymentMethods, #id)();

  /// Día local "AAAA-MM-DD" y hora opcional "HH:MM".
  TextColumn get occurredOn => text()();
  TextColumn get timeOfDay => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => textEnum<TxStatus>().withDefault(const Constant('confirmed'))();

  /// Si lo generó una regla recurrente: la regla y la fecha de la ocurrencia.
  TextColumn get recurringRuleId => text().nullable().references(RecurringRules, #id)();
  TextColumn get occurrenceDate => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (amount_cents > 0)',
        'CHECK ((recurring_rule_id IS NULL) = (occurrence_date IS NULL))',
      ];
}

@DataClassName('BudgetRow')
class Budgets extends Table with SyncColumns {
  /// Null = presupuesto global de todos los gastos.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get period => textEnum<BudgetPeriod>()();
  IntColumn get amountCents => integer()();
  IntColumn get alertPct => integer().withDefault(const Constant(80))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (amount_cents > 0)',
        'CHECK (alert_pct BETWEEN 1 AND 100)',
      ];
}

@DataClassName('ShoppingListRow')
class ShoppingLists extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get status => textEnum<ShoppingListStatus>().withDefault(const Constant('active'))();
  TextColumn get completedAt => text().nullable()();

  /// Gasto creado al finalizar la compra.
  TextColumn get transactionId => text().nullable().references(Transactions, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ShoppingItemRow')
class ShoppingItems extends Table with SyncColumns {
  TextColumn get listId => text().references(ShoppingLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// Cantidad en milésimas: 1,5 kg = 1500.
  IntColumn get quantityMilli => integer().withDefault(const Constant(1000))();
  TextColumn get unit => textEnum<ItemUnit>().withDefault(const Constant('ud'))();

  /// Precios por unidad de medida (por unidad, por kg o por litro).
  IntColumn get estUnitPriceCents => integer().nullable()();
  IntColumn get realUnitPriceCents => integer().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();
  TextColumn get checkedAt => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (quantity_milli > 0)',
        'CHECK (est_unit_price_cents IS NULL OR est_unit_price_cents >= 0)',
        'CHECK (real_unit_price_cents IS NULL OR real_unit_price_cents >= 0)',
      ];
}

/// Importe previsto de una categoría en un mes contable (el "presupuestado"
/// de cada fila y mes del Excel).
@DataClassName('PlanEntryRow')
class PlanEntries extends Table with SyncColumns {
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get amountCents => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (month BETWEEN 1 AND 12)',
        'CHECK (amount_cents >= 0)',
      ];
}

/// Un bien (plan de pensiones, acciones, cuenta de ahorro...) o una deuda.
@DataClassName('AssetRow')
class Assets extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get emoji => text()();
  TextColumn get kind => textEnum<AssetKind>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Valor de un bien o deuda en un mes contable (se arrastra a los meses
/// siguientes hasta que se anota uno nuevo).
@DataClassName('AssetValueRow')
class AssetValues extends Table with SyncColumns {
  TextColumn get assetId => text().references(Assets, #id)();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get valueCents => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (month BETWEEN 1 AND 12)',
        'CHECK (value_cents >= 0)',
      ];
}

/// Regla orientativa de salud financiera: qué parte de los ingresos debería
/// ir, como mucho o como poco, a un concepto (vivienda, alimentación...).
@DataClassName('BenchmarkRow')
class Benchmarks extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get emoji => text()();
  TextColumn get metric => textEnum<BenchmarkMetric>().withDefault(const Constant('categories'))();

  /// Porcentajes de los ingresos propios (cualquiera puede ser null).
  IntColumn get minPct => integer().nullable()();
  IntColumn get maxPct => integer().nullable()();

  /// Ids de las categorías que incluye, como lista JSON ("["exp-luz", ...]").
  /// Sus subcategorías cuentan también.
  TextColumn get categoryIds => text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (min_pct IS NULL OR min_pct BETWEEN 0 AND 100)',
        'CHECK (max_pct IS NULL OR max_pct BETWEEN 0 AND 100)',
      ];
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Índices parciales y triggers que el DSL de Dart no expresa directamente.
const List<String> _extraSql = [
  // Impide duplicar una ocurrencia recurrente, incluso si se borró (borrado
  // lógico): por eso NO filtra deleted_at.
  'CREATE UNIQUE INDEX IF NOT EXISTS ux_tx_occurrence '
      'ON transactions (recurring_rule_id, occurrence_date) WHERE recurring_rule_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS ix_tx_date ON transactions (occurred_on) WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS ix_tx_category_date ON transactions (category_id, occurred_on) WHERE deleted_at IS NULL',
  "CREATE UNIQUE INDEX IF NOT EXISTS ux_budget ON budgets (COALESCE(category_id, ''), period) WHERE deleted_at IS NULL",
  'CREATE INDEX IF NOT EXISTS ix_items_list ON shopping_items (list_id)',
  // La categoría de un movimiento debe ser del mismo tipo (gasto/ingreso).
  "CREATE TRIGGER IF NOT EXISTS tx_category_kind_insert BEFORE INSERT ON transactions "
      "WHEN (SELECT kind FROM categories WHERE id = NEW.category_id) <> NEW.type "
      "BEGIN SELECT RAISE(ABORT, 'category kind does not match transaction type'); END",
  "CREATE TRIGGER IF NOT EXISTS tx_category_kind_update BEFORE UPDATE OF category_id, type ON transactions "
      "WHEN (SELECT kind FROM categories WHERE id = NEW.category_id) <> NEW.type "
      "BEGIN SELECT RAISE(ABORT, 'category kind does not match transaction type'); END",
  ..._v2Sql,
];

/// Índices de las tablas añadidas en la versión 2 del esquema.
const List<String> _v2Sql = [
  'CREATE UNIQUE INDEX IF NOT EXISTS ux_plan_entry ON plan_entries (category_id, year, month) WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS ix_plan_year ON plan_entries (year) WHERE deleted_at IS NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS ux_asset_value ON asset_values (asset_id, year, month) WHERE deleted_at IS NULL',
];

@DriftDatabase(tables: [
  Categories,
  PaymentMethods,
  RecurringRules,
  Transactions,
  Budgets,
  ShoppingLists,
  ShoppingItems,
  Settings,
  PlanEntries,
  Assets,
  AssetValues,
  Benchmarks,
])
class AppDatabase extends _$AppDatabase {
  /// [executor] permite pasar una base de datos en memoria en los tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final sql in _extraSql) {
            await customStatement(sql);
          }
          await seedDatabase(this);
          await seedDefaultBenchmarks(this);
        },
        // Cada versión añade sus cambios sin tocar los datos existentes.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(categories, categories.budgetGroup);
            await m.addColumn(categories, categories.isSavings);
            await m.createTable(planEntries);
            await m.createTable(assets);
            await m.createTable(assetValues);
            for (final sql in _v2Sql) {
              await customStatement(sql);
            }
            await assignDefaultGroups(this);
          }
          if (from < 3) {
            await m.addColumn(categories, categories.expectedDay);
          }
          if (from < 4) {
            await m.createTable(benchmarks);
            await seedDefaultBenchmarks(this);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Ajustes de datos de una sola vez que no cambian el esquema.
          await assignLeisureDefaults(this);
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: databaseFileName,
      native: const DriftNativeOptions(databasePath: databaseFilePath),
    );
  }
}

const databaseFileName = 'hogar_en_cifras';

/// Ruta del archivo de la base de datos en el móvil.
Future<String> databaseFilePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, '$databaseFileName.sqlite');
}
