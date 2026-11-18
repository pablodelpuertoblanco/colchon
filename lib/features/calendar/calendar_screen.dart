import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../transactions/transaction_tile.dart';

/// Calendario económico: cada día muestra si hubo ingresos o gastos y la
/// intensidad del color indica cuánto se gastó.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _month = Dates.startOfMonth(Dates.today());

  void _shift(int delta) {
    setState(() => _month = Dates.addMonthsClamped(_month, delta, day: 1));
    // Mantiene un día seleccionado dentro del mes visible.
    final selected = ref.read(calendarDayProvider);
    if (selected.year != _month.year || selected.month != _month.month) {
      final today = Dates.today();
      final inMonth = today.year == _month.year && today.month == _month.month;
      ref.read(calendarDayProvider.notifier).select(inMonth ? today : _month);
    }
  }

  Future<void> _chooseMonth() async {
    final m = await pickMonth(context, initial: _month);
    if (m == null) return;
    setState(() => _month = m);
    ref.read(calendarDayProvider.notifier).select(m);
  }

  @override
  Widget build(BuildContext context) {
    final start = Dates.startOfMonth(_month);
    final end = Dates.endOfMonth(_month);
    final daily = ref.watch(dailyTotalsProvider(rangeOf(start, end))).value ?? const <String, DayTotal>{};
    final selected = ref.watch(calendarDayProvider);
    final dayTxs = ref.watch(dayTxProvider(Dates.key(selected)));

    var monthIncome = 0, monthExpense = 0, maxExpense = 0;
    for (final d in daily.values) {
      monthIncome += d.incomeCents;
      monthExpense += d.expenseCents;
      maxExpense = math.max(maxExpense, d.expenseCents);
    }
    final dayTotal = daily[Dates.key(selected)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [
          TextButton(
            onPressed: () {
              final today = Dates.today();
              setState(() => _month = Dates.startOfMonth(today));
              ref.read(calendarDayProvider.notifier).select(today);
            },
            child: const Text('Hoy'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
        children: [
          PeriodSwitcher(
            label: Dates.monthYear(_month),
            onPrevious: () => _shift(-1),
            onNext: () => _shift(1),
            onTapLabel: _chooseMonth,
          ),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: _Total(label: 'Ingresos', cents: monthIncome, color: AppColors.income)),
                      Expanded(child: _Total(label: 'Gastos', cents: monthExpense, color: AppColors.expense)),
                      Expanded(
                        child: _Total(
                          label: 'Balance',
                          cents: monthIncome - monthExpense,
                          color: monthIncome - monthExpense >= 0 ? AppColors.income : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  // Deslizar a izquierda/derecha cambia de mes.
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -200) _shift(1);
                    if (v > 200) _shift(-1);
                  },
                  child: _MonthGrid(
                    month: _month,
                    daily: daily,
                    maxExpense: maxExpense,
                    selected: selected,
                    onSelect: (d) => ref.read(calendarDayProvider.notifier).select(d),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(Dates.relativeDay(selected), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(child: _Total(label: 'Ingresado', cents: dayTotal?.incomeCents ?? 0, color: AppColors.income)),
                      Expanded(child: _Total(label: 'Gastado', cents: dayTotal?.expenseCents ?? 0, color: AppColors.expense)),
                      Expanded(
                        child: _Total(
                          label: 'Balance del día',
                          cents: dayTotal?.balanceCents ?? 0,
                          color: (dayTotal?.balanceCents ?? 0) >= 0 ? AppColors.income : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                dayTxs.when(
                  loading: () => const LoadingBox(height: 60),
                  error: (e, _) => ErrorBox(e),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Sin movimientos este día. Pulsa + para añadir uno.',
                              textAlign: TextAlign.center, style: TextStyle(color: context.colors.onSurfaceVariant)),
                        )
                      : Column(children: [for (final tx in list) TransactionTile(tx: tx)]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.cents, required this.color});
  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Money.format(cents),
              style: TextStyle(fontWeight: FontWeight.w700, color: color, fontFeatures: tabularFigures),
            ),
          ),
        ],
      );
}

/// Cuadrícula mensual de lunes a domingo, hecha a medida.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.daily,
    required this.maxExpense,
    required this.selected,
    required this.onSelect,
  });

  final DateTime month;
  final Map<String, DayTotal> daily;
  final int maxExpense;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = Dates.startOfMonth(month);
    final daysInMonth = Dates.daysInMonth(month.year, month.month);
    final leading = first.weekday - 1; // huecos antes del día 1 (lunes = 0)
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = Dates.today();

    return Column(
      children: [
        Row(
          children: [
            for (final l in Dates.weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(l, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final dayNumber = r * 7 + c - leading + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox(height: 52);
                    final date = DateTime(month.year, month.month, dayNumber);
                    return _DayCell(
                      date: date,
                      total: daily[Dates.key(date)],
                      maxExpense: maxExpense,
                      isSelected: Dates.sameDay(date, selected),
                      isToday: Dates.sameDay(date, today),
                      onTap: () => onSelect(date),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.total,
    required this.maxExpense,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final DayTotal? total;
  final int maxExpense;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expense = total?.expenseCents ?? 0;
    final income = total?.incomeCents ?? 0;
    // Intensidad de 0,08 a 0,45 según lo gastado ese día respecto al máximo.
    final intensity = maxExpense == 0 || expense == 0 ? 0.0 : 0.08 + 0.37 * (expense / maxExpense);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: intensity > 0 ? AppColors.expense.withValues(alpha: intensity) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? context.colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? context.colors.primary : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (income > 0) const _Dot(color: AppColors.income),
                    if (income > 0 && expense > 0) const SizedBox(width: 3),
                    if (expense > 0) const _Dot(color: AppColors.expense),
                    if (income == 0 && expense == 0) const SizedBox(height: 6),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 0.5)),
      );
}
