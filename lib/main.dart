import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nombres de meses y días en español para intl.
  await initializeDateFormatting('es_ES');
  Intl.defaultLocale = 'es_ES';
  runApp(const ProviderScope(child: HogarApp()));
}
