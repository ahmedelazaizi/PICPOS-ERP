// WH-006 on PostgreSQL: the stock pre-check and the PO `received_quantity`
// write are race-free (row lock before the read; one conditional UPDATE).
// The two-connection proof of the row lock lives in wh_two_connection_pg_test.dart.
// Also runs the blind-count SQL (CAST of ref_id) on real PostgreSQL.
@Tags(['pg'])
library;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_blind.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_doc_store.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_stock_guard.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late int product, warehouse, poId, itemId;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    final db = fx.db;
    await db.ensureWhMobileDocsSchema();
    warehouse = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'PG-W'));
    product = await db.insertProduct(ProductsCompanion.insert(
      code: 'PGP', name: 'PG item', salePrice: const Value(20.0), costPrice: const Value(10.0),
      trackInventory: const Value(true),
    ));
    final supplier = await db.into(db.parties).insert(PartiesCompanion.insert(name: 'PG-S', isSupplier: const Value(true)));
    poId = await db.createPurchaseOrder(
      supplierId: supplier,
      warehouseId: warehouse,
      orderDate: DateTime(2026, 9, 1),
      items: [PurchaseOrderItemsCompanion.insert(orderId: 0, productId: product, quantity: 12, unitCost: 40, total: 480)],
    );
    itemId = (await db.getPurchaseOrderItems(poId)).single.id;
  });
  tearDownAll(() => fx.tearDown());

  test('two concurrent receipts of 6 against a line of 12 add up to 12 (no lost update)', () async {
    final r = await Future.wait([
      addReceivedQuantity(fx.db, itemId, 6, 12),
      addReceivedQuantity(fx.db, itemId, 6, 12),
    ]);
    expect(r, [true, true]);
    expect((await fx.db.getPurchaseOrderItems(poId)).single.receivedQuantity, 12);
  });

  test('a third concurrent receipt over the allowed quantity is refused and changes nothing', () async {
    final r = await Future.wait([
      addReceivedQuantity(fx.db, itemId, 1, 12),
      addReceivedQuantity(fx.db, itemId, 1, 12),
    ]);
    expect(r, [false, false]);
    expect((await fx.db.getPurchaseOrderItems(poId)).single.receivedQuantity, 12);
  });

  test('the blind-count SQL (isCountingItem) runs on PostgreSQL', () async {
    expect(await isCountingItem(fx.db, 1, product, warehouse), isFalse);
  });

  test('WH-009: with NON-NUMERIC ref_id rows in the table (transfer gids, PO ids) the blind-count SQL still runs and finds the counter', () async {
    final db = fx.db;
    final store = WhDocStore(db);
    await db.adjustStock(productId: product, warehouseId: warehouse, quantity: 3, type: 'purchase', unitCost: 10);
    final plan = await db.into(db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: warehouse));
    final task = await db.generateCycleCountTask(planId: plan, warehouseId: warehouse, productsPerTask: 20);
    // rows whose ref_id is not an integer: a transfer gid, a free text, a PO id
    for (final ref in ['0191-abcd-not-a-number', 'PO/2026/x', '77']) {
      await store.create(kind: 'transfer', state: 'requested', warehouseId: warehouse, createdBy: 5, deviceId: 'd', refType: 'purchase_order', refId: ref);
    }
    await store.create(
        kind: 'count_submission', state: 'draft', warehouseId: warehouse, createdBy: 9, deviceId: 'd',
        refType: 'cycle_count_task', refId: '$task');
    expect(await isCountingItem(db, 9, product, warehouse), isTrue);
    expect(await isCountingItem(db, 5, product, warehouse), isFalse);
  });
}
