import '../core/dates.dart';
import 'models.dart';

/// Cálculo puro (sin base de datos) de las fechas en que se repite una regla.
///
/// El día de cobro lo fija [start]: una regla mensual que empieza el 31 de
/// enero cae el 28/29 de febrero, el 31 de marzo, el 30 de abril, etc.
class Recurrence {
  Recurrence._();

  /// Fecha de la ocurrencia número [k] (la 0 es [start]).
  static DateTime occurrenceAt(DateTime start, Frequency frequency, int everyN, int k) {
    final step = k * everyN;
    return switch (frequency) {
      Frequency.day => DateTime(start.year, start.month, start.day + step),
      Frequency.week => DateTime(start.year, start.month, start.day + 7 * step),
      Frequency.month => Dates.addMonthsClamped(start, step, day: start.day),
      Frequency.year => Dates.addMonthsClamped(start, 12 * step, day: start.day),
    };
  }

  /// Todas las ocurrencias dentro de [from, to] (ambos inclusive), sin pasar
  /// de [end] si la regla tiene fecha de fin.
  static List<DateTime> between({
    required DateTime start,
    required Frequency frequency,
    required int everyN,
    required DateTime from,
    required DateTime to,
    DateTime? end,
    int maxResults = 2000,
  }) {
    assert(everyN >= 1);
    final s = Dates.dateOnly(start);
    final f = Dates.dateOnly(from);
    final t = Dates.dateOnly(to);
    final limit = end == null || Dates.dateOnly(end).isAfter(t) ? t : Dates.dateOnly(end);
    final result = <DateTime>[];
    if (limit.isBefore(s) || limit.isBefore(f)) return result;

    for (var k = 0; result.length < maxResults; k++) {
      final d = occurrenceAt(s, frequency, everyN, k);
      if (d.isAfter(limit)) break;
      if (!d.isBefore(f)) result.add(d);
    }
    return result;
  }

  /// Próxima ocurrencia a partir de [from] (inclusive), o null si la regla ya
  /// terminó.
  static DateTime? nextFrom({
    required DateTime start,
    required Frequency frequency,
    required int everyN,
    required DateTime from,
    DateTime? end,
  }) {
    // Buscamos en una ventana amplia (hasta 2 periodos completos por delante).
    final horizon = switch (frequency) {
      Frequency.day => Dates.addDays(from, everyN * 2 + 1),
      Frequency.week => Dates.addDays(from, 7 * everyN * 2 + 1),
      Frequency.month => Dates.addMonthsClamped(from, everyN * 2 + 1),
      Frequency.year => Dates.addMonthsClamped(from, 12 * (everyN * 2 + 1)),
    };
    final list = between(
      start: start,
      frequency: frequency,
      everyN: everyN,
      from: from.isBefore(start) ? start : from,
      to: horizon,
      end: end,
      maxResults: 1,
    );
    return list.isEmpty ? null : list.first;
  }
}
