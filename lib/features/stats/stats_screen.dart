import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/period.dart';
import '../health/health_screen.dart';
import 'category_detail_screen.dart';
import 'charts.dart';

/// Panel de estadísticas: semana, mes, año o fechas personalizadas.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late Period _period = Period.month(Dates.today(), cycle: ref.read(monthCycleProvider));
  TxType _donutType = TxType.expense;
  bool _grouped = true;

  Future<void> _setKind(PeriodKind kind) async {
    if (kind == PeriodKind.custom) {
      final today = Dates.today();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(start: _period.cycle.startOf(_period.cycle.monthOf(today)), end: today),
      );
      if (range != null) setState(() => _period = Period.custom(range.start, range.end, cycle: _period.cycle));
      return;
    }
    // Conserva la fecha de referencia al cambiar de vista.
    final anchor = _period.contains(Dates.today()) ? Dates.today() : _period.start;
    setState(() => _period = Period.of(kind, anchor, cycle: _period.cycle));
  }

  void _openCategory(CategoryTotal t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CategoryDetailScreen(categoryId: t.categoryId, period: _period, type: _donutType),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Si cambia el día de inicio de mes en Ajustes, se recalcula el periodo.
    _period = _period.withCycle(ref.watch(monthCycleProvider));
    final p = _period;
    final prev = p.previous();
    final totals = ref.watch(totalsProvider(rangeOf(p.start, p.end))).value ?? const Totals();
    final prevTotals = ref.watch(totalsProvider(rangeOf(prev.start, prev.end))).value ?? const Totals();
    final daily = ref.watch(dailyTotalsProvider(rangeOf(p.start, p.end))).value ?? const <String, DayTotal>{};
    final cats = ref
            .watch(categoryTotalsProvider((from: p.fromKey, to: p.toKey, type: _donutType, grouped: _grouped)))
            .value ??
        const <CategoryTotal>[];

    final bars = bucketize(p.buckets(), daily);
    // Ahorro acumulado tramo a tramo dentro del periodo.
    var running = 0;
    final cumulative = <int>[for (final b in bars) running += b.balanceCents];
    final catSum = cats.fold<int>(0, (s, t) => s + t.totalCents);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            tooltip: 'Salud financiera',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => openHealth(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: [for (final k in PeriodKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {p.kind},
            onSelectionChanged: (s) => _setKind(s.first),
          ),
          PeriodSwitcher(
            label: p.label,
            subtitle: p.rangeHint,
            onPrevious: () => setState(() => _period = p.previous()),
            onNext: () => setState(() => _period = p.next()),
            onTapLabel: p.kind == PeriodKind.custom ? () => _setKind(PeriodKind.custom) : null,
          ),

          // --------------------------------------------------- resumen
          SectionCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Figure(label: 'Ingresos', cents: totals.incomeCents, color: AppColors.income)),
                    Expanded(child: _Figure(label: 'Gastos', cents: totals.expenseCents, color: AppColors.expense)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Balance neto',
                        cents: totals.balanceCents,
                        color: totals.balanceCents >= 0 ? AppColors.income : AppColors.expense,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tasa de ahorro', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                          Text(
                            totals.savingsRate == null ? '—' : '${totals.savingsRate!.toStringAsFixed(0)} %',
                            style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _Comparison(label: 'Gastos', current: totals.expenseCents, previous: prevTotals.expenseCents, against: p.previousLabel, higherIsBad: true),
                _Comparison(label: 'Ingresos', current: totals.incomeCents, previous: prevTotals.incomeCents, against: p.previousLabel, higherIsBad: false),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ----------------------------------------- ingresos vs gastos
          SectionCard(
            title: 'Ingresos frente a gastos',
            child: Column(
              children: [
                IncomeExpenseBars(data: bars),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 16,
                  children: [
                    LegendDot(color: AppColors.income, label: 'Ingresos'),
                    LegendDot(color: AppColors.expense, label: 'Gastos'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ------------------------------------------------ categorías
          SectionCard(
            title: 'Por categorías',
            trailing: SegmentedButton<TxType>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Gastos')),
                ButtonSegment(value: TxType.income, label: Text('Ingresos')),
              ],
              selected: {_donutType},
              onSelectionChanged: (s) => setState(() => _donutType = s.first),
            ),
            child: Column(
              children: [
                Center(
                  child: CategoryDonut(
                    totals: cats,
                    centerTitle: _donutType.pluralLabel,
                    centerValue: Money.format(catSum),
                    onTapCategory: _openCategory,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _grouped,
                  onChanged: (v) => setState(() => _grouped = v),
                  title: const Text('Agrupar subcategorías (p. ej. Facturas)'),
                ),
                if (cats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('No hay ${_donutType.pluralLabel.toLowerCase()} en este periodo.',
                        style: TextStyle(color: context.colors.onSurfaceVariant)),
                  )
                else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Ranking', style: context.text.titleSmall),
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < cats.length; i++)
                    CategoryRankRow(
                      total: cats[i],
                      sumCents: catSum,
                      position: i + 1,
                      onTap: () => _openCategory(cats[i]),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -------------------------------------------- evolución ahorro
          SectionCard(
            title: 'Evolución del ahorro',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ingresos − gastos acumulados en el periodo',
                    style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                const SizedBox(height: 12),
                BalanceLine(labels: [for (final b in bars) b.label], valuesCents: cumulative),
              ],
            ),
          ),

          // ------------------------------------- comparación entre años
          if (p.kind == PeriodKind.year) ...[
            const SizedBox(height: 12),
            _YearComparisonCard(year: p.cycleYear, cycle: p.cycle),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.cents, required this.color});
  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(cents),
              style: context.text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
            ),
          ),
        ],
      );
}

class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.label,
    required this.current,
    required this.previous,
    required this.against,
    required this.higherIsBad,
  });
  final String label;
  final int current;
  final int previous;
  final String against;
  final bool higherIsBad;

  @override
  Widget build(BuildContext context) {
    final change = Money.percentChange(previous, current);
    final diff = current - previous;
    final bad = higherIsBad ? diff > 0 : diff < 0;
    final color = diff == 0 ? context.colors.onSurfaceVariant : (bad ? AppColors.warning : AppColors.income);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(diff >= 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              change == null
                  ? '$label: sin datos de $against'
                  : '$label ${diff >= 0 ? '+' : ''}${change.toStringAsFixed(0)} % que $against '
                      '(${Money.formatSigned(diff, positive: diff >= 0)})',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearComparisonCard extends ConsumerWidget {
  const _YearComparisonCard({required this.year, required this.cycle});
  final int year;
  final MonthCycle cycle;

  /// Gastos de cada mes contable.
  List<int> _monthly(Map<String, DayTotal> daily) {
    final result = List<int>.filled(12, 0);
    for (final d in daily.values) {
      final month = cycle.monthOf(Dates.parseKey(d.dayKey)).month;
      result[month - 1] += d.expenseCents;
    }
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (cs, ce) = cycle.yearRange(year);
    final (ps, pe) = cycle.yearRange(year - 1);
    final current = ref.watch(dailyTotalsProvider(rangeOf(cs, ce))).value ?? const {};
    final previous = ref.watch(dailyTotalsProvider(rangeOf(ps, pe))).value ?? const {};
    final cur = _monthly(current);
    final prev = _monthly(previous);
    final curTotal = cur.fold<int>(0, (a, b) => a + b);
    final prevTotal = prev.fold<int>(0, (a, b) => a + b);

    return SectionCard(
      title: 'Gastos $year frente a ${year - 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YearComparisonChart(
            currentCents: cur,
            previousCents: prev,
            currentLabel: '$year',
            previousLabel: '${year - 1}',
          ),
          const SizedBox(height: 8),
          Text('Total: ${Money.format(curTotal)} en $year · ${Money.format(prevTotal)} en ${year - 1}',
              style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
