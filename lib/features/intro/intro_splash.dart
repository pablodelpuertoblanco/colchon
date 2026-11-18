import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bounce_timeline.dart';

// Colores del icono (ver design/build_icons.py).
const _tealLight = Color(0xFF3C868B);
const _tealDark = Color(0xFF1C4C4F);
const _creamLight = Color(0xFFFFFEFA);
const _creamDark = Color(0xFFE8DBC2);

/// Muestra la animación de entrada encima de [child] la primera vez que se
/// construye. La app real se construye debajo desde el principio, así que la
/// base de datos se abre mientras el euro rebota y no se pierde tiempo.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});
  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    // Si el sistema pide quitar animaciones (accesibilidad), se respeta.
    final skip = _done || MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!skip) IntroSplash(onFinished: () => setState(() => _done = true)),
      ],
    );
  }
}

/// Pantalla de bienvenida: el euro del icono cae sobre un muelle, rebota
/// hasta quedarse quieto (la app se llama Colchón) y aparece el nombre.
/// Un toque la salta.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key, required this.onFinished});
  final VoidCallback onFinished;

  /// Pausa tras el último rebote y duración de la salida (el euro se amplía
  /// hasta llenar la pantalla y todo se funde con la app).
  static const holdSeconds = 0.12;
  static const exitSeconds = 0.7;

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with SingleTickerProviderStateMixin {
  final _timeline = BounceTimeline();
  late final double _total = _timeline.duration + IntroSplash.holdSeconds + IntroSplash.exitSeconds;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _exitStart => (_total - IntroSplash.exitSeconds) / _total;

  /// Saltar: pasa directamente a la salida. Ojo: asignar
  /// `_controller.value` detendría la animación; `forward(from:)` la sigue.
  void _skip() {
    if (_controller.value < _exitStart) _controller.forward(from: _exitStart);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // Sin un Material por encima, Flutter subraya los textos en amarillo
      // (su aviso de "texto sin estilo"). Este Material transparente lo evita.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final seconds = _controller.value * _total;
            final exit = ((_controller.value - _exitStart) / (1 - _exitStart)).clamp(0.0, 1.0);
            // El título aparece mientras el euro hace los últimos rebotes y se
            // va al empezar la salida, igual que el muelle.
            final leave = 1 - (exit * 2.5).clamp(0.0, 1.0);
            final title = Curves.easeOutCubic.transform(((seconds - 0.55) / 0.4).clamp(0.0, 1.0));
            return IgnorePointer(
              ignoring: exit > 0,
              child: Opacity(
                opacity: 1 - Curves.easeIn.transform(((exit - 0.45) / 0.55).clamp(0.0, 1.0)),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _skip,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-0.8, -1),
                        end: Alignment(0.8, 1),
                        colors: [_tealLight, _tealDark],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final baseY = box.maxHeight * 0.56;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _SpringPainter(
                                  frame: _timeline.at(seconds),
                                  maxCompression: _timeline.maxCompression,
                                  baseY: baseY,
                                  zoom: Curves.easeInCubic.transform(exit),
                                  springOpacity: leave,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              top: baseY + 40,
                              child: Opacity(
                                opacity: title * leave,
                                child: Transform.translate(
                                  offset: Offset(0, 14 * (1 - title)),
                                  child: const Text(
                                    'Colchón',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _creamLight,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dibuja el muelle (una hélice vista de lado) y el euro del icono encima.
class _SpringPainter extends CustomPainter {
  _SpringPainter({
    required this.frame,
    required this.maxCompression,
    required this.baseY,
    this.zoom = 0,
    this.springOpacity = 1,
  });

  final BounceFrame frame;
  final double maxCompression;
  final double baseY;

  /// Salida: 0 = tamaño normal; 1 = el euro llena la pantalla.
  final double zoom;

  /// Opacidad del muelle y su sombra (se desvanecen durante la salida).
  final double springOpacity;

  static const _restHeight = 100.0;
  static const _springWidth = 62.0;
  static const _coils = 4;
  static const _plate = 8.0;
  static const _euroSize = 112.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cream = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_creamLight, _creamDark],
      ).createShader(Rect.fromCenter(center: Offset(cx, baseY - 100), width: 220, height: 260));

    // Muelle, base y sombra en una capa para poder desvanecerlos juntos.
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, springOpacity));

    // Sombra en el suelo: se estrecha cuando el euro está más alto.
    final lift = (frame.height / 110).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, baseY + 10), width: 110 - 30 * lift, height: 14),
      Paint()..color = Colors.black.withValues(alpha: 0.18 - 0.08 * lift),
    );

    // Base del muelle.
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, baseY), width: 92, height: _plate),
      const Radius.circular(_plate / 2),
    );
    canvas.drawRRect(baseRect, cream);

    // Hélice: la mitad trasera de cada espira, más tenue, va detrás.
    final bottom = baseY - _plate / 2;
    final length = _restHeight - frame.compression;
    final front = Path();
    final back = Path();
    const steps = _coils * 24;
    bool? lastFront;
    Offset point(int i) {
      final theta = 2 * math.pi * _coils * i / steps;
      return Offset(cx + _springWidth / 2 * math.sin(theta), bottom - length * i / steps);
    }

    for (var i = 0; i < steps; i++) {
      final mid = 2 * math.pi * _coils * (i + 0.5) / steps;
      final isFront = math.cos(mid) >= 0;
      final path = isFront ? front : back;
      final a = point(i), b = point(i + 1);
      if (lastFront != isFront) path.moveTo(a.dx, a.dy);
      path.lineTo(b.dx, b.dy);
      lastFront = isFront;
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(back, stroke..color = _creamDark.withValues(alpha: 0.35));
    canvas.drawPath(
      front,
      Paint()
        ..shader = cream.shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Plataforma superior, sobre la que se apoya el euro.
    final top = bottom - length;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, top - _plate / 2), width: 82, height: _plate),
        const Radius.circular(_plate / 2),
      ),
      cream,
    );
    canvas.restore();

    // Euro: se aplasta al hundir el muelle (estirar y aplastar, un clásico
    // de la animación para que parezca blando).
    final squash = 0.18 * (frame.compression / maxCompression).clamp(0.0, 1.0);
    final euroBottom = top - _plate - math.max(0.0, frame.height);
    // (251, 405) es el centro de la base del dibujo original, de 512 de lado,
    // y (251, 256) su centro: la ampliación de salida crece desde ahí.
    const s = _euroSize / 512;
    canvas.save();
    canvas.translate(cx, euroBottom - 149 * s);
    canvas.scale(1 + 30 * zoom);
    canvas.translate(0, 149 * s);
    canvas.scale(1 + squash, 1 - squash);
    canvas.scale(s);
    canvas.translate(-251, -405);
    _drawEuro(canvas, Paint()..color = Colors.black.withValues(alpha: 0.16), const Offset(0, 12));
    _drawEuro(
      canvas,
      Paint()
        ..shader = const LinearGradient(
          colors: [_creamLight, _creamDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(70, 100, 370, 310)),
      Offset.zero,
    );
    canvas.restore();
  }

  /// Mismo trazo que el icono: arco abierto y dos barras con puntas redondas.
  void _drawEuro(Canvas canvas, Paint base, Offset shift) {
    Paint stroke(double width) => Paint()
      ..color = base.color
      ..shader = base.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    const cy = 256.0;
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(282, cy) + shift, radius: 120),
      36 * math.pi / 180,
      288 * math.pi / 180,
      false,
      stroke(58),
    );
    for (final dy in const [-38.0, 38.0]) {
      canvas.drawLine(Offset(100, cy + dy) + shift, Offset(296, cy + dy) + shift, stroke(42));
    }
  }

  @override
  bool shouldRepaint(_SpringPainter old) =>
      old.frame.height != frame.height ||
      old.frame.compression != frame.compression ||
      old.baseY != baseY ||
      old.zoom != zoom ||
      old.springOpacity != springOpacity;
}
