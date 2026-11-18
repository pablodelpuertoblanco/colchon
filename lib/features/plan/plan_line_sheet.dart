import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models.dart';
import '../../domain/period.dart';
import '../../domain/plan.dart';
import '../categories/category_form_sheet.dart';
import '../stats/category_detail_screen.dart';

enum _ApplyTo {
  thisMonth,
  untilDecember,
  wholeYear;

  String get label => switch (this) {
        _ApplyTo.thisMonth => 'Este mes',
        _ApplyTo.untilDecember => 'Hasta dic.',
        _ApplyTo.wholeYear => 'Todo el año',
      };
}

/// Hoja para cambiar lo previsto de una categoría en un mes.
Future<void> showPlanLineSheet(
  BuildContext context, {
  required PlanCategory category,
  required DateTime month,
  required int plannedCents,
  required int realCents,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlanLineSheet(category: category, month: month, plannedCents: plannedCents, realCents: realCents),
  );
}

class _PlanLineSheet extends ConsumerStatefulWidget {
  const _PlanLineSheet({required this.category, required this.month, required this.plannedCents, required this.realCents});
  final PlanCategory category;
  final DateTime month;
  final int plannedCents;
  final int realCents;

  @override
  ConsumerState<_PlanLineSheet> createState() => _PlanLineSheetState();
}

class _PlanLineSheetState extends ConsumerState<_PlanLineSheet> {
  late final _amount = TextEditingController(text: widget.plannedCents == 0 ? '' : centsToInput(widget.plannedCents));
  _ApplyTo _applyTo = _ApplyTo.thisMonth;
  late int? _expectedDay = widget.category.expectedDay;
  bool _saving = false;

  String get _monthName => Dates.monthNames[widget.month.month - 1];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _amount.text.trim();
    final cents = text.isEmpty ? 0 : Money.parse(text);
    if (cents == null || cents < 0) {
      showSnack(context, 'Importe no válido');
      return;
    }
    setState(() => _saving = true);
    final m = widget.month.month;
    final months = switch (_applyTo) {
      _ApplyTo.thisMonth => [m],
      _ApplyTo.untilDecember => [for (var i = m; i <= 12; i++) i],
      _ApplyTo.wholeYear => [for (var i = 1; i <= 12; i++) i],
    };
    await ref.read(planRepoProvider).setAmount(widget.category.id, widget.month.year, months, cents);
    if (_expectedDay != widget.category.expectedDay) {
      await ref.read(categoryRepoProvider).setExpectedDay(widget.category.id, _expectedDay);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final year = widget.month.year;
    final ok = await confirmDialog(
      context,
      title: '¿Quitar "${widget.category.name}" del plan de $year?',
      message: 'Se borra lo previsto de todos los meses de $year. Los movimientos no se tocan.',
      confirmLabel: 'Quitar',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(planRepoProvider).removeFromYear(widget.category.id, year);
    if (mounted) Navigator.pop(context);
  }

  /// Cambia la categoría de bloque, o de ingreso a gasto (o al revés).
  Future<void> _move() async {
    final c = widget.category;
    final destinations = <({CategoryKind kind, BudgetGroup? group, String label, String emoji})>[
      (kind: CategoryKind.income, group: null, label: 'Ingreso', emoji: '💶'),
      for (final g in BudgetGroup.values) (kind: CategoryKind.expense, group: g, label: g.label, emoji: g.emoji),
      (kind: CategoryKind.expense, group: null, label: 'Gasto sin clasificar', emoji: '❔'),
    ];
    bool isCurrent(({CategoryKind kind, BudgetGroup? group, String label, String emoji}) d) =>
        d.kind == c.kind && (c.isIncome || d.group == c.group);

    final picked = await showDialog<({CategoryKind kind, BudgetGroup? group, String label, String emoji})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Mover "${c.name}" a'),
        children: [
          for (final d in destinations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Row(
                children: [
                  Text(d.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(d.label)),
                  if (isCurrent(d)) const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || isCurrent(picked) || !mounted) return;

    final repo = ref.read(categoryRepoProvider);
    if (picked.kind != c.kind) {
      final n = await repo.countTransactionsWithChildren(c.id);
      if (!mounted) return;
      if (n > 0) {
        final ok = await confirmDialog(
          context,
          title: '¿Pasar "${c.name}" a ${picked.kind == CategoryKind.income ? 'ingresos' : 'gastos'}?',
          message: 'Tiene $n ${n == 1 ? 'movimiento' : 'movimientos'}: '
              '${n == 1 ? 'pasará' : 'pasarán'} a ser ${picked.kind == CategoryKind.income ? 'ingresos' : 'gastos'}.',
          confirmLabel: 'Mover',
        );
        if (!ok) return;
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await repo.move(c.id, kind: picked.kind, group: picked.group);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('"${c.name}" ahora está en ${picked.label}')));
  }

  void _openYear() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => PlanCategoryYearScreen(categoryId: widget.category.id, year: widget.month.year),
    ));
  }

  void _openMovements() {
    final cycle = ref.read(monthCycleProvider);
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => CategoryDetailScreen(
        categoryId: widget.category.id,
        period: Period.ofMonth(widget.month, cycle: cycle),
        type: widget.category.isIncome ? TxType.income : TxType.expense,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final group = c.isIncome ? 'Ingreso' : (c.group?.label ?? 'Sin clasificar');
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CategoryAvatar(emoji: c.emoji, color: c.color, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: context.text.titleLarge),
                      Text(group, style: TextStyle(color: context.colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _move,
                  icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  label: const Text('Mover'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${c.isIncome ? 'Cobrado' : 'Gastado'} en $_monthName: ${Money.format(widget.realCents)}',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            MoneyField(controller: _amount, label: 'Previsto en $_monthName', autofocus: true, helper: 'Vacío o 0 = sin previsto'),
            const SizedBox(height: 12),
            SegmentedButton<_ApplyTo>(
              showSelectedIcon: false,
              segments: [for (final a in _ApplyTo.values) ButtonSegment(value: a, label: Text(a.label))],
              selected: {_applyTo},
              onSelectionChanged: (s) => setState(() => _applyTo = s.first),
            ),
            FieldLabel(c.isIncome ? 'Día habitual de cobro' : 'Día habitual de cargo'),
            ExpectedDayField(value: _expectedDay, onChanged: (d) => setState(() => _expectedDay = d)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(onPressed: _openYear, icon: const Icon(Icons.calendar_view_month), label: const Text('Mes a mes')),
                TextButton.icon(onPressed: _openMovements, icon: const Icon(Icons.receipt_long), label: const Text('Movimientos')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _remove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Quitar del plan de ${widget.month.year}',
                ),
                const Spacer(),
                FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Los 12 meses de una categoría, como una fila del Excel.
class PlanCategoryYearScreen extends ConsumerStatefulWidget {
  const PlanCategoryYearScreen({super.key, required this.categoryId, required this.year});
  final String categoryId;
  final int year;

  @override
  ConsumerState<PlanCategoryYearScreen> createState() => _PlanCategoryYearScreenState();
}

class _PlanCategoryYearScreenState extends ConsumerState<PlanCategoryYearScreen> {
  final _controllers = List.generate(12, (_) => TextEditingController());
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fillAll() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mismo importe todos los meses'),
        content: MoneyField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Rellenar')),
        ],
      ),
    );
    // No se hace dispose: el diálogo aún usa el controlador mientras se cierra.
    if (value == null) return;
    final cents = value.trim().isEmpty ? 0 : Money.parse(value);
    if (cents == null || cents < 0) {
      if (mounted) showSnack(context, 'Importe no válido');
      return;
    }
    setState(() {
      for (final c in _controllers) {
        c.text = cents == 0 ? '' : centsToInput(cents);
      }
    });
  }

  Future<void> _save() async {
    final values = <int, int>{};
    for (var i = 0; i < 12; i++) {
      final text = _controllers[i].text.trim();
      final cents = text.isEmpty ? 0 : Money.parse(text);
      if (cents == null || cents < 0) {
        showSnack(context, 'Revisa el importe de ${Dates.monthNames[i]}');
        return;
      }
      values[i + 1] = cents;
    }
    setState(() => _saving = true);
    await ref.read(planRepoProvider).setMonths(widget.categoryId, widget.year, values);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planYearProvider(widget.year));
    final category = ref.watch(categoryMapProvider).value?[widget.categoryId];

    return Scaffold(
      appBar: AppBar(
        title: Text(category == null ? 'Plan ${widget.year}' : '${category.emoji} ${category.name}'),
        actions: [
          IconButton(onPressed: _fillAll, icon: const Icon(Icons.format_paint_outlined), tooltip: 'Mismo importe todos los meses'),
        ],
      ),
      body: plan.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (year) {
          final lines = [for (var m = 1; m <= 12; m++) year.monthAt(m).lineOf(widget.categoryId)];
          if (!_loaded) {
            _loaded = true;
            for (var i = 0; i < 12; i++) {
              final p = lines[i]?.plannedCents ?? 0;
              _controllers[i].text = p == 0 ? '' : centsToInput(p);
            }
          }
          final totalReal = lines.fold<int>(0, (s, l) => s + (l?.realCents ?? 0));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('Previsto de ${widget.year} mes a mes. Deja vacío lo que no toque.',
                  style: TextStyle(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (var i = 0; i < 12; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 92, child: Text(Dates.capitalize(Dates.monthNames[i]))),
                      Expanded(
                        child: TextField(
                          controller: _controllers[i],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontFeatures: tabularFigures),
                          decoration: const InputDecoration(isDense: true, suffixText: '€', hintText: '0'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 96,
                        child: Text(
                          'real ${Money.formatShort(lines[i]?.realCents ?? 0)}',
                          textAlign: TextAlign.end,
                          style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text('Real en el año: ${Money.format(totalReal)}', style: TextStyle(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _saving ? null : _save,
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Diálogo para cambiar los objetivos de la regla 50/30/20.
Future<void> showRuleTargetsDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(ruleTargetsProvider);
  final needs = TextEditingController(text: '${current.needs}');
  final wants = TextEditingController(text: '${current.wants}');
  final savings = TextEditingController(text: '${current.savings}');

  Widget field(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: '%'),
      );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Objetivos del plan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Qué parte de tus ingresos quieres dedicar a cada bloque. Deben sumar 100.'),
          const SizedBox(height: 12),
          field(needs, 'Necesarios (fijos + variables)'),
          field(wants, 'Prescindibles y ocio'),
          field(savings, 'Ahorro e inversión'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
      ],
    ),
  );
  final values = [needs.text, wants.text, savings.text].map((t) => int.tryParse(t.trim())).toList();
  if (ok != true) return;
  if (values.any((v) => v == null || v < 0) || values.fold<int>(0, (s, v) => s + (v ?? 0)) != 100) {
    if (context.mounted) showSnack(context, 'Los tres porcentajes deben sumar 100');
    return;
  }
  final targets = RuleTargets(needs: values[0]!, wants: values[1]!, savings: values[2]!);
  await ref.read(settingsRepoProvider).set(SettingKeys.ruleTargets, targets.serialize());
}
