// WH-019 (owner decision 2026-10-26): `expectedVersion` is honoured by EVERY
// document command, and it is judged before the command does anything else.
// A decision taken on a stale read is refused with `409 stale` (+ the current
// version) and leaves the document, the stock and the ledgers untouched.
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', cost: 10);
    milk = await h.product('MILK', trackExpiry: true);
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
  });
  tearDown(() => h.dispose());

  Future<WhReply> post(String path, int user, [Object? body]) => h.call('POST', path, user: user, body: body ?? {});

  Future<int> version(String path) async {
    final r = await h.call('GET', path, user: h.keeper);
    expect(r.status, 200, reason: r.text);
    return ((r.json['docs'] as List).single as Map)['version'] as int;
  }

  Future<String> stateOf(String gid) async =>
      '${(await h.db.customSelect('SELECT state FROM wh_mobile_docs WHERE global_id = ?', variables: [Variable<String>(gid)]).getSingle()).data['state']}';

  group('vouchers', () {
    Future<void> voucher(String gid, String qty) async {
      final r = await post('/api/m1/wh/vouchers', h.keeper, {
        'globalId': gid, 'type': 'out', 'warehouseId': h.a1, 'reason': 'damaged in aisle',
        'lines': [{'lineGlobalId': 'vline-$gid', 'productId': rice, 'quantity': qty}],
      });
      expect(r.status, 200, reason: r.text);
    }

    test('a stale version is refused BEFORE the stock effect; the right one posts', () async {
      await voucher('voucher-0001', '3');
      final v = await version('/api/m1/wh/vouchers');
      final stale = await post('/api/m1/wh/vouchers/voucher-0001/approve', h.supervisor, {'expectedVersion': v + 5});
      expect(stale.status, 409, reason: stale.text);
      expect(stale.error, 'stale');
      expect(stale.json['currentVersion'], v);
      expect(await stateOf('voucher-0001'), 'pending');
      expect(await h.stock(rice, h.a1), 10);

      final ok = await post('/api/m1/wh/vouchers/voucher-0001/approve', h.supervisor, {'expectedVersion': v});
      expect(ok.status, 200, reason: ok.text);
      expect(await h.stock(rice, h.a1), 7);
    });

    test('stale wins over a different refusal: an unpostable voucher with an old version says stale', () async {
      await voucher('voucher-0002', '50'); // more than the 10 in stock
      final v = await version('/api/m1/wh/vouchers');
      final stale = await post('/api/m1/wh/vouchers/voucher-0002/reject', h.supervisor, {'expectedVersion': v + 1});
      expect(stale.error, 'stale');
      expect(await stateOf('voucher-0002'), 'pending');
      final reject = await post('/api/m1/wh/vouchers/voucher-0002/reject', h.supervisor, {'expectedVersion': v});
      expect(reject.status, 200, reason: reject.text);
      expect(await stateOf('voucher-0002'), 'rejected');
    });
  });

  group('transfers', () {
    setUp(() async {
      final req = await post('/api/m1/wh/transfers', h.keeper, {
        'globalId': 'transfer-ver-1', 'fromWarehouseId': h.a1, 'toWarehouseId': h.a2,
        'lines': [{'lineGlobalId': 'tline-ver-1', 'productId': rice, 'quantity': '4'}],
      });
      expect(req.status, 200, reason: req.text);
    });

    test('every step refuses an old version; a command built on the version it read goes through', () async {
      final v1 = await version('/api/m1/wh/transfers');
      expect((await post('/api/m1/wh/transfers/transfer-ver-1/approve', h.supervisor, {'expectedVersion': v1 - 1})).error, 'stale');
      expect(await stateOf('transfer-ver-1'), 'requested');
      expect((await post('/api/m1/wh/transfers/transfer-ver-1/approve', h.supervisor, {'expectedVersion': v1})).status, 200);

      final v2 = await version('/api/m1/wh/transfers');
      expect(v2, greaterThan(v1));
      // the keeper still holds the OLD version when he dispatches
      final old = await post('/api/m1/wh/transfers/transfer-ver-1/dispatch', h.keeper, {'expectedVersion': v1});
      expect(old.status, 409, reason: old.text);
      expect(old.error, 'stale');
      expect(old.json['currentVersion'], v2);
      expect(await h.stock(rice, h.a1), 10, reason: 'nothing left the source');
      expect((await post('/api/m1/wh/transfers/transfer-ver-1/dispatch', h.keeper, {'expectedVersion': v2})).status, 200);
      expect(await h.stock(rice, h.a1), 6);

      final v3 = await version('/api/m1/wh/transfers');
      final lines = {'lines': [{'lineGlobalId': 'tline-ver-1', 'received': '4', 'damaged': '0'}]};
      final stale = await post('/api/m1/wh/transfers/transfer-ver-1/receive', h.supervisor2, {...lines, 'expectedVersion': v3 - 1});
      expect(stale.error, 'stale');
      expect(await h.stock(rice, h.a2), 0);
      expect((await post('/api/m1/wh/transfers/transfer-ver-1/receive', h.supervisor2, {...lines, 'expectedVersion': v3})).status, 200);
      expect(await h.stock(rice, h.a2), 4);
    });

    test('without expectedVersion the command still works (the state machine and the row version guard it)', () async {
      expect((await post('/api/m1/wh/transfers/transfer-ver-1/approve', h.supervisor)).status, 200);
    });
  });

  group('receipts', () {
    test('conversion with a stale version posts nothing: no invoice, no stock', () async {
      final po = await h.purchaseOrder(h.a1, {milk: 10});
      await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: {
        'globalId': 'doc-ver-0001',
        'lines': [{'lineGlobalId': 'line-ver-0001', 'productId': milk, 'quantity': '6', 'condition': 'ok', 'batchNumber': 'L1', 'expiryDate': '2027-01-31'}],
      });
      final sub = await h.call('POST', '/api/m1/wh/receipts/doc-ver-0001/submit', user: h.clerk);
      expect(sub.status, 200, reason: sub.text);
      final v = (sub.json['receipt'] as Map)['version'] as int;

      final stale = await h.call('POST', '/api/m1/wh/receipts/doc-ver-0001/convert', user: h.admin, body: {'expectedVersion': v - 1});
      expect(stale.status, 409, reason: stale.text);
      expect(stale.error, 'stale');
      expect(await h.db.select(h.db.purchaseInvoices).get(), isEmpty);
      expect(await h.stock(milk, h.a1), 0);
      expect(await stateOf('doc-ver-0001'), 'submitted');

      final ok = await h.call('POST', '/api/m1/wh/receipts/doc-ver-0001/convert', user: h.admin, body: {'expectedVersion': v});
      expect(ok.status, 200, reason: ok.text);
      expect(await h.stock(milk, h.a1), 6);
      expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));
    });
  });

  group('approvals inbox', () {
    test('every item that can be decided carries the version to decide on', () async {
      await post('/api/m1/wh/vouchers', h.keeper, {
        'globalId': 'voucher-inbox-1', 'type': 'out', 'warehouseId': h.a1, 'reason': 'damaged in aisle',
        'lines': [{'lineGlobalId': 'vline-inbox-1', 'productId': rice, 'quantity': '1'}],
      });
      final r = await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor);
      final item = (r.json['approvals'] as List).cast<Map>().singleWhere((a) => a['type'] == 'voucher');
      expect(item['version'], await version('/api/m1/wh/vouchers'));
    });
  });
}
