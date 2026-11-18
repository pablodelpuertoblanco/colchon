import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';

/// Selector del día del mes en que suele cargarse o cobrarse una categoría
/// (lo usa la previsión de saldo). Null = sin día fijo.
class ExpectedDayField extends StatelessWidget {
  const ExpectedDayField({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int?>(
          initialValue: value,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Sin día fijo')),
            for (var d = 1; d <= 31; d++) DropdownMenuItem<int?>(value: d, child: Text('Día $d')),
          ],
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            value == null
                ? 'Sin día fijo, la previsión reparte lo que queda entre los días del mes'
                : value! > 28
                    ? 'En los meses más cortos se usa su último día'
                    : 'La previsión cuenta lo que queda de la partida ese día',
            style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Crea o edita una categoría. Devuelve el id de la categoría creada.
Future<String?> showCategoryForm(BuildContext context, {required CategoryKind kind, CategoryRow? editing}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryForm(kind: kind, editing: editing),
  );
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({required this.kind, this.editing});
  final CategoryKind kind;
  final CategoryRow? editing;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late String _emoji = widget.editing?.emoji ?? '📦';
  late int _color = widget.editing?.color ?? categoryPalette.first;
  late String? _parentId = widget.editing?.parentId;
  late BudgetGroup? _group = widget.editing?.budgetGroup;
  late bool _isSavings = widget.editing?.isSavings ?? false;
  late int? _expectedDay = widget.editing?.expectedDay;

  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Escribe un nombre');
      return;
    }
    final repo = ref.read(categoryRepoProvider);
    final group = widget.kind == CategoryKind.expense ? _group : null;
    final isSavings = widget.kind == CategoryKind.product ? false : _isSavings;
    final day = widget.kind == CategoryKind.product ? null : _expectedDay;
    if (_isEditing) {
      await repo.update(widget.editing!.id,
          name: name,
          emoji: _emoji,
          color: _color,
          parentId: _parentId,
          group: group,
          isSavings: isSavings,
          expectedDay: day);
      if (mounted) Navigator.pop(context, widget.editing!.id);
    } else {
      final id = await repo.create(
          kind: widget.kind,
          name: name,
          emoji: _emoji,
          color: _color,
          parentId: _parentId,
          group: group,
          isSavings: isSavings,
          expectedDay: day);
      if (mounted) Navigator.pop(context, id);
    }
  }

  Future<void> _archive() async {
    final c = widget.editing!;
    await ref.read(categoryRepoProvider).setArchived(c.id, !c.isArchived);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final c = widget.editing!;
    final repo = ref.read(categoryRepoProvider);
    final count = await repo.countTransactions(c.id);
    if (!mounted) return;
    if (count == 0) {
      final ok = await confirmDialog(context, title: '¿Eliminar "${c.name}"?', confirmLabel: 'Eliminar', destructive: true);
      if (!ok) return;
      await repo.delete(c.id);
      if (mounted) Navigator.pop(context);
      return;
    }
    // Tiene movimientos: reasignarlos o archivar la categoría.
    final siblings = (ref.read(categoriesProvider(c.kind)).value ?? const <CategoryRow>[])
        .where((x) => x.id != c.id && !x.isArchived)
        .toList();
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('"${c.name}" tiene $count movimientos'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Elige a qué categoría pasarlos antes de eliminarla, o archívala para conservarla en el historial.'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__archive__'),
            child: const Text('📁 Archivar en lugar de eliminar'),
          ),
          const Divider(),
          for (final s in siblings)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s.id), child: Text('Pasar a ${s.emoji} ${s.name}')),
        ],
      ),
    );
    if (target == null) return;
    if (target == '__archive__') {
      await repo.setArchived(c.id, true);
    } else {
      await repo.delete(c.id, reassignTo: target);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(categoriesProvider(widget.kind)).value ?? const <CategoryRow>[];
    // Solo categorías de primer nivel pueden ser grupo (un nivel de anidación).
    final parents = all.where((c) => c.parentId == null && c.id != widget.editing?.id).toList();
    final hasChildren = widget.editing != null && all.any((c) => c.parentId == widget.editing!.id);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Editar categoría' : 'Nueva categoría', style: context.text.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () async {
                    final e = await pickEmoji(context, current: _emoji);
                    if (e != null) setState(() => _emoji = e);
                  },
                  child: CategoryAvatar(emoji: _emoji, color: _color, size: 60),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Toca el círculo para cambiar el emoji', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
            const FieldLabel('Color'),
            ColorChoice(selected: _color, onChanged: (c) => setState(() => _color = c)),
            if (widget.kind != CategoryKind.product && !hasChildren) ...[
              const FieldLabel('Agrupar dentro de (opcional)'),
              DropdownButtonFormField<String?>(
                key: ValueKey('parent-${parents.length}'),
                initialValue: _parentId == null || parents.any((p) => p.id == _parentId) ? _parentId : null,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ninguno (categoría principal)')),
                  for (final p in parents) DropdownMenuItem<String?>(value: p.id, child: Text('${p.emoji} ${p.name}')),
                ],
                onChanged: (v) => setState(() => _parentId = v),
              ),
            ],
            if (widget.kind == CategoryKind.expense) ...[
              const FieldLabel('Bloque del plan (regla 50/30/20)'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final g in BudgetGroup.values)
                    ChoiceChip(
                      label: Text('${g.emoji} ${g.label}'),
                      selected: _group == g,
                      onSelected: (sel) => setState(() {
                        _group = sel ? g : null;
                        if (sel && g == BudgetGroup.savings) _isSavings = true;
                      }),
                    ),
                ],
              ),
              if (_group == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _parentId != null ? 'Sin elegir: usa el del grupo' : 'Sin elegir: aparece como "Sin clasificar" en el plan',
                    style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
                  ),
                ),
            ],
            if (widget.kind != CategoryKind.product) ...[
              FieldLabel(widget.kind == CategoryKind.expense ? 'Día habitual de cargo' : 'Día habitual de cobro'),
              ExpectedDayField(value: _expectedDay, onChanged: (d) => setState(() => _expectedDay = d)),
            ],
            if (widget.kind != CategoryKind.product)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isSavings,
                onChanged: (v) => setState(() => _isSavings = v),
                title: Text(widget.kind == CategoryKind.expense ? 'Cuenta como ahorro' : 'Sale de tus ahorros'),
                subtitle: Text(
                  widget.kind == CategoryKind.expense
                      ? 'Plan de pensiones, hipoteca, traspasos a la cuenta de ahorro... Suma al ahorro real.'
                      : 'Traspasos desde tu cuenta de ahorro: no cuentan como ingreso real.',
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_isEditing) ...[
                  IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
                  TextButton(
                    onPressed: _archive,
                    child: Text(widget.editing!.isArchived ? 'Desarchivar' : 'Archivar'),
                  ),
                ],
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
