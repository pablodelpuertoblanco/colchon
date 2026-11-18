import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/period.dart';
import '../transactions/transaction_tile.dart';
import 'charts.dart';

/// Media mensual de la categoría en los últimos 3, 6 y 12 meses contables
/// completos, y cómo va el mes frente a cada media.
class _AveragesCard extends ConsumerWidget {
  const _AveragesCard({required this.categoryId, required this.period, required this.type});
  final String categoryId;
  final Period period;
  final TxType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El mes del periodo que se está viendo (o el actual, si el periodo acaba
    // en el futuro, como un año en curso).
    final today = Dates.today();
    final month = period.cycle.monthOf(period.end.isAfter(today) ? today : period.end);
    final data = ref.watch(categoryAveragesProvider((categoryId: categoryId, month: month))).value;
    if (data == null) return const SizedBox.shrink();
    final muted = TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant);
    final hasHistory = data.averages.values.any((v) => v != null);

    return SectionCard(
      title: 'Media mensual',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${Dates.monthYear(month)}: ${Money.format(data.currentCents)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (!hasHistory)
            Text('Aún no hay meses anteriores con datos para calcular la media.', style: muted)
          else
            Row(
              children: [
                for (final n in const [3, 6, 12])
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$n meses', style: muted),
                        Text(
                          data.averages[n] == null ? '—' : Money.format(data.averages[n]!),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                        ),
                        _Change(pct: data.changeVs(n), isExpense: type == TxType.expense),
                      ],
                    ),
                  ),
              ],
            ),
          if (hasHistory) ...[
            const SizedBox(height: 8),
            Text('El porcentaje compara este mes con cada media. Solo cuentan meses completos con datos.', style: muted),
          ],
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.pct, required this.isExpense});
  final double? pct;
  final bool isExpense;

  @override
  Widget build(BuildContext context) {
    final p = pct;
    if (p == null) return Text(' ', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant));
    final up = p > 0.5;
    final down = p < -0.5;
    // Gastar más que la media es malo; cobrar más, bueno.
    final bad = isExpense ? up : down;
    final color = !up && !down ? context.colors.onSurfaceVariant : (bad ? AppColors.warning : AppColors.income);
    return Text(
      '${p > 0 ? '+' : ''}${p.toStringAsFixed(0)} %',
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
    );
  }
}

/// Detalle de una categoría: total del periodo, medias mensuales, evolución
/// de 6 meses y los movimientos que la componen.
class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.categoryId, required this.period, required this.type});
  final String categoryId;
  final Period period;
  final TxType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryMapProvider).value?[categoryId];
    final txs = ref.watch(filteredTxProvider(TxFilter(
      categoryIds: {categoryId},
      from: period.start,
      to: period.end,
      type: type,
      limit: 1000,
    )));

    // Evolución de los 6 meses (contables) que terminan en el final del periodo.
    final cycle = period.cycle;
    final endMonth = cycle.monthOf(period.end);
    final firstMonth = Dates.shiftMonth(endMonth, -5);
    final start = cycle.startOf(firstMonth);
    final end = cycle.endOf(endMonth);
    final daily = ref
            .watch(categoryDailyTotalsProvider((from: Dates.key(start), to: Dates.key(end), categoryId: categoryId)))
            .value ??
        const <String, DayTotal>{};
    final bars = bucketize(Period.monthBuckets(firstMonth, 6, cycle), daily);
    final monthly = [for (final b in bars) type == TxType.expense ? b.expenseCents : b.incomeCents];

    return Scaffold(
      appBar: AppBar(title: Text(category == null ? 'Categoría' : '${category.emoji} ${category.name}')),
      body: txs.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (list) {
          final confirmed = list.where((t) => !t.isPending).toList();
          final total = confirmed.fold<int>(0, (s, t) => s + t.amountCents);
          final average = confirmed.isEmpty ? 0 : total ~/ confirmed.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(period.label, style: TextStyle(color: context.colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    AmountText(total, type: type, signed: false, style: context.text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${confirmed.length} ${confirmed.length == 1 ? 'movimiento' : 'movimientos'}'
                      '${confirmed.isEmpty ? '' : ' · media ${Money.format(average)}'}',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AveragesCard(categoryId: categoryId, period: period, type: type),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Últimos 6 meses',
                child: BalanceLine(
                  labels: [for (final b in bars) b.label],
                  valuesCents: monthly,
                  height: 160,
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Movimientos',
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No hay movimientos en este periodo.'),
                      )
                    : Column(children: [for (final tx in list) TransactionTile(tx: tx, showDate: true)]),
              ),
            ],
          );
        },
      ),
    );
  }
}
