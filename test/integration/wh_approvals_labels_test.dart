// Plan 2026-10-23 W5 (server side) + E-9a fence:
//   * the approvals inbox shows only what the caller may approve (four-eyes);
//   * label data is scoped and carries no cost;
//   * the legacy LAN transfer / adjust routes are unreachable from a warehouse
//     phone (the defective POST /api/inventory/transfer is fenced off).
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/lan_device_route_policy.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', barcode: '6221234567890');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
  });
  tearDown(() => h.dispose());

  Future<void> voucher(int user, String gid) => h.call('POST', '/api/m1/wh/vouchers', user: user, body: {
        'globalId': gid, 'type': 'out', 'warehouseId': h.a1, 'reason': 'r',
        'lines': [{'lineGlobalId': 'l-$gid', 'productId': rice, 'quantity': '1'}],
      }).then((r) => expect(r.status, 200, reason: r.text));

  test('the inbox lists others\' pending work and hides my own', () async {
    await voucher(h.keeper, 'voucher-0001');
    await voucher(h.supervisor, 'voucher-0002');
    await h.call('POST', '/api/m1/wh/transfers', user: h.keeper, body: {
      'globalId': 'transfer-0001', 'fromWarehouseId': h.a1, 'toWarehouseId': h.a2,
      'lines': [{'lineGlobalId': 'tl-0001-a', 'productId': rice, 'quantity': '2'}],
    });
    final r = await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor);
    expect(r.status, 200);
    final refs = (r.json['approvals'] as List).cast<Map>().map((a) => a['ref']).toSet();
    expect(refs, {'voucher-0001', 'transfer-0001'}, reason: 'his own voucher-0002 is excluded');
    expect(r.json['count'], 2);
    final mine = await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor2);
    expect(mine.json['count'], 3, reason: 'a second supervisor sees all three');
  });

  test('a user without stock_adjust_approve gets no inbox', () async {
    expect((await h.call('GET', '/api/m1/wh/approvals', user: h.keeper)).status, 403);
    expect((await h.call('GET', '/api/m1/wh/approvals', user: h.clerk)).status, 403);
  });

  test('an open count that is ready appears for a non-counter approver only', () async {
    final plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: h.a1));
    final task = await h.db.generateCycleCountTask(planId: plan, warehouseId: h.a1, productsPerTask: 5);
    await h.call('POST', '/api/m1/wh/counts/$task/entries', user: h.supervisor, body: {
      'globalId': 'count-doc-0001', 'entries': [{'lineGlobalId': 'cl-0001-a', 'productId': rice, 'quantity': '10'}],
    });
    await h.call('POST', '/api/m1/wh/counts/$task/submit', user: h.supervisor, body: {'globalId': 'count-doc-0001'});
    expect(((await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor)).json['approvals'] as List), isEmpty);
    final other = await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor2);
    expect(((other.json['approvals'] as List).single as Map)['type'], 'count');
  });

  test('labels: item and bin data, no cost, unknown refs refused', () async {
    final item = await h.call('GET', '/api/m1/wh/labels?kind=item&ref=6221234567890', user: h.clerk);
    expect(item.json['barcode'], '6221234567890');
    expect(item.text.toLowerCase(), isNot(contains('cost')));
    expect((await h.call('GET', '/api/m1/wh/labels?kind=item&ref=nope', user: h.clerk)).status, 404);
    final noCode = await h.product('NOBAR');
    expect((await h.call('GET', '/api/m1/wh/labels?kind=item&ref=$noCode', user: h.clerk)).error, 'no_barcode');
    expect((await h.call('GET', '/api/m1/wh/labels?kind=location&ref=BIN-missing', user: h.clerk)).status, 404);
    expect((await h.call('GET', '/api/m1/wh/labels?kind=zzz&ref=1', user: h.clerk)).status, 400);
  });

  group('the legacy LAN stock routes are fenced from a warehouse phone (plan E-9a)', () {
    for (final (method, path) in [
      ('POST', '/api/inventory/transfer'),
      ('POST', '/api/inventory/adjust'),
      ('POST', '/api/inventory/bond'),
      ('POST', '/api/purchase-orders'),
      ('GET', '/api/purchase-orders'),
    ]) {
      test('$method $path -> 403 device_scope', () async {
        final r = await h.call(method, path, user: h.supervisor, body: method == 'POST' ? {} : null);
        expect(r.status, 403);
        expect(r.error, 'device_scope');
      });
    }

    test('policy: every warehouse route is allowed, nothing else is', () {
      for (final p in [
        '/api/m1/info', '/api/auth/session', '/api/m1/wh/po', '/api/m1/wh/counts/tasks',
        '/api/m1/wh/transfers/x/dispatch', '/api/m1/wh/approvals', '/api/m1/wh/labels',
      ]) {
        expect(LanDeviceRoutePolicy.allows('warehouse', p), isTrue, reason: p);
      }
      for (final p in ['/api/inventory/transfer', '/api/sync/pull', '/api/m1/whx', '/api/m1', '/api/pair']) {
        expect(LanDeviceRoutePolicy.allows('warehouse', p), isFalse, reason: p);
      }
    });
  });
}
