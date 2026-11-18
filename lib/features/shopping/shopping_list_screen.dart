import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../data/repositories/shopping_repository.dart';
import '../../data/seed.dart';
import '../../domain/budget_math.dart';
import '../../domain/models.dart';
import 'shopping_lists_screen.dart';

void openShoppingList(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShoppingListScreen(listId: id)));
}

/// Una lista de la compra, pensada para usarse con una mano en el súper.
class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key, required this.listId});
  final String listId;

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  List<FrequentProduct> _frequent = const [];
  List<FrequentProduct> _matches = const [];
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    // La pantalla no se apaga mientras la lista está abierta.
    WakelockPlus.enable();
    _loadFrequent();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFrequent() async {
    final list = await ref.read(shoppingRepoProvider).frequentProducts();
    if (mounted) setState(() => _frequent = list);
  }

  void _onAddChanged(String text) {
    final q = normalizeForSearch(text);
    setState(() {
      _matches = q.isEmpty ? const [] : _frequent.where((p) => normalizeForSearch(p.name).contains(q)).take(6).toList();
    });
  }

  Future<void> _quickAdd(String name, {FrequentProduct? from}) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final match = from ??
        _frequent.where((p) => normalizeForSearch(p.name) == normalizeForSearch(clean)).firstOrNull;
    await ref.read(shoppingRepoProvider).addItem(
          widget.listId,
          ItemDraft(
            name: from?.name ?? clean,
            unit: match?.unit ?? ItemUnit.ud,
            estUnitPriceCents: match?.unitPriceCents,
            categoryId: match?.categoryId,
          ),
        );
    _add.clear();
    setState(() => _matches = const []);
    _addFocus.requestFocus();
  }

  void _toggle(ShoppingItemRow item) {
    ref.read(shoppingRepoProvider).setChecked(item.id, !item.isChecked);
  }

  void _delete(ShoppingItemRow item) {
    setState(() => _hidden.add(item.id));
    final repo = ref.read(shoppingRepoProvider);
    repo.deleteItem(item.id);
    showSnack(
      context,
      '${item.name} eliminado',
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          await repo.restoreItem(item.id);
          if (mounted) setState(() => _hidden.remove(item.id));
        },
      ),
    );
  }

  Future<void> _menu(String action, ShoppingListView view) async {
    final repo = ref.read(shoppingRepoProvider);
    switch (action) {
      case 'rename':
        final name = await askText(context, title: 'Renombrar lista', initial: view.list.name);
        if (name != null && name.trim().isNotEmpty) await repo.renameList(widget.listId, name);
      case 'duplicate':
        final id = await repo.duplicateList(widget.listId);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => ShoppingListScreen(listId: id)),
          );
        }
      case 'delete':
        final ok = await confirmDialog(context,
            title: '¿Eliminar la lista?',
            message: view.isCompleted ? 'El gasto ya registrado se conserva en el historial.' : null,
            confirmLabel: 'Eliminar',
            destructive: true);
        if (!ok) return;
        await repo.deleteList(widget.listId);
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewAsync = ref.watch(shoppingListProvider(widget.listId));
    final items = (ref.watch(shoppingItemsProvider(widget.listId)).value ?? const <ShoppingItemRow>[])
        .where((i) => !_hidden.contains(i.id))
        .toList();
    final categories = ref.watch(categoryMapProvider).value ?? const <String, CategoryRow>{};

    final view = viewAsync.value;
    if (view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: viewAsync.isLoading ? const LoadingBox() : const EmptyState(emoji: '🗑️', title: 'Esta lista ya no existe'),
      );
    }
    final completed = view.isCompleted;
    final pending = items.where((i) => !i.isChecked).toList();
    final checked = items.where((i) => i.isChecked).toList();
    final estimated = items.fold<int>(0, (s, i) => s + (i.estimatedLineCents ?? 0));
    final inCart = checked.fold<int>(0, (s, i) => s + (i.bestLineCents ?? 0));

    // Agrupa lo pendiente por categoría de producto (orden de pasillo).
    final groups = <String?, List<ShoppingItemRow>>{};
    for (final i in pending) {
      groups.putIfAbsent(i.categoryId, () => []).add(i);
    }
    final groupKeys = groups.keys.toList()
      ..sort((a, b) {
        final ca = a == null ? null : categories[a];
        final cb = b == null ? null : categories[b];
        if (ca == null) return 1;
        if (cb == null) return -1;
        return ca.sortOrder.compareTo(cb.sortOrder);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(view.list.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (a) => _menu(a, view),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renombrar')),
              PopupMenuItem(value: 'duplicate', child: Text('Duplicar lista')),
              PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!completed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _add,
                    focusNode: _addFocus,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: _onAddChanged,
                    onSubmitted: (v) => _quickAdd(v),
                    decoration: InputDecoration(
                      hintText: 'Añadir producto',
                      prefixIcon: const Icon(Icons.add_shopping_cart),
                      suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _quickAdd(_add.text)),
                    ),
                  ),
                  if (_matches.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final p in _matches)
                            Padding(
                              padding: const EdgeInsets.only(right: 6, top: 6),
                              child: ActionChip(
                                label: Text(p.unitPriceCents == null
                                    ? p.name
                                    : '${p.name} · ${Money.format(p.unitPriceCents!)}'),
                                onPressed: () => _quickAdd(p.name, from: p),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SectionCard(
                child: Row(
                  children: [
                    const Text('✅', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Compra finalizada${view.spentCents == null ? '' : ' · gasto de ${Money.format(view.spentCents!)}'}',
                      ),
                    ),
                    TextButton(onPressed: () => _menu('duplicate', view), child: const Text('Reutilizar')),
                  ],
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    emoji: '📝',
                    title: 'Lista vacía',
                    message: 'Escribe arriba lo que necesitas. Los productos que ya compraste antes se sugieren solos.',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final key in groupKeys) ...[
                        _GroupHeader(
                          emoji: key == null ? '🛍️' : (categories[key]?.emoji ?? '🛍️'),
                          title: key == null ? 'Sin categoría' : (categories[key]?.name ?? 'Sin categoría'),
                        ),
                        for (final item in groups[key]!) _itemRow(item, completed),
                      ],
                      if (checked.isNotEmpty) ...[
                        _GroupHeader(emoji: '🧺', title: 'En el carrito (${checked.length})'),
                        for (final item in checked) _itemRow(item, completed),
                      ],
                    ],
                  ),
          ),
          if (!completed)
            Container(
              color: context.cardColor,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Estimado: ${Money.format(estimated)}',
                              style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant)),
                          Text('En el carrito: ${Money.format(inCart)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () => _showFinishSheet(context, view, suggested: inCart > 0 ? inCart : estimated, hasPending: pending.isNotEmpty),
                      icon: const Icon(Icons.check),
                      label: const Text('Finalizar compra'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemRow(ShoppingItemRow item, bool completed) {
    final row = _ItemRow(
      item: item,
      enabled: !completed,
      onToggle: () => _toggle(item),
      onEdit: () => _showItemSheet(context, item),
    );
    if (completed) return row;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(item),
      child: row,
    );
  }

  Future<void> _showItemSheet(BuildContext context, ShoppingItemRow item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemSheet(item: item),
    );
  }

  Future<void> _showFinishSheet(BuildContext context, ShoppingListView view,
      {required int suggested, required bool hasPending}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FinishSheet(view: view, suggestedCents: suggested, hasPending: hasPending),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.emoji, required this.title});
  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('$emoji  $title',
            style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
      );
}

/// Fila de producto: toda la fila es pulsable y la casilla es grande.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.enabled, required this.onToggle, required this.onEdit});
  final ShoppingItemRow item;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final line = item.bestLineCents;
    final qty = '${Quantity.format(item.quantityMilli)} ${item.unit.label}';
    final unitPrice = item.realUnitPriceCents ?? item.estUnitPriceCents;
    final detail = unitPrice == null ? qty : '$qty × ${Money.format(unitPrice)}';
    final muted = item.isChecked;

    return InkWell(
      onTap: enabled ? onToggle : null,
      onLongPress: enabled ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          children: [
            Transform.scale(
              scale: 1.35,
              child: Checkbox(value: item.isChecked, onChanged: enabled ? (_) => onToggle() : null),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 17,
                      decoration: muted ? TextDecoration.lineThrough : null,
                      color: muted ? context.colors.onSurfaceVariant : null,
                    ),
                  ),
                  Text(detail, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
            if (line != null)
              Text(Money.format(line), style: const TextStyle(fontFeatures: tabularFigures, fontWeight: FontWeight.w600)),
            if (enabled) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar'),
          ],
        ),
      ),
    );
  }
}

/// Edición de un producto: cantidad, unidad, precios y categoría.
class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.item});
  final ShoppingItemRow item;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _qty = TextEditingController(text: Quantity.format(widget.item.quantityMilli));
  late final _est = TextEditingController(
      text: widget.item.estUnitPriceCents == null ? '' : centsToInput(widget.item.estUnitPriceCents!));
  late final _real = TextEditingController(
      text: widget.item.realUnitPriceCents == null ? '' : centsToInput(widget.item.realUnitPriceCents!));
  late ItemUnit _unit = widget.item.unit;
  late String? _categoryId = widget.item.categoryId;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _est.dispose();
    _real.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = Quantity.parse(_qty.text);
    if (_name.text.trim().isEmpty || qty == null) {
      showSnack(context, 'Revisa el nombre y la cantidad');
      return;
    }
    await ref.read(shoppingRepoProvider).updateItem(
          widget.item.id,
          ItemDraft(
            name: _name.text,
            quantityMilli: qty,
            unit: _unit,
            estUnitPriceCents: _est.text.trim().isEmpty ? null : Money.parse(_est.text),
            realUnitPriceCents: _real.text.trim().isEmpty ? null : Money.parse(_real.text),
            categoryId: _categoryId,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider(CategoryKind.product)).value ?? const <CategoryRow>[];
    final unitWord = _unit == ItemUnit.ud ? 'unidad' : _unit.label;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Producto'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<ItemUnit>(
                    segments: [for (final u in ItemUnit.values) ButtonSegment(value: u, label: Text(u.label))],
                    selected: {_unit},
                    onSelectionChanged: (s) => setState(() => _unit = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: MoneyField(controller: _est, label: 'Estimado / $unitWord')),
                const SizedBox(width: 12),
                Expanded(child: MoneyField(controller: _real, label: 'Real / $unitWord')),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('item-cat-${cats.length}'),
              initialValue: _categoryId == null || cats.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('🛍️ Sin categoría')),
                for (final c in cats) DropdownMenuItem<String?>(value: c.id, child: Text('${c.emoji} ${c.name}')),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}

/// Finalizar la compra: registra el gasto real en Supermercado.
class _FinishSheet extends ConsumerStatefulWidget {
  const _FinishSheet({required this.view, required this.suggestedCents, required this.hasPending});
  final ShoppingListView view;
  final int suggestedCents;
  final bool hasPending;

  @override
  ConsumerState<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends ConsumerState<_FinishSheet> {
  late final _total =
      TextEditingController(text: widget.suggestedCents > 0 ? centsToInput(widget.suggestedCents) : '');
  DateTime _date = Dates.today();
  String? _paymentMethodId;
  String _categoryId = supermarketCategoryId;
  late bool _moveUnchecked = widget.hasPending;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(transactionRepoProvider).lastPaymentMethod(TxType.expense).then((id) {
      if (mounted && _paymentMethodId == null) setState(() => _paymentMethodId = id);
    });
  }

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final cents = Money.parse(_total.text);
    if (cents == null || cents <= 0) {
      showSnack(context, 'Introduce el total del ticket');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(shoppingRepoProvider).finishList(
            listId: widget.view.list.id,
            totalCents: cents,
            date: _date,
            categoryId: _categoryId,
            paymentMethodId: _paymentMethodId,
            moveUncheckedToNewList: _moveUnchecked,
          );
      final alerts = await ref
          .read(budgetRepoProvider)
          .alertsAfterExpense(
              categoryId: _categoryId, date: _date, amountCents: cents, cycle: ref.read(monthCycleProvider));
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(alerts.isNotEmpty ? alerts.first.message : 'Gasto de ${Money.format(cents)} registrado'),
        backgroundColor: alerts.isEmpty
            ? null
            : (alerts.first.state == BudgetState.exceeded ? AppColors.danger : AppColors.warning),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'No se ha podido finalizar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethodRow>[];
    final cats = ref.watch(selectableCategoriesProvider(CategoryKind.expense)).value ?? const <CategoryRow>[];
    final today = Dates.today();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Finalizar compra', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Se registrará un gasto con el total del ticket.',
                style: TextStyle(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 16),
            MoneyField(controller: _total, label: 'Total del ticket', autofocus: true),
            const FieldLabel('Fecha'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Hoy'),
                  selected: Dates.sameDay(_date, today),
                  onSelected: (_) => setState(() => _date = today),
                ),
                ChoiceChip(
                  label: Text(Dates.sameDay(_date, today) ? 'Otra fecha' : Dates.dayMonthYearShort(_date)),
                  selected: !Dates.sameDay(_date, today),
                  onSelected: (_) async {
                    final d = await showDatePicker(
                        context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date = Dates.dateOnly(d));
                  },
                ),
              ],
            ),
            const FieldLabel('Método de pago'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in methods.where((m) => !m.isArchived))
                  ChoiceChip(
                    label: Text('${m.emoji} ${m.name}'),
                    selected: m.id == _paymentMethodId,
                    onSelected: (s) => setState(() => _paymentMethodId = s ? m.id : null),
                  ),
              ],
            ),
            const FieldLabel('Categoría del gasto'),
            DropdownButtonFormField<String>(
              key: ValueKey('finish-cat-${cats.length}'),
              initialValue: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
              items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}'))],
              onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
            ),
            if (widget.hasPending)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _moveUnchecked,
                onChanged: (v) => setState(() => _moveUnchecked = v),
                title: const Text('Pasar lo no comprado a una lista nueva'),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _saving ? null : _finish,
              child: const Text('Registrar gasto'),
            ),
          ],
        ),
      ),
    );
  }
}
