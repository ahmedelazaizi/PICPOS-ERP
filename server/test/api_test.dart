@Tags(['postgres'])
library;

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

const _uuid = Uuid();

void main() {
  late Harness h;
  setUp(() async => h = await Harness.start());
  tearDown(() async => h.stop());

  Map<String, Object?> invoice({
    required String number,
    String customer = Demo.cust2Gid,
    double waterQty = 2,
    double breadQty = 0,
    double paid = 0,
    String? globalId,
  }) =>
      {
        'kind': 'sales_invoice',
        'globalId': globalId ?? _uuid.v4(),
        'number': number,
        'date': '2026-05-01T10:00:00.000Z',
        'customerGlobalId': customer,
        'lines': [
          if (waterQty > 0) {'productGlobalId': Demo.prodWaterGid, 'quantity': waterQty, 'unitPrice': 2.5},
          if (breadQty > 0) {'productGlobalId': Demo.prodBreadGid, 'quantity': breadQty, 'unitPrice': 1},
        ],
        'paid': paid,
      };

  Future<List<Map<String, dynamic>>> push(RepDevice d, List<Map<String, Object?>> docs) async {
    final (st, b) = await h.call('POST', '/mobile/sync/push', headers: d.headers, body: {'documents': docs});
    expect(st, 200, reason: '$b');
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> leaseNumber(RepDevice d, [int offset = 0]) async {
    final (_, b) = await h.call('GET', '/mobile/bootstrap', headers: d.headers);
    final lease = (b['leases'] as List).firstWhere((l) => l['docType'] == 'sales_invoice');
    return '${lease['prefix']}${(lease['nextNumber'] as int) + offset}';
  }

  test('health reports db ok and mock WhatsApp provider', () async {
    final (st, b) = await h.call('GET', '/health');
    expect(st, 200);
    expect(b, containsPair('db', 'ok'));
    expect(b['whatsappProvider'], 'mock');
  });

  group('pairing & auth', () {
    test('code -> device token; code is single use; wrong code/admin key rejected', () async {
      final code = await h.pairingCode(Demo.rep1Gid);
      final (st, b) = await h.call('POST', '/mobile/pair', body: {'code': code, 'deviceId': 'dev-1'});
      expect(st, 200);
      expect(b['deviceToken'], isA<String>());
      expect(b['employeeGlobalId'], Demo.rep1Gid);

      final (st2, b2) = await h.call('POST', '/mobile/pair', body: {'code': code, 'deviceId': 'dev-2'});
      expect(st2, 401);
      expect(b2['error'], 'code_expired');

      final (st3, b3) = await h.call('POST', '/mobile/pair', body: {'code': 'ABCDEFGH', 'deviceId': 'dev-3'});
      expect((st3, b3['error']), (401, 'invalid_code'));

      final (st4, _) = await h.call('POST', '/admin/pairing-codes',
          headers: {'x-admin-key': 'wrong'},
          body: {'companyGlobalId': Demo.companyGid, 'employeeGlobalId': Demo.rep1Gid});
      expect(st4, 401);
    });

    test('pairing attempts are rate limited per IP', () async {
      for (var i = 0; i < 5; i++) {
        await h.call('POST', '/mobile/pair', body: {'code': 'ZZZZZZZZ', 'deviceId': 'x'});
      }
      final (st, b) = await h.call('POST', '/mobile/pair', body: {'code': 'ZZZZZZZZ', 'deviceId': 'x'});
      expect((st, b['error']), (429, 'too_many_attempts'));
    });

    test('wrong PIN rejected; data endpoints need a session; revoked device is locked out', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final deviceOnly = Map.of(rep.headers)..remove('x-session-token');
      final (ls, lb) = await h.call('POST', '/mobile/login', headers: deviceOnly, body: {'pin': '0000'});
      expect((ls, lb['error']), (401, 'invalid_pin'));
      final (bs, bb) = await h.call('GET', '/mobile/bootstrap', headers: deviceOnly);
      expect((bs, bb['error']), (401, 'invalid_session'));

      await h.call('POST', '/admin/devices/${rep.deviceId}/revoke', headers: {'x-admin-key': Harness.adminKey});
      final (rs, rb) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      expect((rs, rb['error']), (401, 'device_revoked'));
    });
  });

  test('bootstrap is scoped to the rep (customers, van stock, books, leases)', () async {
    final rep1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final (st, b) = await h.call('GET', '/mobile/bootstrap', headers: rep1.headers);
    expect(st, 200);
    final customers = (b['customers'] as List).map((c) => c['globalId']).toList();
    expect(customers, [Demo.cust1Gid, Demo.cust2Gid]); // route sequence order
    expect(customers, isNot(contains(Demo.cust3Gid)));
    final stock = {for (final s in b['vanStock'] as List) s['productGlobalId']: s['quantity']};
    expect(stock, {Demo.prodWaterGid: 50.0, Demo.prodBreadGid: 20.0});
    expect((b['voucherBooks'] as List).map((v) => v['globalId']), [Demo.book1Gid]);
    expect((b['products'] as List).length, 2);
    final leases = b['leases'] as List;
    expect(leases.map((l) => l['docType']).toSet(), {'sales_invoice', 'sales_return'});
    expect(b['company']['defaultTaxRate'], 16.0);

    final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
    final (_, b2) = await h.call('GET', '/mobile/bootstrap', headers: rep2.headers);
    expect((b2['customers'] as List).map((c) => c['globalId']), [Demo.cust3Gid]);
    final l1 = leases.firstWhere((l) => l['docType'] == 'sales_invoice');
    final l2 = (b2['leases'] as List).firstWhere((l) => l['docType'] == 'sales_invoice');
    expect(l2['rangeFrom'], greaterThan(l1['rangeTo'] as int), reason: 'device blocks are disjoint');
  });

  group('push', () {
    test('accepted invoice deducts van stock, raises balance, signs; replay is idempotent', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final doc = invoice(number: await leaseNumber(rep), waterQty: 4, breadQty: 3, paid: 5);
      final r1 = await push(rep, [doc]);
      expect(r1.single['status'], 'accepted', reason: '${r1.single}');
      // water 4*2.5=10 +16% = 11.6 ; bread 3 exempt = 3 → 14.6 ; paid 5 → remaining 9.6
      expect(r1.single['total'], 14.6);
      expect(r1.single['tax'], 1.6);
      expect(r1.single['remaining'], 9.6);
      expect(r1.single['integrityHash'], startsWith('v2:'));

      final r2 = await push(rep, [doc]);
      expect(r2.single['status'], 'duplicate');
      expect(r2.single['integrityHash'], r1.single['integrityHash']);

      final stock = await h.db.query('''
        SELECT p.global_id, ib.quantity FROM inventory_balances ib JOIN products p ON p.id=ib.product_id
        JOIN rep_resources rr ON rr.van_warehouse_id = ib.warehouse_id
        JOIN employees e ON e.id = rr.employee_id WHERE e.global_id=@g''', {'g': Demo.rep1Gid});
      expect({for (final r in stock) r[0]: num0(r[1])}, {Demo.prodWaterGid: 46.0, Demo.prodBreadGid: 17.0});
      final bal = await h.db.query('SELECT balance FROM parties WHERE global_id=@g', {'g': Demo.cust2Gid});
      expect(num0(bal.first[0]), 9.6);
      final moves = await h.db.query('SELECT count(*) FROM stock_movements');
      expect(moves.first[0], 2);
    });

    test('same globalId from another device is a conflict', () async {
      final a = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final b = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final gid = _uuid.v4();
      expect((await push(a, [invoice(number: await leaseNumber(a), globalId: gid)])).single['status'], 'accepted');
      final r = await push(b, [invoice(number: await leaseNumber(b), globalId: gid)]);
      expect(r.single['code'], 'global_id_conflict');
    });

    test('rejects insufficient van stock (and leaves stock untouched)', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final r = await push(rep, [invoice(number: await leaseNumber(rep), waterQty: 51)]);
      expect(r.single['status'], 'rejected');
      expect(r.single['code'], 'insufficient_van_stock');
      expect(r.single['details']['available'], 50.0);
      final q = await h.db.query('SELECT sum(quantity) FROM inventory_balances');
      expect(num0(q.first[0]), 80.0);
    });

    test('rejects credit above limit; cash sale to same customer accepted', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      // cust1 credit limit 100; 40 * 2.5 * 1.16 = 116 on credit
      final r = await push(rep, [invoice(number: await leaseNumber(rep), customer: Demo.cust1Gid, waterQty: 40)]);
      expect(r.single['code'], 'credit_limit_exceeded');
      final ok = await push(rep,
          [invoice(number: await leaseNumber(rep), customer: Demo.cust1Gid, waterQty: 40, paid: 116)]);
      expect(ok.single['status'], 'accepted');
    });

    test('rejects numbers outside this device lease and customers off route', () async {
      final rep1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
      final rep2Number = await leaseNumber(rep2);
      expect((await push(rep1, [invoice(number: 'VS-999999')])).single['code'], 'number_out_of_range');
      expect((await push(rep1, [invoice(number: rep2Number)])).single['code'], 'number_out_of_range');
      expect((await push(rep1, [invoice(number: await leaseNumber(rep1), customer: Demo.cust3Gid)])).single['code'],
          'customer_not_on_route');
      final n = await leaseNumber(rep1);
      expect((await push(rep1, [invoice(number: n)])).single['status'], 'accepted');
      expect((await push(rep1, [invoice(number: n)])).single['code'], 'number_already_used');
    });

    test('collections validate voucher-book leaf and advance the book', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      Map<String, Object?> col(int leaf, {String book = Demo.book1Gid}) => {
            'kind': 'collection',
            'globalId': _uuid.v4(),
            'customerGlobalId': Demo.cust1Gid,
            'amount': 20,
            'bookGlobalId': book,
            'bookNumber': leaf,
          };
      final r = await push(rep, [col(1001), col(1001), col(2001, book: Demo.book2Gid), col(1100)]);
      expect(r.map((x) => x['status'] == 'accepted' ? 'ok' : x['code']).toList(),
          ['ok', 'book_leaf_used', 'book_not_held_by_rep', 'book_number_out_of_range']);
      expect(r.first['number'], 'R-1001');
      expect(r.first['customerBalance'], -20.0);
      final book = await h.db.query('SELECT next_number FROM voucher_books WHERE global_id=@g', {'g': Demo.book1Gid});
      expect(book.first[0], 1002);
    });
  });

  test('pull returns only the delta since the watermark', () async {
    final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final (_, boot) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
    final since = boot['serverTime'] as int;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final (_, empty) = await h.call('GET', '/mobile/sync/pull?since=$since', headers: rep.headers);
    expect(empty['customers'], isEmpty);
    expect(empty['products'], isEmpty);
    expect(empty['vanStock'], isEmpty);
    expect(empty['customerScope'], [Demo.cust1Gid, Demo.cust2Gid]);

    final doc = invoice(number: await leaseNumber(rep), waterQty: 2);
    await push(rep, [doc]);
    final (st, d) = await h.call('GET', '/mobile/sync/pull?since=$since', headers: rep.headers);
    expect(st, 200);
    expect((d['customers'] as List).map((c) => c['globalId']), [Demo.cust2Gid]);
    expect(d['customers'][0]['balance'], 5.8);
    expect(d['vanStock'], [
      {'productGlobalId': Demo.prodWaterGid, 'quantity': 48.0},
    ]);
    expect((d['documents'] as List).single['globalId'], doc['globalId']);
    expect(d['products'], isEmpty);
  });

  group('WhatsApp outbox (mock provider)', () {
    test('opted-in customer gets queued template; worker sends via mock; others skipped', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      await push(rep, [
        invoice(number: await leaseNumber(rep), customer: Demo.cust1Gid, waterQty: 1, paid: 2.9),
      ]);
      await push(rep, [invoice(number: await leaseNumber(rep), customer: Demo.cust2Gid, waterQty: 1)]);
      final (_, ob) = await h.call('GET', '/admin/whatsapp/outbox', headers: {'x-admin-key': Harness.adminKey});
      final msgs = ob['messages'] as List;
      expect(msgs, hasLength(1));
      expect(msgs.single['template'], 'invoice_issued');
      expect(msgs.single['to_phone'], '+962790000001');

      h.provider.failNext = 1;
      expect(await h.services.outbox.processDue(), 1);
      final failed = await h.db.query('SELECT status, attempts, last_error FROM whatsapp_outbox');
      expect(failed.first[0], 'queued');
      expect(failed.first[1], 1);

      await h.db.query('UPDATE whatsapp_outbox SET next_attempt_at = 0');
      await h.services.outbox.processDue();
      final sent = await h.db.query('SELECT status, provider_message_id FROM whatsapp_outbox');
      expect(sent.first[0], 'sent');
      expect(h.provider.sent.single.template, 'invoice_issued');
      expect(h.provider.sent.single.params[1], startsWith('VS-'));
    });
  });
}
