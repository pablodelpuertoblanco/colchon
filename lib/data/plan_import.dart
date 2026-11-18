import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/text.dart';
import '../domain/models.dart';
import 'database.dart';
import 'repositories/asset_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Importación de un plan anual: categorías con su bloque 50/30/20, lo previsto
// mes a mes, bienes del patrimonio y ajustes (día de inicio de mes, saldo
// mínimo, objetivos). El contenido sale del Excel del usuario (ver
// plan_excel.dart).
//
// Importar dos veces el mismo archivo no duplica nada: las categorías y los
// bienes se reconocen por nombre, y lo previsto se sobrescribe. Lo que el
// archivo no dice (emoji, color, bloque, si cuenta como ahorro, grupo) se
// respeta en las categorías que ya existían.
// ---------------------------------------------------------------------------

class PlanImportCategory {
  const PlanImportCategory({
    required this.key,
    required this.kind,
    required this.name,
    this.id,
    this.emoji,
    this.color,
    this.parentKey,
    this.group,
    this.isSavings,
    this.plan,
  });

  final String key;
  final String? id;
  final CategoryKind kind;
  final String name;

  /// Null = el archivo no lo indica (se mantiene el actual o uno por defecto).
  final String? emoji;
  final int? color;
  final String? parentKey;
  final BudgetGroup? group;
  final bool? isSavings;

  /// Céntimos previstos de enero a diciembre (null = sin plan).
  final List<int>? plan;
}

class PlanImportAsset {
  const PlanImportAsset({required this.name, required this.emoji, required this.kind, required this.values});
  final String name;
  final String emoji;
  final AssetKind kind;
  final List<({int year, int month, int cents})> values;
}

/// Contenido de un plan ya leído y validado.
class PlanImportFile {
  const PlanImportFile({
    required this.title,
    required this.year,
    required this.categories,
    required this.assets,
    this.hasGroups = true,
    this.monthStartDay,
    this.minBalanceCents,
    this.targets,
  });

  final String title;
  final int year;
  final List<PlanImportCategory> categories;
  final List<PlanImportAsset> assets;

  /// Si el archivo indica los grupos. Si no, no se toca el grupo de las
  /// categorías que ya existían.
  final bool hasGroups;
  final int? monthStartDay;
  final int? minBalanceCents;
  final RuleTargets? targets;

  int get plannedCategories => categories.where((c) => c.plan != null).length;

  int plannedTotal(CategoryKind kind) => categories
      .where((c) => c.kind == kind && c.plan != null)
      .fold(0, (s, c) => s + c.plan!.fold<int>(0, (a, b) => a + b));

  bool get hasSettings => monthStartDay != null || minBalanceCents != null || targets != null;
}

/// Qué pasará al importar (para enseñarlo antes de confirmar).
class PlanImportPreview {
  const PlanImportPreview({
    required this.file,
    required this.newCategories,
    required this.existingCategories,
    required this.yearHasPlan,
    required this.unusedDefaults,
  });
  final PlanImportFile file;
  final int newCategories;
  final int existingCategories;
  final bool yearHasPlan;

  /// Categorías actuales sin movimientos que no están en el plan (se pueden archivar).
  final int unusedDefaults;
}

class PlanImportResult {
  const PlanImportResult({required this.created, required this.updated, required this.entries, required this.assets, required this.archived});
  final int created;
  final int updated;
  final int entries;
  final int assets;
  final int archived;
}

class PlanImporter {
  PlanImporter(this.db);
  final AppDatabase db;

  static const defaultColor = 0xFF868E96;

  /// Emoji para una categoría nueva si el archivo no trae uno.
  static String defaultEmoji(PlanImportCategory c) => c.plan == null && c.key.startsWith('grupo:')
      ? '📁'
      : c.kind == CategoryKind.income
          ? '💶'
          : '📦';

  late final _plans = PlanRepository(db);
  late final _assets = AssetRepository(db);
  late final _settings = SettingsRepository(db);

  Future<List<CategoryRow>> _categories() =>
      (db.select(db.categories)..where((c) => c.deletedAt.isNull() & c.kind.equalsValue(CategoryKind.product).not())).get();

  CategoryRow? _match(PlanImportCategory c, List<CategoryRow> existing) {
    if (c.id != null) {
      final byId = existing.where((e) => e.id == c.id && e.kind == c.kind).firstOrNull;
      if (byId != null) return byId;
    }
    final wanted = normalizeForSearch(c.name);
    return existing.where((e) => e.kind == c.kind && normalizeForSearch(e.name) == wanted).firstOrNull;
  }

  /// Ids de categorías con movimientos o recurrentes (no se pueden archivar).
  Future<Set<String>> _usedCategoryIds() async {
    final rows = await db.customSelect(
      'SELECT category_id AS id FROM transactions WHERE deleted_at IS NULL '
      'UNION SELECT category_id FROM recurring_rules WHERE deleted_at IS NULL',
      readsFrom: {db.transactions, db.recurringRules},
    ).get();
    return {for (final r in rows) r.read<String>('id')};
  }

  /// Categorías que se archivarían: no están en el plan, no tienen
  /// movimientos ni recurrentes y no son grupo de nada que siga activo.
  Future<Set<String>> _archivable(PlanImportFile file, List<CategoryRow> existing, Set<String> matchedIds) async {
    final used = await _usedCategoryIds();
    final candidates = {
      for (final c in existing)
        if (!c.isArchived && !matchedIds.contains(c.id) && !used.contains(c.id)) c.id,
    };
    // Un grupo solo se archiva si todas sus subcategorías se archivan también.
    for (final c in existing) {
      if (c.parentId != null && !candidates.contains(c.id) && !c.isArchived) candidates.remove(c.parentId);
    }
    return candidates;
  }

  Future<PlanImportPreview> preview(PlanImportFile file) async {
    final existing = await _categories();
    final matched = <String>{};
    var newCount = 0;
    for (final c in file.categories) {
      final m = _match(c, existing);
      if (m == null) {
        newCount++;
      } else {
        matched.add(m.id);
      }
    }
    return PlanImportPreview(
      file: file,
      newCategories: newCount,
      existingCategories: matched.length,
      yearHasPlan: await _plans.hasYear(file.year),
      unusedDefaults: (await _archivable(file, existing, matched)).length,
    );
  }

  Future<PlanImportResult> apply(PlanImportFile file, {bool applySettings = true, bool archiveUnused = true}) {
    return db.transaction(() async {
      final now = Dates.nowIso();
      final existing = await _categories();
      final hasChildren = {for (final c in existing) if (c.parentId != null) c.parentId!};
      final idOfKey = <String, String>{};
      var created = 0, updated = 0, entries = 0, assetCount = 0, archived = 0;

      // Primero los grupos y luego sus subcategorías.
      final ordered = [
        ...file.categories.where((c) => c.parentKey == null),
        ...file.categories.where((c) => c.parentKey != null),
      ];
      for (final c in ordered) {
        final order = file.categories.indexOf(c);
        final match = _match(c, existing);
        var parentId = c.parentKey == null ? null : idOfKey[c.parentKey];
        // Solo un nivel de anidación: una categoría que ya es grupo no se mete en otro.
        if (match != null && hasChildren.contains(match.id)) parentId = null;
        if (match == null) {
          final id = newId();
          await db.into(db.categories).insert(CategoriesCompanion.insert(
                id: id,
                createdAt: now,
                updatedAt: now,
                kind: c.kind,
                name: c.name,
                emoji: c.emoji ?? defaultEmoji(c),
                color: c.color ?? defaultColor,
                parentId: Value(parentId),
                sortOrder: Value(order),
                budgetGroup: Value(c.group),
                isSavings: Value(c.isSavings ?? false),
              ));
          idOfKey[c.key] = id;
          created++;
        } else {
          final emoji = c.emoji;
          final color = c.color;
          final isSavings = c.isSavings;
          await (db.update(db.categories)..where((x) => x.id.equals(match.id))).write(CategoriesCompanion(
            name: Value(c.name),
            emoji: emoji == null ? const Value.absent() : Value(emoji),
            color: color == null ? const Value.absent() : Value(color),
            parentId: file.hasGroups ? Value(parentId) : const Value.absent(),
            sortOrder: Value(order),
            budgetGroup: c.group == null ? const Value.absent() : Value(c.group),
            isSavings: isSavings == null ? const Value.absent() : Value(isSavings),
            isArchived: const Value(false),
            updatedAt: Value(now),
          ));
          idOfKey[c.key] = match.id;
          updated++;
        }
      }

      // El resto de categorías va detrás, en su orden, y las que no se usan
      // se archivan (siguen existiendo y se pueden recuperar).
      final matchedIds = idOfKey.values.toSet();
      final toArchive = archiveUnused ? await _archivable(file, existing, matchedIds) : <String>{};
      for (final c in existing) {
        if (matchedIds.contains(c.id)) continue;
        await (db.update(db.categories)..where((x) => x.id.equals(c.id))).write(CategoriesCompanion(
          sortOrder: Value(1000 + c.sortOrder),
          isArchived: toArchive.contains(c.id) ? const Value(true) : const Value.absent(),
          updatedAt: Value(now),
        ));
        if (toArchive.contains(c.id)) archived++;
      }

      // Lo previsto, mes a mes (sobrescribe lo que hubiera para estas categorías).
      for (final c in file.categories) {
        final plan = c.plan;
        if (plan == null) continue;
        for (var m = 1; m <= 12; m++) {
          await _plans.writeEntry(idOfKey[c.key]!, file.year, m, plan[m - 1]);
          if (plan[m - 1] > 0) entries++;
        }
      }

      // Patrimonio: no pisa valores que ya hayas anotado ese mes.
      for (final a in file.assets) {
        final found = await _assets.findByName(a.name);
        final id = found?.id ?? await _assets.create(name: a.name, emoji: a.emoji, kind: a.kind);
        if (found == null) assetCount++;
        for (final v in a.values) {
          final has = await (db.select(db.assetValues)
                ..where((x) => x.assetId.equals(id) & x.year.equals(v.year) & x.month.equals(v.month) & x.deletedAt.isNull()))
              .getSingleOrNull();
          if (has == null) await _assets.writeValue(id, v.year, v.month, v.cents);
        }
      }

      if (applySettings) {
        if (file.monthStartDay != null) await _settings.set(SettingKeys.monthStartDay, '${file.monthStartDay}');
        if (file.minBalanceCents != null) await _settings.set(SettingKeys.minBalanceCents, '${file.minBalanceCents}');
        if (file.targets != null) await _settings.set(SettingKeys.ruleTargets, file.targets!.serialize());
      }

      return PlanImportResult(created: created, updated: updated, entries: entries, assets: assetCount, archived: archived);
    });
  }
}
