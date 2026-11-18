import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/benchmarks.dart';
import '../database.dart';
import 'plan_repository.dart';

/// Reglas orientativas de salud financiera.
class BenchmarkRepository {
  BenchmarkRepository(this.db);
  final AppDatabase db;

  Stream<List<Benchmark>> watchAll() {
    final q = db.select(db.benchmarks)
      ..where((b) => b.deletedAt.isNull())
      ..orderBy([(b) => OrderingTerm(expression: b.sortOrder), (b) => OrderingTerm(expression: b.name)]);
    return q.watch().map((rows) => rows.map(benchmarkOf).toList());
  }

  Future<String> create({
    required String name,
    required String emoji,
    BenchmarkMetric metric = BenchmarkMetric.categories,
    int? minPct,
    int? maxPct,
    Set<String> categoryIds = const {},
  }) async {
    final now = Dates.nowIso();
    final id = newId();
    final order = await db.customSelect('SELECT COALESCE(MAX(sort_order), 0) AS m FROM benchmarks').getSingle();
    await db.into(db.benchmarks).insert(BenchmarksCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          name: name.trim(),
          emoji: emoji,
          metric: Value(metric),
          minPct: Value(minPct),
          maxPct: Value(maxPct),
          categoryIds: Value(encodeIds(categoryIds)),
          sortOrder: Value(order.read<int>('m') + 1),
        ));
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required String emoji,
    int? minPct,
    int? maxPct,
    required Set<String> categoryIds,
  }) {
    return (db.update(db.benchmarks)..where((b) => b.id.equals(id))).write(BenchmarksCompanion(
      name: Value(name.trim()),
      emoji: Value(emoji),
      minPct: Value(minPct),
      maxPct: Value(maxPct),
      categoryIds: Value(encodeIds(categoryIds)),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  /// Vuelve a las reglas iniciales, eligiendo de nuevo sus categorías.
  Future<void> resetDefaults() => seedDefaultBenchmarks(db, reset: true);

  Future<void> softDelete(String id) {
    final now = Dates.nowIso();
    return (db.update(db.benchmarks)..where((b) => b.id.equals(id)))
        .write(BenchmarksCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}

String encodeIds(Set<String> ids) => jsonEncode(ids.toList()..sort());

Set<String> decodeIds(String text) {
  try {
    final list = jsonDecode(text);
    return list is List ? {for (final v in list) if (v is String) v} : <String>{};
  } on FormatException {
    return <String>{};
  }
}

Benchmark benchmarkOf(BenchmarkRow r) => Benchmark(
      id: r.id,
      name: r.name,
      emoji: r.emoji,
      metric: r.metric,
      minPct: r.minPct,
      maxPct: r.maxPct,
      categoryIds: decodeIds(r.categoryIds),
      sortOrder: r.sortOrder,
    );

/// Crea las reglas iniciales (orientativas) si no hay ninguna. Las
/// categorías se eligen por id o por nombre entre las que ya existen; el
/// usuario las revisa después en "Salud financiera".
///
/// Con [reset], vuelve a dejar las reglas iniciales como al principio (y
/// recupera las borradas), sin tocar las que haya creado el usuario.
Future<void> seedDefaultBenchmarks(AppDatabase db, {bool reset = false}) async {
  final existing = await db.customSelect('SELECT COUNT(*) AS n FROM benchmarks').getSingle();
  if (!reset && existing.read<int>('n') > 0) return;
  final rows = await (db.select(db.categories)..where((c) => c.deletedAt.isNull())).get();
  final specs = defaultBenchmarks(planCategoriesOf({for (final c in rows) c.id: c}).values);
  final now = Dates.nowIso();
  await db.batch((b) {
    b.insertAllOnConflictUpdate(db.benchmarks, [
      for (var i = 0; i < specs.length; i++)
        BenchmarksCompanion.insert(
          // Ids fijos, como las categorías por defecto, para no duplicar al sincronizar.
          id: 'bm-${specs[i].key}',
          createdAt: now,
          updatedAt: now,
          name: specs[i].name,
          emoji: specs[i].emoji,
          metric: Value(specs[i].metric),
          minPct: Value(specs[i].minPct),
          maxPct: Value(specs[i].maxPct),
          categoryIds: Value(encodeIds(specs[i].categoryIds)),
          sortOrder: Value(i),
          deletedAt: const Value(null),
        ),
    ]);
  });
}
