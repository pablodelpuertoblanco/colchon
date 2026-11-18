import 'dart:typed_data';

import '../core/text.dart';
import '../domain/models.dart';
import 'plan_import.dart';
import 'xlsx_reader.dart';

// ---------------------------------------------------------------------------
// Lee un plan anual desde un Excel (.xlsx).
//
// Formato (el de la plantilla, assets/plantilla/plantilla_plan.xlsx):
//
// · Hoja "Plan": una fila de cabecera con los 12 meses (Ene ... Dic, o los
//   nombres completos) y una fila por categoría. Columnas opcionales, en
//   cualquier orden: Tipo (Ingreso / Gasto), Bloque (Necesario fijo,
//   Necesario variable, Prescindible, Ocio, Ahorro), Grupo, Categoría,
//   Emoji y Ahorro ("Sí" si cuenta como ahorro: plan de pensiones,
//   hipoteca...).
//   Sin columnas Tipo y Bloque también vale: una fila con solo un título como
//   "INGRESOS", "NECESARIOS FIJOS" o "PRESCINDIBLES" marca las filas que
//   vienen debajo, igual que ese título en una columna a la izquierda del
//   nombre (celda combinada). Un título que no se reconoce ("VIVIENDA",
//   "MASCOTAS"...) después de los ingresos significa que empiezan los gastos.
//   Las filas de totales se ignoran.
// · Hoja "Ajustes" (opcional): Año, Día de inicio de mes, Saldo mínimo y
//   los objetivos de la regla 50/30/20 (Necesarios, Prescindibles, Ahorro).
// · Hoja "Patrimonio" (opcional): una fila por bien o deuda con su valor de
//   cada mes, como en la hoja Plan. Columnas: Nombre, Tipo (Bien / Deuda),
//   Emoji.
// ---------------------------------------------------------------------------

class PlanExcel {
  PlanExcel._();

  /// Lee el libro. [fallbackYear] se usa si el Excel no indica el año.
  /// Lanza [FormatException] con un mensaje para el usuario.
  static PlanImportFile parse(Uint8List bytes, {required int fallbackYear}) {
    final sheets = XlsxReader.read(bytes);

    // La hoja del plan: la que se llame "Plan" o "Presupuesto" o, si no,
    // la primera que tenga la fila de los meses.
    XlsxSheet? planSheet;
    _MonthHeader? header;
    final candidates = [
      ...sheets.where((s) => _isNamed(s, ['plan', 'presupuesto'])),
      ...sheets.where((s) => !_isNamed(s, ['patrimonio', 'bienes', 'ajustes', 'configuracion'])),
    ];
    for (final s in candidates) {
      final h = _MonthHeader.find(s);
      if (h != null) {
        planSheet = s;
        header = h;
        break;
      }
    }
    if (planSheet == null || header == null) {
      throw const FormatException(
        'No encuentro la fila de los meses. El Excel necesita una fila con Ene, Feb, Mar... '
        'hasta Dic y debajo una fila por categoría. Puedes partir de la plantilla.',
      );
    }

    final settings = _settings(_pick(sheets, ['ajustes', 'configuracion']));
    final year = settings.year ?? _yearIn(planSheet, header.row) ?? fallbackYear;
    final categories = _categories(planSheet, header);
    if (categories.where((c) => c.plan != null).isEmpty) {
      throw FormatException(
        'En la hoja "${planSheet.name}" no hay ninguna categoría con importes. '
        'Pon una fila por categoría con lo previsto de cada mes.',
      );
    }

    final assetsSheet = _pick(sheets, ['patrimonio', 'bienes']);
    return PlanImportFile(
      title: 'Plan $year · ${planSheet.name}',
      year: year,
      categories: categories,
      assets: assetsSheet == null ? const [] : _assets(assetsSheet, year),
      hasGroups: header.groupCol != null,
      monthStartDay: settings.monthStartDay,
      minBalanceCents: settings.minBalanceCents,
      targets: settings.targets,
    );
  }

  // --- Plan ----------------------------------------------------------------

  static List<PlanImportCategory> _categories(XlsxSheet sheet, _MonthHeader h) {
    final byKey = <String, PlanImportCategory>{};
    var sectionKind = CategoryKind.expense;
    BudgetGroup? sectionGroup;

    for (var r = h.row + 1; r < sheet.rows.length; r++) {
      final texts = _labels(sheet, r, h);
      if (texts.isEmpty) continue;
      final name = texts.last;
      final amounts = [for (final col in h.monthCols) _amount(sheet.cell(r, col))];
      final hasAmounts = amounts.any((a) => a != null);

      // Título de bloque en una columna a la izquierda del nombre (p. ej. una
      // celda combinada "GASTOS FIJOS" junto a sus filas).
      for (final t in texts.take(texts.length - 1)) {
        final s = _section(t);
        if (s != null) {
          sectionKind = s.kind;
          sectionGroup = s.group;
        }
      }

      // Fila de título de bloque ("INGRESOS", "NECESARIOS FIJOS"...): marca lo
      // que viene debajo. Con importes (un subtotal) solo si está en mayúsculas
      // y es un título claro: "OCIO 50 50..." es una categoría, no un bloque.
      final section = hasAmounts ? (_isUpperCase(name) ? _section(name, strict: true) : null) : _section(name);
      if (section != null) {
        sectionKind = section.kind;
        sectionGroup = section.group;
        continue;
      }
      if (_isTotal(name)) continue;
      if (!hasAmounts && h.kindCol == null) {
        // Un título que no conozco ("VIVIENDA", "MASCOTAS"...): si va después de
        // los ingresos, lo que viene ya son gastos.
        if (normalizeForSearch(name).contains('ingreso')) {
          sectionKind = CategoryKind.income;
          sectionGroup = null;
        } else if (sectionKind == CategoryKind.income) {
          sectionKind = CategoryKind.expense;
          sectionGroup = null;
        }
        continue;
      }

      final kind = _kind(sheet.cell(r, h.kindCol), name) ?? sectionKind;
      final blockText = _string(sheet.cell(r, h.blockCol));
      final group = kind == CategoryKind.income
          ? null
          : blockText == null
              ? (h.blockCol == null ? sectionGroup : null)
              : _block(blockText, name);

      String? parentKey;
      final groupName = _string(sheet.cell(r, h.groupCol));
      if (groupName != null) {
        final groupKey = 'grupo:${kind.name}:${normalizeForSearch(groupName)}';
        parentKey = groupKey;
        byKey.putIfAbsent(groupKey, () => PlanImportCategory(key: groupKey, kind: kind, name: _clip(groupName)));
      }

      final plan = hasAmounts ? [for (final a in amounts) a ?? 0] : null;
      final key = '${kind.name}:${normalizeForSearch(name)}';
      final previous = byKey[key];
      if (previous != null) {
        // La misma categoría dos veces: se suman sus importes.
        final merged = previous.plan == null
            ? plan
            : plan == null
                ? previous.plan
                : [for (var i = 0; i < 12; i++) previous.plan![i] + plan[i]];
        byKey[key] = PlanImportCategory(
          key: key,
          kind: kind,
          name: previous.name,
          emoji: previous.emoji,
          parentKey: previous.parentKey,
          group: previous.group,
          isSavings: previous.isSavings,
          plan: merged,
        );
        continue;
      }
      byKey[key] = PlanImportCategory(
        key: key,
        kind: kind,
        name: _clip(name),
        emoji: _emoji(sheet.cell(r, h.emojiCol)),
        parentKey: parentKey,
        group: group,
        isSavings: h.savingsCol == null ? null : _yes(sheet.cell(r, h.savingsCol)),
        plan: plan,
      );
    }
    return byKey.values.toList();
  }

  /// Textos de la fila a la izquierda de los meses. El último es el nombre
  /// (o la columna Categoría, si la hay); los anteriores pueden ser títulos
  /// de bloque.
  static List<String> _labels(XlsxSheet sheet, int r, _MonthHeader h) {
    final end = h.nameCol ?? h.firstMonthCol;
    final texts = <String>[];
    for (var c = 0; c < end; c++) {
      if (h.roleCols.contains(c)) continue;
      final s = _string(sheet.cell(r, c));
      if (s != null) texts.add(s);
    }
    if (h.nameCol != null) {
      // Sin nombre, un texto a su izquierda puede ser un título de bloque suelto.
      final name = _string(sheet.cell(r, h.nameCol));
      if (name != null) texts.add(name);
    }
    return texts;
  }

  /// Título de bloque. Con [strict] solo los títulos inequívocos ("INGRESOS",
  /// "GASTOS FIJOS"...), no los que también pueden ser una categoría ("Ocio").
  static ({CategoryKind kind, BudgetGroup? group})? _section(String label, {bool strict = false}) {
    final n = normalizeForSearch(label);
    if (n.length > 40) return null;
    if (n == 'ingresos' || n.startsWith('ingresos ')) return (kind: CategoryKind.income, group: null);
    final group = _groupIn(n);
    if (strict) {
      final clear = RegExp(r'^(gastos )?(necesarios )?(fijos|variables|prescindibles)$|^gastos$|^ahorro e inversion$');
      return clear.hasMatch(n) ? (kind: CategoryKind.expense, group: group) : null;
    }
    if (n.startsWith('gastos') || n.startsWith('necesarios')) return (kind: CategoryKind.expense, group: group);
    if (const {'fijos', 'variables', 'prescindibles', 'ocio', 'ahorro', 'inversion'}.contains(n) ||
        n.startsWith('ahorro e inversion')) {
      return (kind: CategoryKind.expense, group: group);
    }
    return null;
  }

  static BudgetGroup? _groupIn(String n) {
    if (n.contains('fijo')) return BudgetGroup.fixed;
    if (n.contains('variable')) return BudgetGroup.variable;
    if (n.contains('prescindible')) return BudgetGroup.discretionary;
    if (n.contains('ocio')) return BudgetGroup.leisure;
    if (n.contains('ahorro') || n.contains('inversion')) return BudgetGroup.savings;
    return null;
  }

  static bool _isUpperCase(String s) => s.toUpperCase() == s && s.toLowerCase() != s;

  static bool _isTotal(String label) {
    final n = normalizeForSearch(label);
    return n.startsWith('total') ||
        n.startsWith('subtotal') ||
        n.startsWith('suma') ||
        n.startsWith('saldo') ||
        n.startsWith('diferencia') ||
        n.startsWith('resultado') ||
        n.startsWith('balance');
  }

  static CategoryKind? _kind(Object? cell, String name) {
    final s = _string(cell);
    if (s == null) return null;
    final n = normalizeForSearch(s);
    if (n.startsWith('ingreso')) return CategoryKind.income;
    if (n.startsWith('gasto')) return CategoryKind.expense;
    throw FormatException('Tipo "$s" no válido en "$name". Usa Ingreso o Gasto.');
  }

  static BudgetGroup _block(String text, String name) {
    final n = normalizeForSearch(text);
    if (n.contains('fijo')) return BudgetGroup.fixed;
    if (n.contains('variable')) return BudgetGroup.variable;
    if (n.contains('prescindible')) return BudgetGroup.discretionary;
    if (n.contains('ocio')) return BudgetGroup.leisure;
    if (n.contains('ahorro') || n.contains('inversion')) return BudgetGroup.savings;
    throw FormatException(
      'Bloque "$text" no válido en "$name". Usa: '
      '${BudgetGroup.values.map((g) => g.label).join(', ')}.',
    );
  }

  // --- Ajustes -------------------------------------------------------------

  static ({int? year, int? monthStartDay, int? minBalanceCents, RuleTargets? targets}) _settings(XlsxSheet? sheet) {
    if (sheet == null) return (year: null, monthStartDay: null, minBalanceCents: null, targets: null);
    int? year, startDay, minBalance, needs, wants, savings;
    for (var r = 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      // Etiqueta = primer texto de la fila; valor = primer número a su derecha.
      String? label;
      double? value;
      for (final cell in row) {
        if (label == null) {
          label = _string(cell);
          continue;
        }
        final v = _number(cell);
        if (v != null) {
          value = v;
          break;
        }
      }
      if (label == null || value == null) continue;
      final n = normalizeForSearch(label);
      final whole = value.round();
      if (n.startsWith('ano')) {
        if (whole >= 2000 && whole <= 2100) year = whole;
      } else if (n.contains('inicio')) {
        if (whole >= 1 && whole <= 28) startDay = whole;
      } else if (n.contains('saldo minimo')) {
        if (value >= 0) minBalance = (value * 100).round();
      } else if (n.startsWith('necesario')) {
        needs = _percent(value);
      } else if (n.startsWith('prescindible')) {
        wants = _percent(value);
      } else if (n.startsWith('ahorro')) {
        savings = _percent(value);
      }
    }
    RuleTargets? targets;
    if (needs != null && wants != null && savings != null && needs + wants + savings == 100) {
      targets = RuleTargets(needs: needs, wants: wants, savings: savings);
    }
    return (year: year, monthStartDay: startDay, minBalanceCents: minBalance, targets: targets);
  }

  /// 50 o 0,5 (celda con formato de porcentaje) -> 50.
  static int _percent(double v) => (v > 0 && v <= 1 ? v * 100 : v).round();

  /// Año escrito en el nombre de la hoja o encima de la cabecera ("Presupuesto 2027").
  static int? _yearIn(XlsxSheet sheet, int headerRow) {
    final texts = <String>[
      sheet.name,
      for (var r = 0; r <= headerRow; r++)
        for (final cell in sheet.rows[r])
          if (cell is String) cell,
    ];
    for (final t in texts) {
      final m = RegExp(r'\b(20\d\d)\b').firstMatch(t);
      if (m != null) return int.parse(m.group(1)!);
    }
    return null;
  }

  // --- Patrimonio ----------------------------------------------------------

  static List<PlanImportAsset> _assets(XlsxSheet sheet, int year) {
    final h = _MonthHeader.find(sheet);
    if (h == null) return const [];
    final assets = <PlanImportAsset>[];
    for (var r = h.row + 1; r < sheet.rows.length; r++) {
      final texts = _labels(sheet, r, h);
      if (texts.isEmpty || _isTotal(texts.last)) continue;
      final name = texts.last;
      final values = <({int year, int month, int cents})>[];
      for (var m = 0; m < 12; m++) {
        final cents = _amount(sheet.cell(r, h.monthCols[m]));
        if (cents != null) values.add((year: year, month: m + 1, cents: cents));
      }
      if (values.isEmpty) continue;
      final type = normalizeForSearch(_string(sheet.cell(r, h.kindCol)) ?? '');
      final liability = type.startsWith('deuda') || type.startsWith('prestamo') || type.startsWith('hipoteca');
      assets.add(PlanImportAsset(
        name: _clip(name),
        emoji: _emoji(sheet.cell(r, h.emojiCol)) ?? (liability ? '🏦' : '💰'),
        kind: liability ? AssetKind.liability : AssetKind.asset,
        values: values,
      ));
    }
    return assets;
  }

  // --- Celdas --------------------------------------------------------------

  static XlsxSheet? _pick(List<XlsxSheet> sheets, List<String> names) =>
      sheets.where((s) => _isNamed(s, names)).firstOrNull;

  static bool _isNamed(XlsxSheet s, List<String> names) {
    final n = normalizeForSearch(s.name);
    return names.any(n.startsWith);
  }

  static String? _string(Object? cell) {
    if (cell is! String) return null;
    final s = cell.trim();
    return s.isEmpty ? null : s;
  }

  static String _clip(String s) => s.length <= 60 ? s : s.substring(0, 60).trim();

  static String? _emoji(Object? cell) {
    final s = _string(cell);
    return s == null || s.runes.length > 8 ? null : s;
  }

  static bool _yes(Object? cell) {
    if (cell is bool) return cell;
    if (cell is double) return cell != 0;
    final n = normalizeForSearch(_string(cell) ?? '');
    return n == 'si' || n == 'x' || n == 'yes' || n == 'true' || n == 'verdadero';
  }

  /// Importe en céntimos (siempre positivo) o null si la celda no es un número.
  static int? _amount(Object? cell) {
    final v = _number(cell);
    return v == null ? null : (v.abs() * 100).round();
  }

  /// Número de una celda, también si está escrito como texto ("1.234,56 €").
  static double? _number(Object? cell) {
    if (cell is double) return cell.isFinite ? cell : null;
    if (cell is! String) return null;
    var s = cell.replaceAll(RegExp(r'[€\s %]'), '');
    if (s.isEmpty || s == '-') return null;
    final comma = s.lastIndexOf(',');
    final dot = s.lastIndexOf('.');
    if (comma > dot) {
      s = s.replaceAll('.', '').replaceAll(',', '.'); // 1.234,56
    } else if (dot > comma && comma >= 0) {
      s = s.replaceAll(',', ''); // 1,234.56
    }
    return double.tryParse(s);
  }
}

/// La fila de cabecera de una hoja: dónde está cada mes y cada columna.
class _MonthHeader {
  _MonthHeader({
    required this.row,
    required this.monthCols,
    this.nameCol,
    this.kindCol,
    this.blockCol,
    this.groupCol,
    this.emojiCol,
    this.savingsCol,
  });

  final int row;

  /// Columna de cada mes, de enero a diciembre.
  final List<int> monthCols;
  final int? nameCol;
  final int? kindCol;
  final int? blockCol;
  final int? groupCol;
  final int? emojiCol;
  final int? savingsCol;

  int get firstMonthCol => monthCols.reduce((a, b) => a < b ? a : b);

  Set<int> get roleCols => {
        for (final c in [kindCol, blockCol, groupCol, emojiCol, savingsCol])
          if (c != null) c,
      };

  static const _months = [
    ['ene', 'enero', 'jan', 'january'],
    ['feb', 'febrero', 'february'],
    ['mar', 'marzo', 'march'],
    ['abr', 'abril', 'apr', 'april'],
    ['may', 'mayo'],
    ['jun', 'junio', 'june'],
    ['jul', 'julio', 'july'],
    ['ago', 'agosto', 'aug', 'august'],
    ['sep', 'sept', 'septiembre', 'setiembre', 'september'],
    ['oct', 'octubre', 'october'],
    ['nov', 'noviembre', 'november'],
    ['dic', 'diciembre', 'dec', 'december'],
  ];

  static int? _month(String text) {
    final n = normalizeForSearch(text).replaceAll('.', '');
    for (var m = 0; m < 12; m++) {
      if (_months[m].contains(n)) return m;
    }
    return null;
  }

  /// Primera fila (de las 30 primeras) con los 12 meses.
  static _MonthHeader? find(XlsxSheet sheet) {
    final last = sheet.rows.length < 30 ? sheet.rows.length : 30;
    for (var r = 0; r < last; r++) {
      final cols = List<int?>.filled(12, null);
      int? name, kind, block, group, emoji, savings;
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell is! String) continue;
        final m = _month(cell);
        if (m != null) {
          cols[m] ??= c;
          continue;
        }
        final n = normalizeForSearch(cell);
        if (n.startsWith('categoria') || n.startsWith('concepto') || n.startsWith('partida') || n == 'nombre') {
          name ??= c;
        } else if (n == 'tipo') {
          kind ??= c;
        } else if (n == 'bloque') {
          block ??= c;
        } else if (n == 'grupo') {
          group ??= c;
        } else if (n == 'emoji' || n == 'icono') {
          emoji ??= c;
        } else if (n == 'ahorro' || n.startsWith('cuenta como ahorro')) {
          savings ??= c;
        }
      }
      if (cols.every((c) => c != null)) {
        return _MonthHeader(
          row: r,
          monthCols: cols.cast<int>(),
          nameCol: name,
          kindCol: kind,
          blockCol: block,
          groupCol: group,
          emojiCol: emoji,
          savingsCol: savings,
        );
      }
    }
    return null;
  }
}
