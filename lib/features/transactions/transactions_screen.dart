import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/database.dart';
import '../../domain/models.dart';
import 'transaction_tile.dart';

/// Historial completo con búsqueda, filtros y ordenación.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialFilter});
  final TxFilter? initialFilter;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late TxFilter _filter = widget.initialFilter ?? const TxFilter();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _hidden = {}; // borrados por deslizar, mientras se actualiza la consulta
  List<TxView>? _lastData;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setFilter(TxFilter f) => setState(() => _filter = f.copyWith(limit: 200));

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    final data = _lastData;
    if (data != null && data.length >= _filter.limit) {
      setState(() => _filter = _filter.copyWith(limit: _filter.limit + 200));
    }
  }

  MonthCycle get _cycle => ref.read(monthCycleProvider);

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _setFilter(_filter.copyWith(query: text)));
  }

  Future<void> _pickDates() async {
    final now = Dates.today();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _filter.from != null && _filter.to != null
          ? DateTimeRange(start: _filter.from!, end: _filter.to!)
          : DateTimeRange(start: _cycle.startOf(_cycle.monthOf(now)), end: now),
    );
    if (range != null) _setFilter(_filter.copyWith(from: Dates.dateOnly(range.start), to: Dates.dateOnly(range.end)));
  }

  Future<void> _pickMonth() async {
    final cycle = _cycle;
    final month = await pickMonth(context, initial: cycle.monthOf(_filter.to ?? Dates.today()));
    if (month != null) _setFilter(_filter.copyWith(from: cycle.startOf(month), to: cycle.endOf(month)));
  }

  Future<void> _pickCategories() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryFilterSheet(initial: _filter.categoryIds),
    );
    if (selected != null) _setFilter(_filter.copyWith(categoryIds: selected));
  }

  Future<void> _pickMethod(List<PaymentMethodRow> methods) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in methods)
              ListTile(
                leading: Text(m.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(m.name),
                trailing: m.id == _filter.paymentMethodId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) _setFilter(_filter.copyWith(paymentMethodId: id));
  }

  void _delete(TxView tx) {
    setState(() => _hidden.add(tx.id));
    final repo = ref.read(transactionRepoProvider);
    repo.softDelete(tx.id);
    showSnack(
      context,
      'Movimiento eliminado',
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          await repo.restore(tx.id);
          if (mounted) setState(() => _hidden.remove(tx.id));
        },
      ),
    );
  }

  String _dateChipLabel() {
    final f = _filter.from, t = _filter.to;
    if (f == null || t == null) return 'Fechas';
    final m = _cycle.monthOf(t);
    if (Dates.sameDay(f, _cycle.startOf(m)) && Dates.sameDay(t, _cycle.endOf(m))) return Dates.monthYear(m);
    return '${Dates.dayMonthShort(f)} – ${Dates.dayMonthShort(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(filteredTxProvider(_filter));
    if (async.hasValue) _lastData = async.value;
    final data = (async.value ?? _lastData)?.where((t) => !_hidden.contains(t.id)).toList();
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethodRow>[];
    final methodName = methods.where((m) => m.id == _filter.paymentMethodId).map((m) => m.name).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        actions: [
          PopupMenuButton<TxSort>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _filter.sort,
            onSelected: (s) => _setFilter(_filter.copyWith(sort: s)),
            itemBuilder: (_) => [for (final s in TxSort.values) PopupMenuItem(value: s, child: Text(s.label))],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por descripción, nota o categoría',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _setFilter(_filter.copyWith(query: ''));
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip(
                  FilterChip(
                    label: const Text('Gastos'),
                    selected: _filter.type == TxType.expense,
                    onSelected: (s) => _setFilter(_filter.copyWith(type: s ? TxType.expense : null)),
                  ),
                ),
                _chip(
                  FilterChip(
                    label: const Text('Ingresos'),
                    selected: _filter.type == TxType.income,
                    onSelected: (s) => _setFilter(_filter.copyWith(type: s ? TxType.income : null)),
                  ),
                ),
                _chip(
                  ActionChip(
                    avatar: const Icon(Icons.calendar_view_month, size: 18),
                    label: const Text('Mes'),
                    onPressed: _pickMonth,
                  ),
                ),
                _chip(
                  InputChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_dateChipLabel()),
                    selected: _filter.from != null,
                    onPressed: _pickDates,
                    onDeleted: _filter.from == null ? null : () => _setFilter(_filter.copyWith(from: null, to: null)),
                  ),
                ),
                _chip(
                  InputChip(
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    label: Text(_filter.categoryIds.isEmpty ? 'Categorías' : 'Categorías (${_filter.categoryIds.length})'),
                    selected: _filter.categoryIds.isNotEmpty,
                    onPressed: _pickCategories,
                    onDeleted: _filter.categoryIds.isEmpty
                        ? null
                        : () => _setFilter(_filter.copyWith(categoryIds: const {})),
                  ),
                ),
                _chip(
                  InputChip(
                    avatar: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(methodName ?? 'Método'),
                    selected: _filter.paymentMethodId != null,
                    onPressed: () => _pickMethod(methods),
                    onDeleted: _filter.paymentMethodId == null
                        ? null
                        : () => _setFilter(_filter.copyWith(paymentMethodId: null)),
                  ),
                ),
                if (_filter.hasFilters)
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      _setFilter(TxFilter(sort: _filter.sort));
                    },
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.hasError && data == null
                ? ErrorBox(async.error!)
                : data == null
                    ? const LoadingBox()
                    : data.isEmpty
                        ? EmptyState(
                            emoji: _filter.hasFilters ? '🔍' : '🧾',
                            title: _filter.hasFilters ? 'Sin resultados' : 'Aún no hay movimientos',
                            message: _filter.hasFilters
                                ? 'Prueba con otros filtros.'
                                : 'Pulsa + para registrar tu primer gasto o ingreso.',
                          )
                        : _buildList(data),
          ),
        ],
      ),
    );
  }

  Widget _chip(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child);

  Widget _buildList(List<TxView> data) {
    // Resumen del resultado (solo confirmados).
    var income = 0, expense = 0;
    for (final t in data) {
      if (t.isPending) continue;
      if (t.isExpense) {
        expense += t.amountCents;
      } else {
        income += t.amountCents;
      }
    }
    final groupByDay = _filter.sort == TxSort.dateDesc || _filter.sort == TxSort.dateAsc;

    // Lista plana: cabecera de día + filas.
    final entries = <Object>[];
    if (groupByDay) {
      String? currentKey;
      for (final t in data) {
        final k = Dates.key(t.date);
        if (k != currentKey) {
          entries.add(t.date);
          currentKey = k;
        }
        entries.add(t);
      }
    } else {
      entries.addAll(data);
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 16,
              children: [
                Text('${data.length}${data.length >= _filter.limit ? '+' : ''} movimientos',
                    style: TextStyle(color: context.colors.onSurfaceVariant)),
                AmountText(-expense, style: context.text.bodyMedium),
                AmountText(income, style: context.text.bodyMedium),
              ],
            ),
          );
        }
        final e = entries[i - 1];
        if (e is DateTime) {
          final dayNet = data
              .where((t) => Dates.sameDay(t.date, e) && !t.isPending)
              .fold<int>(0, (sum, t) => sum + t.signedCents);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(Dates.relativeDay(e),
                      style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
                ),
                Text(Money.formatSigned(dayNet, positive: dayNet >= 0),
                    style: TextStyle(color: context.colors.onSurfaceVariant, fontFeatures: tabularFigures)),
              ],
            ),
          );
        }
        final tx = e as TxView;
        return Dismissible(
          key: ValueKey(tx.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColors.danger,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => _delete(tx),
          child: TransactionTile(tx: tx, showDate: !groupByDay),
        );
      },
    );
  }
}

/// Hoja para elegir varias categorías (gastos e ingresos).
class _CategoryFilterSheet extends ConsumerStatefulWidget {
  const _CategoryFilterSheet({required this.initial});
  final Set<String> initial;

  @override
  ConsumerState<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends ConsumerState<_CategoryFilterSheet> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final expense = ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const <CategoryRow>[];
    final income = ref.watch(categoriesProvider(CategoryKind.income)).value ?? const <CategoryRow>[];

    Widget section(String title, List<CategoryRow> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title, style: context.text.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in list)
                    FilterChip(
                      label: Text('${c.emoji} ${c.name}'),
                      selected: _selected.contains(c.id),
                      onSelected: (s) => setState(() => s ? _selected.add(c.id) : _selected.remove(c.id)),
                    ),
                ],
              ),
            ),
          ],
        );

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [section('Gastos', expense), section('Ingresos', income)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('Ninguna')),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Aplicar')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
