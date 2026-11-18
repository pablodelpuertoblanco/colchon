import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text.dart';
import '../../domain/models.dart';
import '../database.dart';
import 'transaction_repository.dart';

/// Lista de la compra con sus contadores y totales.
class ShoppingListView {
  const ShoppingListView({
    required this.list,
    required this.itemCount,
    required this.checkedCount,
    required this.estimatedCents,
    this.spentCents,
  });
  final ShoppingListRow list;
  final int itemCount;
  final int checkedCount;
  final int estimatedCents;

  /// Importe del gasto creado al finalizar (si está completada).
  final int? spentCents;

  bool get isCompleted => list.status == ShoppingListStatus.completed;
}

/// Producto usado antes, para autocompletar.
class FrequentProduct {
  const FrequentProduct({required this.name, required this.unit, this.categoryId, this.unitPriceCents});
  final String name;
  final ItemUnit unit;
  final String? categoryId;
  final int? unitPriceCents;
}

/// Datos del formulario de un producto.
class ItemDraft {
  const ItemDraft({
    required this.name,
    this.quantityMilli = 1000,
    this.unit = ItemUnit.ud,
    this.estUnitPriceCents,
    this.realUnitPriceCents,
    this.categoryId,
  });
  final String name;
  final int quantityMilli;
  final ItemUnit unit;
  final int? estUnitPriceCents;
  final int? realUnitPriceCents;
  final String? categoryId;
}

extension ShoppingItemMath on ShoppingItemRow {
  int? get estimatedLineCents =>
      estUnitPriceCents == null ? null : Money.lineTotal(quantityMilli, estUnitPriceCents!);

  /// Precio real si se anotó; si no, el estimado.
  int? get bestLineCents {
    final price = realUnitPriceCents ?? estUnitPriceCents;
    return price == null ? null : Money.lineTotal(quantityMilli, price);
  }
}

/// Listas de la compra y sus productos.
class ShoppingRepository {
  ShoppingRepository(this.db);
  final AppDatabase db;

  static const _listSql = '''
SELECT l.*,
  (SELECT COUNT(*) FROM shopping_items i WHERE i.list_id = l.id AND i.deleted_at IS NULL) AS item_count,
  (SELECT COUNT(*) FROM shopping_items i WHERE i.list_id = l.id AND i.deleted_at IS NULL AND i.is_checked = 1) AS checked_count,
  (SELECT COALESCE(SUM((i.quantity_milli * i.est_unit_price_cents + 500) / 1000), 0)
     FROM shopping_items i WHERE i.list_id = l.id AND i.deleted_at IS NULL AND i.est_unit_price_cents IS NOT NULL) AS est_total,
  (SELECT t.amount_cents FROM transactions t WHERE t.id = l.transaction_id AND t.deleted_at IS NULL) AS spent
FROM shopping_lists l
''';

  ShoppingListView _view(QueryRow r) => ShoppingListView(
        list: db.shoppingLists.map(r.data),
        itemCount: r.read<int>('item_count'),
        checkedCount: r.read<int>('checked_count'),
        estimatedCents: r.read<int>('est_total'),
        spentCents: r.readNullable<int>('spent'),
      );

  Set<ResultSetImplementation<dynamic, dynamic>> get _reads => {db.shoppingLists, db.shoppingItems, db.transactions};

  Stream<List<ShoppingListView>> watchLists() {
    return db
        .customSelect('$_listSql WHERE l.deleted_at IS NULL ORDER BY l.status, l.updated_at DESC', readsFrom: _reads)
        .watch()
        .map((rows) => rows.map(_view).toList());
  }

  Stream<ShoppingListView?> watchList(String id) {
    return db
        .customSelect('$_listSql WHERE l.id = ? AND l.deleted_at IS NULL',
            variables: [Variable.withString(id)], readsFrom: _reads)
        .watchSingleOrNull()
        .map((r) => r == null ? null : _view(r));
  }

  Stream<List<ShoppingItemRow>> watchItems(String listId) {
    final q = db.select(db.shoppingItems)
      ..where((i) => i.listId.equals(listId) & i.deletedAt.isNull())
      ..orderBy([
        (i) => OrderingTerm(expression: i.sortOrder),
        (i) => OrderingTerm(expression: i.createdAt),
      ]);
    return q.watch();
  }

  Future<String> createList(String name) async {
    final now = Dates.nowIso();
    final id = newId();
    await db.into(db.shoppingLists).insert(ShoppingListsCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          name: name.trim(),
        ));
    return id;
  }

  Future<void> renameList(String id, String name) {
    return (db.update(db.shoppingLists)..where((l) => l.id.equals(id)))
        .write(ShoppingListsCompanion(name: Value(name.trim()), updatedAt: Value(Dates.nowIso())));
  }

  Future<void> deleteList(String id) {
    final now = Dates.nowIso();
    return (db.update(db.shoppingLists)..where((l) => l.id.equals(id)))
        .write(ShoppingListsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  /// Copia una lista (por ejemplo, la compra de la semana pasada).
  Future<String> duplicateList(String id, {String? newName, bool onlyUnchecked = false}) {
    return db.transaction(() async {
      final list = await (db.select(db.shoppingLists)..where((l) => l.id.equals(id))).getSingle();
      final items = await (db.select(db.shoppingItems)
            ..where((i) => i.listId.equals(id) & i.deletedAt.isNull())
            ..orderBy([(i) => OrderingTerm(expression: i.sortOrder)]))
          .get();
      final newListId = await createList(newName ?? list.name);
      final now = Dates.nowIso();
      var order = 0;
      for (final it in items) {
        if (onlyUnchecked && it.isChecked) continue;
        await db.into(db.shoppingItems).insert(ShoppingItemsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              listId: newListId,
              name: it.name,
              quantityMilli: Value(it.quantityMilli),
              unit: Value(it.unit),
              // El último precio real pasa a ser la nueva estimación.
              estUnitPriceCents: Value(it.realUnitPriceCents ?? it.estUnitPriceCents),
              categoryId: Value(it.categoryId),
              sortOrder: Value(order++),
            ));
      }
      return newListId;
    });
  }

  Future<void> addItem(String listId, ItemDraft d) async {
    final now = Dates.nowIso();
    final order = await db.customSelect(
      'SELECT COALESCE(MAX(sort_order), 0) AS m FROM shopping_items WHERE list_id = ?',
      variables: [Variable.withString(listId)],
    ).getSingle();
    await db.into(db.shoppingItems).insert(ShoppingItemsCompanion.insert(
          id: newId(),
          createdAt: now,
          updatedAt: now,
          listId: listId,
          name: d.name.trim(),
          quantityMilli: Value(d.quantityMilli),
          unit: Value(d.unit),
          estUnitPriceCents: Value(d.estUnitPriceCents),
          realUnitPriceCents: Value(d.realUnitPriceCents),
          categoryId: Value(d.categoryId),
          sortOrder: Value(order.read<int>('m') + 1),
        ));
    await _touchList(listId);
  }

  Future<void> updateItem(String id, ItemDraft d) {
    return (db.update(db.shoppingItems)..where((i) => i.id.equals(id))).write(ShoppingItemsCompanion(
      name: Value(d.name.trim()),
      quantityMilli: Value(d.quantityMilli),
      unit: Value(d.unit),
      estUnitPriceCents: Value(d.estUnitPriceCents),
      realUnitPriceCents: Value(d.realUnitPriceCents),
      categoryId: Value(d.categoryId),
      updatedAt: Value(Dates.nowIso()),
    ));
  }

  Future<void> setChecked(String id, bool checked) {
    final now = Dates.nowIso();
    return (db.update(db.shoppingItems)..where((i) => i.id.equals(id))).write(ShoppingItemsCompanion(
      isChecked: Value(checked),
      checkedAt: Value(checked ? now : null),
      updatedAt: Value(now),
    ));
  }

  Future<void> deleteItem(String id) {
    final now = Dates.nowIso();
    return (db.update(db.shoppingItems)..where((i) => i.id.equals(id)))
        .write(ShoppingItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> restoreItem(String id) {
    return (db.update(db.shoppingItems)..where((i) => i.id.equals(id)))
        .write(ShoppingItemsCompanion(deletedAt: const Value(null), updatedAt: Value(Dates.nowIso())));
  }

  Future<void> _touchList(String listId) {
    return (db.update(db.shoppingLists)..where((l) => l.id.equals(listId)))
        .write(ShoppingListsCompanion(updatedAt: Value(Dates.nowIso())));
  }

  /// Productos usados antes, los más frecuentes primero. Para cada nombre se
  /// toman los datos de su uso más reciente.
  Future<List<FrequentProduct>> frequentProducts() async {
    final rows = await db.customSelect(
      'SELECT name, unit, category_id, est_unit_price_cents, real_unit_price_cents, '
      'COUNT(*) AS uses, MAX(updated_at) AS last_used '
      'FROM shopping_items WHERE deleted_at IS NULL '
      'GROUP BY lower(name) ORDER BY uses DESC, last_used DESC LIMIT 150',
    ).get();
    return rows
        .map((r) => FrequentProduct(
              name: r.read<String>('name'),
              unit: ItemUnit.values.byName(r.read<String>('unit')),
              categoryId: r.readNullable<String>('category_id'),
              unitPriceCents: r.readNullable<int>('real_unit_price_cents') ?? r.readNullable<int>('est_unit_price_cents'),
            ))
        .toList();
  }

  /// Finaliza la compra: crea el gasto, marca la lista como completada y,
  /// si se pide, pasa lo no comprado a una lista nueva. Todo o nada.
  Future<String> finishList({
    required String listId,
    required int totalCents,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId,
    bool moveUncheckedToNewList = false,
  }) {
    return db.transaction(() async {
      final list = await (db.select(db.shoppingLists)..where((l) => l.id.equals(listId))).getSingle();
      final companion = newTransactionCompanion(TxDraft(
        type: TxType.expense,
        amountCents: totalCents,
        categoryId: categoryId,
        date: date,
        description: 'Compra: ${list.name}',
        paymentMethodId: paymentMethodId,
      ));
      await db.into(db.transactions).insert(companion);
      final now = Dates.nowIso();
      await (db.update(db.shoppingLists)..where((l) => l.id.equals(listId))).write(ShoppingListsCompanion(
        status: const Value(ShoppingListStatus.completed),
        completedAt: Value(now),
        transactionId: Value(companion.id.value),
        updatedAt: Value(now),
      ));
      if (moveUncheckedToNewList) {
        await duplicateList(listId, newName: list.name, onlyUnchecked: true);
      }
      return companion.id.value;
    });
  }
}
