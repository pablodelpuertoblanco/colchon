import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../domain/models.dart';
import '../../domain/net_worth.dart';
import '../stats/charts.dart';

void openNetWorth(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NetWorthScreen()));
}

/// Patrimonio: lo que tienes menos lo que debes, mes a mes.
class NetWorthScreen extends ConsumerStatefulWidget {
  const NetWorthScreen({super.key});

  @override
  ConsumerState<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends ConsumerState<NetWorthScreen> {
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final cycle = ref.watch(monthCycleProvider);
    final current = cycle.monthOf(Dates.today());
    final month = _month ?? current;
    final worth = ref.watch(netWorthProvider(month));
    final assets = ref.watch(assetsProvider).value ?? const <AssetInfo>[];
    final values = ref.watch(assetValuesProvider).value ?? const <AssetValue>[];

    void openUpdate() => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => UpdateValuesScreen(month: month),
        ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrimonio'),
        actions: [
          if (assets.isNotEmpty)
            IconButton(onPressed: openUpdate, icon: const Icon(Icons.edit_calendar_outlined), tooltip: 'Anotar valores del mes'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'asset-add',
        onPressed: () => showAssetSheet(context, month: month),
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
      body: worth == null
          ? const LoadingBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                PeriodSwitcher(
                  label: Dates.monthYear(month),
                  onPrevious: () => setState(() => _month = Dates.shiftMonth(month, -1)),
                  onNext: () => setState(() => _month = Dates.shiftMonth(month, 1)),
                  onTapLabel: () async {
                    final m = await pickMonth(context, initial: month);
                    if (m != null) setState(() => _month = m);
                  },
                ),
                if (assets.isEmpty)
                  const EmptyState(
                    emoji: '🏦',
                    title: 'Apunta lo que tienes y lo que debes',
                    message: 'Planes de pensiones, acciones, cuenta de ahorro, hipotecas... Una vez al mes anotas su valor '
                        'y verás cómo evoluciona tu patrimonio.',
                  )
                else ...[
                  _SummaryCard(worth: worth, series: netWorthSeries(month, 12, assets, values), lastMonth: month),
                  if (worth.pendingUpdates > 0 && !month.isAfter(current)) ...[
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: context.colors.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.edit_calendar_outlined),
                        title: Text('Anota los valores de ${Dates.monthNames[month.month - 1]}'),
                        subtitle: Text('${worth.pendingUpdates} sin actualizar este mes'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: openUpdate,
                      ),
                    ),
                  ],
                  for (final kind in AssetKind.values)
                    if (worth.positions.any((p) => p.asset.kind == kind)) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        title: kind.label,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          children: [
                            for (final p in worth.positions.where((p) => p.asset.kind == kind))
                              _PositionTile(position: p, onTap: () => showAssetSheet(context, month: month, position: p)),
                          ],
                        ),
                      ),
                    ],
                ],
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.worth, required this.series, required this.lastMonth});
  final NetWorth worth;
  final List<int> series;
  final DateTime lastMonth;

  @override
  Widget build(BuildContext context) {
    final change = worth.changeCents;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Patrimonio neto', style: TextStyle(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            Money.format(worth.netCents),
            style: context.text.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
              color: worth.netCents < 0 ? AppColors.danger : null,
            ),
          ),
          const SizedBox(height: 4),
          if (change != 0)
            Text(
              '${change > 0 ? '▲' : '▼'} ${Money.formatSigned(change, positive: change > 0)} respecto al mes anterior',
              style: TextStyle(fontSize: 13, color: change > 0 ? AppColors.income : AppColors.expense),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Mini(label: 'Lo que tengo', cents: worth.assetsCents, color: AppColors.income)),
              Expanded(child: _Mini(label: 'Lo que debo', cents: worth.liabilitiesCents, color: AppColors.expense)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Últimos 12 meses', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          BalanceLine(
            labels: [
              for (var i = series.length - 1; i >= 0; i--)
                Dates.capitalize(Dates.monthShort[Dates.shiftMonth(lastMonth, -i).month - 1]),
            ],
            valuesCents: series,
            height: 150,
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.cents, required this.color});
  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Money.format(cents),
                style: context.text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
          ),
        ],
      );
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({required this.position, required this.onTap});
  final AssetPosition position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final change = p.changeCents;
    final subtitle = p.valueCents == null
        ? 'Sin valor anotado'
        : (p.recordedThisMonth ? 'Anotado este mes' : 'Último valor de un mes anterior');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Text(p.asset.emoji, style: const TextStyle(fontSize: 26)),
      title: Text(p.asset.isArchived ? '${p.asset.name} (archivado)' : p.asset.name),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(p.valueCents == null ? '—' : Money.format(p.valueCents!),
              style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
          if (change != null && change != 0)
            Text(
              Money.formatSigned(change, positive: change > 0),
              style: TextStyle(
                fontSize: 12,
                fontFeatures: tabularFigures,
                // Que una deuda baje es bueno.
                color: (change > 0) != p.asset.isLiability ? AppColors.income : AppColors.expense,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Crea o edita un bien/deuda y su valor en [month].
Future<void> showAssetSheet(BuildContext context, {required DateTime month, AssetPosition? position}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssetSheet(month: month, position: position),
  );
}

class _AssetSheet extends ConsumerStatefulWidget {
  const _AssetSheet({required this.month, this.position});
  final DateTime month;
  final AssetPosition? position;

  @override
  ConsumerState<_AssetSheet> createState() => _AssetSheetState();
}

class _AssetSheetState extends ConsumerState<_AssetSheet> {
  AssetInfo? get _editing => widget.position?.asset;
  late final _name = TextEditingController(text: _editing?.name ?? '');
  late final _value = TextEditingController(
    text: widget.position?.valueCents == null ? '' : centsToInput(widget.position!.valueCents!),
  );
  late String _emoji = _editing?.emoji ?? '🏦';
  late AssetKind _kind = _editing?.kind ?? AssetKind.asset;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Escribe un nombre');
      return;
    }
    final text = _value.text.trim();
    final cents = text.isEmpty ? null : Money.parse(text);
    if (text.isNotEmpty && (cents == null || cents < 0)) {
      showSnack(context, 'Valor no válido');
      return;
    }
    final repo = ref.read(assetRepoProvider);
    final id = _editing?.id ?? await repo.create(name: name, emoji: _emoji, kind: _kind);
    if (_editing != null) await repo.update(id, name: name, emoji: _emoji, kind: _kind);
    // Solo se anota valor si se ha escrito uno distinto al que ya se arrastraba.
    final previous = widget.position?.valueCents;
    if (cents != null && (cents != previous || !(widget.position?.recordedThisMonth ?? false))) {
      await repo.setValues(widget.month, {id: cents});
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final a = _editing!;
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar "${a.name}"?',
      message: 'Se borran también todos sus valores anotados. Si ya no lo tienes pero quieres conservar el histórico, archívalo.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(assetRepoProvider).delete(a.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _archive() async {
    final a = _editing!;
    await ref.read(assetRepoProvider).setArchived(a.id, !a.isArchived);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final monthName = Dates.monthNames[widget.month.month - 1];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing == null ? 'Nuevo' : 'Editar', style: context.text.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<AssetKind>(
              segments: [for (final k in AssetKind.values) ButtonSegment(value: k, label: Text(k.label))],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () async {
                    final e = await pickEmoji(context, current: _emoji);
                    if (e != null) setState(() => _emoji = e);
                  },
                  child: CircleAvatar(radius: 28, child: Text(_emoji, style: const TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: _editing == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      hintText: _kind == AssetKind.asset ? 'Ej.: Plan de pensiones' : 'Ej.: Hipoteca (pendiente)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MoneyField(
              controller: _value,
              label: _kind == AssetKind.asset ? 'Valor en $monthName' : 'Pendiente en $monthName',
              helper: 'Se mantiene los meses siguientes hasta que anotes otro',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_editing != null) ...[
                  IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
                  TextButton(onPressed: _archive, child: Text(_editing!.isArchived ? 'Desarchivar' : 'Archivar')),
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

// ---------------------------------------------------------------------------

/// Anotar de una vez el valor de todos los bienes y deudas en un mes
/// (lo que en el Excel era rellenar la columna del mes en INMOVILIZADO).
class UpdateValuesScreen extends ConsumerStatefulWidget {
  const UpdateValuesScreen({super.key, required this.month});
  final DateTime month;

  @override
  ConsumerState<UpdateValuesScreen> createState() => _UpdateValuesScreenState();
}

class _UpdateValuesScreenState extends ConsumerState<UpdateValuesScreen> {
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(NetWorth worth) async {
    final values = <String, int?>{};
    for (final p in worth.positions.where((p) => !p.asset.isArchived)) {
      final text = _controllers[p.asset.id]?.text.trim() ?? '';
      if (text.isEmpty) {
        if (p.recordedThisMonth) values[p.asset.id] = null; // borra el valor de este mes
        continue;
      }
      final cents = Money.parse(text);
      if (cents == null || cents < 0) {
        showSnack(context, 'Revisa el valor de ${p.asset.name}');
        return;
      }
      values[p.asset.id] = cents;
    }
    setState(() => _saving = true);
    await ref.read(assetRepoProvider).setValues(widget.month, values);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final worth = ref.watch(netWorthProvider(widget.month));
    return Scaffold(
      appBar: AppBar(title: Text('Valores de ${Dates.monthNames[widget.month.month - 1]}')),
      body: worth == null
          ? const LoadingBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Viene rellenado con el último valor conocido. Cambia lo que haya variado y guarda.',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final p in worth.positions.where((p) => !p.asset.isArchived))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: TextField(
                      controller: _controllers.putIfAbsent(
                        p.asset.id,
                        () => TextEditingController(text: p.valueCents == null ? '' : centsToInput(p.valueCents!)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontFeatures: tabularFigures),
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(p.asset.emoji, style: const TextStyle(fontSize: 20)),
                        ),
                        labelText: '${p.asset.name}${p.asset.isLiability ? ' (deuda)' : ''}',
                        suffixText: '€',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _saving ? null : () => _save(worth),
                  child: const Text('Guardar'),
                ),
              ],
            ),
    );
  }
}
