import 'dart:math' as math;

/// Estado del euro y del muelle en un instante de la animación de entrada.
class BounceFrame {
  const BounceFrame({required this.height, required this.compression});

  /// Altura de la base del euro sobre la parte alta del muelle en reposo, en
  /// píxeles lógicos. 0 = apoyado; negativo = hundiendo el muelle.
  final double height;

  /// Cuánto está aplastado el muelle (px). 0 = en reposo.
  final double compression;
}

/// Un apoyo sobre el muelle: cuánto lo hunde y cuánto dura.
typedef BounceContact = ({double depth, double seconds});

/// Trayectoria de un objeto que cae sobre un muelle y rebota cada vez menos.
///
/// En el aire sigue una parábola (gravedad constante), igual que una pelota
/// real; en cada apoyo el muelle se hunde con medio seno, que da un frenazo y
/// un impulso suaves. Se describe por tramos en lugar de simular física para
/// que la duración total sea exacta y fácil de ajustar.
class BounceTimeline {
  BounceTimeline({
    this.gravity = 3500,
    this.dropHeight = 110,
    this.contacts = const [
      (depth: 34, seconds: 0.15),
      (depth: 18, seconds: 0.12),
      (depth: 8, seconds: 0.10),
      (depth: 3, seconds: 0.08),
    ],
    this.rebounds = const [85, 30, 8],
  }) : assert(rebounds.length == contacts.length - 1) {
    var t = 0.0;
    void add(double seconds, BounceFrame Function(double local) at) {
      _segments.add((start: t, seconds: seconds, at: at));
      t += seconds;
    }

    // Caída inicial desde el reposo.
    add(math.sqrt(2 * dropHeight / gravity), (s) => BounceFrame(height: dropHeight - gravity * s * s / 2, compression: 0));
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      add(c.seconds, (s) {
        final squash = c.depth * math.sin(math.pi * s / c.seconds);
        return BounceFrame(height: -squash, compression: squash);
      });
      if (i < rebounds.length) {
        final v = math.sqrt(2 * gravity * rebounds[i]);
        add(2 * v / gravity, (s) => BounceFrame(height: math.max(0, v * s - gravity * s * s / 2), compression: 0));
      }
    }
    duration = t;
  }

  final double gravity;
  final double dropHeight;
  final List<BounceContact> contacts;
  final List<double> rebounds;

  /// Duración total en segundos; a partir de ahí el euro queda en reposo.
  late final double duration;

  final _segments = <({double start, double seconds, BounceFrame Function(double) at})>[];

  /// Hundimiento máximo del muelle (el primer apoyo, el más fuerte).
  double get maxCompression => contacts.map((c) => c.depth).reduce(math.max);

  BounceFrame at(double seconds) {
    if (seconds <= 0) return _segments.first.at(0);
    for (final s in _segments) {
      if (seconds < s.start + s.seconds) return s.at(seconds - s.start);
    }
    return const BounceFrame(height: 0, compression: 0);
  }
}
