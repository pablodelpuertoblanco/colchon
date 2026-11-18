import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hogar_en_cifras/features/intro/bounce_timeline.dart';
import 'package:hogar_en_cifras/features/intro/intro_splash.dart';

void main() {
  group('BounceTimeline', () {
    final t = BounceTimeline();

    test('empieza arriba, sin hundir el muelle, y acaba en reposo', () {
      expect(t.at(0).height, t.dropHeight);
      expect(t.at(0).compression, 0);
      expect(t.at(t.duration).height, 0);
      expect(t.at(t.duration).compression, 0);
      expect(t.at(t.duration + 5).height, 0);
    });

    test('dura lo que se espera (entre 1 y 2 segundos)', () {
      expect(t.duration, inInclusiveRange(1.0, 2.0));
    });

    test('es continua: no hay saltos entre milisegundos', () {
      var previous = t.at(0);
      for (var ms = 1; ms <= (t.duration * 1000).ceil() + 10; ms++) {
        final f = t.at(ms / 1000);
        expect((f.height - previous.height).abs(), lessThan(6), reason: 'altura en $ms ms');
        expect((f.compression - previous.compression).abs(), lessThan(2), reason: 'muelle en $ms ms');
        previous = f;
      }
    });

    test('el muelle nunca se estira y el primer apoyo es el más fuerte', () {
      var maxSquash = 0.0;
      for (var ms = 0; ms <= t.duration * 1000; ms++) {
        final f = t.at(ms / 1000);
        expect(f.compression, greaterThanOrEqualTo(0));
        if (f.compression > 0) expect(f.height, closeTo(-f.compression, 1e-9));
        if (f.compression > maxSquash) maxSquash = f.compression;
      }
      expect(maxSquash, closeTo(t.maxCompression, 0.5));
    });

    test('cada rebote sube menos que el anterior', () {
      for (var i = 1; i < t.rebounds.length; i++) {
        expect(t.rebounds[i], lessThan(t.rebounds[i - 1]));
      }
      expect(t.rebounds.first, lessThan(t.dropHeight));
    });
  });

  group('IntroGate', () {
    Widget app({bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const IntroGate(child: Text('app')),
      ),
    );

    testWidgets('muestra la animación y luego deja solo la app', (tester) async {
      await tester.pumpWidget(app());
      expect(find.byType(IntroSplash), findsOneWidget);
      expect(find.text('app'), findsOneWidget, reason: 'la app se construye debajo desde el principio');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('Colchón'), findsOneWidget);
      // Sin subrayado amarillo (el aviso de Flutter de texto sin Material).
      final title = tester.widget<RichText>(find.descendant(of: find.byType(IntroSplash), matching: find.byType(RichText)));
      expect(title.text.style?.decoration, isNot(TextDecoration.underline));
      expect(find.textContaining('amortiguada'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(IntroSplash), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('un toque la salta', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(IntroSplash));
      // Tras el toque solo queda el fundido: se va en mucho menos de lo que
      // dura la animación entera (el reloj empieza a contar en el frame siguiente).
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(IntroSplash), findsNothing);
    });

    testWidgets('sin animaciones del sistema, va directa a la app', (tester) async {
      await tester.pumpWidget(app(disableAnimations: true));
      expect(find.byType(IntroSplash), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });
  });
}
