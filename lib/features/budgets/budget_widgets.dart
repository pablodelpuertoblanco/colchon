import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../data/repositories/budget_repository.dart';
import '../../domain/budget_math.dart';

Color budgetColor(BudgetState s) => switch (s) {
      BudgetState.ok => AppColors.income,
      BudgetState.warning => AppColors.warning,
      BudgetState.exceeded => AppColors.danger,
    };

/// Fila con la barra de progreso de un presupuesto.
class BudgetProgressRow extends StatelessWidget {
  const BudgetProgressRow({super.key, required this.view, this.detailed = false, this.onTap});
  final BudgetView view;
  final bool detailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = view.progress;
    final color = budgetColor(p.state);
    final remaining = p.remainingCents;
    final daily = p.dailyAllowanceCents;

    String detail;
    if (p.state == BudgetState.exceeded) {
      detail = 'Superado en ${Money.format(-remaining)}';
    } else if (daily != null) {
      detail = 'Quedan ${Money.format(remaining)} · ${Money.format(daily)} al día durante ${p.daysLeft} '
          '${p.daysLeft == 1 ? 'día' : 'días'}';
    } else {
      detail = 'Quedan ${Money.format(remaining)}';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(view.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detailed ? '${view.title} · ${view.budget.period.label}' : view.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${Money.formatShort(view.spentCents)} / ${Money.formatShort(view.budget.amountCents)}',
                  style: TextStyle(fontFeatures: tabularFigures, color: context.colors.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                color: color,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.state == BudgetState.exceeded ? AppColors.danger : context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text('${p.percent} %', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
