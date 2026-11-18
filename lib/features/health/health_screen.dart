import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../domain/benchmarks.dart';
import '../../domain/models.dart';
import '../plan/plan_widgets.dart';
import '../settings/settings_screen.dart';

void openHealth(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HealthScreen()));

/// Aviso fijo: son referencias, no consejos.
const healthDisclaimer = 'Son referencias orientativas habituales para comparar tus cifras, no asesoramiento '
    'financiero. Cada hogar es distinto: ajusta los porcentajes a tu situación.';

Color statusColor(BuildContext context, BenchmarkStatus? s) => switch (s) {
      BenchmarkStatus.inside => AppColors.income,
      BenchmarkStatus.near => AppColors.warning,
      BenchmarkStatus.outside => AppColors.danger,
      null => context.colors.outline,
    };

String pctText(double? pct) => pct == null ? '—' : '${pct.toStringAsFixed(0)} %';

/// Reglas orientativas por concepto frente a tu gasto real.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: '¿Restablecer las reglas iniciales?',
      message: 'Las seis reglas iniciales vuelven a sus porcentajes y se eligen de nuevo sus categorías por nombre '
          '(útil tras importar un plan). Las reglas que hayas creado tú no se tocan.',
      confirmLabel: 'Restablecer',
    );
    if (ok) await ref.read(benchmarkRepoProvider).resetDefaults();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(financialHealthProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salud financiera'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _reset(context, ref);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Restablecer reglas iniciales'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBenchmarkSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Regla'),
      ),
      body: health.when(
        loading: () => const LoadingBox(),
        error: (e, _) => ErrorBox(e),
        data: (h) {
          final cycle = ref.watch(monthCycleProvider);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: context.colors.primary),
                    const SizedBox(width: 10),
                    const Expanded(child: Text(healthDisclaimer, style: TextStyle(fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'Porcentajes de tus ingresos propios en ${Dates.monthYear(h.month)}'
                  '${cycle.isCalendar ? '' : ' (${cycle.rangeLabel(h.month)})'} y media de los últimos 12 meses.',
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
                ),
              ),
              for (final r in h.results) ...[
                const SizedBox(height: 8),
                _BenchmarkCard(result: r, onTap: () => showBenchmarkSheet(context, editing: r.benchmark)),
              ],
              const SizedBox(height: 8),
              _EmergencyFundCard(fund: h.fund),
            ],
          );
        },
      ),
    );
  }
}

class _BenchmarkCard extends StatelessWidget {
  const _BenchmarkCard({required this.result, required this.onTap});
  final BenchmarkResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final b = r.benchmark;
    final target = (b.maxPct ?? b.minPct ?? 0).toDouble();
    final status = r.status;
    final monthColor = statusColor(context, r.monthStatus);
    final avgColor = statusColor(context, r.averageStatus);
    final muted = TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant);
    return SectionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(b.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${b.metric == BenchmarkMetric.savings ? 'Ahorro real' : 'Gasto'} · ${b.limitLabel} de los ingresos',
                        style: muted),
                  ],
                ),
              ),
              if (status != null) Tag(status.label, color: statusColor(context, status)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('Este mes', style: TextStyle(fontSize: 13))),
              Text(
                r.monthPct == null ? 'aún sin ingresos' : pctText(r.monthPct),
                style: TextStyle(fontWeight: FontWeight.w700, color: monthColor, fontFeatures: tabularFigures),
              ),
              Text('  ${Money.format(r.monthCents)}', style: muted),
            ],
          ),
          const SizedBox(height: 6),
          TargetBar(valuePct: r.monthPct ?? 0, targetPct: target, color: monthColor),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.averageMonths == 0
                      ? 'Media: aún no hay meses anteriores'
                      : 'Media de ${r.averageMonths == 1 ? '1 mes' : '${r.averageMonths} meses'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (r.averageMonths > 0) ...[
                Text(pctText(r.averagePct),
                    style: TextStyle(fontWeight: FontWeight.w700, color: avgColor, fontFeatures: tabularFigures)),
                Text('  ${Money.format(r.averageCents ?? 0)}/mes', style: muted),
              ],
            ],
          ),
          if (r.averageMonths > 0) ...[
            const SizedBox(height: 6),
            TargetBar(valuePct: r.averagePct ?? 0, targetPct: target, color: avgColor, height: 6),
          ],
          if (b.metric == BenchmarkMetric.categories && b.categoryIds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Sin categorías: toca para elegirlas', style: TextStyle(fontSize: 12, color: AppColors.warning)),
            ),
        ],
      ),
    );
  }
}

class _EmergencyFundCard extends ConsumerWidget {
  const _EmergencyFundCard({required this.fund});
  final EmergencyFund? fund;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = fund;
    final muted = TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant);
    final months = f?.months;
    final color = statusColor(context, f?.status);
    // Barra de 0 a 9 meses, con la marca en el mínimo recomendado (3).
    const scale = 9.0;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('🛟', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fondo de emergencia', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Objetivo: de ${EmergencyFund.minMonths} a ${EmergencyFund.maxMonths} meses de gastos necesarios',
                        style: muted),
                  ],
                ),
              ),
              if (f?.status != null) Tag(f!.status!.label, color: color),
            ],
          ),
          const SizedBox(height: 12),
          if (f == null)
            InkWell(
              onTap: () => showInitialBalanceDialog(context, ref),
              child: Text('Indica tu saldo inicial para calcularlo', style: TextStyle(color: context.colors.primary)),
            )
          else if (months == null)
            Text('Aún no hay meses completos con gastos necesarios para calcular la media.', style: muted)
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${months.toStringAsFixed(1).replaceAll('.', ',')} meses',
                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TargetBar(
              valuePct: months / scale * 100,
              targetPct: EmergencyFund.minMonths / scale * 100,
              color: color,
            ),
            const SizedBox(height: 6),
            Text(
              '${Money.format(f.availableCents)} disponibles ÷ ${Money.format(f.monthlyNeedsCents!)} al mes de necesarios '
              '(media de ${f.monthsUsed == 1 ? '1 mes' : '${f.monthsUsed} meses'})',
              style: muted,
            ),
            if (f.aboveTarget)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Tienes más de ${EmergencyFund.maxMonths} meses cubiertos: quizá parte de ese dinero '
                    'podría estar trabajando en otro sitio.', style: muted),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Crear y editar reglas
// ---------------------------------------------------------------------------

Future<void> showBenchmarkSheet(BuildContext context, {Benchmark? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BenchmarkSheet(editing: editing),
  );
}

class _BenchmarkSheet extends ConsumerStatefulWidget {
  const _BenchmarkSheet({this.editing});
  final Benchmark? editing;

  @override
  ConsumerState<_BenchmarkSheet> createState() => _BenchmarkSheetState();
}

class _BenchmarkSheetState extends ConsumerState<_BenchmarkSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _min = TextEditingController(text: widget.editing?.minPct?.toString() ?? '');
  late final _max = TextEditingController(text: widget.editing?.maxPct?.toString() ?? '');
  late String _emoji = widget.editing?.emoji ?? '📊';
  late final Set<String> _categories = {...?widget.editing?.categoryIds};

  bool get _isSavings => widget.editing?.metric == BenchmarkMetric.savings;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _pct(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _save() async {
    final name = _name.text.trim();
    final min = _pct(_min), max = _pct(_max);
    String? error;
    if (name.isEmpty) error = 'Escribe un nombre';
    if ((_min.text.trim().isNotEmpty && min == null) || (_max.text.trim().isNotEmpty && max == null)) {
      error = 'Los porcentajes deben ser números enteros';
    } else if ((min ?? 0) > 100 || (max ?? 0) > 100) {
      error = 'Los porcentajes van de 0 a 100';
    } else if (min != null && max != null && min > max) {
      error = 'El mínimo no puede ser mayor que el máximo';
    } else if (min == null && max == null) {
      error = 'Indica un mínimo, un máximo o los dos';
    }
    if (error != null) {
      showSnack(context, error);
      return;
    }
    final repo = ref.read(benchmarkRepoProvider);
    if (widget.editing == null) {
      await repo.create(name: name, emoji: _emoji, minPct: min, maxPct: max, categoryIds: _categories);
    } else {
      await repo.update(widget.editing!.id, name: name, emoji: _emoji, minPct: min, maxPct: max, categoryIds: _categories);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar "${widget.editing!.name}"?',
      message: 'Puedes recuperar las reglas iniciales con "Restablecer reglas iniciales".',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(benchmarkRepoProvider).softDelete(widget.editing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final all = (ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const <CategoryRow>[])
        .where((c) => !c.isArchived || _categories.contains(c.id))
        .toList();
    // Grupos con sus subcategorías debajo, como en la pantalla de categorías.
    final parents = all.where((c) => c.parentId == null).toList();
    final childrenOf = <String, List<CategoryRow>>{};
    for (final c in all) {
      if (c.parentId != null) childrenOf.putIfAbsent(c.parentId!, () => []).add(c);
    }

    Widget chip(CategoryRow c) {
      final viaParent = c.parentId != null && _categories.contains(c.parentId);
      return FilterChip(
        label: Text('${c.emoji} ${c.name}'),
        selected: _categories.contains(c.id) || viaParent,
        onSelected: viaParent
            ? null
            : (sel) => setState(() => sel ? _categories.add(c.id) : _categories.remove(c.id)),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.editing == null ? 'Nueva regla' : 'Editar regla', style: context.text.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () async {
                    final e = await pickEmoji(context, current: _emoji);
                    if (e != null) setState(() => _emoji = e);
                  },
                  child: CircleAvatar(radius: 26, child: Text(_emoji, style: const TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                ),
              ],
            ),
            FieldLabel(_isSavings ? 'Ahorro real, en % de los ingresos' : 'Gasto, en % de los ingresos'),
            Row(
              children: [
                Expanded(child: _PctField(controller: _min, label: 'Mínimo')),
                const SizedBox(width: 12),
                Expanded(child: _PctField(controller: _max, label: 'Máximo')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Deja vacío el que no quieras usar.',
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
            ),
            if (_isSavings)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Esta regla mide el ahorro real del mes (lo que te sobra más lo que va a ahorro o patrimonio, '
                  'menos lo que sacas de tus ahorros), así que no usa categorías.',
                  style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant),
                ),
              )
            else ...[
              FieldLabel('Categorías que incluye (${_categories.length})'),
              Text('Si eliges un grupo, cuentan todas sus subcategorías.',
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final p in parents) ...[
                Wrap(spacing: 6, runSpacing: 2, children: [chip(p)]),
                if (childrenOf[p.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [for (final c in childrenOf[p.id]!) chip(c)],
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.editing != null)
                  IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
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

class _PctField extends StatelessWidget {
  const _PctField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(labelText: label, suffixText: '%'),
      );
}

/// Resumen para el inicio: reglas incumplidas (o nada si todo va bien).
class HealthSummaryCard extends ConsumerWidget {
  const HealthSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(financialHealthProvider).value;
    if (h == null) return const SizedBox.shrink();
    final outside = h.outside;
    if (outside.isEmpty && !h.fundOutside) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: 'Salud financiera',
        trailing: Icon(Icons.chevron_right, color: context.colors.onSurfaceVariant),
        onTap: () => openHealth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in outside)
              _SummaryLine(
                emoji: r.benchmark.emoji,
                text: '${r.benchmark.name}: ${pctText(r.statusPct)} (${r.benchmark.limitLabel})'
                    '${r.monthPct == null ? ' de media' : ''}',
              ),
            if (h.fundOutside)
              _SummaryLine(
                emoji: '🛟',
                text: 'Fondo de emergencia: ${h.fund!.months!.toStringAsFixed(1).replaceAll('.', ',')} meses '
                    '(objetivo ${EmergencyFund.minMonths}–${EmergencyFund.maxMonths})',
              ),
            const SizedBox(height: 4),
            Text('Referencias orientativas, no asesoramiento financiero.',
                style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.emoji, required this.text});
  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(emoji),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.danger))),
          ],
        ),
      );
}
