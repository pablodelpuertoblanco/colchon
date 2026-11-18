import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/text.dart';
import '../../domain/models.dart';
import '../../domain/net_worth.dart';
import '../database.dart';

/// Bienes y deudas del patrimonio con su valor mes a mes.
class AssetRepository {
  AssetRepository(this.db);
  final AppDatabase db;

  Stream<List<AssetInfo>> watchAssets() {
    final q = db.select(db.assets)
      ..where((a) => a.deletedAt.isNull())
      ..orderBy([(a) => OrderingTerm(expression: a.sortOrder), (a) => OrderingTerm(expression: a.name)]);
    return q.watch().map((rows) => [for (final r in rows) _info(r)]);
  }

  Stream<List<AssetValue>> watchValues() {
    final q = db.select(db.assetValues)..where((v) => v.deletedAt.isNull());
    return q.watch().map((rows) => [
          for (final r in rows) AssetValue(assetId: r.assetId, year: r.year, month: r.month, cents: r.valueCents),
        ]);
  }

  static AssetInfo _info(AssetRow r) => AssetInfo(
        id: r.id,
        name: r.name,
        emoji: r.emoji,
        kind: r.kind,
        sortOrder: r.sortOrder,
        isArchived: r.isArchived,
      );

  Future<String> create({required String name, required String emoji, required AssetKind kind}) async {
    final now = Dates.nowIso();
    final id = newId();
    final order = await db.customSelect('SELECT COALESCE(MAX(sort_order), 0) AS m FROM assets').getSingle();
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          name: name.trim(),
          emoji: emoji,
          kind: kind,
          sortOrder: Value(order.read<int>('m') + 1),
        ));
    return id;
  }

  Future<void> update(String id, {required String name, required String emoji, required AssetKind kind}) {
    return (db.update(db.assets)..where((a) => a.id.equals(id))).write(AssetsCompanion(
      name: Value(name.trim()),
      emoji: Value(emoji),
      kind: Value(kind),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> setArchived(String id, bool archived) {
    return (db.update(db.assets)..where((a) => a.id.equals(id)))
        .write(AssetsCompanion(isArchived: Value(archived), updatedAt: Value(Dates.nowIso())));
  }

  /// Borra el bien y todos sus valores (borrado lógico).
  Future<void> delete(String id) {
    return db.transaction(() async {
      final now = Dates.nowIso();
      await (db.update(db.assetValues)..where((v) => v.assetId.equals(id) & v.deletedAt.isNull()))
          .write(AssetValuesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (db.update(db.assets)..where((a) => a.id.equals(id)))
          .write(AssetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    });
  }

  /// Anota los valores de varios bienes en el mes [month] ({id: céntimos};
  /// null borra el valor de ese mes).
  Future<void> setValues(DateTime month, Map<String, int?> values) {
    return db.transaction(() async {
      for (final e in values.entries) {
        await writeValue(e.key, month.year, month.month, e.value);
      }
    });
  }

  /// Escribe un valor. Llamar siempre dentro de una transacción.
  Future<void> writeValue(String assetId, int year, int month, int? cents) async {
    final now = Dates.nowIso();
    final existing = await (db.select(db.assetValues)
          ..where((v) => v.assetId.equals(assetId) & v.year.equals(year) & v.month.equals(month) & v.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) {
      if (existing.valueCents == cents) return;
      await (db.update(db.assetValues)..where((v) => v.id.equals(existing.id))).write(cents == null
          ? AssetValuesCompanion(deletedAt: Value(now), updatedAt: Value(now))
          : AssetValuesCompanion(valueCents: Value(cents), updatedAt: Value(now)));
    } else if (cents != null) {
      await db.into(db.assetValues).insert(AssetValuesCompanion.insert(
            id: newId(),
            createdAt: now,
            updatedAt: now,
            assetId: assetId,
            year: year,
            month: month,
            valueCents: cents,
          ));
    }
  }

  /// Busca un bien por nombre (sin tildes ni mayúsculas) para no duplicarlo.
  Future<AssetRow?> findByName(String name) async {
    final all = await (db.select(db.assets)..where((a) => a.deletedAt.isNull())).get();
    final wanted = normalizeForSearch(name);
    for (final a in all) {
      if (normalizeForSearch(a.name) == wanted) return a;
    }
    return null;
  }
}
