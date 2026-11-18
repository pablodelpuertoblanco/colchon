import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/data/database.dart';
import 'package:hogar_en_cifras/data/repositories/benchmark_repository.dart';
import 'package:hogar_en_cifras/data/repositories/category_repository.dart';
import 'package:hogar_en_cifras/data/repositories/recurring_repository.dart';
import 'package:hogar_en_cifras/data/repositories/transaction_repository.dart';
import 'package:hogar_en_cifras/data/seed.dart';
import 'package:hogar_en_cifras/domain/models.dart';

/// Pruebas de la base de datos real (SQLite en memoria): semilla y pasos de
/// datos que se ejecutan al abrir la app con datos existentes.
void main() {
  // Cada test abre su propia base de datos (en memoria o en un archivo
  // temporal): no comparten ejecutor, así que el aviso de drift no aplica.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<BudgetGroup?> groupOf(String id) async =>
      (await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle()).budgetGroup;

  Future<void> setGroup(String id, BudgetGroup? g) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(budgetGroup: Value(g)));

  test('una instalación nueva trae ocio, viajes y restaurantes en "Ocio"', () async {
    for (final id in leisureDefaultIds) {
      expect(await groupOf(id), BudgetGroup.leisure, reason: id);
    }
    expect(await groupOf('exp-ropa'), BudgetGroup.discretionary);
  });

  test('con datos antiguos solo pasa a "Ocio" lo que seguía en el bloque por defecto, y una sola vez', () async {
    // Simula una base de datos anterior a "Ocio": el usuario cambió Viajes a
    // "Necesario fijo" y nunca se hizo el paso.
    await setGroup('exp-ocio', BudgetGroup.discretionary);
    await setGroup('exp-restaurantes', BudgetGroup.discretionary);
    await setGroup('exp-viajes', BudgetGroup.fixed);
    await (db.delete(db.settings)..where((s) => s.key.equals('leisure_defaults_done'))).go();

    await assignLeisureDefaults(db);
    expect(await groupOf('exp-ocio'), BudgetGroup.leisure);
    expect(await groupOf('exp-restaurantes'), BudgetGroup.leisure);
    expect(await groupOf('exp-viajes'), BudgetGroup.fixed);

    // Si después el usuario vuelve a ponerla en "Prescindible", se respeta.
    await setGroup('exp-ocio', BudgetGroup.discretionary);
    await assignLeisureDefaults(db);
    expect(await groupOf('exp-ocio'), BudgetGroup.discretionary);
  });

  test('el día habitual se guarda y solo admite días del 1 al 31', () async {
    final repo = CategoryRepository(db);
    await repo.setExpectedDay('exp-luz', 31);
    expect((await repo.getById('exp-luz'))!.expectedDay, 31);
    await repo.setExpectedDay('exp-luz', null);
    expect((await repo.getById('exp-luz'))!.expectedDay, isNull);
    expect(() => repo.setExpectedDay('exp-luz', 32), throwsA(anything));
  });

  test('las reglas de la previsión traen la última ocurrencia generada', () async {
    final repo = RecurringRepository(db);
    final id = await repo.create(RuleDraft(
      type: TxType.expense,
      amountCents: 1299,
      description: '',
      categoryId: 'exp-ocio',
      frequency: Frequency.month,
      everyN: 1,
      startDate: DateTime(2026, 9, 20),
      mode: RecurringMode.auto,
    ));
    await repo.generateDue(today: DateTime(2026, 11, 14));
    final rule = (await repo.watchForecastRules().first).single;
    expect(rule.id, id);
    expect(rule.label, 'Ocio y entretenimiento');
    expect(rule.lastGenerated, DateTime(2026, 10, 20));
    expect(rule.pendingUntil(DateTime(2026, 12, 31)), [DateTime(2026, 11, 20), DateTime(2026, 12, 20)]);
  });

  test('reglas: se editan, y "restablecer" recupera las iniciales sin tocar las propias', () async {
    final repo = BenchmarkRepository(db);
    final initial = await repo.watchAll().first;
    expect(initial.length, 6);
    await repo.update('bm-food', name: 'Comida', emoji: '🥕', maxPct: 20, categoryIds: {'exp-supermercado'});
    await repo.softDelete('bm-debt');
    final mine = await repo.create(name: 'Mascotas', emoji: '🐶', maxPct: 5, categoryIds: {'exp-mascotas'});

    var rules = await repo.watchAll().first;
    expect(rules.map((b) => b.name), containsAllInOrder(['Vivienda', 'Comida', 'Transporte', 'Mascotas']));
    expect(rules.any((b) => b.id == 'bm-debt'), isFalse);

    await repo.resetDefaults();
    rules = await repo.watchAll().first;
    expect(rules.length, 7);
    expect(rules.firstWhere((b) => b.id == 'bm-food').maxPct, 15);
    expect(rules.any((b) => b.id == 'bm-debt'), isTrue);
    expect(rules.firstWhere((b) => b.id == mine).categoryIds, {'exp-mascotas'});
  });

  test('una base de datos v2 (la del móvil) se actualiza conservando los datos', () async {
    final dir = Directory.systemTemp.createTempSync('hec_migracion');
    final file = File('${dir.path}/v2.sqlite');
    try {
      // Base de datos actual a la que se le quita lo añadido en v3 y v4 y se
      // marca como v2. Se crea una categoría con nombre de vivienda para ver
      // que las reglas iniciales la reconocen.
      final old = AppDatabase(NativeDatabase(file));
      await old.customStatement("UPDATE categories SET name = 'Mi luz' WHERE id = 'exp-luz'");
      await CategoryRepository(old).create(kind: CategoryKind.expense, name: 'IBI', emoji: '🧾', color: 0);
      await old.customStatement('ALTER TABLE categories DROP COLUMN expected_day');
      await old.customStatement('DROP TABLE benchmarks');
      await old.customStatement('PRAGMA user_version = 2');
      await old.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      final repo = CategoryRepository(upgraded);
      final luz = await repo.getById('exp-luz');
      expect(luz!.name, 'Mi luz');
      expect(luz.expectedDay, isNull);
      await repo.setExpectedDay('exp-luz', 10);
      expect((await repo.getById('exp-luz'))!.expectedDay, 10);

      final rules = await BenchmarkRepository(upgraded).watchAll().first;
      expect(rules.map((b) => b.name),
          ['Vivienda', 'Alimentación', 'Transporte', 'Ocio y prescindibles', 'Deudas', 'Ahorro']);
      final ibi = (await (upgraded.select(upgraded.categories)..where((c) => c.name.equals('IBI'))).getSingle()).id;
      expect(rules.first.categoryIds, containsAll(['exp-vivienda', 'exp-luz', 'exp-agua', 'exp-gas', ibi]));
      final version = await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), upgraded.schemaVersion);
      await upgraded.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('mover una categoría de ingreso a gasto se lleva sus subcategorías y sus movimientos', () async {
    final cats = CategoryRepository(db);
    final txs = TransactionRepository(db);
    // Como tras importar un Excel mal clasificado: "Mascotas" y "Arena" como ingresos.
    final mascotas = await cats.create(kind: CategoryKind.income, name: 'Mascotas', emoji: '🐾', color: 0);
    final arena =
        await cats.create(kind: CategoryKind.income, name: 'Arena', emoji: '🐈', color: 0, parentId: mascotas, isSavings: true);
    await txs.create(TxDraft(type: TxType.income, amountCents: 1500, categoryId: arena, date: DateTime(2026, 3, 5)));
    expect(await cats.countTransactionsWithChildren(mascotas), 1);

    await cats.move(mascotas, kind: CategoryKind.expense, group: BudgetGroup.variable);

    final m = (await cats.getById(mascotas))!;
    final a = (await cats.getById(arena))!;
    expect(m.kind, CategoryKind.expense);
    expect(m.budgetGroup, BudgetGroup.variable);
    expect(a.kind, CategoryKind.expense);
    expect(a.parentId, mascotas); // sigue dentro del grupo
    expect(a.budgetGroup, isNull); // toma el bloque del grupo
    expect(a.isSavings, isFalse); // "sale de tus ahorros" no vale para un gasto
    final tx = await (db.select(db.transactions)..where((t) => t.categoryId.equals(arena))).getSingle();
    expect(tx.type, TxType.expense);
  });

  test('mover de bloque sin cambiar de tipo solo cambia el bloque', () async {
    final cats = CategoryRepository(db);
    await cats.move('exp-ropa', kind: CategoryKind.expense, group: BudgetGroup.leisure);
    final c = (await cats.getById('exp-ropa'))!;
    expect(c.kind, CategoryKind.expense);
    expect(c.budgetGroup, BudgetGroup.leisure);
  });
}
