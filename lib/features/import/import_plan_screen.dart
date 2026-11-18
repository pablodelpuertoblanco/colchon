import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/plan_excel.dart';
import '../../data/plan_import.dart';
import '../../domain/models.dart';

/// Plantilla de Excel que se ofrece para rellenar (sin datos de nadie).
const planTemplateAsset = 'assets/plantilla/plantilla_plan.xlsx';

void openImportPlan(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImportPlanScreen()));
}

/// Importa un plan anual desde un Excel (categorías, previsto mes a mes,
/// patrimonio y ajustes).
class ImportPlanScreen extends ConsumerStatefulWidget {
  const ImportPlanScreen({super.key});

  @override
  ConsumerState<ImportPlanScreen> createState() => _ImportPlanScreenState();
}

class _ImportPlanScreenState extends ConsumerState<ImportPlanScreen> {
  PlanImportPreview? _preview;
  bool _busy = false;
  bool _applySettings = true;
  bool _archiveUnused = true;

  PlanImporter get _importer => PlanImporter(ref.read(databaseProvider));

  Future<void> _pickExcel() async {
    setState(() => _busy = true);
    try {
      // Solo Excel (.xlsx): ni JSON ni otros formatos.
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Elige un Excel (.xlsx)',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (picked == null) return;
      if ((picked.extension ?? '').toLowerCase() != 'xlsx') {
        if (mounted) showSnack(context, 'Solo se pueden importar archivos Excel (.xlsx)');
        return;
      }
      final bytes = await picked.readAsBytes();
      final file = PlanExcel.parse(bytes, fallbackYear: DateTime.now().year);
      final preview = await _importer.preview(file);
      if (mounted) setState(() => _preview = preview);
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'No se ha podido leer el Excel: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Comparte la plantilla para guardarla o abrirla en Excel / Google Sheets.
  Future<void> _shareTemplate() async {
    try {
      final data = await rootBundle.load(planTemplateAsset);
      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, 'plantilla_plan_colchon.xlsx'));
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Plantilla de plan - Colchón',
        text: 'Rellénala con lo que prevés cada mes e impórtala en Colchón (Ajustes → Importar plan).',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'No se ha podido compartir la plantilla: $e');
    }
  }

  Future<void> _import() async {
    final preview = _preview!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final r = await _importer.apply(preview.file, applySettings: _applySettings, archiveUnused: _archiveUnused);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Plan ${preview.file.year} importado: ${r.entries} importes previstos, '
          '${r.created} categorías nuevas${r.assets > 0 ? ', ${r.assets} bienes' : ''}',
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'No se ha podido importar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Importar plan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (p == null) ...[
            Text(
              'Importa un presupuesto anual desde un archivo Excel (.xlsx): una fila por categoría con lo previsto '
              'de cada mes. Opcionalmente, sus bloques (necesarios, prescindibles, ocio y ahorro), bienes y ajustes.',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SectionCard(
              onTap: _busy ? null : _pickExcel,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text('📊', style: TextStyle(fontSize: 30)),
                title: Text('Elegir archivo Excel (.xlsx)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Antes de importar verás un resumen'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              onTap: _busy ? null : _shareTemplate,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.table_view_outlined, size: 30),
                title: Text('Descargar la plantilla'),
                subtitle: Text('Un Excel de ejemplo, sin datos reales, con el formato que entiende la app'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
            if (_busy) const LoadingBox(),
          ] else
            ..._previewWidgets(p),
        ],
      ),
    );
  }

  List<Widget> _previewWidgets(PlanImportPreview p) {
    final f = p.file;
    final muted = TextStyle(color: context.colors.onSurfaceVariant);
    final incomes = [for (final c in f.categories) if (c.kind == CategoryKind.income && c.plan != null) c.name];
    final expenses = f.categories.where((c) => c.kind == CategoryKind.expense && c.plan != null).length;
    return [
      SectionCard(
        title: f.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Line('🗓️', 'Año ${f.year}: ${f.plannedCategories} partidas con importe previsto'),
            _Line(
              '💶',
              'Ingresos previstos: ${Money.format(f.plannedTotal(CategoryKind.income))}'
                  '${incomes.isEmpty ? '' : ' · ${_names(incomes)}'}',
            ),
            _Line('🧾', 'Gastos previstos: ${Money.format(f.plannedTotal(CategoryKind.expense))} · $expenses partidas'),
            _Line('🏷️', '${p.newCategories} categorías nuevas · ${p.existingCategories} que ya tenías se actualizan'),
            if (f.assets.isNotEmpty) _Line('🏦', '${f.assets.length} bienes para Patrimonio'),
          ],
        ),
      ),
      if (p.yearHasPlan) ...[
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: AppColors.warning.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Ya tienes plan en ${f.year}. Lo previsto de estas categorías se sustituirá por el del archivo; '
              'el resto no se toca.',
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (f.hasSettings)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _applySettings,
          onChanged: (v) => setState(() => _applySettings = v ?? true),
          title: const Text('Aplicar también los ajustes'),
          subtitle: Text(
            [
              if (f.monthStartDay != null && f.monthStartDay! > 1)
                'el mes empieza el día ${f.monthStartDay}'
              else if (f.monthStartDay == 1)
                'mes natural',
              if (f.minBalanceCents != null) 'saldo mínimo ${Money.formatShort(f.minBalanceCents!)}',
              if (f.targets != null) 'objetivos ${f.targets!.needs}/${f.targets!.wants}/${f.targets!.savings}',
            ].join(' · '),
          ),
        ),
      if (p.unusedDefaults > 0)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _archiveUnused,
          onChanged: (v) => setState(() => _archiveUnused = v ?? true),
          title: Text('Archivar ${p.unusedDefaults} categorías que no usas'),
          subtitle: const Text('Las de ejemplo sin movimientos. No se borran: se pueden recuperar en Categorías.'),
        ),
      const SizedBox(height: 8),
      Text(
        'Puedes importar el mismo Excel varias veces: no duplica nada. Si alguna partida queda en el sitio '
        'equivocado, en el plan tócala y usa "Mover".',
        style: muted,
      ),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy ? null : _import,
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Importar', style: TextStyle(fontSize: 16)),
      ),
      TextButton(onPressed: _busy ? null : () => setState(() => _preview = null), child: const Text('Elegir otro')),
    ];
  }
}

/// "Nómina, Alquiler y 3 más".
String _names(List<String> names) {
  const shown = 4;
  if (names.length <= shown) {
    return names.length == 1 ? names.first : '${names.take(names.length - 1).join(', ')} y ${names.last}';
  }
  return '${names.take(shown).join(', ')} y ${names.length - shown} más';
}

class _Line extends StatelessWidget {
  const _Line(this.emoji, this.text);
  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
