import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../data/seed.dart';

/// Campo de importe con teclado numérico del sistema (para hojas y diálogos).
class MoneyField extends StatelessWidget {
  const MoneyField({super.key, required this.controller, this.label = 'Importe', this.autofocus = false, this.helper});
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: const TextStyle(fontFeatures: tabularFigures, fontSize: 18),
      decoration: InputDecoration(labelText: label, suffixText: '€', helperText: helper),
    );
  }
}

/// Convierte céntimos al texto que se edita: 1250 -> "12,50"; 1200 -> "12".
String centsToInput(int cents) {
  final euros = cents ~/ 100;
  final rest = cents % 100;
  return rest == 0 ? '$euros' : '$euros,${rest.toString().padLeft(2, '0')}';
}

/// Teclado numérico propio para registrar importes con un pulgar.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  static const backspace = '⌫';
  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', backspace];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.cardColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: [
          for (final k in _keys)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.selectionClick();
                onKey(k);
              },
              onLongPress: k == backspace ? () => onKey('clear') : null,
              child: Center(
                child: k == backspace
                    ? const Icon(Icons.backspace_outlined)
                    : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }
}

const _emojiChoices = [
  '🛒', '🍽️', '🏠', '💡', '💧', '🔥', '🌐', '🚗', '🏥', '🎬', '👕', '🐶', '📚', '🧾', '🛡️', '🧹', '🎁', '✈️', '📦',
  '💼', '💻', '💰', '💸', '🏦', '📄', '☕', '🍺', '🍕', '🍔', '🥗', '🍰', '🚌', '🚆', '⛽', '🅿️', '🚕', '🛵', '🚲',
  '💊', '🦷', '👓', '💇', '💄', '🧴', '👶', '🧸', '🎮', '🎵', '🎟️', '📺', '📱', '🖥️', '🏋️', '⚽', '🎾', '🏊',
  '🐱', '🌱', '🛠️', '🔧', '🛋️', '🧺', '🧼', '🔑', '🏖️', '🏔️', '🏨', '🎓', '✏️', '🎨', '📸', '🎂', '💍', '❤️',
  '⭐', '📈', '🪙', '💳', '💶', '🏧', '🧑‍💻', '👨‍👩‍👧', '🥦', '🥩', '🐟', '🥛', '🍞', '🥫', '🧽', '🥤', '🍫', '🍎',
  '🥚', '🧀', '🍝', '🍚', '🧃', '🍷', '🧻', '🪥', '🍼',
];

/// Hoja inferior para elegir un emoji (de la lista o escribiendo uno).
Future<String?> pickEmoji(BuildContext context, {String? current}) {
  final custom = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Elige un emoji', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: GridView.count(
              crossAxisCount: 8,
              children: [
                for (final e in _emojiChoices)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(ctx, e),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: e == current
                          ? BoxDecoration(
                              color: Theme.of(ctx).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: custom,
                  decoration: const InputDecoration(hintText: 'O escribe cualquier emoji'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final value = custom.text.trim();
                  if (value.isNotEmpty) Navigator.pop(ctx, value.characters.first);
                },
                child: const Text('Usar'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Fila de colores de la paleta de categorías.
class ColorChoice extends StatelessWidget {
  const ColorChoice({super.key, required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in categoryPalette)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == selected ? context.colors.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: c == selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
            ),
          ),
      ],
    );
  }
}

/// Etiqueta de sección en formularios.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text,
            style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
      );
}
