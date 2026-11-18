import 'package:flutter/material.dart';

/// Colores con significado. Los ingresos en verde y los gastos en coral
/// suave; el rojo intenso se reserva para avisos y presupuestos superados.
class AppColors {
  AppColors._();
  static const seed = Color(0xFF2F6F73);
  static const income = Color(0xFF2E9E6B);
  static const expense = Color(0xFFE5735C);
  static const warning = Color(0xFFE0A100);
  static const danger = Color(0xFFD64545);
}

/// Cifras con dígitos de ancho fijo para que los importes se alineen.
const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed, brightness: brightness);
  final isDark = brightness == Brightness.dark;
  final background = isDark ? scheme.surface : scheme.surfaceContainerLow;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

extension ThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Fondo de las tarjetas: blanco sobre gris en claro; gris elevado en oscuro.
  Color get cardColor => isDark ? colors.surfaceContainerHigh : colors.surfaceContainerLowest;
}
