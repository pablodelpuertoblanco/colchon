import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/database.dart';
import '../../domain/models.dart';
import 'category_form_sheet.dart';

/// Gestión de categorías de gastos, ingresos y productos.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  static const _kinds = [CategoryKind.expense, CategoryKind.income, CategoryKind.product];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _kinds.length,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Categorías'),
            bottom: TabBar(tabs: [for (final k in _kinds) Tab(text: k.label)]),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Nueva categoría',
            onPressed: () {
              final kind = _kinds[DefaultTabController.of(context).index];
              showCategoryForm(context, kind: kind);
            },
            child: const Icon(Icons.add),
          ),
          body: TabBarView(children: [for (final k in _kinds) _CategoryList(kind: k)]),
        );
      }),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.kind});
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider(kind));
    return async.when(
      loading: () => const LoadingBox(),
      error: (e, _) => ErrorBox(e),
      data: (all) {
        final byId = {for (final c in all) c.id: c};
        // Cada grupo seguido de sus subcategorías.
        final list = <CategoryRow>[];
        for (final top in all.where((c) => c.parentId == null || !byId.containsKey(c.parentId))) {
          list
            ..add(top)
            ..addAll(all.where((c) => c.parentId == top.id));
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: list.length,
          onReorder: (oldIndex, newIndex) {
            final ids = [for (final c in list) c.id];
            if (newIndex > oldIndex) newIndex -= 1;
            final moved = ids.removeAt(oldIndex);
            ids.insert(newIndex, moved);
            ref.read(categoryRepoProvider).reorder(ids);
          },
          itemBuilder: (context, i) {
            final c = list[i];
            final parent = c.parentId == null ? null : byId[c.parentId];
            final isGroup = list.any((x) => x.parentId == c.id);
            return Opacity(
              key: ValueKey(c.id),
              opacity: c.isArchived ? 0.5 : 1,
              child: ListTile(
                contentPadding: EdgeInsets.only(left: parent == null ? 16 : 40, right: 8),
                leading: CategoryAvatar(emoji: c.emoji, color: c.color),
                title: Text(c.name),
                subtitle: Text([
                  if (isGroup) 'Grupo',
                  if (parent != null) 'Dentro de ${parent.name}',
                  if (c.budgetGroup != null) c.budgetGroup!.label,
                  if (c.isSavings) kind == CategoryKind.income ? 'Sale de ahorros' : 'Cuenta como ahorro',
                  if (c.isArchived) 'Archivada',
                ].join(' · ')),
                trailing: const Icon(Icons.drag_handle),
                onTap: () => showCategoryForm(context, kind: kind, editing: c),
              ),
            );
          },
        );
      },
    );
  }
}

/// Métodos de pago y de recepción.
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {PaymentMethodRow? editing}) async {
    final name = TextEditingController(text: editing?.name ?? '');
    var emoji = editing?.emoji ?? '💳';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(editing == null ? 'Nuevo método' : 'Editar método'),
          content: Row(
            children: [
              TextButton(
                onPressed: () async {
                  final e = await _pickSimpleEmoji(ctx);
                  if (e != null) setState(() => emoji = e);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
              Expanded(
                child: TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
              ),
            ],
          ),
          actions: [
            if (editing != null)
              TextButton(
                onPressed: () async {
                  await ref.read(paymentMethodRepoProvider).setArchived(editing.id, !editing.isArchived);
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: Text(editing.isArchived ? 'Desarchivar' : 'Archivar'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (result != true || name.text.trim().isEmpty) return;
    final repo = ref.read(paymentMethodRepoProvider);
    if (editing == null) {
      await repo.create(name: name.text, emoji: emoji);
    } else {
      await repo.update(editing.id, name: name.text, emoji: emoji);
    }
  }

  static const _emojis = ['💳', '💶', '📱', '🏦', '🧾', '💰', '🪙', '🎟️', '🛍️', '💼'];

  Future<String?> _pickSimpleEmoji(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Emoji'),
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final e in _emojis)
                  TextButton(onPressed: () => Navigator.pop(ctx, e), child: Text(e, style: const TextStyle(fontSize: 26))),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethodRow>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Métodos de pago')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          for (final m in methods)
            Opacity(
              opacity: m.isArchived ? 0.5 : 1,
              child: ListTile(
                leading: Text(m.emoji, style: const TextStyle(fontSize: 26)),
                title: Text(m.name),
                subtitle: m.isArchived ? const Text('Archivado') : null,
                trailing: Icon(Icons.edit_outlined, color: context.colors.onSurfaceVariant),
                onTap: () => _edit(context, ref, editing: m),
              ),
            ),
        ],
      ),
    );
  }
}
