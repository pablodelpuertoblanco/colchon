import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../domain/budget_math.dart';
import '../../domain/models.dart';
import '../categories/category_form_sheet.dart';
import '../categories/category_picker.dart';

/// Abre el formulario para crear, editar, duplicar o confirmar un movimiento.
Future<void> openTransactionForm(
  BuildContext context, {
  TxType type = TxType.expense,
  DateTime? date,
  String? categoryId,
  TxView? editing,
  TxView? duplicateOf,
  bool confirmMode = false,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => TransactionFormScreen(
      initialType: type,
      initialDate: date,
      initialCategoryId: categoryId,
      editing: editing,
      duplicateOf: duplicateOf,
      confirmMode: confirmMode,
    ),
  ));
}

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.initialType = TxType.expense,
    this.initialDate,
    this.initialCategoryId,
    this.editing,
    this.duplicateOf,
    this.confirmMode = false,
  });

  final TxType initialType;
  final DateTime? initialDate;
  final String? initialCategoryId;
  final TxView? editing;
  final TxView? duplicateOf;

  /// Confirmar un recibo pendiente (p. ej. la luz con su importe real).
  final bool confirmMode;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late TxType _type;
  String _amount = '';
  String? _categoryId;
  bool _categoryTouched = false;
  late final TextEditingController _desc;
  late final TextEditingController _notes;
  late DateTime _date;
  TimeOfDay? _time;
  String? _paymentMethodId;
  bool _repeat = false;
  Frequency _repeatFrequency = Frequency.month;
  List<String> _suggestions = const [];
  Timer? _debounce;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final source = widget.editing ?? widget.duplicateOf;
    if (source != null) {
      _type = source.type;
      _amount = centsToInput(source.amountCents);
      _categoryId = source.categoryId;
      _categoryTouched = true;
      _desc = TextEditingController(text: source.description);
      _notes = TextEditingController(text: source.notes ?? '');
      _date = widget.editing != null ? source.date : Dates.today();
      _paymentMethodId = source.paymentMethodId;
      if (widget.editing != null && source.time != null) {
        final p = source.time!.split(':');
        _time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
    } else {
      _type = widget.initialType;
      _categoryId = widget.initialCategoryId;
      _categoryTouched = _categoryId != null;
      _desc = TextEditingController();
      _notes = TextEditingController();
      _date = widget.initialDate ?? Dates.today();
      _loadLastPaymentMethod();
    }
  }

  Future<void> _loadLastPaymentMethod() async {
    final id = await ref.read(transactionRepoProvider).lastPaymentMethod(_type);
    if (mounted && _paymentMethodId == null && id != null) setState(() => _paymentMethodId = id);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _desc.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? get _amountCents => _amount.isEmpty ? null : Money.parse(_amount);

  String get _title {
    if (widget.confirmMode) return 'Confirmar recibo';
    if (_isEditing) return 'Editar movimiento';
    return _type == TxType.expense ? 'Nuevo gasto' : 'Nuevo ingreso';
  }

  // ---------------------------------------------------------------- teclado

  void _onKey(String key) {
    setState(() {
      if (key == 'clear') {
        _amount = '';
      } else if (key == AmountKeypad.backspace) {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (key == ',') {
        if (!_amount.contains(',')) _amount = _amount.isEmpty ? '0,' : '$_amount,';
      } else if (_amount.contains(',')) {
        if (_amount.split(',')[1].length < 2) _amount += key;
      } else if (_amount == '0') {
        _amount = key;
      } else if (_amount.length < 7) {
        _amount += key;
      }
    });
  }

  String get _amountDisplay {
    if (_amount.isEmpty) return '0';
    final parts = _amount.split(',');
    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? 0;
    final grouped = NumberFormat('#,##0', 'es_ES').format(whole);
    return parts.length > 1 ? '$grouped,${parts[1]}' : grouped;
  }

  // ------------------------------------------------------------ descripción

  void _onDescriptionChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final repo = ref.read(transactionRepoProvider);
      final list = await repo.suggestDescriptions(text, _type);
      if (!mounted) return;
      setState(() => _suggestions = list.where((s) => s.toLowerCase() != text.trim().toLowerCase()).toList());
      await _suggestCategoryFor(text);
    });
  }

  Future<void> _suggestCategoryFor(String text) async {
    if (_categoryTouched) return;
    final id = await ref.read(transactionRepoProvider).suggestCategory(text, _type);
    if (mounted && id != null && !_categoryTouched) setState(() => _categoryId = id);
  }

  void _applySuggestion(String s) {
    _desc.text = s;
    _desc.selection = TextSelection.collapsed(offset: s.length);
    setState(() => _suggestions = const []);
    _suggestCategoryFor(s);
  }

  // ------------------------------------------------------------------ fecha

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = Dates.dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) setState(() => _time = picked);
  }

  String? get _timeText =>
      _time == null ? null : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- guardar

  Future<void> _save() async {
    final cents = _amountCents;
    if (cents == null || cents <= 0) {
      showSnack(context, 'Introduce un importe');
      return;
    }
    if (_categoryId == null) {
      showSnack(context, 'Elige una categoría');
      return;
    }
    final status = widget.confirmMode ? TxStatus.confirmed : (widget.editing?.status ?? TxStatus.confirmed);
    final draft = TxDraft(
      type: _type,
      amountCents: cents,
      categoryId: _categoryId!,
      date: _date,
      description: _desc.text,
      paymentMethodId: _paymentMethodId,
      time: _timeText,
      notes: _notes.text,
      status: status,
    );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final txRepo = ref.read(transactionRepoProvider);
      var alerts = const <BudgetAlert>[];
      if (_isEditing) {
        await txRepo.update(widget.editing!.id, draft);
      } else {
        final id = await txRepo.create(draft);
        if (_repeat) {
          final rules = ref.read(recurringRepoProvider);
          final ruleId = await rules.create(RuleDraft(
            type: _type,
            amountCents: cents,
            description: _desc.text,
            categoryId: _categoryId!,
            paymentMethodId: _paymentMethodId,
            frequency: _repeatFrequency,
            everyN: 1,
            startDate: _date,
            mode: RecurringMode.auto,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ));
          // Este movimiento es la primera ocurrencia: así la regla no lo duplica.
          await txRepo.linkToRule(id, ruleId, _date);
          await rules.generateDue();
        }
        if (_type == TxType.expense) {
          alerts = await ref
              .read(budgetRepoProvider)
              .alertsAfterExpense(
                  categoryId: _categoryId!, date: _date, amountCents: cents, cycle: ref.read(monthCycleProvider));
        }
      }
      navigator.pop();
      if (alerts.isNotEmpty) {
        final a = alerts.first;
        messenger.showSnackBar(SnackBar(
          content: Text(a.message),
          backgroundColor: a.state == BudgetState.exceeded ? AppColors.danger : AppColors.warning,
          duration: const Duration(seconds: 5),
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(widget.confirmMode
              ? 'Recibo confirmado'
              : _isEditing
                  ? 'Movimiento actualizado'
                  : '${_type.label} guardado'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'No se ha podido guardar: $e');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: '¿Eliminar este movimiento?', confirmLabel: 'Eliminar', destructive: true);
    if (!ok || !mounted) return;
    final repo = ref.read(transactionRepoProvider);
    final id = widget.editing!.id;
    final messenger = ScaffoldMessenger.of(context);
    await repo.softDelete(id);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Movimiento eliminado'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => repo.restore(id)),
    ));
  }

  Future<void> _newCategory() async {
    final id = await showCategoryForm(context, kind: CategoryKind.fromTxType(_type));
    if (id != null && mounted) {
      setState(() {
        _categoryId = id;
        _categoryTouched = true;
      });
    }
  }

  Future<void> _pickFromAll(List<CategoryRow> list) async {
    final all = ref.read(categoryMapProvider).value?.values.toList() ?? list;
    final id = await showCategoryPicker(context, selectable: list, all: all, selectedId: _categoryId);
    if (id != null && mounted) {
      setState(() {
        _categoryId = id;
        _categoryTouched = true;
      });
    }
  }

  // -------------------------------------------------------------- interfaz

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final color = _type == TxType.expense ? AppColors.expense : AppColors.income;
    final categories = ref.watch(selectableCategoriesProvider(CategoryKind.fromTxType(_type)));
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethodRow>[];
    final today = Dates.today();
    final isToday = Dates.sameDay(_date, today);
    final isYesterday = Dates.sameDay(_date, Dates.addDays(today, -1));

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_isEditing)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (!widget.confirmMode)
                    Center(
                      child: SegmentedButton<TxType>(
                        segments: const [
                          ButtonSegment(value: TxType.expense, label: Text('Gasto'), icon: Icon(Icons.remove)),
                          ButtonSegment(value: TxType.income, label: Text('Ingreso'), icon: Icon(Icons.add)),
                        ],
                        selected: {_type},
                        onSelectionChanged: (s) => setState(() {
                          _type = s.first;
                          _categoryId = null;
                          _categoryTouched = false;
                        }),
                      ),
                    ),
                  // Importe grande: tocarlo devuelve el teclado numérico.
                  GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        '$_amountDisplay €',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: _amount.isEmpty ? context.colors.outline : color,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                  ),
                  const FieldLabel('Categoría'),
                  categories.when(
                    loading: () => const LoadingBox(height: 80),
                    error: (e, _) => ErrorBox(e),
                    data: (list) {
                      // Con muchas categorías se ven las más usadas y el resto
                      // en un buscador ("Más").
                      const maxVisible = 10;
                      final collapsed = list.length > maxVisible + 1;
                      var visible = collapsed ? list.take(maxVisible).toList() : list;
                      if (collapsed && _categoryId != null && !visible.any((c) => c.id == _categoryId)) {
                        visible = [...list.where((c) => c.id == _categoryId), ...visible.take(maxVisible - 1)];
                      }
                      return GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 0.92,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        children: [
                          for (final c in visible)
                            _CategoryChoice(
                              category: c,
                              selected: c.id == _categoryId,
                              onTap: () => setState(() {
                                _categoryId = c.id;
                                _categoryTouched = true;
                              }),
                            ),
                          if (collapsed) _MoreCategoriesButton(count: list.length, onTap: () => _pickFromAll(list)),
                          _NewCategoryButton(onTap: _newCategory),
                        ],
                      );
                    },
                  ),
                  const FieldLabel('Descripción'),
                  TextField(
                    controller: _desc,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _onDescriptionChanged,
                    decoration: InputDecoration(
                      hintText: _type == TxType.expense ? 'Ej.: Mercadona' : 'Ej.: Nómina de noviembre',
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final s in _suggestions)
                            ActionChip(label: Text(s), onPressed: () => _applySuggestion(s)),
                        ],
                      ),
                    ),
                  const FieldLabel('Fecha'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Hoy'),
                        selected: isToday,
                        onSelected: (_) => setState(() => _date = today),
                      ),
                      ChoiceChip(
                        label: const Text('Ayer'),
                        selected: isYesterday,
                        onSelected: (_) => setState(() => _date = Dates.addDays(today, -1)),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Text(isToday || isYesterday ? 'Otra fecha' : Dates.dayMonthYearShort(_date)),
                        selected: !isToday && !isYesterday,
                        onSelected: (_) => _pickDate(),
                      ),
                      InputChip(
                        avatar: const Icon(Icons.schedule, size: 18),
                        label: Text(_timeText ?? 'Añadir hora'),
                        onPressed: _pickTime,
                        onDeleted: _time == null ? null : () => setState(() => _time = null),
                      ),
                    ],
                  ),
                  FieldLabel(_type == TxType.expense ? 'Método de pago' : 'Método de recepción'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in methods)
                        if (!m.isArchived || m.id == _paymentMethodId)
                          ChoiceChip(
                            label: Text('${m.emoji} ${m.name}'),
                            selected: m.id == _paymentMethodId,
                            onSelected: (s) => setState(() => _paymentMethodId = s ? m.id : null),
                          ),
                    ],
                  ),
                  const FieldLabel('Notas'),
                  TextField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Opcional'),
                  ),
                  if (!_isEditing && !widget.confirmMode) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _repeat,
                      onChanged: (v) => setState(() => _repeat = v),
                      title: const Text('Repetir'),
                      subtitle: Text(_repeat
                          ? 'Se creará automáticamente ${_repeatFrequency.describe(1).toLowerCase()}'
                          : 'Para alquiler, suscripciones, nómina...'),
                    ),
                    if (_repeat)
                      SegmentedButton<Frequency>(
                        segments: const [
                          ButtonSegment(value: Frequency.week, label: Text('Semanal')),
                          ButtonSegment(value: Frequency.month, label: Text('Mensual')),
                          ButtonSegment(value: Frequency.year, label: Text('Anual')),
                        ],
                        selected: {_repeatFrequency},
                        onSelectionChanged: (s) => setState(() => _repeatFrequency = s.first),
                      ),
                  ],
                ],
              ),
            ),
            if (!keyboardOpen) AmountKeypad(onKey: _onKey),
            Container(
              color: context.cardColor,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _saving ? null : _save,
                child: Text(widget.confirmMode ? 'Confirmar' : 'Guardar', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({required this.category, required this.selected, required this.onTap});
  final CategoryRow category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Color(category.color);
    return Material(
      color: selected ? c.withValues(alpha: 0.22) : context.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? c : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(category.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                category.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCategoriesButton extends StatelessWidget {
  const _MoreCategoriesButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: context.colors.onSecondaryContainer),
            const SizedBox(height: 4),
            Text('Más ($count)', style: TextStyle(fontSize: 11, color: context.colors.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }
}

class _NewCategoryButton extends StatelessWidget {
  const _NewCategoryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: context.colors.primary),
            const SizedBox(height: 4),
            const Text('Nueva', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
