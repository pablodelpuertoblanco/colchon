import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../domain/models.dart';

Future<void> openRecurringForm(BuildContext context, {String? ruleId}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RecurringFormScreen(ruleId: ruleId),
  ));
}

/// Alta y edición de una regla recurrente.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.ruleId});
  final String? ruleId;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  bool _loading = true;
  TxType _type = TxType.expense;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _notes = TextEditingController();
  final _everyN = TextEditingController(text: '1');
  String? _categoryId;
  String? _paymentMethodId;
  Frequency _frequency = Frequency.month;
  DateTime _start = Dates.today();
  DateTime? _end;
  RecurringMode _mode = RecurringMode.auto;

  bool get _isEditing => widget.ruleId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.ruleId != null) {
      final r = await ref.read(recurringRepoProvider).getById(widget.ruleId!);
      if (r != null) {
        _type = r.type;
        _amount.text = centsToInput(r.amountCents);
        _desc.text = r.description;
        _notes.text = r.notes ?? '';
        _everyN.text = '${r.everyN}';
        _categoryId = r.categoryId;
        _paymentMethodId = r.paymentMethodId;
        _frequency = r.frequency;
        _start = Dates.parseKey(r.startDate);
        _end = r.endDate == null ? null : Dates.parseKey(r.endDate!);
        _mode = r.mode;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _notes.dispose();
    _everyN.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _start = Dates.dateOnly(d));
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
        context: context, initialDate: _end ?? Dates.addMonthsClamped(_start, 12), firstDate: _start, lastDate: DateTime(2100));
    if (d != null) setState(() => _end = Dates.dateOnly(d));
  }

  Future<void> _save() async {
    final cents = Money.parse(_amount.text);
    final everyN = int.tryParse(_everyN.text) ?? 0;
    String? error;
    if (cents == null || cents <= 0) {
      error = 'Introduce un importe válido';
    } else if (_categoryId == null) {
      error = 'Elige una categoría';
    } else if (everyN < 1) {
      error = 'La frecuencia debe ser 1 o más';
    } else if (_end != null && _end!.isBefore(_start)) {
      error = 'La fecha de fin es anterior al inicio';
    }
    if (error != null) {
      showSnack(context, error);
      return;
    }

    final draft = RuleDraft(
      type: _type,
      amountCents: cents!,
      description: _desc.text,
      categoryId: _categoryId!,
      paymentMethodId: _paymentMethodId,
      frequency: _frequency,
      everyN: everyN,
      startDate: _start,
      endDate: _end,
      mode: _mode,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final repo = ref.read(recurringRepoProvider);
    if (_isEditing) {
      await repo.update(widget.ruleId!, draft);
    } else {
      await repo.create(draft);
    }
    final created = await repo.generateDue();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(created > 0 ? 'Guardado. Se han creado $created movimientos hasta hoy.' : 'Guardado'),
    ));
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar esta regla?',
      message: 'Los movimientos ya creados se conservan en el historial.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(recurringRepoProvider).softDelete(widget.ruleId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider(CategoryKind.fromTxType(_type))).value ?? const <CategoryRow>[];
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethodRow>[];
    final isPast = _start.isBefore(Dates.today());

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar recurrente' : 'Nuevo recurrente'),
        actions: [
          if (_isEditing) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
        ],
      ),
      body: _loading
          ? const LoadingBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Center(
                  child: SegmentedButton<TxType>(
                    segments: const [
                      ButtonSegment(value: TxType.expense, label: Text('Gasto')),
                      ButtonSegment(value: TxType.income, label: Text('Ingreso')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                    }),
                  ),
                ),
                const FieldLabel('Importe'),
                MoneyField(
                  controller: _amount,
                  helper: _mode == RecurringMode.confirm ? 'Importe estimado; lo confirmarás cada vez' : null,
                ),
                const FieldLabel('Descripción'),
                TextField(
                  controller: _desc,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Ej.: Alquiler, Netflix, Nómina'),
                ),
                const FieldLabel('Categoría'),
                DropdownButtonFormField<String>(
                  key: ValueKey('cat-$_type-${categories.length}'),
                  initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  hint: const Text('Elige una categoría'),
                  items: [
                    for (final c in categories.where((c) => !c.isArchived || c.id == _categoryId))
                      DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}')),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const FieldLabel('Método de pago'),
                DropdownButtonFormField<String?>(
                  key: ValueKey('pm-${methods.length}'),
                  initialValue: methods.any((m) => m.id == _paymentMethodId) ? _paymentMethodId : null,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sin indicar')),
                    for (final m in methods) DropdownMenuItem<String?>(value: m.id, child: Text('${m.emoji} ${m.name}')),
                  ],
                  onChanged: (v) => setState(() => _paymentMethodId = v),
                ),
                const FieldLabel('Se repite'),
                Row(
                  children: [
                    const Text('Cada '),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _everyN,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<Frequency>(
                        initialValue: _frequency,
                        items: [
                          for (final f in Frequency.values)
                            DropdownMenuItem(value: f, child: Text(f.unitLabel(int.tryParse(_everyN.text) ?? 1))),
                        ],
                        onChanged: (v) => setState(() => _frequency = v ?? _frequency),
                      ),
                    ),
                  ],
                ),
                const FieldLabel('Fechas'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Primer cobro'),
                  subtitle: Text(isPast
                      ? '${Dates.dayMonthYearShort(_start)} · se crearán los movimientos desde esa fecha'
                      : Dates.dayMonthYearShort(_start)),
                  onTap: _pickStart,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.stop_circle_outlined),
                  title: const Text('Fin (opcional)'),
                  subtitle: Text(_end == null ? 'Sin fecha de fin' : Dates.dayMonthYearShort(_end!)),
                  onTap: _pickEnd,
                  trailing: _end == null
                      ? null
                      : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _end = null)),
                ),
                const FieldLabel('Importe de cada cargo'),
                SegmentedButton<RecurringMode>(
                  segments: const [
                    ButtonSegment(value: RecurringMode.auto, label: Text('Fijo')),
                    ButtonSegment(value: RecurringMode.confirm, label: Text('Variable')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _mode == RecurringMode.auto
                        ? 'Se registra solo con este importe (alquiler, cuotas, suscripciones).'
                        : 'Se crea como pendiente y lo confirmas con el importe real (luz, agua, gas).',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                const FieldLabel('Notas'),
                TextField(controller: _notes, maxLines: 3, minLines: 1),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  child: const Text('Guardar'),
                ),
              ],
            ),
    );
  }
}
