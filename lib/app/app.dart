import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/intro/intro_splash.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'theme.dart';

class HogarApp extends ConsumerWidget {
  const HogarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Colchón',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // Español de España: calendarios que empiezan en lunes, textos en español.
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Animación de entrada (el euro rebota en un muelle) sobre la app real.
      home: const IntroGate(child: HomeShell()),
    );
  }
}
