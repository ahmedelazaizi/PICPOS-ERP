// WH-006 + NEW-02 on PostgreSQL with TWO REAL CONNECTIONS (two AppDatabase
// instances, two pools): the previous version ran both "connections" on one
// AppDatabase, which drift serialises, so it passed without any lock.
//
//  * WH-006: A holds the balance row mid-withdrawal while B tries the same one.
//    Without `FOR UPDATE` B reads the stale balance and both withdraw (stock
//    goes negative); with it B waits and then sees the true balance.
//  * NEW-02: two requests with the SAME X-Idempotency-Key race; the loser hits
//    a UNIQUE key. It must answer the stored result as a replay, never a 409.
@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_doc_store.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_scope.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_stock_guard.dart';
import 'package:shelf/shelf.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase dbB;
  late int product, warehouse;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.ensureWhMobileDocsSchema();
    dbB = openExtraPgConnection();
    await dbB.ensureWhMobileDocsSchema();
    warehouse = await fx.db.into(fx.db.warehouses).insert(WarehousesCompanion.insert(name: 'PG-W'));
    product = await fx.db.insertProduct(ProductsCompanion.insert(
      code: 'PGP', name: 'PG item', salePrice: const Value(20.0), costPrice: const Value(10.0),
      trackInventory: const Value(true),
    ));
  });
  tearDownAll(() async {
    await dbB.close();
    await fx.tearDown();
  });

  test('WH-006: two connections withdrawing 8 of 10 - the second waits on the row lock, '
      'sees the true balance and is refused (stock never negative)', () async {
    final db = fx.db;
    await db.setSetting('enable_negative_sales', 'true');
    await db.adjustStock(productId: product, warehouseId: warehouse, quantity: 10, type: 'purchase', unitCost: 10);
    final aChecked = Completer<void>();
    Future<bool> withdraw(AppDatabase d, {Future<void> Function()? pauseAfterCheck}) async {
      try {
        await d.transaction(() async {
          await requireCoveredStock(d, productId: product, warehouseId: warehouse, qty: 8, viewerId: 1);
          await pauseAfterCheck?.call();
          await d.adjustStock(
              productId: product, warehouseId: warehouse, quantity: -8, type: 'transfer_out', unitCost: 10);
        });
        return true;
      } on WhError {
        return false;
      }
    }

    final a = withdraw(db, pauseAfterCheck: () async {
      aChecked.complete();
      // B is now trying to read the same balance on ITS connection.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await aChecked.future;
    final b = withdraw(dbB);
    final r = await Future.wait([a, b]);
    expect(r, [true, false], reason: 'A won, B was refused after waiting for the lock: $r');
    final bal = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(product) & x.warehouseId.equals(warehouse)))
        .getSingle();
    expect(bal.quantity, 2);
  });

  test('WH-006: two connections receiving 6 + 6 against a line of 12 add up to 12; a third is refused', () async {
    final db = fx.db;
    final supplier = await db.into(db.parties).insert(PartiesCompanion.insert(name: 'PG-S', isSupplier: const Value(true)));
    final po = await db.createPurchaseOrder(
      supplierId: supplier,
      warehouseId: warehouse,
      orderDate: DateTime(2026, 9, 1),
      items: [PurchaseOrderItemsCompanion.insert(orderId: 0, productId: product, quantity: 12, unitCost: 40, total: 480)],
    );
    final item = (await db.getPurchaseOrderItems(po)).single.id;
    final r = await Future.wait([addReceivedQuantity(db, item, 6, 12), addReceivedQuantity(dbB, item, 6, 12)]);
    expect(r, [true, true]);
    expect((await db.getPurchaseOrderItems(po)).single.receivedQuantity, 12);
    final over = await Future.wait([addReceivedQuantity(db, item, 1, 12), addReceivedQuantity(dbB, item, 1, 12)]);
    expect(over, [false, false]);
    expect((await db.getPurchaseOrderItems(po)).single.receivedQuantity, 12);
  });

  test('WH-018: a failing activity-log INSERT does not poison the command transaction (savepoint)', () async {
    final db = fx.db;
    final store = WhDocStore(db);
    final ctx = WhCtx(
      userId: 1, branchId: 1, deviceId: 'phone-1', scope: const WhScope(branchId: 1, warehouses: []),
      request: Request('POST', Uri.parse('http://lan/x'), headers: {'x-idempotency-key': 'key-audit-0001'}),
    );
    await db.customStatement('ALTER TABLE activity_logs RENAME TO activity_logs_off');
    try {
      final out = await store.command(ctx, action: 'create', body: {'a': 2}, effect: () async {
        final doc = await store.create(
            kind: 'voucher', state: 'pending', warehouseId: warehouse, createdBy: 1, deviceId: 'phone-1', gid: 'audit-doc-gid');
        return (docId: doc.id, result: <String, Object?>{'globalId': doc.gid});
      });
      expect(out['globalId'], 'audit-doc-gid');
    } finally {
      await db.customStatement('ALTER TABLE activity_logs_off RENAME TO activity_logs');
    }
    final docs = await db.customSelect("SELECT id FROM wh_mobile_docs WHERE global_id = 'audit-doc-gid'").get();
    final ev = await db.customSelect("SELECT id FROM wh_mobile_doc_events WHERE command_id = 'key-audit-0001'").get();
    expect((docs.length, ev.length), (1, 1), reason: 'the command committed although its log line failed');
  });

  test('NEW-02: the same idempotency key on two connections - one runs, the other '
      'answers the stored result as a replay (no 409, one document, one event)', () async {
    WhCtx ctx() => WhCtx(
          userId: 1,
          branchId: 1,
          deviceId: 'phone-1',
          scope: const WhScope(branchId: 1, warehouses: []),
          request: Request('POST', Uri.parse('http://lan/x'), headers: {'x-idempotency-key': 'key-race-0001'}),
        );
    Future<Map<String, Object?>> run(AppDatabase d) {
      final store = WhDocStore(d);
      return store.command(ctx(), action: 'create', body: {'a': 1}, effect: () async {
        final doc = await store.create(
            kind: 'voucher', state: 'pending', warehouseId: warehouse, createdBy: 1, deviceId: 'phone-1',
            gid: 'race-doc-gid');
        // both are past the replay check before either commits
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return (docId: doc.id, result: <String, Object?>{'globalId': doc.gid});
      });
    }

    final r = await Future.wait([run(fx.db), run(dbB)]);
    expect(r.map((x) => x['globalId']), ['race-doc-gid', 'race-doc-gid']);
    expect(r.where((x) => x['replayed'] == true), hasLength(1), reason: '$r');
    final docs = await fx.db.customSelect("SELECT id FROM wh_mobile_docs WHERE global_id = 'race-doc-gid'").get();
    final events = await fx.db.customSelect("SELECT id FROM wh_mobile_doc_events WHERE command_id = 'key-race-0001'").get();
    expect(docs, hasLength(1));
    expect(events, hasLength(1));
  });
}
