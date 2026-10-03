@Tags(['postgres'])
library;

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// J3: the system cash customer is served to EVERY rep (exception to one
/// route per customer), its sales keep the one-time name and the rep's route
/// stamp, it sells cash only; a `customer` document («حفظ كعميل دائم») puts
/// a new cash-only customer at the end of the rep's route and reaches the
/// desktop feed before the sales made to it.
const _uuid = Uuid();
const _cashGid = '00000000-0000-4000-8000-0000000000ca';

void main() {
  late Harness h;
  late Map<String, String> desk;
  setUp(() async {
    h = await Harness.start();
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': Demo.companyGid, 'name': 'HQ'});
    expect(st, 201, reason: '$b');
    desk = {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
    // The desktop master push carries the cash customer with its role.
    final (ms, mb) = await h.call('POST', '/desktop/master', headers: desk, body: {
      'parties': [
        {'globalId': _cashGid, 'name': 'عميل نقدي', 'balance': 0, 'creditLimit': 0, 'systemRole': 'cash_customer'},
      ],
    });
    expect(ms, 200, reason: '$mb');
  });
  tearDown(() async => h.stop());

  Future<List<Map<String, dynamic>>> push(RepDevice d, List<Map<String, Object?>> docs) async {
    final (st, b) = await h.call('POST', '/mobile/sync/push', headers: d.headers, body: {'documents': docs});
    expect(st, 200, reason: '$b');
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> boot(RepDevice d) async {
    final (st, b) = await h.call('GET', '/mobile/bootstrap', headers: d.headers);
    expect(st, 200, reason: '$b');
    return b;
  }

  Future<String> lease(RepDevice d) async {
    final l = ((await boot(d))['leases'] as List).firstWhere((l) => l['docType'] == 'sales_invoice');
    return '${l['prefix']}${l['nextNumber']}';
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final (st, b) = await h.call('GET', '/desktop/documents/pending', headers: desk);
    expect(st, 200, reason: '$b');
    return (b['documents'] as List).cast<Map<String, dynamic>>();
  }

  Map<String, Object?> sale(String number, String customer, {required double paid, Map<String, Object?>? extra}) => {
        'kind': 'sales_invoice',
        'globalId': _uuid.v4(),
        'number': number,
        'date': DateTime.now().toUtc().toIso8601String(),
        'customerGlobalId': customer,
        'lines': [
          {'productGlobalId': Demo.prodWaterGid, 'quantity': 2, 'unitPrice': 2.5},
        ],
        'paid': paid,
        ...?extra,
      };

  test('bootstrap: the cash customer is on every rep\'s list (cash only), '
      'route customers stay scoped', () async {
    for (final (gid, pin, own) in [
      (Demo.rep1Gid, Demo.rep1Pin, {Demo.cust1Gid, Demo.cust2Gid}),
      (Demo.rep2Gid, Demo.rep2Pin, {Demo.cust3Gid}),
    ]) {
      final b = await boot(await h.repDevice(gid, pin));
      expect((b['customerScope'] as List).toSet(), {...own, _cashGid});
      final cash = (b['customers'] as List).cast<Map>().singleWhere((c) => c['globalId'] == _cashGid);
      expect(cash['systemRole'], 'cash_customer');
      expect(cash['cashOnly'], isTrue);
      expect(cash['routeGlobalId'], isNull);
      final others = (b['customers'] as List).cast<Map>().where((c) => c['globalId'] != _cashGid);
      expect(others.every((c) => c['cashOnly'] == false), isTrue);
    }
  });

  test('cash-customer sale by any rep: one-time name kept, rep/route stamped, '
      'cash only', () async {
    final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
    final credit = await push(rep2, [sale(await lease(rep2), _cashGid, paid: 0)]);
    expect(credit.single['code'], 'cash_only_customer');

    final doc = sale(await lease(rep2), _cashGid,
        paid: 5.8, extra: {'customerName': 'أبو خالد', 'customerPhone': '0797777777'});
    final r = await push(rep2, [doc]);
    expect(r.single['status'], 'accepted', reason: '${r.single}');
    final row = (await h.db.query('''
      SELECT si.adhoc_customer_name, si.adhoc_customer_phone, e.global_id, r.name
      FROM sales_invoices si JOIN employees e ON e.id = si.rep_employee_id
      LEFT JOIN sales_routes r ON r.id = si.route_id WHERE si.global_id=@g''', {'g': doc['globalId']}))
        .first;
    expect(row[0], 'أبو خالد');
    expect(row[1], '0797777777');
    expect(row[2], Demo.rep2Gid);
    expect(row[3], 'خط الجنوب', reason: "grouped per rep/route via the rep's route stamp");

    final feed = (await pending()).singleWhere((d) => d['globalId'] == doc['globalId']);
    expect(feed['customerName'], 'أبو خالد');
    expect(feed['customerPhone'], '0797777777');
    expect(feed['routeGlobalId'], isNotNull);

    // A route customer never carries a one-time name.
    final rep1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final named = sale(await lease(rep1), Demo.cust2Gid, paid: 0, extra: {'customerName': 'x'});
    expect((await push(rep1, [named])).single['status'], 'accepted');
    expect((await h.db.query('SELECT adhoc_customer_name FROM sales_invoices WHERE global_id=@g',
            {'g': named['globalId']}))
        .first[0], isNull);
  });

  test('customer document: end of the rep\'s route, cash only, idempotent, '
      'fed to the desktop before its sales', () async {
    final rep1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final custGid = _uuid.v4();
    final custDoc = {'kind': 'customer', 'globalId': custGid, 'name': 'محل الوادي', 'phone': '0795555555'};
    final first = await push(rep1, [
      custDoc,
      sale(await lease(rep1), custGid, paid: 5.8),
    ]);
    expect(first[0]['status'], 'accepted', reason: '${first[0]}');
    expect(first[0]['sequence'], 3, reason: 'after c1 (1) and c2 (2)');
    expect(first[0]['routeCustomerGlobalId'], isA<String>());
    expect(first[1]['status'], 'accepted', reason: 'the rep sells to it right away: ${first[1]}');

    final replay = await push(rep1, [custDoc]);
    expect(replay.single['status'], 'duplicate');
    expect((await h.db.query('SELECT COUNT(*) FROM parties WHERE global_id=@g', {'g': custGid})).first[0], 1);

    final b = await boot(rep1);
    final c = (b['customers'] as List).cast<Map>().singleWhere((x) => x['globalId'] == custGid);
    expect(c['cashOnly'], isTrue, reason: 'credit limit 0 until management sets one');
    expect(c['sequence'], 3);
    expect((await push(rep1, [sale(await lease(rep1), custGid, paid: 0)])).single['code'], 'cash_only_customer');

    // Not on rep2's list.
    final b2 = await boot(await h.repDevice(Demo.rep2Gid, Demo.rep2Pin));
    expect(b2['customerScope'], isNot(contains(custGid)));

    final feed = await pending();
    final ci = feed.indexWhere((d) => d['kind'] == 'customer');
    final si = feed.indexWhere((d) => d['kind'] == 'sales_invoice' && d['customerGlobalId'] == custGid);
    expect(ci, lessThan(si), reason: 'the desktop creates the customer first');
    expect(feed[ci]['routeCustomerGlobalId'], first[0]['routeCustomerGlobalId']);
    expect(feed[ci]['name'], 'محل الوادي');
    expect(feed[ci]['repEmployeeGlobalId'], Demo.rep1Gid);

    final (ackStatus, ab) = await h.call('POST', '/desktop/documents/ack', headers: desk, body: {
      'results': [
        {'kind': 'customer', 'globalId': custGid, 'status': 'posted', 'desktopId': '77', 'desktopNumber': 'CUST-00077'},
      ],
    });
    expect(ackStatus, 200, reason: '$ab');
    expect((await pending()).where((d) => d['kind'] == 'customer'), isEmpty);
  });
}
