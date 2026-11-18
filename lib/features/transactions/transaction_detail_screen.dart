import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../recurring/recurring_form_screen.dart';
import '../shopping/shopping_list_screen.dart';
import 'transaction_form_screen.dart';

void openTransactionDetail(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransactionDetailScreen(id: id)));
}

/// Detalle de un movimiento con acciones de editar, duplicar y eliminar.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context, title: '¿Eliminar este movimiento?', confirmLabel: 'Eliminar', destructive: true);
    if (!ok || !context.mounted) return;
    final repo = ref.read(transactionRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.softDelete(id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Movimiento eliminado'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => repo.restore(id)),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(txByIdProvider(id));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingBox()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorBox(e)),
      data: (tx) {
        if (tx == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(emoji: '🗑️', title: 'Este movimiento ya no existe'),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(tx.type.label),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => openTransactionForm(context, editing: tx),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'dup') openTransactionForm(context, duplicateOf: tx);
                  if (v == 'del') _delete(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'dup', child: Text('Duplicar')),
                  PopupMenuItem(value: 'del', child: Text('Eliminar')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              Center(child: CategoryAvatar(emoji: tx.categoryEmoji, color: tx.categoryColor, size: 72)),
              const SizedBox(height: 12),
              Text(tx.title, textAlign: TextAlign.center, style: context.text.titleLarge),
              const SizedBox(height: 4),
              Center(child: AmountText(tx.amountCents, type: tx.type, style: context.text.headlineMedium)),
              if (tx.isPending) ...[
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: () => openTransactionForm(context, editing: tx, confirmMode: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar importe'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _row(context, Icons.category_outlined, 'Categoría', '${tx.categoryEmoji} ${tx.categoryName}'),
                    _row(context, Icons.event_outlined, 'Fecha',
                        '${Dates.relativeDay(tx.date)}${tx.time != null ? ' · ${tx.time}' : ''}'),
                    _row(context, Icons.payments_outlined, tx.isExpense ? 'Método de pago' : 'Método de recepción',
                        tx.paymentMethodName ?? 'Sin indicar'),
                    _row(context, Icons.verified_outlined, 'Estado', tx.isPending ? 'Pendiente de confirmar' : 'Confirmado'),
                    if (tx.notes != null) _row(context, Icons.notes, 'Notas', tx.notes!),
                  ],
                ),
              ),
              if (tx.recurringRuleId != null) ...[
                const SizedBox(height: 12),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.repeat_rounded),
                    title: const Text('Generado por un movimiento recurrente'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openRecurringForm(context, ruleId: tx.recurringRuleId),
                  ),
                ),
              ],
              if (tx.type == TxType.expense)
                FutureBuilder<(String, String)?>(
                  future: ref.read(transactionRepoProvider).shoppingListFor(tx.id),
                  builder: (context, snap) {
                    final list = snap.data;
                    if (list == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SectionCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.shopping_cart_outlined),
                          title: Text('Generado desde la lista "${list.$2}"'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openShoppingList(context, list.$1),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: context.colors.onSurfaceVariant),
      title: Text(label, style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant)),
      subtitle: Text(value, style: context.text.bodyLarge),
    );
  }
}
