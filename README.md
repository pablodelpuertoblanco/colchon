# Colchón

App móvil en Flutter para controlar la economía de casa: gastos, ingresos, calendario, estadísticas, presupuestos, plan anual, gastos recurrentes y listas de la compra. Todo se guarda en el móvil (SQLite) y funciona sin conexión: tus datos no salen del teléfono.

**Stack:** Flutter · Dart · Riverpod · Drift (SQLite) · fl_chart

---

## 1. Puesta en marcha (Windows + Android)

### Requisitos

- **Flutter estable reciente** (3.38 o posterior; recomendado el último estable). Compruébalo con `flutter --version`.
- **Android Studio** con un emulador o un móvil Android con la depuración USB activada.
- `flutter doctor` sin errores en la parte de Android.

### Pasos

Abre una terminal en la carpeta del proyecto (la que contiene `pubspec.yaml`):

```bash
# 1. Genera las carpetas de plataforma (android/, ios/...). No sobrescribe lib/ ni test/.
flutter create --org es.hogarencifras --project-name hogar_en_cifras --platforms android,ios .

# 2. Descarga las dependencias
flutter pub get

# 3. Genera el código de la base de datos (crea lib/data/database.g.dart)
dart run build_runner build --delete-conflicting-outputs

# 4. Ejecuta los tests
flutter test

# 5. Arranca la app en el móvil o emulador
flutter run
```

> Si cambias las tablas de `lib/data/database.dart`, repite el paso 3.
> Mientras desarrollas puedes dejar `dart run build_runner watch` abierto en otra terminal.

### Si algo falla al compilar

- **`database.g.dart` no existe / `_$AppDatabase` no encontrado** → falta el paso 3.
- **Conflicto de versiones en `flutter pub get`** → ejecuta `flutter pub upgrade --major-versions` y vuelve a probar.
- **Avisos de "deprecated" sobre `package:flutter/material.dart`** → desde Flutter 3.50 los widgets Material viven en el paquete `material_ui`. Son solo avisos; la migración se hace más adelante con la herramienta `dart fix` de Flutter.
- **Error de un paquete sobre la versión del NDK o de Gradle** → el propio mensaje indica la versión a poner en `android/app/build.gradle(.kts)`.
- Cualquier otro error: abre un *issue* con el mensaje completo.

### Generar el APK para instalarlo

```bash
flutter build apk --release
```

El archivo queda en `build/app/outputs/flutter-apk/app-release.apk`.

---

## 2. Qué hace la app

| Pestaña | Qué hay |
| --- | --- |
| **Inicio** | Balance del mes, ingresos, gastos, comparación con el mes anterior, ahorro, dinero disponible, pendientes y próximos cargos, presupuestos, en qué se va el dinero, últimos 6 meses y últimos movimientos. Engranaje → Ajustes. |
| **Movimientos** | Historial completo con búsqueda (ignora tildes), filtros por tipo, mes, fechas, categorías y método de pago, y orden por fecha o importe. Deslizar a la izquierda borra (con Deshacer). |
| **Calendario** | Mes completo: punto verde si hubo ingresos, coral si hubo gastos y color más intenso cuanto más se gastó. Al tocar un día: sus movimientos y totales. Deslizar cambia de mes. |
| **Estadísticas** | Semana, mes, año o fechas a medida: resumen, tasa de ahorro, comparación con el periodo anterior, barras de ingresos frente a gastos, anillo y ranking por categorías (tocar abre el detalle), evolución del ahorro y comparación anual. |
| **Compra** | Listas de la compra con autocompletado de productos usados, casillas grandes, agrupación por pasillo, pantalla siempre encendida y "Finalizar compra", que registra el gasto en Supermercado. |

Desde **Ajustes**: presupuestos, recurrentes, categorías (crear, editar, agrupar, archivar, reordenar), métodos de pago, saldo inicial, tema claro/oscuro, exportar a CSV (se abre con Excel), copia de seguridad y restauración.

### Novedades de la versión 1.1

- **Plan anual** (Ajustes → Plan anual, o la tarjeta "Plan" del inicio): importe *previsto* por categoría y mes frente a lo *real*, agrupado por bloques (ingresos, necesarios variables, necesarios fijos, prescindibles, ahorro). Pestaña **Año** con la tabla de los 12 meses y los totales de cada partida. Tocar una fila cambia lo previsto (este mes, hasta diciembre o todo el año) o abre la fila "mes a mes".
- **Regla 50/30/20** con objetivos configurables y la parte de los ingresos que va a cada bloque.
- **Mes contable** configurable (Ajustes → Inicio del mes): con el día 24, "noviembre" va del 24 de octubre al 23 de noviembre en el inicio, estadísticas, presupuestos, historial y plan. El calendario sigue siendo el mes natural.
- **Ahorro real** = saldo del mes + gastos marcados como "cuenta como ahorro" (plan de pensiones, seguro de ahorro, hipotecas, traspasos a la cuenta de ahorro) − ingresos que "salen de tus ahorros".
- **Saldo mínimo** ("mínimo del que no debo bajar"): aviso en el inicio si el dinero disponible baja de ahí o va a bajar con los cargos recurrentes que quedan del mes.
- **Patrimonio**: bienes (planes, acciones, cuentas de ahorro...) y deudas con su valor mes a mes; el último valor se arrastra hasta que se anota otro.
- **Categorías agrupadas**: por ejemplo, una vivienda con su luz, agua e IBI; en Estadísticas, con "Agrupar subcategorías", sale el total de cada grupo.
- **Importar plan** (Ajustes → Importar plan): carga el plan desde un archivo. Desde la versión 1.3, desde tu propio Excel (ver más abajo).

### Novedades de la versión 1.3

- **Importar el plan desde un Excel** (Ajustes → Importar plan, o "Importar Excel (.xlsx)" en el plan vacío). Solo acepta `.xlsx`: eliges el archivo y, antes de importar, ves un resumen: año, partidas, ingresos y gastos previstos, categorías nuevas y las que se actualizan.
  - **Formato** (el de la plantilla que la app comparte con "Descargar la plantilla", `assets/plantilla/plantilla_plan.xlsx`):
    - Hoja **Plan**: una fila de cabecera con los 12 meses (Ene… Dic o los nombres completos) y una fila por categoría. Columnas opcionales: **Tipo** (Ingreso o Gasto), **Bloque** (Necesario fijo, Necesario variable, Prescindible, Ocio, Ahorro), **Grupo**, **Emoji** y **Ahorro** ("Sí" si cuenta como ahorro).
    - Sin columnas Tipo y Bloque también vale: un título como "INGRESOS", "GASTOS FIJOS" o "PRESCINDIBLES" marca las filas que vienen debajo, en su propia fila o en una columna a la izquierda del nombre. Un título que no reconoce ("VIVIENDA", "MASCOTAS"…) después de los ingresos indica que empiezan los gastos. Las filas y columnas de totales se ignoran, y los importes pueden ser números o texto ("1.234,56 €").
    - Hojas opcionales **Ajustes** (año, día de inicio de mes, saldo mínimo y objetivos 50/30/20) y **Patrimonio** (bienes y deudas mes a mes).
  - El resumen nombra las partidas que entrarán como ingresos, para detectar a tiempo una mal clasificada.
  - Reutiliza las categorías que ya existen (por nombre) y respeta su emoji, color y bloque si el Excel no los indica. Se puede repetir sin duplicar nada.
- **Mover una partida del plan** (tocarla → "Mover"): a otro bloque de gastos, a "Gasto sin clasificar" o de gasto a ingreso (y al revés). Al cambiar de tipo se lleva sus subcategorías, y sus movimientos y recurrentes pasan a ser del nuevo tipo; si tiene movimientos, la app pide confirmación.
  - El `.xlsx` se lee sin librerías de Excel: es un ZIP con XML dentro, que se abre con `dart:io` y el paquete `xml` (`lib/data/xlsx_reader.dart` y `lib/data/plan_excel.dart`).
- La app ya no incluye ningún plan de ejemplo con datos reales.

### Novedades de la versión 1.2.1

- **Nombre e icono nuevos: Colchón.**
- **Animación de entrada**: el euro del icono cae sobre un muelle, rebota hasta quedarse quieto y se amplía hasta llenar la pantalla para dar paso a la app. Un toque la salta, y no aparece si el móvil tiene desactivadas las animaciones (accesibilidad). La app se carga debajo mientras tanto, así que no hace esperar más.
- Pantalla de arranque nativa con el degradado del icono (sin fogonazo blanco) y fundido suave al cambiar de pestaña.

### Novedades de la versión 1.2

- **Bloque "Ocio"** (🎬): separado de "Prescindible". En el plan es una sección propia con su total; en la regla 50/30/20 cuenta dentro del 30 % ("Prescindibles y ocio"). Ocio, Viajes y Restaurantes pasan a Ocio al actualizar, solo si seguían en "Prescindible". El importador acepta el bloque "Ocio".
- **Previsión de saldo** (tocando "Dinero disponible" en el inicio, desde el plan o desde Ajustes): cómo evolucionará el dinero día a día durante 1 a 12 meses contables (3 por defecto). Gráfico con el saldo mínimo y el punto más bajo ("El 5 dic bajarás a…"), y la lista de próximos cargos e ingresos con el saldo resultante. El aviso del mínimo en el inicio usa esta previsión e indica la fecha.
  - Cada categoría puede tener un **día habitual** de cargo o cobro (formulario de categoría u hoja de la partida del plan). Un día 31 cae el último día en los meses más cortos.
- **Salud financiera** (desde Estadísticas o Ajustes): reglas orientativas por concepto (Vivienda máx. 35 %, Alimentación 15 %, Transporte 15 %, Ocio y prescindibles 30 %, Deudas 35 %, Ahorro mín. 20 %) con el % real del mes, la media de los últimos 12 meses y su estado (dentro, cerca o fuera). Se pueden crear, editar y borrar; "Restablecer reglas iniciales" vuelve a elegir sus categorías por nombre (útil tras importar un plan). Incluye el **fondo de emergencia** (objetivo de 3 a 6 meses). Son referencias, no asesoramiento financiero. Las reglas incumplidas aparecen en el inicio.
- **Medias por categoría**: en el detalle de una categoría, media mensual de los últimos 3, 6 y 12 meses y cómo va el mes frente a cada una.

### Definiciones de las cifras

- **Balance del mes** = ingresos − gastos del mes.
- **Dinero disponible** = saldo inicial + ingresos − gastos desde la fecha de ese saldo.
- **Ahorro / tasa de ahorro** = balance positivo / balance ÷ ingresos.
- Los movimientos **pendientes** (recibos variables sin confirmar) no cuentan en ninguna cifra hasta confirmarlos.
- **Previsto / real del plan**: lo real de una categoría sin previsto se suma a la fila de su grupo si el grupo tiene previsto; si no, aparece como fila propia con previsto 0.
- **Porcentajes 50/30/20** = gasto del bloque ÷ ingresos propios (sin contar lo que sale de tus ahorros).
- **Previsión de saldo** = dinero disponible de hoy + (a) recurrentes que aún no se han generado y movimientos pendientes de confirmar, en su fecha (los atrasados, hoy) + (b) lo que queda de cada partida del plan: previsto − real − lo que ya cubren los recurrentes de esa categoría (mínimo 0). Va en el día habitual de la categoría (si ya pasó este mes, hoy) o, si no tiene, repartido a partes iguales entre los días que quedan del mes. Nada se cuenta dos veces: lo registrado ya está en el saldo y en el real del plan.
- **% de una regla** = gasto de sus categorías (con sus subcategorías) ÷ ingresos propios. La regla de ahorro usa el ahorro real. La **media de 12 meses** es el total de los meses completos anteriores ÷ sus ingresos (no la media de porcentajes), contando solo desde el primer mes con movimientos. **Cerca** = a menos del 10 % del límite (con máx. 35 %, desde el 31,5 %). A principio de mes, sin ingresos todavía, el estado sale de la media.
- **Fondo de emergencia** = dinero disponible ÷ gasto medio mensual en necesarios (fijos y variables) de los meses anteriores.

---

## 3. Arquitectura

```
lib/
  main.dart                  arranque: idioma español y ProviderScope de Riverpod
  app/
    app.dart                 MaterialApp, temas y localización
    theme.dart               colores con significado, tema claro/oscuro
    home_shell.dart          barra inferior, botón + y generación de recurrentes
    providers.dart           TODOS los providers: repositorios y datos en vivo
  core/
    money.dart               importes en céntimos, formato y lectura de importes
    dates.dart               fechas locales "AAAA-MM-DD", semanas de lunes a domingo
    text.dart                ids UUID y normalización para búsquedas
    widgets/                 tarjetas, importes, teclado numérico, selector de emoji...
  domain/                    lógica pura en Dart, sin Flutter ni base de datos
    models.dart              enums y objetos de vista
    period.dart              periodos (semana/mes/año) y sus tramos para gráficos
    recurrence.dart          cálculo de fechas de los recurrentes
    budget_math.dart         progreso, avisos y ritmo de gasto de presupuestos
    plan.dart                plan anual: previsto frente a real por bloques
    net_worth.dart           patrimonio mes a mes
    forecast.dart            previsión de saldo día a día
    benchmarks.dart          salud financiera: reglas, fondo de emergencia y medias
  data/
    database.dart            tablas Drift, índices, triggers y migraciones
    seed.dart                categorías y métodos de pago iniciales
    backup_service.dart      CSV, copia de seguridad y restauración
    xlsx_reader.dart         lector mínimo de .xlsx (ZIP + XML)
    plan_excel.dart          plan anual desde Excel
    plan_import.dart         aplica un plan importado sin duplicar nada
    repositories/            una clase por área con todas sus consultas
  features/                  una carpeta por funcionalidad con sus pantallas
test/                        tests del dominio, de la base de datos real (SQLite en
                             memoria, migraciones incluidas) y de pintado de pantallas
```

### Cómo fluye un dato

1. La pantalla llama a un **repositorio** (`ref.read(transactionRepoProvider).create(...)`).
2. El repositorio escribe en **SQLite** con Drift.
3. Las pantallas no recargan nada a mano: escuchan **StreamProviders** (`ref.watch(...)`) construidos sobre consultas `watch()` de Drift. Cuando una tabla cambia, Drift vuelve a ejecutar las consultas afectadas y la interfaz se repinta sola.

Por eso los gráficos, el calendario y los totales siempre muestran datos reales de la base de datos.

### Decisiones importantes

| Decisión | Motivo |
| --- | --- |
| Importes en céntimos (`int`) | Con `double`, 0,1 + 0,2 ≠ 0,3. Todas las sumas son exactas. |
| Fecha como texto local `AAAA-MM-DD` y hora aparte | Un gasto de las 23:30 nunca salta de día por la zona horaria. |
| Una sola tabla `transactions` con `type` | Balance, historial, calendario y gráficos salen de la misma consulta. |
| Ids UUID y borrado lógico (`deleted_at`) | Permite Deshacer y deja preparada la sincronización entre móviles. |
| Totales calculados con SQL, nunca guardados | Imposible que un total se desincronice. |
| Índice único (regla, fecha) en recurrentes | Generarlos es idempotente: no se duplican aunque abras la app 20 veces, y uno borrado no vuelve a aparecer. |
| Trigger que impide categoría de ingreso en un gasto | La integridad la garantiza también la base de datos, no solo la interfaz. |
| Calendario hecho a medida | Pinta cada día a medida y evita un paquete sin mantenimiento. |
| Riverpod sin generación de código | Menos piezas mágicas mientras aprendes; se puede migrar más tarde. |

### Recurrentes

- **Fijos** (alquiler, cuotas): se crean confirmados el día que toca.
- **Variables** (luz, agua): se crean como *pendientes* con el importe estimado; en Inicio aparecen con un botón **Confirmar** para poner el importe real.
- Se generan al abrir la app y al volver a ella (`HomeShell` → `RecurringRepository.generateDue`).
- Un cobro el día 31 cae el último día en los meses más cortos.

---

### Base de datos: versiones del esquema

Cada versión añade sus cambios en `onUpgrade` (`database.dart`) sin borrar ni recrear nada; los datos que ya tengas se conservan.

| Versión | App | Cambios |
| --- | --- | --- |
| 2 | 1.1 | `categories.budget_group` e `is_savings`; tablas `plan_entries`, `assets` y `asset_values`. |
| 3 | 1.2 | `categories.expected_day` (día habitual de cargo o cobro, 1-31). |
| 4 | 1.2 | Tabla `benchmarks` (reglas de salud financiera) con las reglas iniciales. |

El bloque "Ocio" no necesita migración: `budget_group` es texto. El paso de Ocio, Viajes y Restaurantes a "Ocio" se hace una sola vez al abrir la app (queda marcado en ajustes).

Las copias de seguridad de versiones anteriores se pueden restaurar: la restauración copia por nombre de columna, y si la copia no trae reglas de salud financiera se crean las iniciales.

## 4. Pendiente para siguientes versiones

- Notificaciones del sistema para presupuestos (ahora los avisos son dentro de la app).
- Bloqueo con huella.
- Exportar a PDF y exportar el plan a `.xlsx`.
- Objetivos de ahorro, detección de gastos inusuales y widget de pantalla de inicio.
- v2: cuentas, hogar compartido y sincronización (PowerSync + Supabase), importación de extractos bancarios, IA para escanear tickets.

---

Hecha por [Pablo del Puerto Blanco](https://github.com/pablodelpuertoblanco) · [Portfolio](https://pablodelpuertoblanco.github.io)
