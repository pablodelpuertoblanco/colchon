import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import 'recurring_form_screen.dart';

/// Gastos e ingresos recurrentes (alquiler, nómina, suscripciones...).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurrentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openRecurringForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Recurrente'),
      ),
      body: rules.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              emoji: '🔁',
              title: 'Sin movimientos recurrentes',
              message: 'Añade el alquiler, la nómina o tus suscripciones y se registrarán solos cada periodo.',
            );
          }
          var monthlyExpense = 0;
          for (final v in list) {
            final r = v.rule;
            if (!r.isActive || r.type != TxType.expense) continue;
            // Equivalente mensual aproximado para el resumen.
            monthlyExpense += switch (r.frequency) {
              Frequency.day => r.amountCents * 30 ~/ r.everyN,
              Frequency.week => r.amountCents * 52 ~/ (12 * r.everyN),
              Frequency.month => r.amountCents ~/ r.everyN,
              Frequency.year => r.amountCents ~/ (12 * r.everyN),
            };
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    const Text('📆', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Gastos fijos: unos ${Money.format(monthlyExpense)} al mes',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (final v in list)
                      ListTile(
                        onTap: () => openRecurringForm(context, ruleId: v.rule.id),
                        leading: CategoryAvatar(emoji: v.categoryEmoji, color: v.categoryColor),
                        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          v.rule.frequency.describe(v.rule.everyN),
                          if (v.rule.mode == RecurringMode.confirm) 'confirmar importe',
                          if (!v.rule.isActive)
                            'en pausa'
                          else if (v.nextDate != null)
                            'próximo: ${Dates.dayMonthShort(v.nextDate!)}'
                          else
                            'finalizado',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Opacity(
                              opacity: v.rule.isActive ? 1 : 0.5,
                              child: AmountText(v.rule.amountCents, type: v.rule.type, style: context.text.titleSmall),
                            ),
                            Switch(
                              value: v.rule.isActive,
                              onChanged: (on) => ref.read(recurringRepoProvider).setActive(v.rule.id, on),
                            ),
                          ],
                        ),
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
