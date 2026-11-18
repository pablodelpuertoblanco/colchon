import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Identificador único generado en el móvil (nunca autoincremental), para
/// que en el futuro varios dispositivos puedan sincronizar sin chocar.
String newId() => _uuid.v4();

const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Texto para búsquedas: minúsculas, sin tildes y sin espacios repetidos.
/// "Cafetería  Ñandú" -> "cafeteria nandu"
String normalizeForSearch(String input) {
  final lower = input.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}
