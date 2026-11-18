import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/shopping_repository.dart';
import 'shopping_list_screen.dart';

/// Pestaña Compra: listas activas e historial de compras finalizadas.
class ShoppingListsScreen extends ConsumerWidget {
  const ShoppingListsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askText(context, title: 'Nueva lista', initial: 'Compra semanal', confirm: 'Crear');
    if (name == null || name.trim().isEmpty) return;
    final id = await ref.read(shoppingRepoProvider).createList(name);
    if (context.mounted) openShoppingList(context, id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(shoppingListsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Compra')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-list',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva lista'),
      ),
      body: lists.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              emoji: '🛒',
              title: 'Sin listas de la compra',
              message: 'Crea una lista, márcala mientras compras y al terminar se registrará el gasto en Supermercado.',
            );
          }
          final active = all.where((l) => !l.isCompleted).toList();
          final done = all.where((l) => l.isCompleted).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final l in active) ...[
                _ListCard(view: l),
                const SizedBox(height: 10),
              ],
              if (done.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text('Compras finalizadas (${done.length})'),
                    children: [
                      for (final l in done)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: const Text('✅', style: TextStyle(fontSize: 22)),
                          title: Text(l.list.name),
                          subtitle: Text(l.list.completedAt == null
                              ? ''
                              : Dates.relativeDay(Dates.dateOnly(DateTime.parse(l.list.completedAt!).toLocal()))),
                          trailing: Text(l.spentCents == null ? '' : Money.format(l.spentCents!),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                          onTap: () => openShoppingList(context, l.list.id),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.view});
  final ShoppingListView view;

  @override
  Widget build(BuildContext context) {
    final progress = view.itemCount == 0 ? 0.0 : view.checkedCount / view.itemCount;
    return SectionCard(
      onTap: () => openShoppingList(context, view.list.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🛒', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(child: Text(view.list.name, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('${view.checkedCount} de ${view.itemCount} productos',
                    style: TextStyle(color: context.colors.onSurfaceVariant)),
              ),
              if (view.estimatedCents > 0)
                Text('≈ ${Money.format(view.estimatedCents)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diálogo con un campo de texto (nombres de listas, etc.).
Future<String?> askText(BuildContext context, {required String title, String initial = '', String confirm = 'Guardar'}) {
  final controller = TextEditingController(text: initial);
  controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(confirm)),
      ],
    ),
  );
}
