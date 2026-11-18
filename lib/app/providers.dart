import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../data/backup_service.dart';
import '../data/database.dart';
import '../data/repositories/asset_repository.dart';
import '../data/repositories/benchmark_repository.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/shopping_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/benchmarks.dart';
import '../domain/forecast.dart';
import '../domain/models.dart';
import '../domain/net_worth.dart';
import '../domain/plan.dart';

// ===========================================================================
// Base de datos y repositorios (una única instancia para toda la app).
// En los tests se sustituye databaseProvider por una base de datos en memoria.
// ===========================================================================

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final categoryRepoProvider = Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));
final paymentMethodRepoProvider = Provider((ref) => PaymentMethodRepository(ref.watch(databaseProvider)));
final transactionRepoProvider = Provider((ref) => TransactionRepository(ref.watch(databaseProvider)));
final recurringRepoProvider = Provider((ref) => RecurringRepository(ref.watch(databaseProvider)));
final budgetRepoProvider = Provider((ref) => BudgetRepository(ref.watch(databaseProvider)));
final shoppingRepoProvider = Provider((ref) => ShoppingRepository(ref.watch(databaseProvider)));
final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider)));
final planRepoProvider = Provider((ref) => PlanRepository(ref.watch(databaseProvider)));
final assetRepoProvider = Provider((ref) => AssetRepository(ref.watch(databaseProvider)));
final benchmarkRepoProvider = Provider((ref) => BenchmarkRepository(ref.watch(databaseProvider)));

// ===========================================================================
// Datos en vivo. Cada StreamProvider se actualiza solo cuando cambia la base
// de datos, así las pantallas siempre muestran datos reales.
// ===========================================================================

typedef DateRange = ({String from, String to});

DateRange rangeOf(DateTime from, DateTime to) => (from: Dates.key(from), to: Dates.key(to));

// --- Categorías y métodos de pago

final categoriesProvider = StreamProvider.family<List<CategoryRow>, CategoryKind>(
  (ref, kind) => ref.watch(categoryRepoProvider).watchAll(kind: kind),
);

final selectableCategoriesProvider = StreamProvider.autoDispose.family<List<CategoryRow>, CategoryKind>(
  (ref, kind) => ref.watch(categoryRepoProvider).watchSelectable(kind),
);

/// Todas las categorías indexadas por id (para pintar nombres y emojis).
final categoryMapProvider = StreamProvider<Map<String, CategoryRow>>((ref) {
  return ref.watch(categoryRepoProvider).watchAll().map((list) => {for (final c in list) c.id: c});
});

final paymentMethodsProvider = StreamProvider<List<PaymentMethodRow>>(
  (ref) => ref.watch(paymentMethodRepoProvider).watchAll(),
);

// --- Ajustes

final settingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(settingsRepoProvider).watch(key),
);

final themeModeProvider = Provider<ThemeMode>((ref) {
  final value = ref.watch(settingProvider(SettingKeys.themeMode)).value;
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

final initialBalanceProvider = Provider<InitialBalance?>((ref) {
  final cents = ref.watch(settingProvider(SettingKeys.initialBalanceCents)).value;
  final date = ref.watch(settingProvider(SettingKeys.initialBalanceDate)).value;
  if (cents == null || date == null) return null;
  final parsed = int.tryParse(cents);
  if (parsed == null) return null;
  return InitialBalance(cents: parsed, date: Dates.parseKey(date));
});

/// Mes contable: día en que empieza cada mes (1 = mes natural).
final monthCycleProvider = Provider<MonthCycle>((ref) {
  return MonthCycle.parse(ref.watch(settingProvider(SettingKeys.monthStartDay)).value);
});

/// Objetivos de la regla 50/30/20.
final ruleTargetsProvider = Provider<RuleTargets>((ref) {
  return RuleTargets.parse(ref.watch(settingProvider(SettingKeys.ruleTargets)).value);
});

/// Saldo mínimo de seguridad ("mínimo del que no debo bajar"). Null = sin aviso.
final minBalanceProvider = Provider<int?>((ref) {
  return int.tryParse(ref.watch(settingProvider(SettingKeys.minBalanceCents)).value ?? '');
});

/// Dinero disponible = saldo inicial + ingresos − gastos desde esa fecha.
final availableBalanceProvider = StreamProvider.autoDispose<int?>((ref) {
  final initial = ref.watch(initialBalanceProvider);
  if (initial == null) return Stream.value(null);
  return ref
      .watch(transactionRepoProvider)
      .watchNetSince(Dates.key(initial.date))
      .map((net) => initial.cents + net);
});

// --- Movimientos

final filteredTxProvider = StreamProvider.autoDispose.family<List<TxView>, TxFilter>(
  (ref, filter) => ref.watch(transactionRepoProvider).watchFiltered(filter),
);

final recentTxProvider = StreamProvider.autoDispose<List<TxView>>(
  (ref) => ref.watch(transactionRepoProvider).watchRecent(5),
);

final dayTxProvider = StreamProvider.autoDispose.family<List<TxView>, String>(
  (ref, dayKey) => ref.watch(transactionRepoProvider).watchDay(dayKey),
);

final txByIdProvider = StreamProvider.autoDispose.family<TxView?, String>(
  (ref, id) => ref.watch(transactionRepoProvider).watchById(id),
);

final pendingTxProvider = StreamProvider.autoDispose<List<TxView>>(
  (ref) => ref.watch(transactionRepoProvider).watchPending(),
);

final totalsProvider = StreamProvider.autoDispose.family<Totals, DateRange>(
  (ref, r) => ref.watch(transactionRepoProvider).watchTotals(r.from, r.to),
);

final dailyTotalsProvider = StreamProvider.autoDispose.family<Map<String, DayTotal>, DateRange>(
  (ref, r) => ref.watch(transactionRepoProvider).watchDailyTotals(r.from, r.to),
);

typedef CategoryDailyArgs = ({String from, String to, String categoryId});

final categoryDailyTotalsProvider = StreamProvider.autoDispose.family<Map<String, DayTotal>, CategoryDailyArgs>(
  (ref, a) => ref.watch(transactionRepoProvider).watchDailyTotals(a.from, a.to, categoryId: a.categoryId),
);

typedef CategoryTotalsArgs = ({String from, String to, TxType type, bool grouped});

final categoryTotalsProvider = StreamProvider.autoDispose.family<List<CategoryTotal>, CategoryTotalsArgs>(
  (ref, a) => ref.watch(transactionRepoProvider).watchCategoryTotals(a.from, a.to, a.type, grouped: a.grouped),
);

// --- Presupuestos y recurrentes

final budgetsProvider = StreamProvider.autoDispose<List<BudgetView>>(
  (ref) => ref.watch(budgetRepoProvider).watchAll(ref.watch(monthCycleProvider)),
);

final rulesProvider = StreamProvider.autoDispose<List<RuleView>>(
  (ref) => ref.watch(recurringRepoProvider).watchAll(),
);

final upcomingProvider = StreamProvider.autoDispose.family<List<UpcomingCharge>, int>(
  (ref, days) => ref.watch(recurringRepoProvider).watchUpcoming(days),
);

// --- Plan anual (previsto vs real)

final plannedYearProvider = StreamProvider.autoDispose.family<List<PlannedAmount>, int>(
  (ref, year) => ref.watch(planRepoProvider).watchYear(year),
);

final realByDayProvider = StreamProvider.autoDispose.family<List<RealAmount>, DateRange>(
  (ref, r) => ref.watch(planRepoProvider).watchRealByDay(r.from, r.to),
);

/// El plan de un año contable con lo real de cada mes, ya calculado.
final planYearProvider = Provider.autoDispose.family<AsyncValue<PlanYear>, int>((ref, year) {
  final cycle = ref.watch(monthCycleProvider);
  final (from, to) = cycle.yearRange(year);
  final cats = ref.watch(categoryMapProvider);
  final planned = ref.watch(plannedYearProvider(year));
  final real = ref.watch(realByDayProvider(rangeOf(from, to)));
  for (final a in <AsyncValue<Object>>[cats, planned, real]) {
    if (a.hasError) return AsyncError<PlanYear>(a.error!, a.stackTrace ?? StackTrace.current);
  }
  final c = cats.value, p = planned.value, r = real.value;
  if (c == null || p == null || r == null) return const AsyncLoading<PlanYear>();
  return AsyncData(buildPlanYear(
    year: year,
    cycle: cycle,
    categories: planCategoriesOf(c),
    planned: p,
    real: r,
  ));
});

// --- Previsión de saldo

/// Meses que abarca la previsión (el actual incluido).
final forecastMonthsProvider = Provider<int>((ref) {
  final n = int.tryParse(ref.watch(settingProvider(SettingKeys.forecastMonths)).value ?? '');
  return n == null || n < 1 || n > maxForecastMonths ? defaultForecastMonths : n;
});

final forecastRulesProvider = StreamProvider.autoDispose<List<ForecastRule>>(
  (ref) => ref.watch(recurringRepoProvider).watchForecastRules(),
);

/// Previsión del saldo día a día. Es null si no hay saldo inicial (sin él no
/// se conoce el dinero disponible). Se recalcula sola al registrar
/// movimientos, cambiar el plan o las reglas recurrentes.
final forecastProvider = Provider.autoDispose<AsyncValue<Forecast?>>((ref) {
  final months = ref.watch(forecastMonthsProvider);
  final cycle = ref.watch(monthCycleProvider);
  final today = Dates.today();
  final monthList = forecastMonths(today, cycle, months);
  final from = cycle.startOf(monthList.first);
  final to = cycle.endOf(monthList.last);

  final balance = ref.watch(availableBalanceProvider);
  final cats = ref.watch(categoryMapProvider);
  final real = ref.watch(realByDayProvider(rangeOf(from, to)));
  final rules = ref.watch(forecastRulesProvider);
  final pending = ref.watch(pendingTxProvider);
  final planned = {
    for (final y in {for (final m in monthList) m.year}) y: ref.watch(plannedYearProvider(y)),
  };

  final all = <AsyncValue<Object?>>[balance, cats, real, rules, pending, ...planned.values];
  for (final a in all) {
    if (a.hasError) return AsyncError<Forecast?>(a.error!, a.stackTrace ?? StackTrace.current);
  }
  if (all.any((a) => !a.hasValue)) return const AsyncLoading<Forecast?>();
  final start = balance.value;
  if (start == null) return const AsyncData<Forecast?>(null);

  return AsyncData(buildForecast(
    today: today,
    startBalanceCents: start,
    cycle: cycle,
    months: months,
    categories: planCategoriesOf(cats.value!),
    plannedByYear: {for (final e in planned.entries) e.key: e.value.value!},
    real: real.value!,
    rules: rules.value!,
    pending: [
      for (final tx in pending.value!)
        ForecastPendingTx(
          date: tx.date,
          type: tx.type,
          amountCents: tx.amountCents,
          categoryId: tx.categoryId,
          label: tx.title,
          emoji: tx.categoryEmoji,
        ),
    ],
  ));
});

// --- Salud financiera

final benchmarksProvider = StreamProvider.autoDispose<List<Benchmark>>(
  (ref) => ref.watch(benchmarkRepoProvider).watchAll(),
);

/// Mes contable del primer movimiento confirmado (null sin movimientos).
final firstDataMonthProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  final cycle = ref.watch(monthCycleProvider);
  return ref
      .watch(transactionRepoProvider)
      .watchFirstDay()
      .map((day) => day == null ? null : cycle.monthOf(Dates.parseKey(day)));
});

typedef MonthFiguresData = ({
  MonthFigures current,
  List<MonthFigures> previous,
  Map<String, PlanCategory> categories,
});

/// Cifras del mes contable [month] y de los 12 anteriores (el más reciente
/// primero), sin contar los meses anteriores a empezar a usar la app.
final monthFiguresProvider = Provider.autoDispose.family<AsyncValue<MonthFiguresData>, DateTime>((ref, month) {
  final cycle = ref.watch(monthCycleProvider);
  final first = ref.watch(firstDataMonthProvider);
  final cats = ref.watch(categoryMapProvider);
  if (first.hasError) return AsyncError(first.error!, first.stackTrace ?? StackTrace.current);
  if (!first.hasValue) return const AsyncLoading();
  final previous = previousMonths(month, 12, firstDataMonth: first.value);
  final from = cycle.startOf(previous.isEmpty ? month : previous.last);
  final real = ref.watch(realByDayProvider(rangeOf(from, cycle.endOf(month))));
  for (final a in <AsyncValue<Object>>[cats, real]) {
    if (a.hasError) return AsyncError(a.error!, a.stackTrace ?? StackTrace.current);
  }
  final c = cats.value, r = real.value;
  if (c == null || r == null) return const AsyncLoading();
  final categories = planCategoriesOf(c);
  final figures = monthFigures(months: [month, ...previous], cycle: cycle, categories: categories, real: r);
  return AsyncData((current: figures.first, previous: figures.sublist(1), categories: categories));
});

/// Reglas orientativas evaluadas en el mes contable actual.
final financialHealthProvider = Provider.autoDispose<AsyncValue<FinancialHealth>>((ref) {
  final month = ref.watch(monthCycleProvider).monthOf(Dates.today());
  final data = ref.watch(monthFiguresProvider(month));
  final benchmarks = ref.watch(benchmarksProvider);
  final available = ref.watch(availableBalanceProvider);
  for (final a in <AsyncValue<Object?>>[data, benchmarks, available]) {
    if (a.hasError) return AsyncError(a.error!, a.stackTrace ?? StackTrace.current);
  }
  final d = data.value, b = benchmarks.value;
  if (d == null || b == null || !available.hasValue) return const AsyncLoading();
  return AsyncData(buildFinancialHealth(
    benchmarks: b,
    current: d.current,
    previous: d.previous,
    categories: d.categories,
    availableCents: available.value,
  ));
});

/// Media mensual de una categoría (3, 6 y 12 meses) frente al mes [month].
final categoryAveragesProvider =
    Provider.autoDispose.family<AsyncValue<CategoryAverages>, ({String categoryId, DateTime month})>((ref, a) {
  return ref.watch(monthFiguresProvider(a.month)).whenData((d) => categoryAverages(
        a.categoryId,
        current: d.current,
        previous: d.previous,
        categories: d.categories,
      ));
});

// --- Patrimonio

final assetsProvider = StreamProvider.autoDispose<List<AssetInfo>>(
  (ref) => ref.watch(assetRepoProvider).watchAssets(),
);

final assetValuesProvider = StreamProvider.autoDispose<List<AssetValue>>(
  (ref) => ref.watch(assetRepoProvider).watchValues(),
);

/// Patrimonio en un mes contable (día 1). Null mientras carga.
final netWorthProvider = Provider.autoDispose.family<NetWorth?, DateTime>((ref, month) {
  final assets = ref.watch(assetsProvider).value;
  final values = ref.watch(assetValuesProvider).value;
  if (assets == null || values == null) return null;
  return netWorthAt(month, assets, values);
});

// --- Compra

final shoppingListsProvider = StreamProvider.autoDispose<List<ShoppingListView>>(
  (ref) => ref.watch(shoppingRepoProvider).watchLists(),
);

final shoppingListProvider = StreamProvider.autoDispose.family<ShoppingListView?, String>(
  (ref, id) => ref.watch(shoppingRepoProvider).watchList(id),
);

final shoppingItemsProvider = StreamProvider.autoDispose.family<List<ShoppingItemRow>, String>(
  (ref, listId) => ref.watch(shoppingRepoProvider).watchItems(listId),
);

// ===========================================================================
// Estado de la interfaz compartido entre pantallas.
// ===========================================================================

/// Pestaña seleccionada en la barra inferior.
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<TabIndexNotifier, int>(TabIndexNotifier.new);

/// Día seleccionado en el calendario (el botón + lo usa como fecha).
class CalendarDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => Dates.today();
  void select(DateTime day) => state = Dates.dateOnly(day);
}

final calendarDayProvider = NotifierProvider<CalendarDayNotifier, DateTime>(CalendarDayNotifier.new);
