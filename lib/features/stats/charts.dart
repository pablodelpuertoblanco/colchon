import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/models.dart';
import '../../domain/period.dart';

/// Ingresos y gastos de un tramo (una barra doble del gráfico).
class BarData {
  const BarData(this.label, this.incomeCents, this.expenseCents);
  final String label;
  final int incomeCents;
  final int expenseCents;
  int get balanceCents => incomeCents - expenseCents;
}

/// Reparte los totales diarios en los tramos de un periodo.
List<BarData> bucketize(List<Bucket> buckets, Map<String, DayTotal> daily) {
  final income = List<int>.filled(buckets.length, 0);
  final expense = List<int>.filled(buckets.length, 0);
  for (final d in daily.values) {
    final date = Dates.parseKey(d.dayKey);
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].contains(date)) {
        income[i] += d.incomeCents;
        expense[i] += d.expenseCents;
        break;
      }
    }
  }
  return [for (var i = 0; i < buckets.length; i++) BarData(buckets[i].label, income[i], expense[i])];
}

int _labelStep(int n) => n > 16 ? (n / 8).ceil() : 1;

Widget _bottomLabel(BuildContext context, List<String> labels, double value) {
  final i = value.round();
  if (i < 0 || i >= labels.length || (value - i).abs() > 0.01) return const SizedBox.shrink();
  if (i % _labelStep(labels.length) != 0) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(labels[i], style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

FlTitlesData _titles(BuildContext context, List<String> labels) => FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          interval: 1,
          getTitlesWidget: (value, meta) => _bottomLabel(context, labels, value),
        ),
      ),
    );

FlGridData _grid(BuildContext context, double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => FlLine(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        strokeWidth: 1,
      ),
    );

/// Barras dobles de ingresos (verde) y gastos (coral).
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars({super.key, required this.data, this.height = 200});
  final List<BarData> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxCents = 0;
    for (final b in data) {
      maxCents = math.max(maxCents, math.max(b.incomeCents, b.expenseCents));
    }
    final maxY = maxCents == 0 ? 1.0 : Money.toChart(maxCents) * 1.15;
    final n = data.length;
    final rodWidth = n <= 7 ? 12.0 : (n <= 12 ? 8.0 : 5.0);
    const radius = BorderRadius.vertical(top: Radius.circular(3));

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(
                      toY: Money.toChart(data[i].incomeCents), color: AppColors.income, width: rodWidth, borderRadius: radius),
                  BarChartRodData(
                      toY: Money.toChart(data[i].expenseCents), color: AppColors.expense, width: rodWidth, borderRadius: radius),
                ],
              ),
          ],
          gridData: _grid(context, maxY / 4),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, [for (final b in data) b.label]),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${rodIndex == 0 ? 'Ingresos' : 'Gastos'}\n${Money.format((rod.toY * 100).round())}',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Leyenda de un color con su texto.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
        ],
      );
}

/// Gráfico de anillo por categorías con el total en el centro.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.totals,
    required this.centerTitle,
    required this.centerValue,
    this.onTapCategory,
    this.size = 200,
  });

  final List<CategoryTotal> totals;
  final String centerTitle;
  final String centerValue;
  final ValueChanged<CategoryTotal>? onTapCategory;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sum = totals.fold<int>(0, (s, t) => s + t.totalCents);
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (sum == 0)
            Container(
              width: size * 0.92,
              height: size * 0.92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.outlineVariant, width: size * 0.12),
              ),
            )
          else
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: size * 0.30,
                startDegreeOffset: -90,
                sections: [
                  for (final t in totals)
                    PieChartSectionData(
                      value: t.totalCents.toDouble(),
                      color: Color(t.color),
                      radius: size * 0.16,
                      showTitle: false,
                    ),
                ],
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (onTapCategory == null || event is! FlTapUpEvent) return;
                    final idx = response?.touchedSection?.touchedSectionIndex ?? -1;
                    if (idx >= 0 && idx < totals.length) onTapCategory!(totals[idx]);
                  },
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerTitle, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
              Text(centerValue,
                  style: TextStyle(
                      fontSize: size > 150 ? 18 : 13, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Línea de evolución (balance o ahorro acumulado).
class BalanceLine extends StatelessWidget {
  const BalanceLine({super.key, required this.labels, required this.valuesCents, this.height = 180});
  final List<String> labels;
  final List<int> valuesCents;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (valuesCents.isEmpty) return SizedBox(height: height);
    final values = valuesCents.map(Money.toChart).toList();
    var minY = math.min(0.0, values.reduce(math.min));
    var maxY = math.max(0.0, values.reduce(math.max));
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.12;
    minY = minY < 0 ? minY - pad : 0;
    maxY += pad;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: values.length <= 12),
              belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.10)),
            ),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: 0, color: scheme.outline, strokeWidth: 1, dashArray: [4, 4]),
          ]),
          gridData: _grid(context, (maxY - minY) / 4),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, labels),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    Money.format((s.y * 100).round()),
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gastos mes a mes de este año frente al anterior.
class YearComparisonChart extends StatelessWidget {
  const YearComparisonChart({
    super.key,
    required this.currentCents,
    required this.previousCents,
    required this.currentLabel,
    required this.previousLabel,
  });

  final List<int> currentCents;
  final List<int> previousCents;
  final String currentLabel;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [...currentCents, ...previousCents];
    final maxCents = all.isEmpty ? 0 : all.reduce(math.max);
    final maxY = maxCents == 0 ? 1.0 : Money.toChart(maxCents) * 1.15;
    final labels = [for (final m in Dates.monthShort) m.substring(0, 1).toUpperCase()];

    LineChartBarData line(List<int> cents, Color color, {List<int>? dash}) => LineChartBarData(
          spots: [for (var i = 0; i < cents.length; i++) FlSpot(i.toDouble(), Money.toChart(cents[i]))],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.5,
          dashArray: dash,
          dotData: const FlDotData(show: false),
        );

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                line(previousCents, scheme.outline, dash: [6, 4]),
                line(currentCents, AppColors.expense),
              ],
              gridData: _grid(context, maxY / 4),
              borderData: FlBorderData(show: false),
              titlesData: _titles(context, labels),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.barIndex == 0 ? previousLabel : currentLabel}: ${Money.format((s.y * 100).round())}',
                        TextStyle(color: scheme.onInverseSurface, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            LegendDot(color: AppColors.expense, label: 'Gastos $currentLabel'),
            LegendDot(color: scheme.outline, label: 'Gastos $previousLabel'),
          ],
        ),
      ],
    );
  }
}

/// Fila del ranking de categorías: emoji, nombre, barra de proporción,
/// importe y porcentaje.
class CategoryRankRow extends StatelessWidget {
  const CategoryRankRow({super.key, required this.total, required this.sumCents, this.position, this.onTap});
  final CategoryTotal total;
  final int sumCents;
  final int? position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = sumCents == 0 ? 0.0 : total.totalCents / sumCents;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            if (position != null)
              SizedBox(
                width: 22,
                child: Text('$position', style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
              ),
            Text(total.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(total.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(Money.format(total.totalCents),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 6,
                            color: Color(total.color),
                            backgroundColor: context.colors.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)} %',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
