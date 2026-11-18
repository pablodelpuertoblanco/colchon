import '../core/dates.dart';

enum BudgetState { ok, warning, exceeded }

/// Situación de un presupuesto en su periodo actual.
class BudgetProgress {
  const BudgetProgress({
    required this.limitCents,
    required this.spentCents,
    required this.alertPct,
    required this.periodEnd,
    required this.today,
  });

  final int limitCents;
  final int spentCents;
  final int alertPct;
  final DateTime periodEnd;
  final DateTime today;

  int get remainingCents => limitCents - spentCents;

  /// 0.0 – 1.0+ (puede pasar de 1 si se supera).
  double get ratio => limitCents <= 0 ? 0 : spentCents / limitCents;

  int get percent => (ratio * 100).round();

  BudgetState get state {
    if (spentCents > limitCents) return BudgetState.exceeded;
    if (spentCents * 100 >= limitCents * alertPct) return BudgetState.warning;
    return BudgetState.ok;
  }

  /// Días que quedan del periodo contando hoy.
  int get daysLeft {
    final d = Dates.daysBetween(today, periodEnd) + 1;
    return d < 0 ? 0 : d;
  }

  /// Cuánto se puede gastar al día para no pasarse. Null si ya no queda.
  int? get dailyAllowanceCents {
    if (remainingCents <= 0 || daysLeft <= 0) return null;
    return remainingCents ~/ daysLeft;
  }

  /// ¿Este gasto de [amountCents] ha hecho cruzar el umbral de aviso o el
  /// límite? Se usa para avisar justo después de guardar un gasto.
  static BudgetState? crossedBy({
    required int limitCents,
    required int alertPct,
    required int spentAfterCents,
    required int amountCents,
  }) {
    final before = spentAfterCents - amountCents;
    if (before <= limitCents && spentAfterCents > limitCents) return BudgetState.exceeded;
    final threshold = limitCents * alertPct; // comparamos en "céntimos x 100"
    if (before * 100 < threshold && spentAfterCents * 100 >= threshold) return BudgetState.warning;
    return null;
  }
}
