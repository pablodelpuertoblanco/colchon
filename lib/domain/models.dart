import 'package:flutter/foundation.dart';

import '../core/dates.dart';

// ---------------------------------------------------------------------------
// Enumeraciones. Se guardan en la base de datos por su nombre ('expense'...),
// así que NO se deben renombrar sin una migración.
// ---------------------------------------------------------------------------

enum TxType {
  expense,
  income;

  String get label => this == TxType.expense ? 'Gasto' : 'Ingreso';
  String get pluralLabel => this == TxType.expense ? 'Gastos' : 'Ingresos';
}

enum TxStatus { confirmed, pending }

enum CategoryKind {
  expense,
  income,
  product;

  String get label => switch (this) {
        CategoryKind.expense => 'Gastos',
        CategoryKind.income => 'Ingresos',
        CategoryKind.product => 'Productos',
      };

  static CategoryKind fromTxType(TxType t) => t == TxType.expense ? CategoryKind.expense : CategoryKind.income;
}

enum Frequency {
  day,
  week,
  month,
  year;

  String unitLabel(int n) => switch (this) {
        Frequency.day => n == 1 ? 'día' : 'días',
        Frequency.week => n == 1 ? 'semana' : 'semanas',
        Frequency.month => n == 1 ? 'mes' : 'meses',
        Frequency.year => n == 1 ? 'año' : 'años',
      };

  String describe(int everyN) {
    if (everyN == 1) {
      return switch (this) {
        Frequency.day => 'Cada día',
        Frequency.week => 'Cada semana',
        Frequency.month => 'Cada mes',
        Frequency.year => 'Cada año',
      };
    }
    return 'Cada $everyN ${unitLabel(everyN)}';
  }
}

enum RecurringMode {
  auto,
  confirm;

  String get label => this == RecurringMode.auto ? 'Automático' : 'Confirmar importe';
}

enum BudgetPeriod {
  week,
  month,
  year;

  String get label => switch (this) {
        BudgetPeriod.week => 'Semanal',
        BudgetPeriod.month => 'Mensual',
        BudgetPeriod.year => 'Anual',
      };

  /// Rango del periodo actual que contiene [day]. Los meses y años siguen
  /// el mes contable del usuario (p. ej. del 24 al 23).
  (DateTime, DateTime) rangeFor(DateTime day, [MonthCycle cycle = MonthCycle.calendar]) {
    switch (this) {
      case BudgetPeriod.week:
        return (Dates.startOfWeek(day), Dates.endOfWeek(day));
      case BudgetPeriod.month:
        final m = cycle.monthOf(day);
        return (cycle.startOf(m), cycle.endOf(m));
      case BudgetPeriod.year:
        final y = cycle.monthOf(day).year;
        return cycle.yearRange(y);
    }
  }
}

/// Grupo de una categoría de gasto para la regla 50/30/20 del plan.
enum BudgetGroup {
  fixed,
  variable,
  discretionary,

  /// Ocio (restaurantes, viajes, entretenimiento). En la regla 50/30/20
  /// cuenta dentro del 30 % junto a los prescindibles, pero el plan lo
  /// muestra como bloque propio con su total.
  leisure,
  savings;

  String get label => switch (this) {
        BudgetGroup.fixed => 'Necesario fijo',
        BudgetGroup.variable => 'Necesario variable',
        BudgetGroup.discretionary => 'Prescindible',
        BudgetGroup.leisure => 'Ocio',
        BudgetGroup.savings => 'Ahorro e inversión',
      };

  String get pluralLabel => switch (this) {
        BudgetGroup.fixed => 'Necesarios fijos',
        BudgetGroup.variable => 'Necesarios variables',
        BudgetGroup.discretionary => 'Prescindibles',
        BudgetGroup.leisure => 'Ocio',
        BudgetGroup.savings => 'Ahorro e inversión',
      };

  String get emoji => switch (this) {
        BudgetGroup.fixed => '📌',
        BudgetGroup.variable => '🔄',
        BudgetGroup.discretionary => '🎈',
        BudgetGroup.leisure => '🎬',
        BudgetGroup.savings => '💰',
      };

  /// Bloque de la regla 50/30/20 al que pertenece.
  RuleBucket get bucket => switch (this) {
        BudgetGroup.fixed || BudgetGroup.variable => RuleBucket.needs,
        BudgetGroup.discretionary || BudgetGroup.leisure => RuleBucket.wants,
        BudgetGroup.savings => RuleBucket.savings,
      };
}

/// Los tres bloques de la regla 50/30/20.
enum RuleBucket {
  needs,
  wants,
  savings;

  String get label => switch (this) {
        RuleBucket.needs => 'Necesarios',
        RuleBucket.wants => 'Prescindibles y ocio',
        RuleBucket.savings => 'Ahorro',
      };
}

/// Objetivos de la regla 50/30/20 (porcentajes de los ingresos).
class RuleTargets {
  const RuleTargets({this.needs = 50, this.wants = 30, this.savings = 20});
  final int needs;
  final int wants;
  final int savings;

  int of(RuleBucket b) => switch (b) {
        RuleBucket.needs => needs,
        RuleBucket.wants => wants,
        RuleBucket.savings => savings,
      };

  /// "50,30,20" -> objetivos. Si el texto no es válido, los de por defecto.
  static RuleTargets parse(String? text) {
    final parts = (text ?? '').split(',').map((s) => int.tryParse(s.trim())).toList();
    if (parts.length != 3 || parts.any((p) => p == null || p < 0 || p > 100)) return const RuleTargets();
    return RuleTargets(needs: parts[0]!, wants: parts[1]!, savings: parts[2]!);
  }

  String serialize() => '$needs,$wants,$savings';

  @override
  bool operator ==(Object other) =>
      other is RuleTargets && other.needs == needs && other.wants == wants && other.savings == savings;

  @override
  int get hashCode => Object.hash(needs, wants, savings);
}

/// Bien que suma al patrimonio o deuda que resta.
enum AssetKind {
  asset,
  liability;

  String get label => this == AssetKind.asset ? 'Lo que tengo' : 'Lo que debo';
}

enum ShoppingListStatus { active, completed }

enum ItemUnit {
  ud,
  kg,
  l;

  String get label => switch (this) {
        ItemUnit.ud => 'ud',
        ItemUnit.kg => 'kg',
        ItemUnit.l => 'l',
      };
}

enum TxSort {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  String get label => switch (this) {
        TxSort.dateDesc => 'Más recientes',
        TxSort.dateAsc => 'Más antiguos',
        TxSort.amountDesc => 'Mayor importe',
        TxSort.amountAsc => 'Menor importe',
      };
}

// ---------------------------------------------------------------------------
// Objetos de vista: lo que las pantallas necesitan, ya combinado.
// ---------------------------------------------------------------------------

/// Un movimiento con los datos de su categoría y método de pago.
class TxView {
  const TxView({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.categoryEmoji,
    required this.categoryColor,
    required this.date,
    required this.status,
    this.paymentMethodId,
    this.paymentMethodName,
    this.time,
    this.notes,
    this.recurringRuleId,
  });

  final String id;
  final TxType type;
  final int amountCents;
  final String description;
  final String categoryId;
  final String categoryName;
  final String categoryEmoji;
  final int categoryColor;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final DateTime date;
  final String? time;
  final String? notes;
  final TxStatus status;
  final String? recurringRuleId;

  bool get isExpense => type == TxType.expense;
  bool get isPending => status == TxStatus.pending;
  bool get isRecurring => recurringRuleId != null;

  /// Texto principal: la descripción o, si está vacía, la categoría.
  String get title => description.trim().isEmpty ? categoryName : description;

  /// Importe con signo para balances: gastos en negativo.
  int get signedCents => isExpense ? -amountCents : amountCents;
}

/// Datos que rellena el formulario para crear o editar un movimiento.
class TxDraft {
  const TxDraft({
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.date,
    this.description = '',
    this.paymentMethodId,
    this.time,
    this.notes,
    this.status = TxStatus.confirmed,
  });

  final TxType type;
  final int amountCents;
  final String categoryId;
  final DateTime date;
  final String description;
  final String? paymentMethodId;
  final String? time;
  final String? notes;
  final TxStatus status;
}

/// Filtros del historial. Implementa == para usarse como clave de Riverpod.
class TxFilter {
  const TxFilter({
    this.query = '',
    this.type,
    this.categoryIds = const {},
    this.from,
    this.to,
    this.paymentMethodId,
    this.sort = TxSort.dateDesc,
    this.limit = 200,
  });

  final String query;
  final TxType? type;
  final Set<String> categoryIds;
  final DateTime? from;
  final DateTime? to;
  final String? paymentMethodId;
  final TxSort sort;
  final int limit;

  static const _unset = Object();

  TxFilter copyWith({
    String? query,
    Object? type = _unset,
    Set<String>? categoryIds,
    Object? from = _unset,
    Object? to = _unset,
    Object? paymentMethodId = _unset,
    TxSort? sort,
    int? limit,
  }) {
    return TxFilter(
      query: query ?? this.query,
      type: identical(type, _unset) ? this.type : type as TxType?,
      categoryIds: categoryIds ?? this.categoryIds,
      from: identical(from, _unset) ? this.from : from as DateTime?,
      to: identical(to, _unset) ? this.to : to as DateTime?,
      paymentMethodId: identical(paymentMethodId, _unset) ? this.paymentMethodId : paymentMethodId as String?,
      sort: sort ?? this.sort,
      limit: limit ?? this.limit,
    );
  }

  bool get hasFilters =>
      query.trim().isNotEmpty || type != null || categoryIds.isNotEmpty || from != null || to != null || paymentMethodId != null;

  @override
  bool operator ==(Object other) =>
      other is TxFilter &&
      other.query == query &&
      other.type == type &&
      setEquals(other.categoryIds, categoryIds) &&
      other.from == from &&
      other.to == to &&
      other.paymentMethodId == paymentMethodId &&
      other.sort == sort &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(query, type, Object.hashAllUnordered(categoryIds), from, to, paymentMethodId, sort, limit);
}

/// Totales de ingresos y gastos confirmados de un periodo.
class Totals {
  const Totals({this.incomeCents = 0, this.expenseCents = 0});
  final int incomeCents;
  final int expenseCents;

  int get balanceCents => incomeCents - expenseCents;

  /// Porcentaje de los ingresos que se ha ahorrado (null sin ingresos).
  double? get savingsRate => incomeCents == 0 ? null : balanceCents / incomeCents * 100;
}

/// Totales de un día concreto (calendario y gráficos).
class DayTotal {
  const DayTotal({required this.dayKey, this.incomeCents = 0, this.expenseCents = 0});
  final String dayKey;
  final int incomeCents;
  final int expenseCents;
  int get balanceCents => incomeCents - expenseCents;
}

/// Total de una categoría (o de un grupo de categorías) en un periodo.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.emoji,
    required this.color,
    required this.totalCents,
    required this.count,
  });
  final String categoryId;
  final String name;
  final String emoji;
  final int color;
  final int totalCents;
  final int count;
}

/// Un cargo recurrente que aún no ha llegado.
class UpcomingCharge {
  const UpcomingCharge({
    required this.ruleId,
    required this.date,
    required this.type,
    required this.amountCents,
    required this.description,
    required this.emoji,
    required this.mode,
  });
  final String ruleId;
  final DateTime date;
  final TxType type;
  final int amountCents;
  final String description;
  final String emoji;
  final RecurringMode mode;
}

/// Saldo inicial configurado por el usuario.
class InitialBalance {
  const InitialBalance({required this.cents, required this.date});
  final int cents;
  final DateTime date;
}
