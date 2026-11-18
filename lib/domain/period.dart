import '../core/dates.dart';

enum PeriodKind {
  week,
  month,
  year,
  custom;

  String get label => switch (this) {
        PeriodKind.week => 'Semana',
        PeriodKind.month => 'Mes',
        PeriodKind.year => 'Año',
        PeriodKind.custom => 'Fechas',
      };
}

/// Un tramo dentro de un periodo (un día, un bloque de días o un mes),
/// usado como barra en los gráficos de evolución.
class Bucket {
  const Bucket({required this.start, required this.end, required this.label});
  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

/// Periodo de análisis con fechas inclusivas.
///
/// Los periodos de mes y año siguen el mes contable del usuario ([cycle]):
/// con inicio el día 24, "noviembre" va del 24 de octubre al 23 de noviembre.
class Period {
  const Period._(this.kind, this.start, this.end, this.cycle, [this.cycleMonth]);

  final PeriodKind kind;
  final DateTime start;
  final DateTime end;
  final MonthCycle cycle;

  /// Mes contable (día 1) en los periodos de tipo mes.
  final DateTime? cycleMonth;

  factory Period.week(DateTime d, {MonthCycle cycle = MonthCycle.calendar}) =>
      Period._(PeriodKind.week, Dates.startOfWeek(d), Dates.endOfWeek(d), cycle);

  /// Mes contable que contiene el día [d].
  factory Period.month(DateTime d, {MonthCycle cycle = MonthCycle.calendar}) =>
      Period.ofMonth(cycle.monthOf(d), cycle: cycle);

  /// Mes contable [month] (cualquier día de ese mes sirve como etiqueta).
  factory Period.ofMonth(DateTime month, {MonthCycle cycle = MonthCycle.calendar}) {
    final m = DateTime(month.year, month.month, 1);
    return Period._(PeriodKind.month, cycle.startOf(m), cycle.endOf(m), cycle, m);
  }

  /// Año contable que contiene el día [d].
  factory Period.year(DateTime d, {MonthCycle cycle = MonthCycle.calendar}) => Period.ofYear(cycle.monthOf(d).year, cycle: cycle);

  factory Period.ofYear(int year, {MonthCycle cycle = MonthCycle.calendar}) {
    final (s, e) = cycle.yearRange(year);
    return Period._(PeriodKind.year, s, e, cycle);
  }

  factory Period.custom(DateTime from, DateTime to, {MonthCycle cycle = MonthCycle.calendar}) {
    final a = Dates.dateOnly(from);
    final b = Dates.dateOnly(to);
    return a.isAfter(b) ? Period._(PeriodKind.custom, b, a, cycle) : Period._(PeriodKind.custom, a, b, cycle);
  }

  factory Period.of(PeriodKind kind, DateTime d, {MonthCycle cycle = MonthCycle.calendar}) => switch (kind) {
        PeriodKind.week => Period.week(d, cycle: cycle),
        PeriodKind.month => Period.month(d, cycle: cycle),
        PeriodKind.year => Period.year(d, cycle: cycle),
        PeriodKind.custom => Period.custom(cycle.startOf(cycle.monthOf(d)), Dates.today(), cycle: cycle),
      };

  /// El mismo periodo recalculado con otro mes contable.
  Period withCycle(MonthCycle c) {
    if (c == cycle) return this;
    return switch (kind) {
      PeriodKind.month => Period.ofMonth(cycleMonth!, cycle: c),
      PeriodKind.year => Period.ofYear(cycleYear, cycle: c),
      _ => Period._(kind, start, end, c, cycleMonth),
    };
  }

  String get fromKey => Dates.key(start);
  String get toKey => Dates.key(end);
  int get lengthInDays => Dates.daysBetween(start, end) + 1;

  /// Año contable (para periodos de año) o año del final del periodo.
  int get cycleYear => kind == PeriodKind.year ? cycle.monthOf(end).year : end.year;

  Period previous() => switch (kind) {
        PeriodKind.week => Period.week(Dates.addDays(start, -7), cycle: cycle),
        PeriodKind.month => Period.ofMonth(Dates.shiftMonth(cycleMonth!, -1), cycle: cycle),
        PeriodKind.year => Period.ofYear(cycleYear - 1, cycle: cycle),
        PeriodKind.custom =>
          Period.custom(Dates.addDays(start, -lengthInDays), Dates.addDays(start, -1), cycle: cycle),
      };

  Period next() => switch (kind) {
        PeriodKind.week => Period.week(Dates.addDays(start, 7), cycle: cycle),
        PeriodKind.month => Period.ofMonth(Dates.shiftMonth(cycleMonth!, 1), cycle: cycle),
        PeriodKind.year => Period.ofYear(cycleYear + 1, cycle: cycle),
        PeriodKind.custom => Period.custom(Dates.addDays(end, 1), Dates.addDays(end, lengthInDays), cycle: cycle),
      };

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  String get label => switch (kind) {
        PeriodKind.week => '${Dates.dayMonthShort(start)} – ${Dates.dayMonthShort(end)}',
        PeriodKind.month => Dates.monthYear(cycleMonth!),
        PeriodKind.year => '$cycleYear',
        PeriodKind.custom => '${Dates.dayMonthYearShort(start)} – ${Dates.dayMonthYearShort(end)}',
      };

  /// Fechas reales cuando el mes o el año no son naturales ("24 oct – 23 nov").
  String? get rangeHint {
    if (cycle.isCalendar || (kind != PeriodKind.month && kind != PeriodKind.year)) return null;
    return '${Dates.dayMonthYearShort(start)} – ${Dates.dayMonthYearShort(end)}';
  }

  /// Nombre corto del periodo anterior para comparativas ("octubre", "2025").
  String get previousLabel => switch (kind) {
        PeriodKind.week => 'la semana anterior',
        PeriodKind.month => Dates.monthNames[previous().cycleMonth!.month - 1],
        PeriodKind.year => '${cycleYear - 1}',
        PeriodKind.custom => 'el periodo anterior',
      };

  /// Tramos para los gráficos de barras:
  /// semana -> 7 días; mes -> bloques de 7 días; año -> 12 meses contables;
  /// personalizado -> días, semanas o meses según su duración.
  List<Bucket> buckets() => switch (kind) {
        PeriodKind.week => _dayBuckets(useWeekdayLetters: true),
        PeriodKind.month => _chunkBuckets(7),
        PeriodKind.year => monthBuckets(DateTime(cycleYear, 1, 1), 12, cycle),
        PeriodKind.custom => lengthInDays <= 14
            ? _dayBuckets(useWeekdayLetters: false)
            : (lengthInDays <= 92 ? _chunkBuckets(7) : _monthBuckets()),
      };

  /// [count] meses contables seguidos empezando en [firstMonth].
  static List<Bucket> monthBuckets(DateTime firstMonth, int count, MonthCycle cycle) {
    final result = <Bucket>[];
    for (var i = 0; i < count; i++) {
      final m = Dates.shiftMonth(firstMonth, i);
      result.add(Bucket(
        start: cycle.startOf(m),
        end: cycle.endOf(m),
        label: Dates.capitalize(Dates.monthShort[m.month - 1]),
      ));
    }
    return result;
  }

  List<Bucket> _dayBuckets({required bool useWeekdayLetters}) {
    final result = <Bucket>[];
    for (var d = start; !d.isAfter(end); d = Dates.addDays(d, 1)) {
      final label = useWeekdayLetters ? Dates.weekdayLetters[d.weekday - 1] : '${d.day}';
      result.add(Bucket(start: d, end: d, label: label));
    }
    return result;
  }

  List<Bucket> _chunkBuckets(int size) {
    final result = <Bucket>[];
    var s = start;
    while (!s.isAfter(end)) {
      var e = Dates.addDays(s, size - 1);
      if (e.isAfter(end)) e = end;
      final label = s.month == e.month ? '${s.day}-${e.day}' : '${s.day}/${s.month}';
      result.add(Bucket(start: s, end: e, label: label));
      s = Dates.addDays(e, 1);
    }
    return result;
  }

  List<Bucket> _monthBuckets() {
    final result = <Bucket>[];
    var m = DateTime(start.year, start.month, 1);
    while (!m.isAfter(end)) {
      final s = m.isBefore(start) ? start : m;
      var e = Dates.endOfMonth(m);
      if (e.isAfter(end)) e = end;
      final label = Dates.capitalize(Dates.monthShort[m.month - 1]);
      result.add(Bucket(start: s, end: e, label: label));
      m = DateTime(m.year, m.month + 1, 1);
    }
    return result;
  }
}
