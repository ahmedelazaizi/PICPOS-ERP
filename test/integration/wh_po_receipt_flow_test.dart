// Plan 2026-10-23 W2: receiving against purchase orders from the phone.
//   * a receipt is a DOCUMENT: no stock and no ledger entry until the accountant
//     converts it (R-A), then once, with accepted quantities only;
//   * every write is idempotent by X-Idempotency-Key (replay / conflict);
//   * over-receipt refused, batch/expiry enforced, scope enforced.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int milk, rice;

  setUp(() async {
    h = await WhHarness.create();
    milk = await h.product('MILK', trackExpiry: true);
    rice = await h.product('RICE');
  });
  tearDown(() => h.dispose());

  Map<String, Object?> line(String gid, int pid, String qty, {String cond = 'ok', String? batch, String? exp}) => {
        'lineGlobalId': gid,
        'productId': pid,
        'quantity': qty,
        'condition': cond,
        'batchNumber': ?batch,
        'expiryDate': ?exp,
      };

  Future<WhReply> draft(int user, int po, String gid, List<Map<String, Object?>> lines, {String? key}) =>
      h.call('POST', '/api/m1/wh/po/$po/receipts', user: user, key: key, body: {'globalId': gid, 'lines': lines});

  group('reading POs', () {
    test('lists open POs of the allowed warehouses with ordered/received and no cost', () async {
      final mine = await h.purchaseOrder(h.a1, {rice: 10});
      await h.purchaseOrder(h.b1, {rice: 5});
      await h.purchaseOrder(h.a1, {rice: 3}, status: 'draft');
      final r = await h.call('GET', '/api/m1/wh/po', user: h.clerk);
      expect(r.status, 200);
      final orders = (r.json['orders'] as List).cast<Map>();
      expect(orders.map((o) => o['id']), [mine], reason: 'B-branch PO and draft PO are invisible');
      final item = (orders.single['items'] as List).single as Map;
      expect(item['ordered'], '10');
      expect(item['received'], '0');
      expect(r.text.toLowerCase(), isNot(contains('cost')));
    });

    test('a warehouse outside the caller scope is refused, not silently empty', () async {
      final r = await h.call('GET', '/api/m1/wh/po?warehouse=${h.b1}', user: h.clerk);
      expect(r.status, 403);
      expect(r.error, 'warehouse_forbidden');
    });

    test('a user without goods_receipt_mobile is refused', () async {
      final cashier = await h.db.into(h.db.users).insert(UsersCompanion.insert(
          username: 'cash', passwordHash: 'x', displayName: 'c',
          roleId: await _roleId(h, 'كاشير')));
      final r = await h.call('GET', '/api/m1/wh/po', user: cashier);
      expect(r.status, 403);
    });
  });

  group('draft + submit', () {
    test('creates a draft; a replay with the same key and body is answered from the log', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      final lines = [line('line-0001-a', rice, '4')];
      final a = await draft(h.clerk, po, 'doc-00000001', lines, key: 'cmd-key-0001');
      final b = await draft(h.clerk, po, 'doc-00000001', lines, key: 'cmd-key-0001');
      expect(a.status, 200);
      expect(b.json['replayed'], isTrue);
      expect(((b.json['receipt'] as Map)['lines'] as List), hasLength(1));
    });

    test('same key with a different body is 409 idempotency_conflict', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '4')], key: 'cmd-key-0002');
      final c = await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '5')], key: 'cmd-key-0002');
      expect(c.status, 409);
      expect(c.error, 'idempotency_conflict');
    });

    test('a write without an idempotency key is refused', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      final r = await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk,
          headers: {'x-idempotency-key': ''}, body: {'globalId': 'doc-00000001', 'lines': [line('line-0001-a', rice, '1')]});
      expect(r.status, 400);
      expect(r.error, 'idempotency_key_required');
    });

    test('the same line id in a later command is not duplicated', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '4')]);
      final r = await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '4'), line('line-0002-a', rice, '1')]);
      expect(((r.json['receipt'] as Map)['lines'] as List), hasLength(2));
    });

    test('expiry-tracked item needs batch and expiry; unknown product refused', () async {
      final po = await h.purchaseOrder(h.a1, {milk: 10});
      final r = await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', milk, '2')]);
      expect(r.status, 422);
      expect(r.error, 'batch_required');
      final stranger = await draft(h.clerk, po, 'doc-00000002', [line('line-0002-a', rice, '2')]);
      expect(stranger.error, 'product_not_in_order');
    });

    test('submit moves received_quantity, but stock and invoices stay untouched (R-A)', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '6'), line('line-0002-a', rice, '1', cond: 'damaged')]);
      final s = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
      expect(s.status, 200);
      expect((s.json['receipt'] as Map)['state'], 'submitted');
      final item = (await h.db.getPurchaseOrderItems(po)).single;
      expect(item.receivedQuantity, 7);
      expect(await h.stock(rice, h.a1), 0);
      expect(await h.db.select(h.db.purchaseInvoices).get(), isEmpty);
    });

    test('only the author submits; a second submit is an invalid transition', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '6')]);
      expect((await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk2)).error, 'not_owner');
      await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
      final again = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
      expect(again.status, 409);
    });

    test('over-receipt is refused and received_quantity is not touched', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '11')]);
      final s = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
      expect(s.status, 409);
      expect(s.error, 'over_receipt');
      expect((await h.db.getPurchaseOrderItems(po)).single.receivedQuantity, 0);
    });

    test('a phone of another branch cannot receive this branch PO', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      final r = await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, device: 'wh-B',
          body: {'globalId': 'doc-00000001', 'lines': [line('line-0001-a', rice, '1')]});
      expect(r.status, 403);
    });
  });

  group('convert (accountant)', () {
    test('clerk cannot convert; admin converts once with accepted quantities only', () async {
      final po = await h.purchaseOrder(h.a1, {milk: 10});
      await draft(h.clerk, po, 'doc-00000001', [
        line('line-0001-a', milk, '6', batch: 'L1', exp: '2027-01-31'),
        line('line-0002-a', milk, '1', cond: 'damaged'),
      ]);
      await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);

      expect((await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.clerk)).status, 403);

      final c = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.admin, key: 'convert-key-1');
      expect(c.status, 200, reason: c.text);
      expect(await h.stock(milk, h.a1), 6, reason: 'damaged goods do not enter stock');
      final batches = await h.db.select(h.db.productBatches).get();
      expect(batches.single.batchNumber, 'L1');
      expect(batches.single.quantity, 6);
      expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));

      final replay = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.admin, key: 'convert-key-1');
      expect(replay.json['replayed'], isTrue);
      final second = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.admin);
      expect(second.status, 409);
      expect(await h.stock(milk, h.a1), 6, reason: 'neither replay nor retry may post twice');
      expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));
    });

    test('a partial receipt keeps the PO open; the rest closes it', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '4')]);
      await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
      final first = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.admin);
      expect(first.json['orderClosed'], isFalse);
      expect((await h.db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNull);

      await draft(h.clerk, po, 'doc-00000002', [line('line-0002-a', rice, '6')]);
      await h.call('POST', '/api/m1/wh/receipts/doc-00000002/submit', user: h.clerk);
      final last = await h.call('POST', '/api/m1/wh/receipts/doc-00000002/convert', user: h.admin);
      expect(last.json['orderClosed'], isTrue);
      expect(await h.stock(rice, h.a1), 10);
      expect((await h.db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNotNull);
    });

    test('lists my receipts by state', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 10});
      await draft(h.clerk, po, 'doc-00000001', [line('line-0001-a', rice, '4')]);
      final mine = await h.call('GET', '/api/m1/wh/receipts?state=draft', user: h.clerk);
      expect((mine.json['receipts'] as List), hasLength(1));
      final theirs = await h.call('GET', '/api/m1/wh/receipts?state=draft', user: h.clerk2);
      expect((theirs.json['receipts'] as List), isEmpty);
    });
  });
}

Future<Value<int>> _roleId(WhHarness h, String name) async {
  final r = await (h.db.select(h.db.roles)..where((x) => x.name.equals(name))).getSingle();
  return Value(r.id);
}
