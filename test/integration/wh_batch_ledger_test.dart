// WH-020 (owner decision 2026-10-26): one batch ledger for every warehouse
// document that issues stock.
//   * a voucher `out` / `damage` consumes the product's lots whether or not the
//     product is expiry-tracked (it used to touch only trackExpiry products);
//   * a cycle-count SHORTAGE takes the missing quantity out of the lots in the
//     same issue order (FEFO for expiry goods, FIFO otherwise), expired lots
//     included: a loss is a fact, not an issue the expiry rules may refuse;
//   * a SURPLUS does not invent a lot (no batch number, no expiry to record):
//     the lots stay as recorded.
// Assertions are on the lot rows and the stock, never on messages.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk, taskId;

  Future<void> lot(int product, String no, double qty, DateTime expiry) => h.db.insertBatch(ProductBatchesCompanion.insert(
        productId: product, warehouseId: h.a1, batchNumber: no, expiryDate: expiry,
        quantity: Value(qty), initialQuantity: Value(qty), unitCost: const Value(10),
      ));

  Future<Map<String, double>> lots(int product) async => {
        for (final b in await (h.db.select(h.db.productBatches)..where((x) => x.productId.equals(product))).get())
          b.batchNumber: b.quantity,
      };

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', barcode: '6221234567890');
    milk = await h.product('MILK', trackExpiry: true, barcode: '6229999999999');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await lot(rice, 'R1', 10, DateTime(2030, 1, 1));
    await lot(milk, 'M-EARLY', 3, DateTime(2031, 1, 1));
    await lot(milk, 'M-LATE', 7, DateTime(2032, 1, 1));
  });
  tearDown(() => h.dispose());

  group('count settlement', () {
    setUp(() async {
      final plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: h.a1));
      taskId = await h.db.generateCycleCountTask(planId: plan, warehouseId: h.a1, productsPerTask: 20);
    });

    Future<void> countAndApprove(Map<int, String> first, Map<int, String> second) async {
      Future<void> pass(int user, String doc, Map<int, String> qty) async {
        final e = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: user, body: {
          'globalId': doc,
          'entries': [for (final x in qty.entries) {'lineGlobalId': 'l-$doc-${x.key}', 'productId': x.key, 'quantity': x.value}],
        });
        expect(e.status, 200, reason: e.text);
        final s = await h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: user, body: {'globalId': doc});
        expect(s.status, 200, reason: s.text);
      }

      await pass(h.clerk, 'doc-count-0001', first);
      await pass(h.clerk2, 'doc-count-0002', second);
      final a = await h.call('POST', '/api/m1/wh/counts/$taskId/approve', user: h.supervisor, body: {});
      expect(a.status, 200, reason: a.text);
    }

    test('a shortage on a plain product reduces its lot', () async {
      await countAndApprove({rice: '8', milk: '10'}, {rice: '8', milk: '10'});
      expect(await h.stock(rice, h.a1), 8);
      expect(await lots(rice), {'R1': 8});
    });

    test('a shortage on an expiry product leaves the earliest lot first', () async {
      await countAndApprove({rice: '10', milk: '5'}, {rice: '10', milk: '5'});
      expect(await h.stock(milk, h.a1), 5);
      expect(await lots(milk), {'M-EARLY': 0, 'M-LATE': 5}, reason: '5 missing: the 3 of the early lot, then 2 of the late one');
      final early = await (h.db.select(h.db.productBatches)..where((b) => b.batchNumber.equals('M-EARLY'))).getSingle();
      expect(early.status, 'depleted');
    });

    test('a shortage is never refused for expiry rules', () async {
      await h.db.setSetting('warehouse_bins_enabled', 'true');
      await h.db.setSetting('block_issue_without_valid_batch', 'true');
      await (h.db.update(h.db.productBatches)..where((b) => b.batchNumber.equals('M-EARLY'))).write(
          ProductBatchesCompanion(expiryDate: Value(DateTime(2020, 1, 1)))); // expired lot
      await countAndApprove({rice: '10', milk: '0'}, {rice: '10', milk: '0'});
      expect(await h.stock(milk, h.a1), 0);
      expect((await lots(milk)).values.fold<double>(0, (a, b) => a + b), 0);
      final t = await (h.db.select(h.db.cycleCountTasks)..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, 'completed', reason: 'the settlement is posted, not blocked by the lots');
    });

    test('a surplus invents no lot: the lots stay as recorded', () async {
      await countAndApprove({rice: '12', milk: '10'}, {rice: '12', milk: '10'});
      expect(await h.stock(rice, h.a1), 12);
      expect(await lots(rice), {'R1': 10});
      expect(await h.db.select(h.db.productBatches).get(), hasLength(3));
    });

    test('lots do not exceed the stock after a mixed settlement (invariant)', () async {
      await countAndApprove({rice: '6', milk: '9'}, {rice: '6', milk: '9'});
      for (final p in [rice, milk]) {
        final sum = (await lots(p)).values.fold<double>(0, (a, b) => a + b);
        expect(sum, lessThanOrEqualTo(await h.stock(p, h.a1) + 1e-9), reason: 'product $p');
      }
    });
  });

  group('vouchers', () {
    Future<void> voucherOut(String gid, int product, String qty, {String type = 'out'}) async {
      final c = await h.call('POST', '/api/m1/wh/vouchers', user: h.keeper, body: {
        'globalId': gid, 'type': type, 'warehouseId': h.a1, 'reason': 'damaged in aisle',
        'lines': [{'lineGlobalId': 'vline-$gid', 'productId': product, 'quantity': qty}],
      });
      expect(c.status, 200, reason: c.text);
      final a = await h.call('POST', '/api/m1/wh/vouchers/$gid/approve', user: h.supervisor);
      expect(a.status, 200, reason: a.text);
    }

    test('an out voucher of a plain product takes the quantity from its lot', () async {
      await voucherOut('voucher-0001', rice, '4');
      expect(await h.stock(rice, h.a1), 6);
      expect(await lots(rice), {'R1': 6});
    });

    test('a damage voucher does the same', () async {
      await voucherOut('voucher-0002', rice, '2', type: 'damage');
      expect(await h.stock(rice, h.a1), 8);
      expect(await lots(rice), {'R1': 8});
    });

    test('an expiry product still leaves FEFO (unchanged)', () async {
      await voucherOut('voucher-0003', milk, '4');
      expect(await lots(milk), {'M-EARLY': 0, 'M-LATE': 6});
    });

    test('a plain product with no lots at all is issued normally', () async {
      final salt = await h.product('SALT');
      await h.db.adjustStock(productId: salt, warehouseId: h.a1, quantity: 5, type: 'purchase', unitCost: 10);
      await voucherOut('voucher-0004', salt, '2');
      expect(await h.stock(salt, h.a1), 3);
      expect(await lots(salt), isEmpty);
    });
  });
}