// WH-006 on PostgreSQL: the stock pre-check and the PO `received_quantity`
// write are race-free (row lock before the read; one conditional UPDATE).
// Also runs the blind-count SQL (CAST of ref_id) on real PostgreSQL.
@Tags(['pg'])
library;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_blind.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
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

  test('two concurrent withdrawals of 8 from 10 with negative sales enabled: one wins, stock never negative', () async {
    final db = fx.db;
    await db.setSetting('enable_negative_sales', 'true');
    await db.adjustStock(productId: product, warehouseId: warehouse, quantity: 10, type: 'purchase', unitCost: 10);
    Future<bool> withdraw() async {
      try {
        await db.transaction(() async {
          await requireCoveredStock(db, productId: product, warehouseId: warehouse, qty: 8, viewerId: 1);
          await db.adjustStock(
              productId: product, warehouseId: warehouse, quantity: -8, type: 'transfer_out', unitCost: 10);
        });
        return true;
      } on WhError {
        return false;
      }
    }

    final r = await Future.wait([withdraw(), withdraw()]);
    expect(r.where((x) => x).length, 1, reason: 'exactly one withdrawal is covered: $r');
    final bal = await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(product) & b.warehouseId.equals(warehouse)))
        .getSingle();
    expect(bal.quantity, greaterThanOrEqualTo(0));
    expect(bal.quantity, 2);
  });

  test('the blind-count SQL (isCountingItem) runs on PostgreSQL', () async {
    expect(await isCountingItem(fx.db, 1, product, warehouse), isFalse);
  });
}
