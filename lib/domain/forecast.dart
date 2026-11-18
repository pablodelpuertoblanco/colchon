import '../core/dates.dart';
import 'models.dart';
import 'plan.dart';
import 'recurrence.dart';

// ---------------------------------------------------------------------------
// Previsión de saldo: cómo evolucionará el dinero disponible día a día.
//
// Parte del dinero disponible de hoy y, para cada mes contable desde el
// actual, añade:
//   a) los movimientos recurrentes que aún no han ocurrido (o que están
//      generados pero sin confirmar), en su fecha;
//   b) lo que queda de cada partida del plan (previsto − real − lo que ya
//      cubren los recurrentes de esa categoría), el día en que suele
//      cargarse o, si no se sabe, repartido entre los días que quedan.
//
// Nada se cuenta dos veces: un gasto ya registrado está en el saldo de hoy y
// en el "real" del plan (que baja lo que queda), y un recurrente ya generado
// y confirmado es un movimiento más. Todo es cálculo puro, sin base de datos.
// ---------------------------------------------------------------------------

/// Meses de previsión por defecto y máximos.
const defaultForecastMonths = 3;
const maxForecastMonths = 12;

/// Regla recurrente activa, con su última ocurrencia ya generada.
class ForecastRule {
  const ForecastRule({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.label,
    required this.emoji,
    required this.start,
    required this.frequency,
    this.everyN = 1,
    this.end,
    this.lastGenerated,
  });

  final String id;
  final TxType type;
  final int amountCents;
  final String categoryId;
  final String label;
  final String emoji;
  final DateTime start;
  final Frequency frequency;
  final int everyN;
  final DateTime? end;

  /// Fecha de la última ocurrencia ya convertida en movimiento (aunque se
  /// borrase después): las anteriores no se vuelven a contar.
  final DateTime? lastGenerated;

  /// Ocurrencias aún no generadas hasta [to] (inclusive). Usa el mismo
  /// criterio que el generador de recurrentes: desde el día siguiente a la
  /// última generada.
  List<DateTime> pendingUntil(DateTime to) {
    var from = Dates.dateOnly(start);
    if (lastGenerated != null) {
      final afterLast = Dates.addDays(lastGenerated!, 1);
      if (afterLast.isAfter(from)) from = afterLast;
    }
    return Recurrence.between(start: start, frequency: frequency, everyN: everyN, from: from, to: to, end: end);
  }
}

/// Movimiento que ya existe pero no está en el saldo porque está pendiente de
/// confirmar (p. ej. un recurrente en modo "confirmar importe").
class ForecastPendingTx {
  const ForecastPendingTx({
    required this.date,
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.label,
    required this.emoji,
  });
  final DateTime date;
  final TxType type;
  final int amountCents;
  final String categoryId;
  final String label;
  final String emoji;
}

/// De dónde sale un movimiento previsto.
enum ForecastSource {
  /// Ocurrencia futura de una regla recurrente.
  recurring,

  /// Movimiento pendiente de confirmar.
  pending,

  /// Lo que queda de una partida del plan, en su día habitual.
  plan,

  /// Lo que queda de una partida del plan sin día fijo, repartido a diario.
  planSpread,
}

/// Un movimiento previsto.
class ForecastEvent {
  const ForecastEvent({
    required this.date,
    required this.type,
    required this.cents,
    required this.label,
    required this.emoji,
    required this.categoryId,
    required this.source,
  });

  final DateTime date;
  final TxType type;
  final int cents;
  final String label;
  final String emoji;
  final String categoryId;
  final ForecastSource source;

  bool get isIncome => type == TxType.income;
  int get signedCents => isIncome ? cents : -cents;
  bool get isSpread => source == ForecastSource.planSpread;
}

/// Un día de la previsión: saldo al final del día y lo que pasa ese día.
class ForecastDay {
  const ForecastDay({required this.date, required this.balanceCents, required this.events});
  final DateTime date;
  final int balanceCents;
  final List<ForecastEvent> events;

  int get changeCents => events.fold(0, (s, e) => s + e.signedCents);

  /// Movimientos con fecha propia (sin el gasto repartido a diario).
  List<ForecastEvent> get datedEvents => [for (final e in events) if (!e.isSpread) e];

  /// Gasto (o ingreso) repartido a diario de ese día, con signo.
  int get spreadCents => events.where((e) => e.isSpread).fold(0, (s, e) => s + e.signedCents);
}

/// Resultado de la previsión.
class Forecast {
  Forecast({required this.startBalanceCents, required this.days});

  /// Dinero disponible hoy, antes de lo previsto.
  final int startBalanceCents;

  /// Un elemento por día, de hoy al último día del horizonte.
  final List<ForecastDay> days;

  bool get isEmpty => days.isEmpty;

  DateTime? get endDate => days.isEmpty ? null : days.last.date;

  int get endBalanceCents => days.isEmpty ? startBalanceCents : days.last.balanceCents;

  /// El día con el saldo más bajo (el primero si hay empate).
  ForecastDay? get lowest {
    ForecastDay? low;
    for (final d in days) {
      if (low == null || d.balanceCents < low.balanceCents) low = d;
    }
    return low;
  }

  /// Primer día en que el saldo queda por debajo de [minCents].
  ForecastDay? firstBelow(int minCents) {
    for (final d in days) {
      if (d.balanceCents < minCents) return d;
    }
    return null;
  }

  /// Todos los movimientos previstos, en orden de fecha.
  List<ForecastEvent> get events => [for (final d in days) ...d.events];
}

/// Meses contables que abarca una previsión de [months] meses: el actual y
/// los siguientes (con 3: este mes y los dos próximos).
List<DateTime> forecastMonths(DateTime today, MonthCycle cycle, int months) {
  final n = months.clamp(1, maxForecastMonths);
  final current = cycle.monthOf(Dates.dateOnly(today));
  return [for (var i = 0; i < n; i++) Dates.shiftMonth(current, i)];
}

/// Fecha del día [day] (1-31) dentro del mes contable [month]. Si ese mes no
/// tiene tantos días, el último del mes (un cargo del 31 cae el 28 de
/// febrero). Con meses contables (p. ej. del 24 al 23) hay exactamente una
/// fecha válida: el 28 cae en el mes en que empieza y el 5 en el que acaba.
DateTime expectedDateIn(MonthCycle cycle, DateTime month, int day) {
  final start = cycle.startOf(month);
  final end = cycle.endOf(month);
  for (var d = DateTime(start.year, start.month, 1); !d.isAfter(end); d = DateTime(d.year, d.month + 1, 1)) {
    final last = Dates.daysInMonth(d.year, d.month);
    final candidate = DateTime(d.year, d.month, day > last ? last : day);
    if (!candidate.isBefore(start) && !candidate.isAfter(end)) return candidate;
  }
  return end; // no debería ocurrir
}

/// Calcula la previsión de saldo.
///
/// - [startBalanceCents]: dinero disponible hoy (ya incluye lo confirmado).
/// - [plannedByYear]: lo previsto de cada año que toque la previsión.
/// - [real]: importes confirmados por día desde el inicio del mes actual.
/// - [rules]: reglas recurrentes activas; [pending]: movimientos pendientes.
Forecast buildForecast({
  required DateTime today,
  required int startBalanceCents,
  required MonthCycle cycle,
  int months = defaultForecastMonths,
  required Map<String, PlanCategory> categories,
  required Map<int, List<PlannedAmount>> plannedByYear,
  required List<RealAmount> real,
  List<ForecastRule> rules = const [],
  List<ForecastPendingTx> pending = const [],
}) {
  final t = Dates.dateOnly(today);
  final monthList = forecastMonths(t, cycle, months);
  final end = cycle.endOf(monthList.last);
  DateTime notBeforeToday(DateTime d) => d.isBefore(t) ? t : Dates.dateOnly(d);

  final events = <ForecastEvent>[];
  // Recurrentes por su fecha original, para saber qué mes del plan cubren.
  final coverage = <({DateTime date, String categoryId, int cents})>[];

  // a) Recurrentes: ocurrencias aún no generadas y movimientos pendientes.
  //    Lo que debió ocurrir antes de hoy y sigue sin estar en el saldo se
  //    cuenta hoy.
  for (final r in rules) {
    for (final d in r.pendingUntil(end)) {
      coverage.add((date: d, categoryId: r.categoryId, cents: r.amountCents));
      events.add(ForecastEvent(
        date: notBeforeToday(d),
        type: r.type,
        cents: r.amountCents,
        label: r.label,
        emoji: r.emoji,
        categoryId: r.categoryId,
        source: ForecastSource.recurring,
      ));
    }
  }
  for (final p in pending) {
    if (p.date.isAfter(end)) continue;
    coverage.add((date: Dates.dateOnly(p.date), categoryId: p.categoryId, cents: p.amountCents));
    events.add(ForecastEvent(
      date: notBeforeToday(p.date),
      type: p.type,
      cents: p.amountCents,
      label: p.label,
      emoji: p.emoji,
      categoryId: p.categoryId,
      source: ForecastSource.pending,
    ));
  }

  // b) Lo que queda de cada partida del plan, mes a mes.
  final realByMonth = <DateTime, Map<String, int>>{};
  final types = <String, TxType>{};
  for (final r in real) {
    final m = cycle.monthOf(Dates.parseKey(r.dayKey));
    final map = realByMonth.putIfAbsent(m, () => {});
    map[r.categoryId] = (map[r.categoryId] ?? 0) + r.cents;
    types[r.categoryId] = r.type;
  }

  for (final month in monthList) {
    final mStart = cycle.startOf(month);
    final mEnd = cycle.endOf(month);
    if (mEnd.isBefore(t)) continue;

    final planned = <String, int>{};
    for (final p in plannedByYear[month.year] ?? const <PlannedAmount>[]) {
      if (p.month == month.month && p.cents > 0) planned[p.categoryId] = (planned[p.categoryId] ?? 0) + p.cents;
    }
    if (planned.isEmpty) continue;

    // Lo que ya cubren los recurrentes de cada partida este mes (con la
    // misma regla que lo real: una subcategoría sin previsto suma al grupo).
    String lineOf(String categoryId) {
      if (planned.containsKey(categoryId)) return categoryId;
      final parent = categories[categoryId]?.parentId;
      return parent != null && planned.containsKey(parent) ? parent : categoryId;
    }

    final covered = <String, int>{};
    for (final e in coverage) {
      if (e.date.isBefore(mStart) || e.date.isAfter(mEnd)) continue;
      final id = lineOf(e.categoryId);
      covered[id] = (covered[id] ?? 0) + e.cents;
    }

    final sections = buildPlanSections(categories, planned, realByMonth[month] ?? const {}, types);
    final from = mStart.isBefore(t) ? t : mStart;
    for (final s in sections) {
      for (final line in s.lines) {
        final c = line.category;
        final left = line.plannedCents - line.realCents - (covered[c.id] ?? 0);
        if (line.plannedCents <= 0 || left <= 0) continue;
        final type = line.isIncome ? TxType.income : TxType.expense;
        final day = c.expectedDay;
        if (day != null && day >= 1 && day <= 31) {
          events.add(ForecastEvent(
            date: notBeforeToday(expectedDateIn(cycle, month, day)),
            type: type,
            cents: left,
            label: c.name,
            emoji: c.emoji,
            categoryId: c.id,
            source: ForecastSource.plan,
          ));
        } else {
          // A partes iguales entre los días que quedan; los céntimos que
          // sobran van a los primeros días para que la suma sea exacta.
          final n = Dates.daysBetween(from, mEnd) + 1;
          final base = left ~/ n;
          final extra = left % n;
          for (var i = 0; i < n; i++) {
            final cents = base + (i < extra ? 1 : 0);
            if (cents == 0) continue;
            events.add(ForecastEvent(
              date: Dates.addDays(from, i),
              type: type,
              cents: cents,
              label: c.name,
              emoji: c.emoji,
              categoryId: c.id,
              source: ForecastSource.planSpread,
            ));
          }
        }
      }
    }
  }

  // Saldo día a día.
  final byDay = <String, List<ForecastEvent>>{};
  for (final e in events) {
    byDay.putIfAbsent(Dates.key(e.date), () => []).add(e);
  }
  final days = <ForecastDay>[];
  var balance = startBalanceCents;
  for (var d = t; !d.isAfter(end); d = Dates.addDays(d, 1)) {
    final list = byDay[Dates.key(d)] ?? const <ForecastEvent>[];
    // Primero los ingresos y luego los gastos de mayor a menor.
    final sorted = [...list]..sort((a, b) {
        if (a.isIncome != b.isIncome) return a.isIncome ? -1 : 1;
        return b.cents.compareTo(a.cents);
      });
    balance += sorted.fold(0, (s, e) => s + e.signedCents);
    days.add(ForecastDay(date: d, balanceCents: balance, events: sorted));
  }
  return Forecast(startBalanceCents: startBalanceCents, days: days);
}
