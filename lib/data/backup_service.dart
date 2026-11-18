import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/dates.dart';
import '../core/money.dart';
import 'database.dart';
import 'repositories/benchmark_repository.dart';
import 'repositories/transaction_repository.dart';

/// Exportación a CSV y copias de seguridad de la base de datos completa.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  /// Tablas que tiene cualquier copia (desde la versión 1).
  static const _requiredTables = [
    'settings',
    'payment_methods',
    'categories',
    'recurring_rules',
    'transactions',
    'budgets',
    'shopping_lists',
    'shopping_items',
  ];

  /// Todas las tablas, padres antes que hijos. Las añadidas en versiones
  /// posteriores pueden faltar en copias antiguas.
  static const _tables = [
    ..._requiredTables,
    'plan_entries',
    'assets',
    'asset_values',
    'benchmarks',
  ];

  /// Exporta todos los movimientos a un CSV que Excel abre directamente
  /// (separador ";", coma decimal y BOM UTF-8 para que respete las tildes).
  Future<File> exportCsv() async {
    final rows = await db.customSelect(
      '$txSelectSql WHERE t.deleted_at IS NULL ORDER BY t.occurred_on, t.time_of_day',
      readsFrom: {db.transactions, db.categories, db.paymentMethods},
    ).get();

    final buffer = StringBuffer('﻿');
    buffer.writeln(['Fecha', 'Hora', 'Tipo', 'Categoría', 'Descripción', 'Importe', 'Método de pago', 'Estado', 'Notas']
        .join(';'));
    for (final row in rows) {
      final tx = txViewFromRow(row);
      final d = tx.date;
      buffer.writeln([
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
        tx.time ?? '',
        tx.type.label,
        tx.categoryName,
        tx.description,
        Money.toPlain(tx.signedCents),
        tx.paymentMethodName ?? '',
        tx.isPending ? 'Pendiente' : 'Confirmado',
        tx.notes ?? '',
      ].map(_csvCell).join(';'));
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'movimientos_${Dates.key(Dates.today())}.csv'));
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  String _csvCell(String v) {
    if (v.contains(';') || v.contains('"') || v.contains('\n')) {
      final escaped = v.replaceAll('"', '""');
      return '"$escaped"';
    }
    return v;
  }

  /// Copia exacta y consistente de la base de datos (VACUUM INTO no necesita
  /// cerrar la base de datos).
  Future<File> createBackup() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'hogar_en_cifras_${Dates.key(Dates.today())}.sqlite'));
    if (await file.exists()) await file.delete();
    await db.customStatement("VACUUM INTO '${_escape(file.path)}'");
    return file;
  }

  /// Sustituye todos los datos por los de una copia. Se valida que el archivo
  /// tenga las tablas de la app y todo ocurre en una transacción: si algo
  /// falla, los datos actuales quedan intactos.
  Future<void> restore(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final tmp = File(p.join(dir.path, 'restore_${DateTime.now().millisecondsSinceEpoch}.sqlite'));
    await tmp.writeAsBytes(bytes, flush: true);

    await db.customStatement("ATTACH DATABASE '${_escape(tmp.path)}' AS bk");
    try {
      final present = (await db.customSelect("SELECT name FROM bk.sqlite_master WHERE type = 'table'").get())
          .map((r) => r.read<String>('name'))
          .toSet();
      if (!_requiredTables.every(present.contains)) {
        throw const FormatException('El archivo no es una copia de seguridad de Colchón.');
      }
      await db.transaction(() async {
        // Borrar hijos antes que padres e insertar padres antes que hijos,
        // para respetar las claves foráneas.
        for (final t in _tables.reversed) {
          await db.customStatement('DELETE FROM main.$t');
        }
        for (final t in _tables) {
          if (!present.contains(t)) continue;
          // Columnas explícitas: una copia de otra versión puede tener
          // columnas de menos (toman su valor por defecto) o en otro orden.
          final cols = await _commonColumns(t);
          if (cols.isEmpty) continue;
          final list = cols.map((c) => '"$c"').join(', ');
          await db.customStatement('INSERT INTO main.$t ($list) SELECT $list FROM bk.$t');
        }
        // Una copia anterior a la salud financiera no trae reglas: se crean
        // las iniciales con las categorías restauradas.
        if (!present.contains('benchmarks')) await seedDefaultBenchmarks(db);
      });
    } finally {
      await db.customStatement('DETACH DATABASE bk');
      if (await tmp.exists()) await tmp.delete();
    }
    // Las consultas en vivo no ven los cambios hechos con SQL a mano: se avisa.
    db.markTablesUpdated(db.allTables);
  }

  Future<List<String>> _commonColumns(String table) async {
    Future<List<String>> columns(String schema) async =>
        (await db.customSelect('PRAGMA $schema.table_info("$table")').get()).map((r) => r.read<String>('name')).toList();
    final backup = (await columns('bk')).toSet();
    return [for (final c in await columns('main')) if (backup.contains(c)) c];
  }

  String _escape(String path) => path.replaceAll("'", "''");
}
