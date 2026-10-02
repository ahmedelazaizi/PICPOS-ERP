@Tags(['postgres'])
library;

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// Phase I-2: returns, visits, price lists / tax-inclusive pricing, token
/// rotation and revocation, rate limits, audit rows.
const _uuid = Uuid();

void main() {
  late Harness h;
  setUp(() async => h = await Harness.start());
  tearDown(() async => h.stop());

  Future<List<Map<String, dynamic>>> push(RepDevice d, List<Map<String, Object?>> docs) async {
    final (st, b) = await h.call('POST', '/mobile/sync/push', headers: d.headers, body: {'documents': docs});
    expect(st, 200, reason: '$b');
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> lease(RepDevice d, String docType, [int offset = 0]) async {
    final (_, b) = await h.call('GET', '/mobile/bootstrap', headers: d.headers);
    final l = (b['leases'] as List).firstWhere((l) => l['docType'] == docType);
    return '${l['prefix']}${(l['nextNumber'] as int) + offset}';
  }

  Map<String, Object?> invoice(String number,
          {String customer = Demo.cust2Gid,
          double water = 0,
          double bread = 0,
          double waterPrice = 2.5,
          double breadPrice = 1,
          double paid = 0}) =>
      {
        'kind': 'sales_invoice',
        'globalId': _uuid.v4(),
        'number': number,
        'date': DateTime.now().toUtc().toIso8601String(),
        'customerGlobalId': customer,
        'lines': [
          if (water > 0) {'productGlobalId': Demo.prodWaterGid, 'quantity': water, 'unitPrice': waterPrice},
          if (bread > 0) {'productGlobalId': Demo.prodBreadGid, 'quantity': bread, 'unitPrice': breadPrice},
        ],
        'paid': paid,
      };

  Map<String, Object?> ret(String number, String invoiceGid, Map<String, double> qty,
          {Object? total, Object? cashRefund, String? globalId}) =>
      {
        'kind': 'sales_return',
        'globalId': globalId ?? _uuid.v4(),
        'number': number,
        'date': DateTime.now().toUtc().toIso8601String(),
        'originalInvoiceGlobalId': invoiceGid,
        'lines': [
          for (final e in qty.entries) {'productGlobalId': e.key, 'quantity': e.value},
        ],
        'total': ?total,
        'cashRefund': ?cashRefund,
        'reason': 'damaged',
      };

  Future<double> balance(String customerGid) async => num0(
      (await h.db.query('SELECT balance FROM parties WHERE global_id=@g', {'g': customerGid})).first[0]);

  Future<double> vanQty(String repGid, String productGid) async {
    final r = await h.db.query('''
      SELECT ib.quantity FROM inventory_balances ib JOIN products p ON p.id=ib.product_id
      JOIN rep_resources rr ON rr.van_warehouse_id = ib.warehouse_id JOIN employees e ON e.id = rr.employee_id
      WHERE e.global_id=@e AND p.global_id=@p''', {'e': repGid, 'p': productGid});
    return r.isEmpty ? 0 : num0(r.first[0]);
  }

  group('bootstrap (I-2 additions)', () {
    test('company pricing flags, wholesale price, price lists, rep permission, no-sale reasons', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (st, b) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      expect(st, 200);
      expect(b['company']['pricesIncludeTax'], false);
      expect(b['company']['decimalPlaces'], 2);
      expect(b['employee']['canOverridePrice'], false);
      expect(b['noSaleReasons'], containsAll(['closed', 'has_stock', 'other']));
      final water = (b['products'] as List).firstWhere((p) => p['globalId'] == Demo.prodWaterGid);
      expect(water['wholesalePrice'], 2.2);
      final list = (b['priceLists'] as List).single;
      expect(list['globalId'], Demo.priceListGid);
      expect(list['isDefault'], true);
      expect(list['items'], [
        allOf(containsPair('productGlobalId', Demo.prodBreadGid), containsPair('price', 0.9),
            containsPair('minQuantity', 10.0)),
      ]);
      expect(b['priceListScope'], [Demo.priceListGid]);
      expect(b['invoices'], isEmpty);
    });

    test('pull re-sends a price list when one of its items changes', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (_, boot) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final (_, none) = await h.call('GET', '/mobile/sync/pull?since=${boot['serverTime']}', headers: rep.headers);
      expect(none['priceLists'], isEmpty);
      await h.db.query('UPDATE price_list_items SET price = 0.85');
      final (_, d) = await h.call('GET', '/mobile/sync/pull?since=${boot['serverTime']}', headers: rep.headers);
      expect((d['priceLists'] as List).single['items'][0]['price'], 0.85);
    });
  });

  group('pricing at the gate', () {
    test('price list tier and wholesale level are enforced; override permission lifts the check', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final r1 = await push(rep, [invoice(await lease(rep, 'sales_invoice'), bread: 10, breadPrice: 1)]);
      expect(r1.single['code'], 'price_not_allowed');
      expect(r1.single['details'], allOf(containsPair('expected', 0.9), containsPair('source', 'price_list')));
      final ok = await push(rep, [invoice(await lease(rep, 'sales_invoice'), bread: 10, breadPrice: 0.9)]);
      expect(ok.single['status'], 'accepted', reason: '${ok.single}');
      expect(ok.single['total'], 9.0);

      await h.db.query("UPDATE parties SET price_level='wholesale' WHERE global_id=@g", {'g': Demo.cust2Gid});
      final r2 = await push(rep, [invoice(await lease(rep, 'sales_invoice'), water: 1)]);
      expect(r2.single['details'], containsPair('expected', 2.2));
      final ok2 = await push(rep, [invoice(await lease(rep, 'sales_invoice'), water: 1, waterPrice: 2.2)]);
      expect(ok2.single['status'], 'accepted');

      await h.db.query('UPDATE employees SET can_override_price=TRUE WHERE global_id=@g', {'g': Demo.rep1Gid});
      final ok3 = await push(rep, [invoice(await lease(rep, 'sales_invoice'), water: 1, waterPrice: 2.0)]);
      expect(ok3.single['status'], 'accepted', reason: '${ok3.single}');
    });

    test('tax-inclusive company: tax extracted per line, total = price × qty', () async {
      await h.db.query('UPDATE companies SET prices_include_tax = TRUE');
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final r = await push(rep, [invoice(await lease(rep, 'sales_invoice'), water: 2, bread: 1, paid: 6)]);
      expect(r.single['status'], 'accepted', reason: '${r.single}');
      // water 5.00 incl. 16 % → net 4.31, tax 0.69; bread exempt 1.00
      expect((r.single['total'], r.single['tax']), (6.0, 0.69));
      final inv = await h.db.query('SELECT prices_include_tax, subtotal FROM sales_invoices');
      expect(inv.first[0], true);
      expect(num0(inv.first[1]), 6.0);
      final mismatch = await push(rep, [
        {...invoice(await lease(rep, 'sales_invoice'), water: 2), 'total': 5.8},
      ]);
      expect(mismatch.single['code'], 'totals_mismatch');
    });
  });

  group('sales returns', () {
    test('credit invoice: return offsets balance, van stock back in, qty ≤ sold − returned, replay', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final inv = invoice(await lease(rep, 'sales_invoice'), water: 4);
      expect((await push(rep, [inv])).single['total'], 11.6);
      expect(await vanQty(Demo.rep1Gid, Demo.prodWaterGid), 46.0);

      final first = ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 1},
          total: 2.9, cashRefund: 0);
      final r1 = await push(rep, [first]);
      expect(r1.single, allOf(containsPair('status', 'accepted'), containsPair('total', 2.9),
          containsPair('tax', 0.4), containsPair('arOffset', 2.9), containsPair('cashRefund', 0.0),
          containsPair('customerBalance', 8.7)));
      expect(r1.single['number'], startsWith('VR-'));
      expect(r1.single['integrityHash'], startsWith('v2:'));
      expect(await balance(Demo.cust2Gid), 8.7);
      expect(await vanQty(Demo.rep1Gid, Demo.prodWaterGid), 47.0);
      final again = await push(rep, [first]);
      expect(again.single['status'], 'duplicate');
      expect(await vanQty(Demo.rep1Gid, Demo.prodWaterGid), 47.0, reason: 'replay has no side effects');

      final over = await push(rep,
          [ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 4})]);
      expect(over.single['code'], 'return_qty_exceeds_sold');
      expect(over.single['details'], allOf(containsPair('sold', 4.0), containsPair('returned', 1.0),
          containsPair('requested', 4.0)));

      final rest = await push(rep,
          [ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 3})]);
      expect((rest.single['total'], rest.single['tax'], rest.single['arOffset']), (8.7, 1.2, 8.7));
      expect(await balance(Demo.cust2Gid), 0.0);
      expect(await vanQty(Demo.rep1Gid, Demo.prodWaterGid), 50.0);
      final none = await push(rep,
          [ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 1})]);
      expect(none.single['code'], 'return_qty_exceeds_sold');

      final moves = await h.db.query(
          "SELECT count(*), sum(quantity) FROM stock_movements WHERE movement_type='return' AND reference_type='mobile_sales_return'");
      expect((moves.first[0], num0(moves.first[1])), (2, 4.0));
      final sr = await h.db.query('''
        SELECT DISTINCT sr.warehouse_id = rr.van_warehouse_id FROM sales_returns sr
        JOIN rep_resources rr ON rr.employee_id = sr.rep_employee_id''');
      expect(sr.single[0], true, reason: 'returns go back into the rep van');
    });

    test('mixed invoice: unpaid part offset first, rest refunded in cash from custody', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final inv = invoice(await lease(rep, 'sales_invoice'), water: 4, bread: 3, paid: 5);
      expect((await push(rep, [inv])).single['remaining'], 9.6);
      final wrong = await push(rep, [
        ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 4}, cashRefund: 0),
      ]);
      expect(wrong.single['code'], 'refund_mismatch');
      expect(wrong.single['details'], containsPair('cashRefund', 2.0));
      final r = await push(rep, [
        ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 4}, cashRefund: 2.0),
      ]);
      expect((r.single['total'], r.single['arOffset'], r.single['cashRefund']), (11.6, 9.6, 2.0));
      expect(await balance(Demo.cust2Gid), 0.0);
      final pay = await h.db.query(
          "SELECT transaction_type, amount, reference_global_id FROM safe_transactions WHERE category='sales_return'");
      expect((pay.single[0], num0(pay.single[1]), pay.single[2]), ('payment', 2.0, r.single['globalId']));

      // A later return on the same invoice is all cash (nothing left unpaid).
      final r2 = await push(rep, [
        ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodBreadGid: 1}),
      ]);
      expect((r2.single['arOffset'], r2.single['cashRefund']), (0.0, 1.0));
    });

    test('rejections: unknown invoice/product, invoice number lease, rep scope, totals', () async {
      final rep1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
      final inv = invoice(await lease(rep1, 'sales_invoice'), water: 2);
      await push(rep1, [inv]);
      final gid = inv['globalId'] as String;
      final n = await lease(rep1, 'sales_return');
      final codes = await push(rep1, [
        ret(n, _uuid.v4(), {Demo.prodWaterGid: 1}),
        ret(n, gid, {Demo.prodBreadGid: 1}),
        ret(await lease(rep1, 'sales_invoice', 5), gid, {Demo.prodWaterGid: 1}),
        ret(n, gid, {Demo.prodWaterGid: 1}, total: 9.99),
        {...ret(n, gid, {Demo.prodWaterGid: 1}), 'customerGlobalId': Demo.cust1Gid},
        ret(n, gid, {Demo.prodWaterGid: 0}),
      ]);
      expect(codes.map((c) => c['code']), [
        'invoice_not_found',
        'product_not_on_invoice',
        'number_out_of_range',
        'totals_mismatch',
        'customer_mismatch',
        'invalid_line',
      ]);
      // rep2 cannot return against a customer outside his routes.
      final scoped = await push(rep2, [ret(await lease(rep2, 'sales_return'), gid, {Demo.prodWaterGid: 1})]);
      expect(scoped.single['code'], 'customer_not_on_route');
      expect(await vanQty(Demo.rep1Gid, Demo.prodWaterGid), 48.0, reason: 'rejections leave stock untouched');
    });

    test('pull offers recent invoices with per-product returned quantities; documents include returns', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (_, boot) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      final inv = invoice(await lease(rep, 'sales_invoice'), water: 3, bread: 2, paid: 10.7);
      await push(rep, [inv]);
      final r = ret(await lease(rep, 'sales_return'), inv['globalId'] as String, {Demo.prodWaterGid: 1});
      await push(rep, [r]);
      final (_, d) = await h.call('GET', '/mobile/sync/pull?since=${boot['serverTime']}', headers: rep.headers);
      final pulled = (d['invoices'] as List).single as Map;
      expect(pulled, allOf(containsPair('globalId', inv['globalId']), containsPair('customerGlobalId', Demo.cust2Gid),
          containsPair('total', 10.7), containsPair('paid', 10.7), containsPair('returnedTotal', 2.9)));
      final water = (pulled['lines'] as List).firstWhere((l) => l['productGlobalId'] == Demo.prodWaterGid);
      expect((water['quantity'], water['returnedQuantity'], water['total'], water['returnedTotal']),
          (3.0, 1.0, 8.7, 2.9));
      expect((d['documents'] as List).map((x) => x['kind']).toSet(), {'sales_invoice', 'sales_return'});
    });
  });

  group('visits', () {
    test('visited / no-sale with reason in route order; validations; idempotent', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      Map<String, Object?> visit(String customer, String outcome, {String? reason, Object? lat}) => {
            'kind': 'visit',
            'globalId': _uuid.v4(),
            'customerGlobalId': customer,
            'date': '2026-05-01T09:00:00.000Z',
            'outcome': outcome,
            'noSaleReason': ?reason,
            'latitude': ?lat,
            'longitude': lat == null ? null : 35.9,
          };
      final ok = visit(Demo.cust2Gid, 'no_sale', reason: 'has_stock', lat: 31.95);
      final r = await push(rep, [
        visit(Demo.cust1Gid, 'visited'),
        ok,
        visit(Demo.cust2Gid, 'no_sale'),
        visit(Demo.cust2Gid, 'no_sale', reason: 'bored'),
        visit(Demo.cust2Gid, 'maybe'),
        visit(Demo.cust3Gid, 'visited'),
        visit(Demo.cust1Gid, 'visited', lat: 123),
      ]);
      expect(r.map((x) => x['status'] == 'accepted' ? 'ok' : x['code']), [
        'ok',
        'ok',
        'no_sale_reason_required',
        'no_sale_reason_required',
        'invalid_outcome',
        'customer_not_on_route',
        'invalid_geo',
      ]);
      expect((await push(rep, [ok])).single['status'], 'duplicate');
      final rows = await h.db.query(
          'SELECT p.global_id, v.outcome, v.no_sale_reason, v.sequence, v.latitude FROM customer_visits v '
          'JOIN parties p ON p.id = v.customer_id ORDER BY v.sequence');
      expect([for (final x in rows) [x[0], x[1], x[2], x[3]]], [
        [Demo.cust1Gid, 'visited', null, 1],
        [Demo.cust2Gid, 'no_sale', 'has_stock', 2],
      ]);
      expect(rows.last[4], 31.95);
      final (_, d) = await h.call('GET', '/mobile/sync/pull?since=0', headers: rep.headers);
      expect((d['documents'] as List).where((x) => x['kind'] == 'visit'), hasLength(2));
    });
  });

  group('device tokens', () {
    test('rotation: new token works, old one only until the new one is used', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (st, b) = await h.call('POST', '/mobile/token/rotate', headers: rep.headers);
      expect(st, 200);
      final newToken = b['deviceToken'] as String;
      expect(rep.headers['authorization'], isNot('Bearer $newToken'));
      final withNew = {...rep.headers, 'authorization': 'Bearer $newToken'};

      // Grace: the response might have been lost — the old token still works.
      expect((await h.call('GET', '/mobile/sync/pull?since=0', headers: rep.headers)).$1, 200);
      expect((await h.call('GET', '/mobile/sync/pull?since=0', headers: withNew)).$1, 200);
      final (os, ob) = await h.call('GET', '/mobile/sync/pull?since=0', headers: rep.headers);
      expect((os, ob['error']), (401, 'invalid_device_token'));

      final audit = await h.db.query("SELECT count(*) FROM audit_log WHERE action='token_rotated'");
      expect(audit.first[0], 1);
    });

    test('a retried rotation keeps the token the device holds valid', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      await h.call('POST', '/mobile/token/rotate', headers: rep.headers); // response "lost"
      final (st, b) = await h.call('POST', '/mobile/token/rotate', headers: rep.headers);
      expect(st, 200);
      final withNew = {...rep.headers, 'authorization': 'Bearer ${b['deviceToken']}'};
      expect((await h.call('GET', '/mobile/bootstrap', headers: withNew)).$1, 200);
    });

    test('revocation locks out device token, rotation and leases; audit row; unknown device 404', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      final admin = {'x-admin-key': Harness.adminKey};
      expect((await h.call('POST', '/admin/devices/${rep.deviceId}/revoke', headers: admin)).$1, 200);
      final (rs, rb) = await h.call('POST', '/mobile/token/rotate', headers: rep.headers);
      expect((rs, rb['error']), (401, 'device_revoked'));
      final (ls, lb) = await h.call('POST', '/mobile/login', headers: rep.headers, body: {'pin': Demo.rep1Pin});
      expect((ls, lb['error']), (401, 'device_revoked'));
      final leases = await h.db.query('SELECT DISTINCT status FROM device_number_leases');
      expect(leases.single[0], 'revoked');
      final audit = await h.db.query("SELECT detail FROM audit_log WHERE action='device_revoked'");
      expect(audit.single[0], 'admin');
      expect((await h.call('POST', '/admin/devices/nope/revoke', headers: admin)).$1, 404);
    });
  });

  group('rate limits', () {
    test('login: 10 attempts per device per 10 minutes, then 429 with Retry-After', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin); // 1 attempt used
      final deviceOnly = Map.of(rep.headers)..remove('x-session-token');
      for (var i = 0; i < 9; i++) {
        final (st, _) = await h.call('POST', '/mobile/login', headers: deviceOnly, body: {'pin': '0000'});
        expect(st, 401);
      }
      final (st, b) = await h.call('POST', '/mobile/login', headers: deviceOnly, body: {'pin': Demo.rep1Pin});
      expect((st, b['error']), (429, 'too_many_attempts'));
      expect(int.parse(h.lastHeaders['retry-after']!), greaterThan(0));
      // Another device is not affected.
      await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final failed = await h.db.query("SELECT count(*) FROM audit_log WHERE action='login_failed'");
      expect(failed.first[0], 9);
    });

    test('push: 60 per device per minute', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      for (var i = 0; i < 60; i++) {
        final (st, _) =
            await h.call('POST', '/mobile/sync/push', headers: rep.headers, body: {'documents': <Object>[]});
        expect(st, 200);
      }
      final (st, b) =
          await h.call('POST', '/mobile/sync/push', headers: rep.headers, body: {'documents': <Object>[]});
      expect((st, b['error']), (429, 'rate_limited'));
      expect(h.lastHeaders['retry-after'], isNotNull);
    });

    test('RateLimiter window slides', () {
      var now = DateTime(2026);
      final l = RateLimiter(max: 2, window: const Duration(minutes: 1), clock: () => now);
      l.hit('a');
      l.hit('a');
      expect(() => l.hit('a'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 429)));
      l.hit('b');
      now = now.add(const Duration(minutes: 1));
      l.hit('a');
    });
  });

  test('audit log records accepted and rejected pushes with the device and IP', () async {
    final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    await push(rep, [
      invoice(await lease(rep, 'sales_invoice'), water: 1),
      invoice('VS-1', water: 1),
    ]);
    final rows = await h.db.query(
        "SELECT action, entity, detail, ip, device_pk IS NOT NULL FROM audit_log WHERE action LIKE 'push_%' ORDER BY id");
    expect([for (final r in rows) [r[0], r[1], r[2], r[3], r[4]]], [
      ['push_accepted', 'sales_invoice', null, 'unknown', true],
      ['push_rejected', 'sales_invoice', 'number_out_of_range', 'unknown', true],
    ]);
    final login = await h.db.query("SELECT count(*) FROM audit_log WHERE action='login'");
    expect(login.first[0], 1);
  });
}
