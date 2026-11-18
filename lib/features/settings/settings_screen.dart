import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/repositories/settings_repository.dart';
import '../budgets/budgets_screen.dart';
import '../categories/categories_screen.dart';
import '../forecast/forecast_screen.dart';
import '../health/health_screen.dart';
import '../import/import_plan_screen.dart';
import '../net_worth/net_worth_screen.dart';
import '../plan/plan_line_sheet.dart';
import '../plan/plan_screen.dart';
import '../recurring/recurring_screen.dart';

/// Ajustes y gestión: presupuestos, recurrentes, categorías, datos.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _chooseTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider);
    final options = {
      ThemeMode.system: ('system', 'Según el sistema'),
      ThemeMode.light: ('light', 'Claro'),
      ThemeMode.dark: ('dark', 'Oscuro'),
    };
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Apariencia'),
        children: [
          for (final e in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.value.$1),
              child: Row(
                children: [
                  Expanded(child: Text(e.value.$2)),
                  if (e.key == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await ref.read(settingsRepoProvider).set(SettingKeys.themeMode, picked);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(backupServiceProvider).exportCsv();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Movimientos - Colchón',
        text: 'Movimientos exportados (CSV, se abre con Excel)',
      ));
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se ha podido exportar: $e');
    }
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(backupServiceProvider).createBackup();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Copia de seguridad - Colchón',
        text: 'Guarda este archivo en Drive, iCloud o envíatelo por correo.',
      ));
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se ha podido crear la copia: $e');
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: '¿Restaurar una copia?',
      message: 'Se sustituirán TODOS los datos actuales por los de la copia. Esta acción no se puede deshacer.',
      confirmLabel: 'Elegir archivo',
      destructive: true,
    );
    if (!ok) return;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await ref.read(backupServiceProvider).restore(bytes);
      if (context.mounted) showSnack(context, 'Copia restaurada correctamente');
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se ha podido restaurar: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = ref.watch(initialBalanceProvider);
    final theme = ref.watch(themeModeProvider);
    final cycle = ref.watch(monthCycleProvider);
    final minBalance = ref.watch(minBalanceProvider);
    final targets = ref.watch(ruleTargetsProvider);
    final themeLabel = switch (theme) {
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Oscuro',
      _ => 'Según el sistema',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Group(title: 'Plan y patrimonio', children: [
            _Tile(
              icon: Icons.event_note_outlined,
              title: 'Plan anual',
              subtitle: 'Previsto frente a real, mes a mes',
              onTap: () => openPlan(context),
            ),
            _Tile(
              icon: Icons.account_balance_outlined,
              title: 'Patrimonio',
              subtitle: 'Lo que tienes y lo que debes',
              onTap: () => openNetWorth(context),
            ),
            _Tile(
              icon: Icons.show_chart,
              title: 'Previsión de saldo',
              subtitle: 'Cómo evolucionará tu dinero día a día',
              onTap: () => openForecast(context),
            ),
            _Tile(
              icon: Icons.health_and_safety_outlined,
              title: 'Salud financiera',
              subtitle: 'Tu gasto frente a porcentajes orientativos',
              onTap: () => openHealth(context),
            ),
            _Tile(
              icon: Icons.today_outlined,
              title: 'Inicio del mes',
              subtitle: cycle.isCalendar ? 'Día 1 (mes natural)' : 'Día ${cycle.startDay} (del ${cycle.startDay} al ${cycle.startDay - 1})',
              onTap: () => showMonthStartDayDialog(context, ref),
            ),
            _Tile(
              icon: Icons.pie_chart_outline,
              title: 'Objetivos del plan',
              subtitle: '${targets.needs} % necesarios · ${targets.wants} % prescindibles y ocio · ${targets.savings} % ahorro',
              onTap: () => showRuleTargetsDialog(context, ref),
            ),
            _Tile(
              icon: Icons.file_download_outlined,
              title: 'Importar plan',
              subtitle: 'Desde un archivo Excel (.xlsx)',
              onTap: () => openImportPlan(context),
            ),
          ]),
          const SizedBox(height: 12),
          _Group(title: 'Organización', children: [
            _Tile(icon: Icons.track_changes, title: 'Presupuestos', onTap: () => _push(context, const BudgetsScreen())),
            _Tile(icon: Icons.repeat_rounded, title: 'Gastos e ingresos recurrentes', onTap: () => _push(context, const RecurringScreen())),
            _Tile(icon: Icons.category_outlined, title: 'Categorías', onTap: () => _push(context, const CategoriesScreen())),
            _Tile(icon: Icons.payments_outlined, title: 'Métodos de pago', onTap: () => _push(context, const PaymentMethodsScreen())),
          ]),
          const SizedBox(height: 12),
          _Group(title: 'Cuenta', children: [
            _Tile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Saldo inicial',
              subtitle: initial == null
                  ? 'Sin configurar'
                  : '${Money.format(initial.cents)} el ${Dates.dayMonthYearShort(initial.date)}',
              onTap: () => showInitialBalanceDialog(context, ref),
            ),
            _Tile(
              icon: Icons.shield_outlined,
              title: 'Saldo mínimo',
              subtitle: minBalance == null ? 'Sin aviso' : 'Avisar si baja de ${Money.formatShort(minBalance)}',
              onTap: () => showMinBalanceDialog(context, ref),
            ),
            _Tile(icon: Icons.palette_outlined, title: 'Apariencia', subtitle: themeLabel, onTap: () => _chooseTheme(context, ref)),
          ]),
          const SizedBox(height: 12),
          _Group(title: 'Tus datos', children: [
            _Tile(
              icon: Icons.table_view_outlined,
              title: 'Exportar movimientos',
              subtitle: 'Archivo CSV que se abre con Excel',
              onTap: () => _export(context, ref),
            ),
            _Tile(
              icon: Icons.backup_outlined,
              title: 'Crear copia de seguridad',
              subtitle: 'Todos los datos en un archivo',
              onTap: () => _backup(context, ref),
            ),
            _Tile(
              icon: Icons.settings_backup_restore,
              title: 'Restaurar copia de seguridad',
              onTap: () => _restore(context, ref),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(title, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
          SectionCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
        ],
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

/// Diálogo para fijar el saldo inicial (lo que tienes hoy en tus cuentas).
Future<void> showInitialBalanceDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(initialBalanceProvider);
  final controller = TextEditingController(text: current == null ? '' : centsToInput(current.cents.abs()));
  var date = current?.date ?? Dates.today();
  var negative = (current?.cents ?? 0) < 0;

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Saldo inicial'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Suma de lo que tienes en tus cuentas y en efectivo en una fecha. '
                'A partir de ahí, la app calcula el dinero disponible.'),
            const SizedBox(height: 16),
            MoneyField(controller: controller, label: 'Saldo', autofocus: true),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: negative,
              onChanged: (v) => setState(() => negative = v ?? false),
              title: const Text('Es negativo (descubierto)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('A fecha de ${Dates.dayMonthYearShort(date)}'),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => date = Dates.dateOnly(d));
              },
            ),
          ],
        ),
        actions: [
          if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Quitar')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar')),
        ],
      ),
    ),
  );

  final repo = ref.read(settingsRepoProvider);
  if (result == 'remove') {
    await repo.setInitialBalance(null, null);
  } else if (result == 'save') {
    final cents = Money.parse(controller.text);
    if (cents == null) {
      if (context.mounted) showSnack(context, 'Importe no válido');
      return;
    }
    await repo.setInitialBalance(negative ? -cents : cents, date);
  }
}

/// Elegir el día en que empieza cada mes (el de cobro).
Future<void> showMonthStartDayDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(monthCycleProvider).startDay;
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Qué día empieza tu mes?'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Si cobras el día 24, elige 24: "noviembre" irá del 24 de octubre al 23 de noviembre '
                'en el inicio, las estadísticas, los presupuestos y el plan.'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var d = 1; d <= 28; d++)
                  d == current
                      ? FilledButton(
                          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => Navigator.pop(ctx, d),
                          child: Text('$d'),
                        )
                      : TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => Navigator.pop(ctx, d),
                          child: Text('$d'),
                        ),
              ],
            ),
            const SizedBox(height: 8),
            Text('1 = mes natural', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
    ),
  );
  if (picked != null) await ref.read(settingsRepoProvider).set(SettingKeys.monthStartDay, '$picked');
}

/// Saldo mínimo de seguridad: avisa en el inicio si el dinero disponible
/// baja de esa cantidad (o va a bajar con los cargos previstos del mes).
Future<void> showMinBalanceDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(minBalanceProvider);
  final controller = TextEditingController(text: current == null ? '' : centsToInput(current));
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Saldo mínimo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('El dinero del que no quieres bajar. Te avisaré en el inicio si el disponible baja de aquí '
              'o si va a bajar con los cargos previstos del mes. Necesita el saldo inicial configurado.'),
          const SizedBox(height: 16),
          MoneyField(controller: controller, label: 'Mínimo', autofocus: true),
        ],
      ),
      actions: [
        if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Quitar')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar')),
      ],
    ),
  );
  final repo = ref.read(settingsRepoProvider);
  if (result == 'remove') {
    await repo.set(SettingKeys.minBalanceCents, null);
  } else if (result == 'save') {
    final cents = Money.parse(controller.text);
    if (cents == null || cents < 0) {
      if (context.mounted) showSnack(context, 'Importe no válido');
      return;
    }
    await repo.set(SettingKeys.minBalanceCents, '$cents');
  }
}
