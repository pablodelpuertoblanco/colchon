import 'package:intl/intl.dart';

/// Utilidades de dinero.
///
/// Regla de oro de la app: TODOS los importes se guardan y se operan como
/// céntimos en un `int`. Nunca se usa `double` para sumar dinero, porque la
/// coma flotante acumula errores (0.1 + 0.2 != 0.3).
class Money {
  Money._();

  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 2);
  static final NumberFormat _currencyNoDecimals =
      NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 0);

  /// 123456 -> "1.234,56 €"
  static String format(int cents) => _currency.format(cents / 100);

  /// Como [format] pero sin decimales cuando el importe es redondo.
  static String formatShort(int cents) =>
      cents % 100 == 0 ? _currencyNoDecimals.format(cents / 100) : format(cents);

  /// Con signo explícito: "+1.200,00 €" o "−35,50 €".
  static String formatSigned(int cents, {required bool positive}) {
    final text = format(cents.abs());
    return positive ? '+$text' : '−$text';
  }

  /// Importe para CSV en formato español sin separador de miles: "1234,56".
  static String toPlain(int cents) {
    final negative = cents < 0;
    final abs = cents.abs();
    final euros = abs ~/ 100;
    final rest = (abs % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$euros,$rest';
  }

  /// Convierte a euros solo para dibujar gráficos (nunca para sumar).
  static double toChart(int cents) => cents / 100;

  /// Interpreta lo que escribe el usuario: "12", "12,5", "12.50",
  /// "1.234,56", "1234.5". Devuelve céntimos o null si no es válido.
  static int? parse(String input) {
    var s = input.replaceAll(RegExp(r'[\s€]'), '');
    if (s.isEmpty) return null;
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    String intPart;
    var decPart = '';
    if (s.contains(',')) {
      // La coma es el separador decimal; los puntos son de miles.
      final idx = s.lastIndexOf(',');
      intPart = s.substring(0, idx).replaceAll('.', '');
      decPart = s.substring(idx + 1);
    } else {
      final idx = s.lastIndexOf('.');
      if (idx != -1 && s.length - idx - 1 <= 2) {
        // "12.5" o "12.50": punto decimal.
        intPart = s.substring(0, idx).replaceAll('.', '');
        decPart = s.substring(idx + 1);
      } else {
        // "1.234" o "1234": sin decimales.
        intPart = s.replaceAll('.', '');
      }
    }
    if (intPart.isEmpty) intPart = '0';
    if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
    if (!RegExp(r'^\d{0,2}$').hasMatch(decPart)) return null;
    if (intPart.length > 10) return null; // límite razonable
    final cents = int.parse(intPart) * 100 + int.parse(decPart.padRight(2, '0'));
    return negative ? -cents : cents;
  }

  /// Total de una línea de la compra: cantidad (en milésimas) x precio
  /// unitario, redondeado al céntimo más cercano.
  static int lineTotal(int quantityMilli, int unitPriceCents) =>
      (quantityMilli * unitPriceCents + 500) ~/ 1000;

  /// Variación porcentual entre dos importes. Null si no hay base.
  static double? percentChange(int previous, int current) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}

/// Cantidades de la lista de la compra, guardadas en milésimas
/// (1,5 kg = 1500) para no usar decimales.
class Quantity {
  Quantity._();

  /// "1", "1,5", "0.25" -> milésimas. Null si no es válido o es 0.
  static int? parse(String input) {
    final s = input.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(s)) return null;
    final parts = s.split('.');
    final whole = int.parse(parts[0]);
    final frac = parts.length > 1 ? int.parse(parts[1].padRight(3, '0')) : 0;
    final milli = whole * 1000 + frac;
    return milli == 0 ? null : milli;
  }

  /// 1500 -> "1,5"; 2000 -> "2"
  static String format(int milli) {
    final whole = milli ~/ 1000;
    final frac = milli % 1000;
    if (frac == 0) return '$whole';
    var f = frac.toString().padLeft(3, '0');
    while (f.endsWith('0')) {
      f = f.substring(0, f.length - 1);
    }
    return '$whole,$f';
  }
}
