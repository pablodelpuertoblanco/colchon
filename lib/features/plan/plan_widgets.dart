import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';

/// Color de la barra de una fila según lo gastado frente a lo previsto.
Color planLineColor(PlanLine l) {
  if (l.isIncome) return AppColors.income;
  final r = l.ratio;
  if (r == null) return l.realCents > 0 ? AppColors.warning : AppColors.income;
  if (r > 1.0001) return AppColors.danger;
  if (r >= 0.85) return AppColors.warning;
  return AppColors.income;
}

/// Resumen: ingresos, gastos, saldo del mes y ahorro real (previsto y real).
class PlanSummaryCard extends StatelessWidget {
  const PlanSummaryCard({super.key, required this.totals, this.title, this.progressLine});
  final PlanTotals totals;
  final String? title;

  /// Texto opcional sobre el ritmo del mes ("Llevas el 45 % del mes...").
  final String? progressLine;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final realSavings = t.realSavingsCents(real: true);
    final plannedSavings = t.realSavingsCents(real: false);
    final share = t.shareOfIncome(realSavings, real: true);
    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Ingresos',
                  real: t.incomeCents(real: true),
                  planned: t.incomeCents(real: false),
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  label: 'Gastos',
                  real: t.expenseCents(real: true),
                  planned: t.expenseCents(real: false),
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Saldo',
                  real: t.balanceCents(real: true),
                  planned: t.balanceCents(real: false),
                  color: t.balanceCents(real: true) >= 0 ? AppColors.income : AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  label: share == null ? 'Ahorro real' : 'Ahorro real · ${share.toStringAsFixed(0)} %',
                  real: realSavings,
                  planned: plannedSavings,
                  color: realSavings >= 0 ? AppColors.income : AppColors.danger,
                ),
              ),
            ],
          ),
          if (progressLine != null) ...[
            const SizedBox(height: 12),
            Text(progressLine!, style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.real, required this.planned, required this.color});
  final String label;
  final int real;
  final int planned;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(real),
              style: context.text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
            ),
          ),
          Text('previsto ${Money.format(planned)}',
              style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures)),
        ],
      );
}

/// Regla 50/30/20: qué parte de los ingresos va a cada bloque.
class RuleCard extends StatelessWidget {
  const RuleCard({super.key, required this.totals, required this.targets, this.title = 'Regla 50/30/20', this.onEditTargets});
  final PlanTotals totals;
  final RuleTargets targets;
  final String title;
  final VoidCallback? onEditTargets;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final hasRealIncome = t.ownIncomeCents(real: true) > 0;
    // Sin ingresos reales todavía (principio de mes) se muestra el previsto.
    final real = hasRealIncome;
    final unclassified = t.sectionCents(PlanSectionKind.unclassified, real: real);
    final free = t.balanceCents(real: real);

    return SectionCard(
      title: title,
      trailing: onEditTargets == null
          ? null
          : IconButton(
              tooltip: 'Cambiar objetivos',
              visualDensity: VisualDensity.compact,
              onPressed: onEditTargets,
              icon: const Icon(Icons.tune, size: 20),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!real)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Aún no hay ingresos este mes: se muestra lo previsto.',
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
            ),
          for (final b in RuleBucket.values)
            _RuleRow(
              bucket: b,
              pct: t.shareOfIncome(t.bucketCents(b, real: real), real: real),
              plannedPct: t.shareOfIncome(t.bucketCents(b, real: false), real: false),
              cents: t.bucketCents(b, real: real),
              target: targets.of(b),
              showPlanned: real,
            ),
          if (unclassified > 0)
            _ExtraLine(
              label: 'Sin clasificar',
              cents: unclassified,
              pct: t.shareOfIncome(unclassified, real: real),
              hint: 'Asigna un bloque a esas categorías',
            ),
          _ExtraLine(
            label: free >= 0 ? 'Saldo sin asignar' : 'Gastas más de lo que ingresas',
            cents: free,
            pct: t.shareOfIncome(free, real: real),
            danger: free < 0,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.bucket,
    required this.pct,
    required this.plannedPct,
    required this.cents,
    required this.target,
    required this.showPlanned,
  });
  final RuleBucket bucket;
  final double? pct;
  final double? plannedPct;
  final int cents;
  final int target;
  final bool showPlanned;

  @override
  Widget build(BuildContext context) {
    final value = pct ?? 0;
    // En necesarios y prescindibles, pasarse del objetivo es malo; en ahorro,
    // quedarse por debajo.
    final bad = bucket == RuleBucket.savings ? value < target - 0.5 : value > target + 0.5;
    final color = pct == null ? context.colors.outline : (bad ? AppColors.warning : AppColors.income);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(bucket.label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(
                pct == null ? '—' : '${value.toStringAsFixed(0)} %',
                style: TextStyle(fontWeight: FontWeight.w700, color: color, fontFeatures: tabularFigures),
              ),
              Text('  / objetivo $target %',
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          TargetBar(valuePct: value, targetPct: target.toDouble(), color: color),
          const SizedBox(height: 4),
          Text(
            '${Money.format(cents)}'
            '${showPlanned && plannedPct != null ? ' · previsto ${plannedPct!.toStringAsFixed(0)} %' : ''}',
            style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ExtraLine extends StatelessWidget {
  const _ExtraLine({required this.label, required this.cents, required this.pct, this.hint, this.danger = false});
  final String label;
  final int cents;
  final double? pct;
  final String? hint;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, color: danger ? AppColors.danger : null)),
                  if (hint != null)
                    Text(hint!, style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              '${Money.format(cents)}${pct == null ? '' : ' · ${pct!.toStringAsFixed(0)} %'}',
              style: TextStyle(fontSize: 13, fontFeatures: tabularFigures, color: danger ? AppColors.danger : null),
            ),
          ],
        ),
      );
}

/// Barra con el valor y una marca vertical en el objetivo.
class TargetBar extends StatelessWidget {
  const TargetBar({super.key, required this.valuePct, required this.targetPct, required this.color, this.height = 10});
  final double valuePct;
  final double targetPct;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final v = (valuePct / 100).clamp(0.0, 1.0).toDouble();
      final t = (targetPct / 100).clamp(0.0, 1.0).toDouble();
      final radius = BorderRadius.circular(height / 2);
      return SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, borderRadius: radius),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: w * v,
              child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: radius)),
            ),
            Positioned(
              left: (w * t - 1).clamp(0.0, w > 2 ? w - 2 : 0.0).toDouble(),
              top: -3,
              bottom: -3,
              width: 2,
              child: ColoredBox(color: context.colors.onSurface),
            ),
          ],
        ),
      );
    });
  }
}

/// Fila del plan: categoría, real / previsto y barra de progreso.
class PlanLineTile extends StatelessWidget {
  const PlanLineTile({super.key, required this.line, this.onTap});
  final PlanLine line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final color = planLineColor(l);
    final parentName = l.parent?.name;
    String detail;
    if (l.plannedCents == 0) {
      detail = 'Sin previsto';
    } else if (l.isIncome) {
      final d = l.differenceCents;
      detail = d > 0 ? 'Falta ${Money.format(d)}' : (d == 0 ? 'Cobrado' : '+${Money.format(-d)} de más');
    } else {
      final d = l.differenceCents;
      detail = d >= 0 ? 'Quedan ${Money.format(d)}' : 'Te has pasado ${Money.format(-d)}';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(l.category.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.category.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        [?parentName, detail].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: l.isOver ? AppColors.danger : context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Money.format(l.realCents),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                    Text('de ${Money.format(l.plannedCents)}',
                        style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: l.plannedCents == 0 ? (l.realCents > 0 ? 1.0 : 0.0) : (l.ratio ?? 0).clamp(0.0, 1.0).toDouble(),
                minHeight: 5,
                color: color,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cabecera de un bloque con sus totales.
class PlanSectionHeader extends StatelessWidget {
  const PlanSectionHeader({super.key, required this.section, this.ownIncomeCents});
  final PlanSection section;

  /// Ingresos para mostrar el porcentaje del bloque.
  final int? ownIncomeCents;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final pct = ownIncomeCents == null || ownIncomeCents! <= 0 || s.kind.isIncome
        ? null
        : s.realCents / ownIncomeCents! * 100;
    return Row(
      children: [
        Text(s.kind.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pct == null ? s.kind.label : '${s.kind.label} · ${pct.toStringAsFixed(0)} %',
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '${Money.formatShort(s.realCents)} / ${Money.formatShort(s.plannedCents)}',
          style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures),
        ),
      ],
    );
  }
}
