import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../categories/category_picker.dart';
import '../forecast/forecast_screen.dart';
import '../import/import_plan_screen.dart';
import '../settings/settings_screen.dart';
import 'plan_line_sheet.dart';
import 'plan_widgets.dart';

/// Abre el plan, opcionalmente en un mes contable concreto.
void openPlan(BuildContext context, {DateTime? month}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanScreen(initialMonth: month)));
}

/// Plan anual: lo previsto frente a lo real, mes a mes y en el año.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.initialMonth});
  final DateTime? initialMonth;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late DateTime? _month = widget.initialMonth;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  DateTime _monthOf(MonthCycle cycle) => _month ?? cycle.monthOf(Dates.today());

  void _shift(DateTime month, int delta) => setState(() => _month = Dates.shiftMonth(month, delta));

  Future<void> _pickMonth(DateTime month) async {
    final m = await pickMonth(context, initial: month);
    if (m != null) setState(() => _month = m);
  }

  void _goToMonth(DateTime month) {
    setState(() => _month = month);
    _tabs.animateTo(0);
  }

  Future<void> _editLine(PlanLine line, DateTime month) async {
    if (ref.read(categoryMapProvider).value?[line.category.id] == null) {
      showSnack(context, 'Esa categoría ya no existe');
      return;
    }
    await showPlanLineSheet(
      context,
      category: line.category,
      month: month,
      plannedCents: line.plannedCents,
      realCents: line.realCents,
    );
  }

  Future<void> _addLine(DateTime month, PlanMonth? planMonth) async {
    final rows = ref.read(categoryMapProvider).value ?? const {};
    final all = rows.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final selectable = all
        .where((c) =>
            !c.isArchived && c.kind != CategoryKind.product && (planMonth?.lineOf(c.id)?.plannedCents ?? 0) == 0)
        .toList()
      // Primero los gastos, luego los ingresos.
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    final id = await showCategoryPicker(
      context,
      selectable: selectable,
      all: all,
      title: 'Añadir al plan de ${Dates.monthNames[month.month - 1]}',
      trailingOf: (c) => c.kind == CategoryKind.income ? 'Ingreso' : (c.budgetGroup?.label ?? ''),
    );
    if (id == null || !mounted) return;
    final category = planCategoriesOf(rows)[id]!;
    final line = planMonth?.lineOf(id);
    await showPlanLineSheet(
      context,
      category: category,
      month: month,
      plannedCents: line?.plannedCents ?? 0,
      realCents: line?.realCents ?? 0,
    );
  }

  Future<void> _copyYear(int from, int to) async {
    final ok = await confirmDialog(
      context,
      title: 'Copiar el plan de $from a $to',
      message: 'Se copian los importes previstos mes a mes. Lo que ya tengas previsto en $to no se toca.',
      confirmLabel: 'Copiar',
    );
    if (!ok) return;
    final n = await ref.read(planRepoProvider).copyYear(from, to);
    if (!mounted) return;
    showSnack(context, n == 0 ? 'No había nada nuevo que copiar' : 'Copiadas $n partidas a $to');
  }

  @override
  Widget build(BuildContext context) {
    final cycle = ref.watch(monthCycleProvider);
    final targets = ref.watch(ruleTargetsProvider);
    final month = _monthOf(cycle);
    final plan = ref.watch(planYearProvider(month.year));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Mes'), Tab(text: 'Año')]),
        actions: [
          IconButton(
            tooltip: 'Previsión de saldo',
            icon: const Icon(Icons.show_chart),
            onPressed: () => openForecast(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'targets':
                  showRuleTargetsDialog(context, ref);
                case 'copy-next':
                  _copyYear(month.year, month.year + 1);
                case 'copy-prev':
                  _copyYear(month.year - 1, month.year);
                case 'start-day':
                  showMonthStartDayDialog(context, ref);
                case 'import':
                  openImportPlan(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'targets', child: Text('Objetivos 50/30/20')),
              const PopupMenuItem(value: 'start-day', child: Text('Día de inicio de mes')),
              PopupMenuItem(value: 'copy-prev', child: Text('Copiar de ${month.year - 1} a ${month.year}')),
              PopupMenuItem(value: 'copy-next', child: Text('Copiar de ${month.year} a ${month.year + 1}')),
              const PopupMenuItem(value: 'import', child: Text('Importar plan (.xlsx)')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan-add',
        onPressed: () => _addLine(month, plan.value?.monthAt(month.month)),
        icon: const Icon(Icons.add),
        label: const Text('Partida'),
      ),
      body: plan.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (year) => TabBarView(
          controller: _tabs,
          children: [
            _MonthTab(
              plan: year,
              month: month,
              cycle: cycle,
              targets: targets,
              onPrevious: () => _shift(month, -1),
              onNext: () => _shift(month, 1),
              onPickMonth: () => _pickMonth(month),
              onEditLine: (l) => _editLine(l, month),
              onEditTargets: () => showRuleTargetsDialog(context, ref),
              onCopyPrevious: () => _copyYear(month.year - 1, month.year),
              onAdd: () => _addLine(month, year.monthAt(month.month)),
            ),
            _YearTab(
              plan: year,
              cycle: cycle,
              targets: targets,
              onPrevious: () => _shift(month, -12),
              onNext: () => _shift(month, 12),
              onTapMonth: _goToMonth,
              onEditTargets: () => showRuleTargetsDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MonthTab extends StatelessWidget {
  const _MonthTab({
    required this.plan,
    required this.month,
    required this.cycle,
    required this.targets,
    required this.onPrevious,
    required this.onNext,
    required this.onPickMonth,
    required this.onEditLine,
    required this.onEditTargets,
    required this.onCopyPrevious,
    required this.onAdd,
  });

  final PlanYear plan;
  final DateTime month;
  final MonthCycle cycle;
  final RuleTargets targets;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickMonth;
  final ValueChanged<PlanLine> onEditLine;
  final VoidCallback onEditTargets;
  final VoidCallback onCopyPrevious;
  final VoidCallback onAdd;

  /// "Llevas el 45 % del mes y has gastado el 52 % de lo previsto".
  String? _progressLine(PlanTotals t) {
    final today = Dates.today();
    final start = cycle.startOf(month);
    final end = cycle.endOf(month);
    if (today.isBefore(start) || today.isAfter(end)) return null;
    final elapsed = (Dates.daysBetween(start, today) + 1) / (Dates.daysBetween(start, end) + 1) * 100;
    final planned = t.expenseCents(real: false);
    if (planned == 0) return 'Llevas el ${elapsed.toStringAsFixed(0)} % del mes';
    final spent = t.expenseCents(real: true) / planned * 100;
    return 'Llevas el ${elapsed.toStringAsFixed(0)} % del mes y has gastado el ${spent.toStringAsFixed(0)} % de lo previsto';
  }

  @override
  Widget build(BuildContext context) {
    final m = plan.monthAt(month.month);
    final t = m.totals;
    final ownIncome = t.ownIncomeCents(real: true);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        PeriodSwitcher(
          label: Dates.monthYear(month),
          subtitle: cycle.isCalendar ? null : cycle.rangeLabel(month),
          onPrevious: onPrevious,
          onNext: onNext,
          onTapLabel: onPickMonth,
        ),
        if (!plan.hasPlan) ...[
          _NoPlanCard(year: plan.year, onCopyPrevious: onCopyPrevious, onAdd: onAdd),
          const SizedBox(height: 12),
        ],
        if (!m.isEmpty) ...[
          PlanSummaryCard(totals: t, progressLine: _progressLine(t)),
          const SizedBox(height: 12),
          RuleCard(totals: t, targets: targets, onEditTargets: onEditTargets),
          for (final s in m.sections) ...[
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlanSectionHeader(section: s, ownIncomeCents: ownIncome),
                  const SizedBox(height: 4),
                  for (final l in s.lines) PlanLineTile(line: l, onTap: () => onEditLine(l)),
                ],
              ),
            ),
          ],
        ] else if (plan.hasPlan)
          const EmptyState(emoji: '🗓️', title: 'Nada previsto este mes', message: 'Pulsa "Partida" para añadir algo.'),
      ],
    );
  }
}

class _NoPlanCard extends StatelessWidget {
  const _NoPlanCard({required this.year, required this.onCopyPrevious, required this.onAdd});
  final int year;
  final VoidCallback onCopyPrevious;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🗓️', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text('Aún no hay plan para $year', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Indica cuánto prevés ingresar y gastar cada mes en cada categoría y verás lo real frente a lo previsto, '
            'como en una hoja de cálculo.',
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => openImportPlan(context),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Importar Excel (.xlsx)'),
              ),
              OutlinedButton(onPressed: onCopyPrevious, child: Text('Copiar de ${year - 1}')),
              TextButton(onPressed: onAdd, child: const Text('Añadir partida')),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _YearTab extends StatelessWidget {
  const _YearTab({
    required this.plan,
    required this.cycle,
    required this.targets,
    required this.onPrevious,
    required this.onNext,
    required this.onTapMonth,
    required this.onEditTargets,
  });

  final PlanYear plan;
  final MonthCycle cycle;
  final RuleTargets targets;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onTapMonth;
  final VoidCallback onEditTargets;

  @override
  Widget build(BuildContext context) {
    final (start, end) = cycle.yearRange(plan.year);
    final ownIncome = plan.totals.ownIncomeCents(real: true);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        PeriodSwitcher(
          label: '${plan.year}',
          subtitle: cycle.isCalendar ? null : '${Dates.dayMonthYearShort(start)} – ${Dates.dayMonthYearShort(end)}',
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        PlanSummaryCard(totals: plan.totals, title: 'Año ${plan.year}'),
        const SizedBox(height: 12),
        RuleCard(totals: plan.totals, targets: targets, title: '50/30/20 en ${plan.year}', onEditTargets: onEditTargets),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Mes a mes',
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: _MonthsTable(plan: plan, cycle: cycle, onTapMonth: onTapMonth),
        ),
        for (final s in plan.annual) ...[
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                title: PlanSectionHeader(section: s, ownIncomeCents: ownIncome),
                children: [
                  for (final l in s.lines)
                    PlanLineTile(
                      line: l,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PlanCategoryYearScreen(categoryId: l.category.id, year: plan.year),
                      )),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tabla de los 12 meses: ingresos, gastos y saldo (real y previsto).
class _MonthsTable extends StatelessWidget {
  const _MonthsTable({required this.plan, required this.cycle, required this.onTapMonth});
  final PlanYear plan;
  final MonthCycle cycle;
  final ValueChanged<DateTime> onTapMonth;

  @override
  Widget build(BuildContext context) {
    final current = cycle.monthOf(Dates.today());
    final headerStyle = TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600);
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 44, child: Text('Mes', style: headerStyle)),
            Expanded(child: Text('Ingresos', textAlign: TextAlign.end, style: headerStyle)),
            Expanded(child: Text('Gastos', textAlign: TextAlign.end, style: headerStyle)),
            Expanded(child: Text('Saldo', textAlign: TextAlign.end, style: headerStyle)),
          ],
        ),
        const Divider(height: 12),
        for (final m in plan.months) _row(m, current),
      ],
    );
  }

  Widget _row(PlanMonth m, DateTime current) {
    final future = m.month.isAfter(current);
    final t = m.totals;
    return InkWell(
      onTap: () => onTapMonth(m.month),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                Dates.capitalize(Dates.monthShort[m.month.month - 1]),
                style: TextStyle(fontWeight: m.month == current ? FontWeight.w800 : FontWeight.w500),
              ),
            ),
            Expanded(child: _Cell(real: future ? null : t.incomeCents(real: true), planned: t.incomeCents(real: false))),
            Expanded(child: _Cell(real: future ? null : t.expenseCents(real: true), planned: t.expenseCents(real: false))),
            Expanded(
              child: _Cell(
                real: future ? null : t.balanceCents(real: true),
                planned: t.balanceCents(real: false),
                colored: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.real, required this.planned, this.colored = false});
  final int? real;
  final int planned;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final value = real;
    Color? color;
    if (colored && value != null) color = value >= 0 ? AppColors.income : AppColors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value == null ? '—' : Money.formatShort(value),
            style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures, color: color),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            Money.formatShort(planned),
            style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures),
          ),
        ),
      ],
    );
  }
}
