import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/forecast.dart';
import '../settings/settings_screen.dart';

void openForecast(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ForecastScreen()));

/// Frase del punto más bajo: "El 5 dic bajarás a 312,40 €".
String lowestSentence(ForecastDay low) => Dates.sameDay(low.date, Dates.today())
    ? 'Hoy estás en tu punto más bajo: ${Money.format(low.balanceCents)}'
    : 'El ${Dates.dayMonthShort(low.date)} bajarás a ${Money.format(low.balanceCents)}';

/// Cómo evolucionará el dinero disponible día a día.
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(forecastProvider);
    final months = ref.watch(forecastMonthsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsión de saldo'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Meses de previsión',
            initialValue: months,
            onSelected: (n) => ref.read(settingsRepoProvider).set(SettingKeys.forecastMonths, '$n'),
            itemBuilder: (_) => [
              for (final n in const [1, 2, 3, 6, 9, 12])
                PopupMenuItem(value: n, child: Text(n == 1 ? 'Este mes' : '$n meses')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [Text(months == 1 ? 'Este mes' : '$months meses'), const Icon(Icons.arrow_drop_down)]),
            ),
          ),
        ],
      ),
      body: forecast.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (f) => f == null
            ? EmptyState(
                emoji: '🔮',
                title: 'Indica tu saldo inicial',
                message: 'La previsión parte del dinero que tienes hoy. Dinos cuánto tenías en una fecha y la app '
                    'lo calcula con tus movimientos.',
                action: FilledButton(
                  onPressed: () => showInitialBalanceDialog(context, ref),
                  child: const Text('Indicar saldo inicial'),
                ),
              )
            : _ForecastBody(forecast: f),
      ),
    );
  }
}

class _ForecastBody extends ConsumerWidget {
  const _ForecastBody({required this.forecast});
  final Forecast forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = forecast;
    final min = ref.watch(minBalanceProvider);
    final low = f.lowest;
    final below = min == null ? null : f.firstBelow(min);
    final spreadTotal = f.days.fold<int>(0, (s, d) => s - d.spreadCents);
    final dated = [for (final d in f.days) if (d.datedEvents.isNotEmpty) d];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _Figure(label: 'Hoy', cents: f.startBalanceCents)),
                  if (f.endDate != null)
                    Expanded(child: _Figure(label: 'El ${Dates.dayMonthShort(f.endDate!)}', cents: f.endBalanceCents)),
                ],
              ),
              const SizedBox(height: 12),
              if (low != null)
                _Line(
                  icon: Icons.south_east,
                  color: low.balanceCents < 0 ? AppColors.danger : context.colors.onSurfaceVariant,
                  text: lowestSentence(low),
                  bold: true,
                ),
              if (min != null)
                below == null
                    ? _Line(
                        icon: Icons.shield_outlined,
                        color: AppColors.income,
                        text: 'No bajarás de tu mínimo (${Money.formatShort(min)})',
                      )
                    : _Line(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.danger,
                        text: Dates.sameDay(below.date, Dates.today())
                            ? 'Ya estás por debajo de tu mínimo (${Money.formatShort(min)})'
                            : 'El ${Dates.dayMonthShort(below.date)} bajarías de tu mínimo '
                                '(${Money.formatShort(min)}): quedarían ${Money.format(below.balanceCents)}',
                      ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Saldo previsto',
          child: ForecastChart(days: f.days, minCents: min),
        ),
        if (spreadTotal != 0) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: _Line(
              icon: Icons.info_outline,
              color: context.colors.onSurfaceVariant,
              text: 'Las partidas del plan sin día fijo (${Money.format(spreadTotal.abs())} en total) se reparten a '
                  'partes iguales entre los días que quedan de cada mes. Indica su día habitual en la categoría o en '
                  'el plan para afinar la previsión.',
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Próximos cargos e ingresos', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (dated.isEmpty)
          const EmptyState(
            emoji: '📭',
            title: 'Nada con fecha',
            message: 'Añade recurrentes o el día habitual de tus partidas del plan.',
          )
        else
          for (final d in dated) _DayCard(day: d),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.cents});
  final String label;
  final int cents;

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
              style: context.text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
                color: cents < 0 ? AppColors.danger : null,
              ),
            ),
          ),
        ],
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text, this.bold = false});
  final IconData icon;
  final Color color;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null)),
            ),
          ],
        ),
      );
}

/// Un día con movimientos previstos y el saldo con el que acaba.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final ForecastDay day;

  @override
  Widget build(BuildContext context) {
    final spread = day.spreadCents;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(Dates.relativeDay(day.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('saldo ', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                Text(
                  Money.format(day.balanceCents),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures,
                    color: day.balanceCents < 0 ? AppColors.danger : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in day.datedEvents) _EventRow(event: e),
            if (spread != 0)
              _EventRowRaw(
                emoji: '📆',
                label: 'Gasto diario repartido',
                tag: 'Plan',
                signedCents: spread,
              ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final ForecastEvent event;

  @override
  Widget build(BuildContext context) => _EventRowRaw(
        emoji: event.emoji,
        label: event.label,
        tag: switch (event.source) {
          ForecastSource.recurring => 'Recurrente',
          ForecastSource.pending => 'Por confirmar',
          ForecastSource.plan || ForecastSource.planSpread => 'Lo que queda del plan',
        },
        signedCents: event.signedCents,
      );
}

class _EventRowRaw extends StatelessWidget {
  const _EventRowRaw({required this.emoji, required this.label, required this.tag, required this.signedCents});
  final String emoji;
  final String label;
  final String tag;
  final int signedCents;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(tag, style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              Money.formatSigned(signedCents, positive: signedCents >= 0),
              style: TextStyle(
                fontFeatures: tabularFigures,
                fontWeight: FontWeight.w600,
                color: signedCents >= 0 ? AppColors.income : AppColors.expense,
              ),
            ),
          ],
        ),
      );
}

/// Línea del saldo previsto, con el mínimo como línea horizontal y el punto
/// más bajo destacado.
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.days, this.minCents, this.height = 220});
  final List<ForecastDay> days;
  final int? minCents;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    if (days.isEmpty) return SizedBox(height: height);
    final values = [for (final d in days) Money.toChart(d.balanceCents)];
    final minLine = minCents == null ? null : Money.toChart(minCents!);
    var lowIndex = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[lowIndex]) lowIndex = i;
    }

    var minY = math.min(values.reduce(math.min), minLine ?? double.infinity);
    var maxY = math.max(values.reduce(math.max), minLine ?? double.negativeInfinity);
    if (minY > 0) minY = 0;
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.1;
    if (minY < 0) minY -= pad;
    maxY += pad;

    // Etiquetas: unas cinco fechas repartidas.
    final step = math.max(1, (days.length / 5).ceil());

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              color: scheme.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.10)),
            ),
            // Punto más bajo.
            LineChartBarData(
              spots: [FlSpot(lowIndex.toDouble(), values[lowIndex])],
              barWidth: 0,
              color: Colors.transparent,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 5,
                  color: values[lowIndex] < (minLine ?? 0) ? AppColors.danger : AppColors.warning,
                  strokeWidth: 2,
                  strokeColor: scheme.surface,
                ),
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (minLine != null)
              HorizontalLine(
                y: minLine,
                color: AppColors.danger,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.w600),
                  labelResolver: (_) => 'mínimo',
                ),
              ),
            if (minY < 0) HorizontalLine(y: 0, color: scheme.outline, strokeWidth: 1, dashArray: [4, 4]),
          ]),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: (maxY - minY) / 4,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                  return Text(Money.formatShort((value * 100).round() ~/ 100 * 100),
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if ((value - i).abs() > 0.01 || i < 0 || i >= days.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(Dates.dayMonthShort(days[i].date),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  s.barIndex == 0
                      ? LineTooltipItem(
                          '${Dates.dayMonthShort(days[s.x.round()].date)}\n${Money.format(days[s.x.round()].balanceCents)}',
                          TextStyle(color: scheme.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                        )
                      : null,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
