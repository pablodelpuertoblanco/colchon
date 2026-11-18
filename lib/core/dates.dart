/// Utilidades de fechas.
///
/// Los movimientos guardan su día como texto local "AAAA-MM-DD" (la "clave"
/// del día). Así un gasto de las 23:30 nunca salta al día siguiente por
/// cambios de zona horaria. Toda la aritmética de días usa el constructor de
/// DateTime (que normaliza meses y cambios de hora), nunca sumar Duration.
class Dates {
  Dates._();

  static const monthNames = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const monthShort = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  static const weekdayNames = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];
  static const weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// DateTime -> "2026-11-14"
  static String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// "2026-11-14" -> DateTime local a medianoche.
  static DateTime parseKey(String k) {
    final p = k.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime today() => dateOnly(DateTime.now());
  static DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Días naturales entre dos fechas, a prueba de cambios de hora.
  static int daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// La semana empieza en lunes.
  static DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  static DateTime endOfWeek(DateTime d) => addDays(startOfWeek(d), 6);
  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
  static DateTime startOfYear(DateTime d) => DateTime(d.year, 1, 1);
  static DateTime endOfYear(DateTime d) => DateTime(d.year, 12, 31);

  /// Suma meses manteniendo el día y ajustándolo al último del mes si no
  /// existe (31 de enero + 1 mes = 28/29 de febrero).
  static DateTime addMonthsClamped(DateTime d, int months, {int? day}) {
    final total = d.month - 1 + months;
    final year = d.year + (total >= 0 ? total ~/ 12 : -((-total + 11) ~/ 12));
    final month = ((total % 12) + 12) % 12 + 1;
    final wanted = day ?? d.day;
    final dd = wanted > daysInMonth(year, month) ? daysInMonth(year, month) : wanted;
    return DateTime(year, month, dd);
  }

  static String nowIso() => DateTime.now().toUtc().toIso8601String();

  static String capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// "Noviembre 2026"
  static String monthYear(DateTime d) => '${capitalize(monthNames[d.month - 1])} ${d.year}';

  /// "14 nov"
  static String dayMonthShort(DateTime d) => '${d.day} ${monthShort[d.month - 1]}';

  /// "14 nov 2026"
  static String dayMonthYearShort(DateTime d) => '${d.day} ${monthShort[d.month - 1]} ${d.year}';

  /// "sábado, 14 de noviembre"
  static String longDay(DateTime d) => '${weekdayNames[d.weekday - 1]}, ${d.day} de ${monthNames[d.month - 1]}';

  /// Primer día del mes desplazado [delta] meses (para recorrer meses).
  static DateTime shiftMonth(DateTime month, int delta) => DateTime(month.year, month.month + delta, 1);

  /// "Hoy", "Ayer", "Mañana" o "sábado, 14 de noviembre" (+ año si no es el actual).
  static String relativeDay(DateTime d, {DateTime? now}) {
    final t = dateOnly(now ?? DateTime.now());
    final diff = daysBetween(t, d);
    if (diff == 0) return 'Hoy';
    if (diff == -1) return 'Ayer';
    if (diff == 1) return 'Mañana';
    final base = capitalize(longDay(d));
    return d.year == t.year ? base : '$base de ${d.year}';
  }
}

/// Mes contable: del día [startDay] de un mes al día anterior del siguiente.
///
/// Con `startDay = 24`, "enero" va del 24 de diciembre al 23 de enero: el mes
/// toma el nombre del mes en el que termina, como en el Excel de presupuesto
/// ("24 DIC – 24 ENERO" = ENERO). Con `startDay = 1` es el mes natural.
/// Los meses se representan con el día 1 de su mes (`DateTime(2026, 1, 1)`).
class MonthCycle {
  const MonthCycle(this.startDay) : assert(startDay >= 1 && startDay <= 28);

  static const calendar = MonthCycle(1);

  /// Día de inicio: de 1 a 28 para que exista en todos los meses.
  final int startDay;

  bool get isCalendar => startDay == 1;

  /// "24" -> MonthCycle(24). Valores no válidos -> mes natural.
  static MonthCycle parse(String? text) {
    final n = int.tryParse(text ?? '');
    if (n == null || n < 1 || n > 28) return calendar;
    return MonthCycle(n);
  }

  /// Mes contable al que pertenece el día [d].
  DateTime monthOf(DateTime d) {
    if (startDay == 1 || d.day < startDay) return DateTime(d.year, d.month, 1);
    return DateTime(d.year, d.month + 1, 1);
  }

  /// Primer día del mes contable [month].
  DateTime startOf(DateTime month) =>
      startDay == 1 ? DateTime(month.year, month.month, 1) : DateTime(month.year, month.month - 1, startDay);

  /// Último día del mes contable [month].
  DateTime endOf(DateTime month) =>
      startDay == 1 ? DateTime(month.year, month.month + 1, 0) : DateTime(month.year, month.month, startDay - 1);

  /// Del primer día de enero al último de diciembre del año contable.
  (DateTime, DateTime) yearRange(int year) => (startOf(DateTime(year, 1, 1)), endOf(DateTime(year, 12, 1)));

  /// "24 oct – 23 nov"
  String rangeLabel(DateTime month) => '${Dates.dayMonthShort(startOf(month))} – ${Dates.dayMonthShort(endOf(month))}';

  @override
  bool operator ==(Object other) => other is MonthCycle && other.startDay == startDay;

  @override
  int get hashCode => startDay.hashCode;
}
