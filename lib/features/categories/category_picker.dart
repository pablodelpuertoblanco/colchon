import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/text.dart';
import '../../data/database.dart';

/// Hoja con buscador para elegir una categoría de una lista larga.
/// Agrupa las subcategorías bajo su grupo. Devuelve el id elegido.
///
/// [all] sirve para mostrar el nombre de los grupos aunque no se puedan
/// elegir; [selectable] son las que se pueden tocar.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required List<CategoryRow> selectable,
  required List<CategoryRow> all,
  String title = 'Elige categoría',
  String? selectedId,
  String Function(CategoryRow c)? trailingOf,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, controller) => _CategoryPicker(
        selectable: selectable,
        all: all,
        title: title,
        selectedId: selectedId,
        trailingOf: trailingOf,
        controller: controller,
      ),
    ),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.selectable,
    required this.all,
    required this.title,
    required this.selectedId,
    required this.trailingOf,
    required this.controller,
  });
  final List<CategoryRow> selectable;
  final List<CategoryRow> all;
  final String title;
  final String? selectedId;
  final String Function(CategoryRow c)? trailingOf;
  final ScrollController controller;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.all) c.id: c};
    final q = normalizeForSearch(_query);
    bool matches(CategoryRow c) {
      if (q.isEmpty) return true;
      final parent = c.parentId == null ? null : byId[c.parentId];
      return normalizeForSearch('${c.name} ${parent?.name ?? ''}').contains(q);
    }

    // Grupos en orden: primero las categorías sueltas y los grupos por su
    // orden; dentro de cada grupo, sus subcategorías.
    final visible = widget.selectable.where(matches).toList();
    final sections = <String?, List<CategoryRow>>{};
    for (final c in visible) {
      sections.putIfAbsent(c.parentId != null && byId.containsKey(c.parentId) ? c.parentId : null, () => []).add(c);
    }
    int orderOf(String? parentId) => parentId == null ? -1 : byId[parentId]!.sortOrder;
    final keys = sections.keys.toList()..sort((a, b) => orderOf(a).compareTo(orderOf(b)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: context.text.titleLarge),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text('Ninguna categoría coincide', style: TextStyle(color: context.colors.onSurfaceVariant)),
                )
              : ListView(
                  controller: widget.controller,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final key in keys) ...[
                      if (key != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '${byId[key]!.emoji} ${byId[key]!.name}',
                            style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ),
                      for (final c in sections[key]!)
                        ListTile(
                          leading: Text(c.emoji, style: const TextStyle(fontSize: 24)),
                          title: Text(c.name),
                          trailing: c.id == widget.selectedId
                              ? Icon(Icons.check, color: context.colors.primary)
                              : (widget.trailingOf == null
                                  ? null
                                  : Text(widget.trailingOf!(c),
                                      style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant))),
                          onTap: () => Navigator.pop(context, c.id),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
