import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import 'transaction_detail_screen.dart';

/// Fila de un movimiento en listas (historial, calendario, inicio).
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, this.showDate = false, this.onTap});
  final TxView tx;
  final bool showDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (tx.description.trim().isNotEmpty) tx.categoryName,
      if (showDate) Dates.dayMonthShort(tx.date),
      if (tx.time != null) tx.time!,
      if (tx.paymentMethodName != null) tx.paymentMethodName!,
    ];
    return ListTile(
      onTap: onTap ?? () => openTransactionDetail(context, tx.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CategoryAvatar(emoji: tx.categoryEmoji, color: tx.categoryColor),
      title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (tx.isPending) ...[const Tag('Pendiente', color: AppColors.warning), const SizedBox(width: 6)],
          if (tx.isRecurring) ...[
            Icon(Icons.repeat_rounded, size: 14, color: context.colors.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Opacity(
        opacity: tx.isPending ? 0.55 : 1,
        child: AmountText(tx.amountCents, type: tx.type, style: context.text.titleMedium),
      ),
    );
  }
}
