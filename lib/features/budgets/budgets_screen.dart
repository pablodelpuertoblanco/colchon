import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../data/repositories/budget_repository.dart';
import '../../domain/models.dart';
import 'budget_widgets.dart';

/// Presupuestos: límites de gasto con su progreso del periodo actual.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Presupuesto'),
      ),
      body: budgets.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              emoji: '🎯',
              title: 'Sin presupuestos',
              message: 'Crea límites por categoría (o uno global) y verás cuánto te queda y a qué ritmo puedes gastar.',
            );
          }
          final total = list.where((b) => b.budget.categoryId == null).toList();
          final byCategory = list.where((b) => b.budget.categoryId != null).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              if (total.isNotEmpty)
                SectionCard(
                  title: 'Global',
                  child: Column(
                    children: [
                      for (final b in total)
                        BudgetProgressRow(view: b, detailed: true, onTap: () => showBudgetForm(context, editing: b)),
                    ],
                  ),
                ),
              if (byCategory.isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Por categoría',
                  child: Column(
                    children: [
                      for (final b in byCategory)
                        BudgetProgressRow(view: b, detailed: true, onTap: () => showBudgetForm(context, editing: b)),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Hoja para crear o editar un presupuesto.
Future<void> showBudgetForm(BuildContext context, {BudgetView? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BudgetForm(editing: editing),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({this.editing});
  final BudgetView? editing;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  late String? _categoryId = widget.editing?.budget.categoryId;
  late BudgetPeriod _period = widget.editing?.budget.period ?? BudgetPeriod.month;
  late int _alertPct = widget.editing?.budget.alertPct ?? 80;
  late final TextEditingController _amount =
      TextEditingController(text: widget.editing == null ? '' : centsToInput(widget.editing!.budget.amountCents));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = Money.parse(_amount.text);
    if (cents == null || cents <= 0) {
      showSnack(context, 'Introduce un importe válido');
      return;
    }
    final repo = ref.read(budgetRepoProvider);
    try {
      if (widget.editing == null) {
        await repo.create(categoryId: _categoryId, period: _period, amountCents: cents, alertPct: _alertPct);
      } else {
        await repo.update(widget.editing!.budget.id,
            categoryId: _categoryId, period: _period, amountCents: cents, alertPct: _alertPct);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) showSnack(context, 'Ya existe un presupuesto para esa categoría y periodo.');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: '¿Eliminar este presupuesto?', confirmLabel: 'Eliminar', destructive: true);
    if (!ok) return;
    await ref.read(budgetRepoProvider).softDelete(widget.editing!.budget.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const <CategoryRow>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.editing == null ? 'Nuevo presupuesto' : 'Editar presupuesto',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              key: ValueKey('budget-cat-${categories.length}'),
              initialValue: _categoryId == null || categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('💶 Todos los gastos')),
                for (final c in categories.where((c) => !c.isArchived || c.id == _categoryId))
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text('${c.emoji} ${c.name}${c.parentId == null ? '' : ' (subcategoría)'}'),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            SegmentedButton<BudgetPeriod>(
              segments: [for (final p in BudgetPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 16),
            MoneyField(controller: _amount, label: 'Límite', autofocus: widget.editing == null),
            const SizedBox(height: 16),
            Text('Avisarme al llegar al $_alertPct %'),
            Slider(
              value: _alertPct.toDouble(),
              min: 50,
              max: 100,
              divisions: 10,
              label: '$_alertPct %',
              onChanged: (v) => setState(() => _alertPct = v.round()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.editing != null)
                  TextButton.icon(onPressed: _delete, icon: const Icon(Icons.delete_outline), label: const Text('Eliminar')),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Guardar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
