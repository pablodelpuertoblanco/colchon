import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../dates.dart';
import '../money.dart';

/// Tarjeta de sección con título opcional y acción a la derecha.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(title!, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Importe con color y signo según sea gasto o ingreso.
class AmountText extends StatelessWidget {
  const AmountText(
    this.cents, {
    super.key,
    this.type,
    this.style,
    this.signed = true,
    this.colored = true,
  });

  final int cents;
  final TxType? type;
  final TextStyle? style;
  final bool signed;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? context.text.bodyLarge)!.copyWith(fontFeatures: tabularFigures);
    Color? color;
    String text;
    if (type == null) {
      text = Money.format(cents);
      if (colored && cents != 0) color = cents > 0 ? AppColors.income : AppColors.expense;
      if (signed && cents != 0) text = Money.formatSigned(cents, positive: cents > 0);
    } else {
      final income = type == TxType.income;
      text = signed ? Money.formatSigned(cents, positive: income) : Money.format(cents);
      if (colored) color = income ? AppColors.income : AppColors.expense;
    }
    return Text(text, style: base.copyWith(color: color, fontWeight: base.fontWeight ?? FontWeight.w600));
  }
}

/// Círculo con el emoji de la categoría sobre su color suavizado.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.emoji, required this.color, this.size = 40});
  final String emoji;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(color).withValues(alpha: context.isDark ? 0.28 : 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// Mensaje para listas vacías.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, this.message, this.action});
  final String emoji;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: context.colors.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Indicador de carga y de error para valores asíncronos.
class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.error, {super.key});
  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Algo ha fallado: $error', style: TextStyle(color: context.colors.error)),
      );
}

/// Selector "‹ Noviembre 2026 ›", con las fechas debajo si hace falta.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.onTapLabel,
    this.subtitle,
  });
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTapLabel;

  /// Texto pequeño bajo la etiqueta (p. ej. "24 oct 2026 – 23 nov 2026").
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Anterior'),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTapLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      textAlign: TextAlign.center,
                      style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Siguiente'),
      ],
    );
  }
}

/// Pequeña etiqueta de estado ("Pendiente", "Recurrente"...).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Diálogo de confirmación. Devuelve true si se acepta.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Aceptar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Diálogo para elegir un mes concreto (año con flechas + 12 meses).
Future<DateTime?> pickMonth(BuildContext context, {required DateTime initial}) {
  var year = initial.year;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Row(
          children: [
            IconButton(onPressed: () => setState(() => year--), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('$year', textAlign: TextAlign.center)),
            IconButton(onPressed: () => setState(() => year++), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            childAspectRatio: 2,
            children: [
              for (var m = 1; m <= 12; m++)
                TextButton(
                  style: m == initial.month && year == initial.year
                      ? TextButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.primaryContainer)
                      : null,
                  onPressed: () => Navigator.pop(ctx, DateTime(year, m, 1)),
                  child: Text(Dates.capitalize(Dates.monthShort[m - 1])),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
