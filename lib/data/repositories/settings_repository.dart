import '../../core/dates.dart';
import '../database.dart';

/// Claves de ajustes guardados en la tabla settings.
class SettingKeys {
  SettingKeys._();
  static const themeMode = 'theme_mode'; // system | light | dark
  static const initialBalanceCents = 'initial_balance_cents';
  static const initialBalanceDate = 'initial_balance_date';
  static const monthStartDay = 'month_start_day'; // 1..28
  static const minBalanceCents = 'min_balance_cents';
  static const ruleTargets = 'rule_targets'; // "50,30,20"
  static const forecastMonths = 'forecast_months'; // 1..12
}

/// Ajustes clave-valor.
class SettingsRepository {
  SettingsRepository(this.db);
  final AppDatabase db;

  Stream<String?> watch(String key) {
    return (db.select(db.settings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((r) => r?.value);
  }

  Future<String?> get(String key) async {
    final row = await (db.select(db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
      return;
    }
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value, updatedAt: Dates.nowIso()),
        );
  }

  Future<void> setInitialBalance(int? cents, DateTime? date) async {
    if (cents == null || date == null) {
      await set(SettingKeys.initialBalanceCents, null);
      await set(SettingKeys.initialBalanceDate, null);
      return;
    }
    await db.transaction(() async {
      await set(SettingKeys.initialBalanceCents, '$cents');
      await set(SettingKeys.initialBalanceDate, Dates.key(date));
    });
  }
}
