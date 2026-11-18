import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:xml/xml.dart';

// ---------------------------------------------------------------------------
// Lector mínimo de archivos .xlsx (Excel, LibreOffice, Google Sheets...).
//
// Un .xlsx es un ZIP con varios XML dentro. Aquí solo se leen los valores de
// las celdas (texto, números y verdadero/falso; de las fórmulas, su último
// resultado guardado), que es lo que necesita la importación del plan.
// El ZIP se descomprime con dart:io y el XML con el paquete xml, así que no
// hace falta ninguna librería de Excel.
// ---------------------------------------------------------------------------

/// Una hoja del libro.
class XlsxSheet {
  const XlsxSheet(this.name, this.rows);

  final String name;

  /// Filas en orden (0 = fila 1 del Excel). Cada fila tiene una celda por
  /// columna (0 = A) con un String, un double, un bool o null si está vacía.
  final List<List<Object?>> rows;

  /// Valor de una celda, o null si no existe (o si [col] es null).
  Object? cell(int row, int? col) {
    if (col == null || row < 0 || row >= rows.length) return null;
    final r = rows[row];
    return col >= 0 && col < r.length ? r[col] : null;
  }
}

class XlsxReader {
  XlsxReader._(this._files);

  final Map<String, Uint8List> _files;

  static const _notXlsx = FormatException(
    'El archivo no es un Excel .xlsx. Si es un .xls antiguo, un .ods o un .csv, ábrelo y guárdalo como .xlsx.',
  );

  /// Lee todas las hojas. Lanza [FormatException] si el archivo no es un .xlsx.
  static List<XlsxSheet> read(Uint8List bytes) => XlsxReader._(_unzip(bytes))._sheets();

  // --- ZIP -----------------------------------------------------------------

  static Map<String, Uint8List> _unzip(Uint8List bytes) {
    if (bytes.length < 22 || bytes[0] != 0x50 || bytes[1] != 0x4B) throw _notXlsx;
    final data = ByteData.sublistView(bytes);
    int u16(int at) => data.getUint16(at, Endian.little);
    int u32(int at) => data.getUint32(at, Endian.little);

    // El directorio central termina con la firma 0x06054b50, al final del
    // archivo (puede ir seguida de un comentario de hasta 64 KB).
    var end = -1;
    final lowest = bytes.length - 22 - 0xFFFF;
    for (var i = bytes.length - 22; i >= 0 && i >= lowest; i--) {
      if (u32(i) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw _notXlsx;

    final count = u16(end + 10);
    var pos = u32(end + 16);
    final files = <String, Uint8List>{};
    for (var n = 0; n < count; n++) {
      if (pos + 46 > bytes.length || u32(pos) != 0x02014b50) throw _notXlsx;
      final method = u16(pos + 10);
      final size = u32(pos + 20);
      final nameLength = u16(pos + 28);
      final local = u32(pos + 42);
      final name = utf8.decode(Uint8List.sublistView(bytes, pos + 46, pos + 46 + nameLength), allowMalformed: true);
      pos += 46 + nameLength + u16(pos + 30) + u16(pos + 32);

      if (!name.endsWith('.xml') && !name.endsWith('.rels')) continue; // imágenes, etc.
      if (local + 30 > bytes.length || u32(local) != 0x04034b50) throw _notXlsx;
      final start = local + 30 + u16(local + 26) + u16(local + 28);
      if (start + size > bytes.length) throw _notXlsx;
      final raw = Uint8List.sublistView(bytes, start, start + size);
      if (method == 0) {
        files[name] = raw;
      } else if (method == 8) {
        files[name] = Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      } else {
        throw _notXlsx;
      }
    }
    return files;
  }

  // --- XML -----------------------------------------------------------------

  XmlDocument? _xml(String path) {
    final bytes = _files[path];
    if (bytes == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } on XmlException {
      throw _notXlsx;
    }
  }

  /// Elementos por nombre local, con o sin prefijo de espacio de nombres.
  static Iterable<XmlElement> _all(XmlNode node, String local) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static Iterable<XmlElement> _children(XmlElement node, String local) =>
      node.children.whereType<XmlElement>().where((e) => e.name.local == local);

  static String _text(XmlElement node) => _all(node, 't').where((t) {
        final parent = t.parent;
        // <rPh> es la pronunciación fonética (japonés): no forma parte del texto.
        return !(parent is XmlElement && parent.name.local == 'rPh');
      }).map((t) => t.innerText).join();

  List<XlsxSheet> _sheets() {
    final workbook = _xml('xl/workbook.xml');
    if (workbook == null) throw _notXlsx;

    final targets = <String, String>{};
    final rels = _xml('xl/_rels/workbook.xml.rels');
    if (rels != null) {
      for (final r in _all(rels, 'Relationship')) {
        final id = r.getAttribute('Id');
        final target = r.getAttribute('Target');
        if (id != null && target != null) targets[id] = target;
      }
    }

    final shared = <String>[];
    final strings = _xml('xl/sharedStrings.xml');
    if (strings != null) {
      for (final si in _all(strings, 'si')) {
        shared.add(_text(si));
      }
    }

    final sheets = <XlsxSheet>[];
    var index = 0;
    for (final s in _all(workbook, 'sheet')) {
      index++;
      String? relId;
      for (final a in s.attributes) {
        if (a.name.local == 'id') relId = a.value;
      }
      var path = relId == null ? null : targets[relId];
      if (path == null) {
        path = 'xl/worksheets/sheet$index.xml';
      } else if (path.startsWith('/')) {
        path = path.substring(1);
      } else if (!path.startsWith('xl/')) {
        path = 'xl/$path';
      }
      final doc = _xml(path);
      if (doc == null) continue;
      sheets.add(XlsxSheet(s.getAttribute('name') ?? 'Hoja $index', _rows(doc, shared)));
    }
    if (sheets.isEmpty) throw _notXlsx;
    return sheets;
  }

  static List<List<Object?>> _rows(XmlDocument doc, List<String> shared) {
    final byIndex = <int, List<Object?>>{};
    var nextRow = 0;
    for (final row in _all(doc, 'row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      final rowIndex = r == null ? nextRow : r - 1;
      nextRow = rowIndex + 1;

      final cells = <Object?>[];
      var nextCol = 0;
      for (final c in _children(row, 'c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? nextCol : _column(ref);
        nextCol = col + 1;
        while (cells.length <= col) {
          cells.add(null);
        }
        cells[col] = _value(c, shared);
      }
      byIndex[rowIndex] = cells;
    }
    if (byIndex.isEmpty) return const [];
    final last = byIndex.keys.reduce((a, b) => a > b ? a : b);
    return [for (var i = 0; i <= last; i++) byIndex[i] ?? <Object?>[]];
  }

  /// "C7" -> 2, "AB12" -> 27.
  static int _column(String ref) {
    var n = 0;
    for (final unit in ref.toUpperCase().codeUnits) {
      if (unit < 65 || unit > 90) break;
      n = n * 26 + (unit - 64);
    }
    return n == 0 ? 0 : n - 1;
  }

  static Object? _value(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') {
      final inline = _children(c, 'is').firstOrNull;
      return inline == null ? null : _text(inline);
    }
    final v = _children(c, 'v').firstOrNull?.innerText;
    if (v == null || v.isEmpty) return null;
    switch (type) {
      case 's':
        final i = int.tryParse(v);
        return i != null && i >= 0 && i < shared.length ? shared[i] : null;
      case 'str':
        return v;
      case 'b':
        return v == '1';
      case 'e':
        return null; // #N/A, #DIV/0!...
      default:
        return double.tryParse(v) ?? v;
    }
  }
}
