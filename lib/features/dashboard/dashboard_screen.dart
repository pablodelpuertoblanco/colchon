import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/period.dart';
import '../../domain/plan.dart';
import '../budgets/budget_widgets.dart';
import '../budgets/budgets_screen.dart';
import '../forecast/forecast_screen.dart';
import '../health/health_screen.dart';
import '../net_worth/net_worth_screen.dart';
import '../plan/plan_screen.dart';
import '../plan/plan_widgets.dart';
import '../settings/settings_screen.dart';
import '../stats/category_detail_screen.dart';
import '../stats/charts.dart';
import '../transactions/transaction_form_screen.dart';
import '../transactions/transaction_tile.dart';

/// Inicio: cómo están las finanzas de casa de un vistazo.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Mes contable elegido (null = el actual).
  DateTime? _month;

  void _shiftMonth(DateTime month, int delta) => setState(() => _month = Dates.shiftMonth(month, delta));

  Future<void> _chooseMonth(DateTime month) async {
    final m = await pickMonth(context, initial: month);
    if (m != null) setState(() => _month = m);
  }

  @override
  Widget build(BuildContext context) {
    final cycle = ref.watch(monthCycleProvider);
    final month = _month ?? cycle.monthOf(Dates.today());
    final period = Period.ofMonth(month, cycle: cycle);
    final isCurrentMonth = period.contains(Dates.today());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colchón'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          PeriodSwitcher(
            label: Dates.monthYear(month),
            subtitle: cycle.isCalendar ? null : cycle.rangeLabel(month),
            onPrevious: () => _shiftMonth(month, -1),
            onNext: () => _shiftMonth(month, 1),
            onTapLabel: () => _chooseMonth(month),
          ),
          _BalanceCard(period: period, isCurrentMonth: isCurrentMonth),
          const SizedBox(height: 12),
          const _QuickAdd(),
          if (isCurrentMonth) const _PendingAndUpcoming(),
          const SizedBox(height: 12),
          _PlanCard(month: month),
          const SizedBox(height: 12),
          if (isCurrentMonth) const HealthSummaryCard(),
          const _BudgetsCard(),
          _NetWorthCard(month: month),
          const SizedBox(height: 12),
          _TopCategoriesCard(period: period),
          const SizedBox(height: 12),
          _EvolutionCard(month: month, cycle: cycle),
          const SizedBox(height: 12),
          const _RecentCard(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.period, required this.isCurrentMonth});
  final Period period;
  final bool isCurrentMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prev = period.previous();
    final totals = ref.watch(totalsProvider(rangeOf(period.start, period.end))).value ?? const Totals();
    final prevTotals = ref.watch(totalsProvider(rangeOf(prev.start, prev.end))).value ?? const Totals();
    final available = ref.watch(availableBalanceProvider).value;
    final initial = ref.watch(initialBalanceProvider);
    final monthName = Dates.monthNames[period.cycleMonth!.month - 1];

    final expenseChange = Money.percentChange(prevTotals.expenseCents, totals.expenseCents);
    final rate = totals.savingsRate;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Balance de $monthName', style: TextStyle(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          AmountText(totals.balanceCents, style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Ingresos', cents: totals.incomeCents, type: TxType.income)),
              Expanded(child: _MiniStat(label: 'Gastos', cents: totals.expenseCents, type: TxType.expense)),
            ],
          ),
          const SizedBox(height: 12),
          if (expenseChange != null)
            _InfoLine(
              icon: expenseChange > 0 ? Icons.trending_up : Icons.trending_down,
              color: expenseChange > 0 ? AppColors.warning : AppColors.income,
              text: 'Gastos ${expenseChange > 0 ? '+' : ''}${expenseChange.toStringAsFixed(0)} % respecto a ${period.previousLabel}',
            ),
          if (totals.balanceCents > 0 && rate != null)
            _InfoLine(
              icon: Icons.savings_outlined,
              color: AppColors.income,
              text: 'Ahorrado: ${Money.format(totals.balanceCents)} (${rate.toStringAsFixed(0)} % de los ingresos)',
            ),
          const Divider(height: 24),
          if (initial == null)
            InkWell(
              onTap: () => showInitialBalanceDialog(context, ref),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: context.colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Indica tu saldo inicial para ver el dinero disponible',
                        style: TextStyle(color: context.colors.primary)),
                  ),
                ],
              ),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openForecast(context),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Dinero disponible')),
                  Text(
                    available == null ? '…' : Money.format(available),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                      color: (available ?? 0) < 0 ? AppColors.danger : null,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: context.colors.onSurfaceVariant),
                ],
              ),
            ),
          if (initial != null && available != null && isCurrentMonth) _MinBalanceWarning(available: available),
        ],
      ),
    );
  }
}

/// Aviso del "mínimo del que no debo bajar": ahora o según la previsión de
/// saldo (recurrentes y lo que queda del plan), con la fecha en que se
/// cruzaría. Al tocarlo se abre la previsión.
class _MinBalanceWarning extends ConsumerWidget {
  const _MinBalanceWarning({required this.available});
  final int available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final min = ref.watch(minBalanceProvider);
    final forecast = ref.watch(forecastProvider).value;
    final below = min == null ? null : forecast?.firstBelow(min);
    final Widget line;
    if (min != null && available < min) {
      line = _InfoLine(
        icon: Icons.warning_amber_rounded,
        color: AppColors.danger,
        text: 'Estás ${Money.format(min - available)} por debajo de tu mínimo (${Money.formatShort(min)})',
      );
    } else if (min != null && below != null) {
      line = _InfoLine(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
        text: 'Según la previsión, el ${Dates.dayMonthShort(below.date)} bajarías de tu mínimo '
            '(${Money.formatShort(min)}): quedarían ${Money.format(below.balanceCents)}',
      );
    } else if (min != null) {
      final low = forecast?.lowest;
      line = _InfoLine(
        icon: Icons.shield_outlined,
        color: AppColors.income,
        text: low == null
            ? 'Margen sobre tu mínimo: ${Money.format(available - min)}'
            : 'Margen sobre tu mínimo: ${Money.format(available - min)}. ${lowestSentence(low)}',
      );
    } else if (forecast?.lowest case final low?) {
      line = _InfoLine(icon: Icons.show_chart, color: context.colors.primary, text: lowestSentence(low));
    } else {
      return const SizedBox.shrink();
    }
    return InkWell(borderRadius: BorderRadius.circular(8), onTap: () => openForecast(context), child: line);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.cents, required this.type});
  final String label;
  final int cents;
  final TxType type;

  @override
  Widget build(BuildContext context) {
    final color = type == TxType.income ? AppColors.income : AppColors.expense;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(type == TxType.income ? Icons.south_west : Icons.north_east, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AmountText(cents, type: type, signed: false, style: context.text.titleMedium),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant))),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------

/// Accesos rápidos a las categorías más usadas.
class _QuickAdd extends ConsumerWidget {
  const _QuickAdd();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(selectableCategoriesProvider(CategoryKind.expense)).value ?? const [];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in cats.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Text(c.emoji),
                label: Text(c.name),
                onPressed: () => openTransactionForm(context, categoryId: c.id),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18, color: AppColors.income),
            label: const Text('Ingreso'),
            onPressed: () => openTransactionForm(context, type: TxType.income),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Recibos pendientes de confirmar y cargos de los próximos 7 días.
class _PendingAndUpcoming extends ConsumerWidget {
  const _PendingAndUpcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTxProvider).value ?? const <TxView>[];
    final upcoming = ref.watch(upcomingProvider(7)).value ?? const <UpcomingCharge>[];
    if (pending.isEmpty && upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'Pendientes y próximos cargos',
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            for (final tx in pending)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(tx.categoryEmoji, style: const TextStyle(fontSize: 24)),
                title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${Dates.relativeDay(tx.date)} · estimado ${Money.format(tx.amountCents)}'),
                trailing: FilledButton.tonal(
                  onPressed: () => openTransactionForm(context, editing: tx, confirmMode: true),
                  child: const Text('Confirmar'),
                ),
              ),
            for (final u in upcoming)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(u.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(u.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(Dates.relativeDay(u.date)),
                trailing: Text(
                  '${u.mode == RecurringMode.confirm ? '≈ ' : ''}${Money.formatSigned(u.amountCents, positive: u.type == TxType.income)}',
                  style: TextStyle(
                    fontFeatures: tabularFigures,
                    fontWeight: FontWeight.w600,
                    color: u.type == TxType.income ? AppColors.income : AppColors.expense,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BudgetsCard extends ConsumerWidget {
  const _BudgetsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const [];
    void openBudgets() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()));

    if (budgets.isEmpty) {
      return SectionCard(
        title: 'Presupuestos',
        onTap: openBudgets,
        child: Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Pon un límite al súper, al ocio o a lo que quieras y te avisaré antes de pasarte.',
                  style: TextStyle(color: context.colors.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }
    final sorted = [...budgets]..sort((a, b) => b.progress.ratio.compareTo(a.progress.ratio));
    return SectionCard(
      title: 'Presupuestos',
      trailing: TextButton(onPressed: openBudgets, child: const Text('Ver todos')),
      child: Column(
        children: [for (final b in sorted.take(3)) BudgetProgressRow(view: b, onTap: openBudgets)],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Resumen del plan del mes: gastado frente a previsto, 50/30/20 y ahorro real.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planYearProvider(month.year)).value;
    final targets = ref.watch(ruleTargetsProvider);
    if (plan == null) return const SizedBox.shrink();
    void open() => openPlan(context, month: month);

    if (!plan.hasPlan) {
      return SectionCard(
        title: 'Plan ${month.year}',
        onTap: open,
        child: Row(
          children: [
            const Text('🗓️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Prevé cuánto ingresas y gastas cada mes por categoría (o importa un Excel .xlsx) y compara con lo real.',
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final m = plan.monthAt(month.month);
    final t = m.totals;
    final planned = t.expenseCents(real: false);
    final spent = t.expenseCents(real: true);
    final ratio = planned == 0 ? 0.0 : spent / planned;
    final left = planned - spent;
    final savings = t.realSavingsCents(real: true);
    final savingsPct = t.shareOfIncome(savings, real: true);
    final over = [for (final s in m.sections) ...s.lines.where((l) => l.isOver && l.plannedCents > 0)]
      ..sort((a, b) => (b.realCents - b.plannedCents).compareTo(a.realCents - a.plannedCents));
    final hasIncome = t.ownIncomeCents(real: true) > 0;

    return SectionCard(
      title: 'Plan de ${Dates.monthNames[month.month - 1]}',
      onTap: open,
      trailing: TextButton(onPressed: open, child: const Text('Ver plan')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Gastado', style: TextStyle(fontWeight: FontWeight.w600))),
              Text('${Money.formatShort(spent)} / ${Money.formatShort(planned)}',
                  style: TextStyle(fontFeatures: tabularFigures, color: context.colors.onSurfaceVariant, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              color: ratio > 1 ? AppColors.danger : (ratio >= 0.85 ? AppColors.warning : AppColors.income),
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            left >= 0 ? 'Quedan ${Money.format(left)} de lo previsto' : 'Te has pasado ${Money.format(-left)} del plan',
            style: TextStyle(fontSize: 12, color: left >= 0 ? context.colors.onSurfaceVariant : AppColors.danger),
          ),
          if (hasIncome) ...[
            const SizedBox(height: 12),
            for (final b in RuleBucket.values) _MiniRule(bucket: b, totals: t, target: targets.of(b)),
            const SizedBox(height: 8),
            Text(
              'Ahorro real: ${Money.format(savings)}${savingsPct == null ? '' : ' (${savingsPct.toStringAsFixed(0)} % de los ingresos)'}',
              style: TextStyle(fontSize: 13, color: savings >= 0 ? AppColors.income : AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ],
          for (final l in over.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠️ ${l.category.name}: ${Money.formatShort(l.realCents)} de ${Money.formatShort(l.plannedCents)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniRule extends StatelessWidget {
  const _MiniRule({required this.bucket, required this.totals, required this.target});
  final RuleBucket bucket;
  final PlanTotals totals;
  final int target;

  @override
  Widget build(BuildContext context) {
    final pct = totals.shareOfIncome(totals.bucketCents(bucket, real: true), real: true) ?? 0;
    final bad = bucket == RuleBucket.savings ? pct < target - 0.5 : pct > target + 0.5;
    final color = bad ? AppColors.warning : AppColors.income;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(bucket.label, style: const TextStyle(fontSize: 13))),
          Expanded(child: TargetBar(valuePct: pct, targetPct: target.toDouble(), color: color, height: 6)),
          SizedBox(
            width: 64,
            child: Text('${pct.toStringAsFixed(0)}/$target %',
                textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: color, fontFeatures: tabularFigures)),
          ),
        ],
      ),
    );
  }
}

/// Patrimonio neto (solo si hay bienes o deudas apuntados).
class _NetWorthCard extends ConsumerWidget {
  const _NetWorthCard({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worth = ref.watch(netWorthProvider(month));
    if (worth == null || worth.positions.isEmpty) return const SizedBox.shrink();
    final change = worth.changeCents;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'Patrimonio',
        onTap: () => openNetWorth(context),
        trailing: const Icon(Icons.chevron_right),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Money.format(worth.netCents),
                      style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                  if (change != 0)
                    Text(
                      '${Money.formatSigned(change, positive: change > 0)} este mes',
                      style: TextStyle(fontSize: 13, color: change > 0 ? AppColors.income : AppColors.expense),
                    ),
                ],
              ),
            ),
            if (worth.pendingUpdates > 0) const Tag('Por actualizar', icon: Icons.edit_calendar_outlined),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopCategoriesCard extends ConsumerWidget {
  const _TopCategoriesCard({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref
            .watch(categoryTotalsProvider(
                (from: period.fromKey, to: period.toKey, type: TxType.expense, grouped: true)))
            .value ??
        const <CategoryTotal>[];
    final sum = totals.fold<int>(0, (s, t) => s + t.totalCents);

    void openCategory(CategoryTotal t) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CategoryDetailScreen(categoryId: t.categoryId, period: period, type: TxType.expense),
        ));

    return SectionCard(
      title: 'En qué se va el dinero',
      trailing: TextButton(
        onPressed: () => ref.read(selectedTabProvider.notifier).select(3),
        child: const Text('Estadísticas'),
      ),
      child: totals.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Sin gastos este mes.', style: TextStyle(color: context.colors.onSurfaceVariant)),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CategoryDonut(
                  totals: totals,
                  size: 120,
                  centerTitle: 'Gastos',
                  centerValue: Money.formatShort(sum),
                  onTapCategory: openCategory,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (final t in totals.take(5))
                        InkWell(
                          onTap: () => openCategory(t),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: Color(t.color), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('${t.emoji} ${t.name}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                ),
                                Text('${(t.totalCents * 100 / sum).round()} %',
                                    style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EvolutionCard extends ConsumerWidget {
  const _EvolutionCard({required this.month, required this.cycle});
  final DateTime month;
  final MonthCycle cycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = Dates.shiftMonth(month, -5);
    final start = cycle.startOf(first);
    final end = cycle.endOf(month);
    final daily = ref.watch(dailyTotalsProvider(rangeOf(start, end))).value ?? const <String, DayTotal>{};
    final data = bucketize(Period.monthBuckets(first, 6, cycle), daily);

    return SectionCard(
      title: 'Últimos 6 meses',
      child: Column(
        children: [
          IncomeExpenseBars(data: data, height: 170),
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
    );
  }
}

// ---------------------------------------------------------------------------

class _RecentCard extends ConsumerWidget {
  const _RecentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTxProvider).value ?? const <TxView>[];
    return SectionCard(
      title: 'Últimos movimientos',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      trailing: TextButton(
        onPressed: () => ref.read(selectedTabProvider.notifier).select(1),
        child: const Text('Ver todos'),
      ),
      child: recent.isEmpty
          ? const EmptyState(
              emoji: '👋',
              title: 'Empieza registrando un gasto',
              message: 'Pulsa el botón + de abajo. Solo necesitas el importe y la categoría.',
            )
          : Column(
              children: [for (final tx in recent) TransactionTile(tx: tx, showDate: true)],
            ),
    );
  }
}
