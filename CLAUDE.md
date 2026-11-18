# Colchón (antes "Hogar en Cifras") — guía para Claude Code

App Flutter (Android primero) para llevar la economía de una casa: gastos, ingresos, presupuestos, recurrentes, lista de la compra, plan anual (previsto vs real), regla 50/30/20, patrimonio, previsión de saldo y salud financiera. Es de uso personal; el usuario la instala desde un APK que compila en este PC (Windows).

El nombre visible es **Colchón**, pero el paquete Dart, el `applicationId` (`com.example.hogar_en_cifras`) y el archivo de la base de datos siguen como `hogar_en_cifras`: cambiarlos haría que Android la tratara como otra app y se perderían los datos. El icono se genera con `design/build_icons.py`.

## Idioma y estilo
- Interfaz, comentarios y mensajes en **español de España**. Formato de dinero `1.234,56 €` (usa `Money` de `lib/core/money.dart`, nunca formatees a mano).
- Explica las decisiones técnicas importantes en el resumen final: el usuario quiere aprender.

## Comandos
```
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # tras tocar tablas de lib/data/database.dart
flutter analyze
flutter test
flutter build apk                                          # APK en build/app/outputs/flutter-apk/app-release.apk
```
Antes de dar algo por terminado: `flutter analyze` sin errores y `flutter test` en verde.

## Stack (no cambiarlo sin motivo)
- Flutter + Dart 3.8+ (se usan elementos null-aware `?x` en listas).
- **Riverpod 3 sin generación de código**: `Provider`, `StreamProvider(.autoDispose).family`, `NotifierProvider`. `AsyncValue.value` es nullable.
- **Drift 2.35** + `drift_flutter`. Tablas en `lib/data/database.dart`; el `.g.dart` se genera.
- fl_chart 1.x, share_plus 13 (`SharePlus.instance.share(ShareParams(...))`), file_picker 13 (`FilePicker.pickFile()` estático), wakelock_plus, uuid, intl (es_ES), xml 7.
- **Importar plan: solo desde Excel (.xlsx).** `lib/data/xlsx_reader.dart` lo lee a mano (ZIP con `dart:io` + XML con el paquete `xml`); no uses el paquete `excel`, que exige xml < 7 y choca con el resto. `lib/data/plan_excel.dart` convierte las hojas en un `PlanImportFile` y `plan_import.dart` lo aplica. Plantilla en `assets/plantilla/plantilla_plan.xlsx`; tests con ella y con `test/fixtures/`.
- No inventes APIs: si dudas de una firma, consulta la versión de `pubspec.lock`.

## Estructura
- `lib/core/`: dinero, fechas (`Dates`, `MonthCycle`), texto, widgets comunes (`SectionCard`, `PeriodSwitcher`, `MoneyField`...).
- `lib/domain/`: lógica pura y testeable (`period.dart`, `plan.dart`, `net_worth.dart`, `recurrence.dart`, `budget_math.dart`, `forecast.dart`, `benchmarks.dart`). Sin Flutter ni base de datos.
- `lib/data/`: base de datos, semilla, copia de seguridad, importador del plan y repositorios.
- `lib/app/providers.dart`: todos los providers.
- `lib/features/<pantalla>/`: una carpeta por funcionalidad. `features/intro/` es la animación de entrada (`IntroGate` envuelve `HomeShell` en `app.dart`); sus colores salen del icono.

## Reglas de datos (importantes)
- Dinero siempre en **céntimos enteros** (`int`). Cantidades de la compra en milésimas.
- Fechas de movimientos como texto local `AAAA-MM-DD`; `created_at`/`updated_at` en UTC ISO.
- Ids UUID (`newId()`), **borrado lógico** con `deleted_at` (filtra siempre `deleted_at IS NULL`).
- **El usuario ya tiene datos reales en el móvil.** Cualquier cambio de tablas: sube `schemaVersion` y añade el paso en `onUpgrade` (nunca borrar ni recrear tablas). La restauración de copias copia columnas por nombre (`backup_service.dart`): si añades tablas, inclúyelas en `_tables`.
- Mes contable configurable (`MonthCycle`, el usuario usa el día 24: "enero" = 24 dic – 23 ene). Todo periodo de mes/año debe usar `monthCycleProvider`, salvo el calendario.
- Esquema actual: **versión 4** (v3: `categories.expected_day`; v4: tabla `benchmarks`). Las migraciones se prueban en `test/database_test.dart` con una base de datos v2 simulada: amplía ese test al añadir una versión.
- Pasos de datos de una sola vez que no cambian el esquema (como pasar categorías a "Ocio"): en `beforeOpen`, marcados con una clave en `settings` para no repetirse.
- Bloques (`BudgetGroup`): fijo, variable, prescindible, ocio (`leisure`) y ahorro. Ocio es sección propia en el plan pero cuenta en el 30 % (`RuleBucket.wants`) con los prescindibles.
- Ahorro real = saldo + gastos de categorías `is_savings` − ingresos `is_savings`.
- Previsión de saldo (`forecast.dart`): nunca contar dos veces. Lo confirmado ya está en el saldo y en el real del plan; los recurrentes se prevén desde el día siguiente a su última ocurrencia generada (igual que `generateDue`); lo que queda de una partida descuenta lo que ya cubren sus recurrentes y pendientes.
- Salud financiera (`benchmarks.dart`): las medias son total ÷ total de ingresos de los meses completos anteriores, solo desde el primer mes con datos. La interfaz debe dejar claro que son referencias orientativas, no asesoramiento financiero.
- **Código público** en https://github.com/pablodelpuertoblanco/colchon (subido el 17-11-2026 como copia limpia, sin historial). Nada de datos reales del usuario en el código, los tests ni el README: ni importes, ni nombres de familiares o viviendas, ni su Excel. `assets/plan/` (su antiguo plan en JSON) ya no se usa y está en `.gitignore`.
- El **historial git local** contiene ese plan en commits antiguos: no hagas `git push` de este historial a GitHub. Para publicar cambios, sube los archivos o crea un historial nuevo.

## Forma de trabajar
- No cambies código que funciona sin una razón clara. Cambios pequeños y verificables.
- Prioriza lo que aporta valor real al usuario; nada de funcionalidades de relleno.
- Si una tarea es grande, primero propón un plan corto y pide confirmación.
- Añade tests en `test/` para la lógica nueva de `lib/domain/`.
- Tests de base de datos: `AppDatabase(NativeDatabase.memory())` funciona en `flutter test`. En tests de widgets NO uses drift (se cuelga con el reloj simulado): sustituye los providers calculados con `overrideWithValue` (ver `test/screens_smoke_test.dart`).
- El proyecto usa git: un commit por petición, con mensaje en español.
