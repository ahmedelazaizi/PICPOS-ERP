@Tags(['postgres'])
library;

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// Phase I-3: desktop link credential, master-data upsert (visible in the
/// mobile bootstrap), pending field documents feed and ack.
const _uuid = Uuid();

void main() {
  late Harness h;
  late Map<String, String> desk;
  setUp(() async {
    h = await Harness.start();
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': Demo.companyGid, 'name': 'HQ'});
    expect(st, 201, reason: '$b');
    desk = {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
  });
  tearDown(() async => h.stop());

  Future<List<Map<String, dynamic>>> push(RepDevice d, List<Map<String, Object?>> docs) async {
    final (st, b) = await h.call('POST', '/mobile/sync/push', headers: d.headers, body: {'documents': docs});
    expect(st, 200, reason: '$b');
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> lease(RepDevice d, String docType) async {
    final (_, b) = await h.call('GET', '/mobile/bootstrap', headers: d.headers);
    final l = (b['leases'] as List).firstWhere((l) => l['docType'] == docType);
    return '${l['prefix']}${l['nextNumber']}';
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final (st, b) = await h.call('GET', '/desktop/documents/pending', headers: desk);
    expect(st, 200, reason: '$b');
    return (b['documents'] as List).cast<Map<String, dynamic>>();
  }

  Future<double> balance(String gid) async =>
      num0((await h.db.query('SELECT balance FROM parties WHERE global_id=@g', {'g': gid})).first[0]);

  group('credential', () {
    test('ping needs the link credential; revoked link is refused', () async {
      expect((await h.call('GET', '/desktop/ping')).$1, 401);
      final (bad, _) = await h.call('GET', '/desktop/ping',
          headers: {...desk, 'authorization': 'Bearer nope'});
      expect(bad, 401);
      final (st, b) = await h.call('GET', '/desktop/ping', headers: desk);
      expect(st, 200);
      expect(b['company']['globalId'], Demo.companyGid);
      expect(b['pending'],
          {'sales_invoice': 0, 'sales_return': 0, 'collection': 0, 'visit': 0, 'customer': 0, 'expense': 0});
      expect((await h.call('POST', '/admin/desktop-links/${desk['x-desktop-link']}/revoke',
              headers: {'x-admin-key': Harness.adminKey}))
          .$1, 200);
      final (rv, rb) = await h.call('GET', '/desktop/ping', headers: desk);
      expect(rv, 401);
      expect(rb['error'], 'desktop_link_revoked');
    });

    test('desktop pairing sets the rep PIN and issues a code the device can pair with', () async {
      final (st, b) = await h.call('POST', '/desktop/pairing-codes',
          headers: desk, body: {'employeeGlobalId': Demo.rep2Gid, 'pin': '9911'});
      expect(st, 201, reason: '$b');
      final deviceId = _uuid.v4();
      final (ps, pb) = await h.call('POST', '/mobile/pair',
          body: {'code': b['code'], 'deviceId': deviceId, 'deviceName': 't'});
      expect(ps, 200);
      final (ls, _) = await h.call('POST', '/mobile/login',
          headers: {'authorization': 'Bearer ${pb['deviceToken']}', 'x-device-id': deviceId}, body: {'pin': '9911'});
      expect(ls, 200);
    });
  });

  group('master data', () {
    test('upsert is idempotent and visible in the mobile bootstrap', () async {
      const rep = '00000000-0000-4000-8000-0000000000f1';
      const van = '00000000-0000-4000-8000-0000000000f2';
      const safe = '00000000-0000-4000-8000-0000000000f3';
      const cust = '00000000-0000-4000-8000-0000000000f4';
      const prod = '00000000-0000-4000-8000-0000000000f5';
      const route = '00000000-0000-4000-8000-0000000000f6';
      const area = '00000000-0000-4000-8000-0000000000f7';
      const book = '00000000-0000-4000-8000-0000000000f8';
      const list = '00000000-0000-4000-8000-0000000000f9';
      final batch = {
        'company': {'name': 'PicPos Demo', 'defaultTaxRate': 16, 'decimalPlaces': 2, 'currency': 'JOD'},
        'employees': [
          {'globalId': rep, 'name': 'مندوب ٣', 'isActive': true},
        ],
        'warehouses': [
          {'globalId': van, 'name': 'سيارة ٣', 'type': 'van'},
        ],
        'safes': [
          {'globalId': safe, 'name': 'عهدة ٣'},
        ],
        'parties': [
          {'globalId': cust, 'name': 'عميل سطح المكتب', 'balance': 40, 'creditLimit': 500, 'phone': '0790'},
        ],
        'products': [
          {'globalId': prod, 'name': 'عصير', 'nameEn': 'Juice', 'salePrice': 1.5, 'taxRate': 16, 'unitName': 'علبة'},
        ],
        'priceLists': [
          {
            'globalId': list,
            'name': 'جملة',
            'isDefault': false,
            'items': [
              {'globalId': _uuid.v4(), 'productGlobalId': prod, 'price': 1.2, 'minQuantity': 24},
            ],
          },
        ],
        'distributionAreas': [
          {'globalId': area, 'name': 'الشمال'},
        ],
        'salesRoutes': [
          {'globalId': route, 'name': 'خط ٣', 'salesRepGlobalId': rep, 'areaGlobalId': area, 'visitDays': 'sun'},
        ],
        'routeCustomers': [
          {
            'globalId': _uuid.v4(),
            'routeGlobalId': route,
            'customerGlobalId': cust,
            'sequence': 1,
            'effectiveFrom': '2020-01-01',
          },
        ],
        'repResources': [
          {'globalId': _uuid.v4(), 'employeeGlobalId': rep, 'vanWarehouseGlobalId': van, 'custodySafeGlobalId': safe},
        ],
        'voucherBooks': [
          {
            'globalId': book,
            'prefix': 'Q-',
            'rangeFrom': 1,
            'rangeTo': 50,
            'nextNumber': 3,
            'holderEmployeeGlobalId': rep,
            'status': 'active',
            'cancelledNumbers': [4],
          },
        ],
        'vanStock': [
          {'warehouseGlobalId': van, 'productGlobalId': prod, 'quantity': 30},
        ],
      };
      for (var i = 0; i < 2; i++) {
        final (st, b) = await h.call('POST', '/desktop/master', headers: desk, body: batch);
        expect(st, 200, reason: '$b');
        expect(b['skipped'], isEmpty);
        expect(b['applied']['parties'], 1);
      }
      expect((await h.db.query('SELECT COUNT(*) FROM parties WHERE global_id=@g', {'g': cust})).first[0], 1);

      final (ps, pb) = await h.call('POST', '/desktop/pairing-codes',
          headers: desk, body: {'employeeGlobalId': rep, 'pin': '4321'});
      expect(ps, 201);
      final deviceId = _uuid.v4();
      final (_, pair) = await h.call('POST', '/mobile/pair', body: {'code': pb['code'], 'deviceId': deviceId});
      final dh = {'authorization': 'Bearer ${pair['deviceToken']}', 'x-device-id': deviceId};
      final (_, login) = await h.call('POST', '/mobile/login', headers: dh, body: {'pin': '4321'});
      final (st, boot) =
          await h.call('GET', '/mobile/bootstrap', headers: {...dh, 'x-session-token': login['sessionToken']});
      expect(st, 200);
      expect(boot['vanWarehouse']['globalId'], van);
      expect(boot['custodySafe']['globalId'], safe);
      expect((boot['routes'] as List).single['globalId'], route);
      final c = (boot['customers'] as List).single;
      expect(c['globalId'], cust);
      expect(c['balance'], 40.0);
      expect(c['creditLimit'], 500.0);
      final p = (boot['products'] as List).firstWhere((x) => x['globalId'] == prod);
      expect(p['salePrice'], 1.5);
      expect(boot['vanStock'], [
        {'productGlobalId': prod, 'quantity': 30.0},
      ]);
      final b = (boot['voucherBooks'] as List).single;
      expect(b['globalId'], book);
      expect(b['nextNumber'], 3);
      expect(b['cancelledNumbers'], [4]);
      expect((boot['priceLists'] as List).map((l) => l['globalId']), contains(list));
    });

    test('I-4: printed company identity reaches the van (bootstrap and pull); '
        'omitted keys keep their value; pushed barcodes are normalized', () async {
      final dev = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (st, b) = await h.call('POST', '/desktop/master', headers: desk, body: {
        'company': {
          'name': 'شركة الوادي',
          'nameEn': 'Al Wadi Co.',
          'taxNumber': '123456',
          'commercialRegister': '9988',
          'address': 'عمّان',
          'phone': '0790000000',
          'eInvoiceEnabled': false,
          'defaultTaxRate': 16,
        },
        'products': [
          {'globalId': Demo.prodWaterGid, 'name': 'ماء', 'barcode': ']E06251234567890\r\n', 'salePrice': 2.5, 'taxRate': 16},
        ],
      });
      expect(st, 200, reason: '$b');
      final (_, boot) = await h.call('GET', '/mobile/bootstrap', headers: dev.headers);
      expect(boot['company'], containsPair('nameEn', 'Al Wadi Co.'));
      expect(boot['company'], containsPair('commercialRegister', '9988'));
      expect(boot['company'], containsPair('address', 'عمّان'));
      expect(boot['company'], containsPair('phone', '0790000000'));
      expect(boot['company'], containsPair('eInvoiceEnabled', false));
      final water = (boot['products'] as List).firstWhere((p) => p['globalId'] == Demo.prodWaterGid);
      expect(water['barcode'], '6251234567890');

      // A desktop that does not send the identity keys leaves them alone.
      await h.call('POST', '/desktop/master', headers: desk, body: {
        'company': {'name': 'شركة الوادي', 'taxNumber': '123456', 'defaultTaxRate': 16},
      });
      final (ps, pull) = await h.call('GET', '/mobile/sync/pull?since=${boot['serverTime']}', headers: dev.headers);
      expect(ps, 200, reason: '$pull');
      expect(pull['company'], containsPair('commercialRegister', '9988'));
      expect(pull['company'], containsPair('nameEn', 'Al Wadi Co.'));
    });

    test('unknown references are skipped and reported, not half-applied', () async {
      final (st, b) = await h.call('POST', '/desktop/master', headers: desk, body: {
        'routeCustomers': [
          {'globalId': _uuid.v4(), 'routeGlobalId': _uuid.v4(), 'customerGlobalId': Demo.cust1Gid},
        ],
        'vanStock': [
          {'warehouseGlobalId': _uuid.v4(), 'productGlobalId': Demo.prodWaterGid, 'quantity': 3},
        ],
      });
      expect(st, 200);
      expect((b['skipped'] as List).map((x) => x['reason']),
          ['unknown_route_or_customer', 'unknown_warehouse_or_product']);
    });
  });

  group('field documents', () {
    test('pending feed → ack posted removes them; failed keeps them with the reason; '
        'pushed balances add the unposted docs', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final invGid = _uuid.v4();
      final r = await push(rep, [
        {
          'kind': 'sales_invoice',
          'globalId': invGid,
          'number': await lease(rep, 'sales_invoice'),
          'date': DateTime.now().toUtc().toIso8601String(),
          'customerGlobalId': Demo.cust2Gid,
          'lines': [
            {'productGlobalId': Demo.prodWaterGid, 'quantity': 4, 'unitPrice': 2.5},
          ],
          'paid': 0,
        },
      ]);
      expect(r.single['status'], 'accepted', reason: '${r.single}');
      final r2 = await push(rep, [
        {
          'kind': 'collection',
          'globalId': _uuid.v4(),
          'customerGlobalId': Demo.cust2Gid,
          'amount': 5,
          'bookGlobalId': Demo.book1Gid,
          'bookNumber': 1001,
        },
        {'kind': 'visit', 'globalId': _uuid.v4(), 'customerGlobalId': Demo.cust2Gid, 'outcome': 'visited'},
      ]);
      expect(r2.map((x) => x['status']), ['accepted', 'accepted']);
      final ret = await push(rep, [
        {
          'kind': 'sales_return',
          'globalId': _uuid.v4(),
          'number': await lease(rep, 'sales_return'),
          'originalInvoiceGlobalId': invGid,
          'lines': [
            {'productGlobalId': Demo.prodWaterGid, 'quantity': 1},
          ],
        },
      ]);
      expect(ret.single['status'], 'accepted', reason: '${ret.single}');

      final docs = await pending();
      expect(docs.map((d) => d['kind']), ['sales_invoice', 'collection', 'visit', 'sales_return']);
      final inv = docs.first;
      expect(inv['customerGlobalId'], Demo.cust2Gid);
      expect(inv['repEmployeeGlobalId'], Demo.rep1Gid);
      expect(inv['total'], 11.6);
      expect((inv['lines'] as List).single, containsPair('taxAmount', 1.6));
      expect(docs[1], allOf(containsPair('bookGlobalId', Demo.book1Gid), containsPair('bookNumber', 1001)));
      expect(docs[3]['originalInvoiceGlobalId'], invGid);

      // Desktop ledger says 0; unposted: +11.6 invoice − 5 collection − 2.9 return offset.
      final (ms, mb) = await h.call('POST', '/desktop/master', headers: desk, body: {
        'parties': [
          {'globalId': Demo.cust2Gid, 'name': 'سوبرماركت النور', 'balance': 0, 'creditLimit': 0},
        ],
      });
      expect(ms, 200, reason: '$mb');
      expect(await balance(Demo.cust2Gid), closeTo(3.7, 1e-9));

      final (ackSt, ab) = await h.call('POST', '/desktop/documents/ack', headers: desk, body: {
        'results': [
          {'kind': 'sales_invoice', 'globalId': invGid, 'status': 'posted', 'desktopId': '7', 'desktopNumber': 'INV-7'},
          {'kind': 'collection', 'globalId': docs[1]['globalId'], 'status': 'failed', 'reason': 'book_not_found'},
        ],
      });
      expect(ackSt, 200);
      expect((ab['results'] as List).map((x) => x['status']), ['posted', 'failed_recorded']);
      final again = await pending();
      expect(again.map((d) => d['kind']), ['collection', 'visit', 'sales_return']);
      expect(again.first['lastDesktopError'], 'book_not_found');

      // Re-ack of a posted doc is a no-op that keeps the first number.
      final (_, ab2) = await h.call('POST', '/desktop/documents/ack', headers: desk, body: {
        'results': [
          {'kind': 'sales_invoice', 'globalId': invGid, 'status': 'posted', 'desktopNumber': 'INV-8'},
        ],
      });
      expect((ab2['results'] as List).single['status'], 'already_posted');
      final row = await h.db.query('SELECT desktop_number FROM sales_invoices WHERE global_id=@g', {'g': invGid});
      expect(row.first[0], 'INV-7');

      // Desktop now includes the posted invoice (11.6): served = 11.6 − 5 − 2.9.
      await h.call('POST', '/desktop/master', headers: desk, body: {
        'parties': [
          {'globalId': Demo.cust2Gid, 'name': 'سوبرماركت النور', 'balance': 11.6, 'creditLimit': 0},
        ],
      });
      expect(await balance(Demo.cust2Gid), closeTo(3.7, 1e-9));
      final (_, ping) = await h.call('GET', '/desktop/ping', headers: desk);
      expect(ping['pending'],
          {'sales_invoice': 0, 'sales_return': 1, 'collection': 1, 'visit': 1, 'customer': 0, 'expense': 0});
    });

    test('van stock pushed by the desktop subtracts unposted field sales', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final r = await push(rep, [
        {
          'kind': 'sales_invoice',
          'globalId': _uuid.v4(),
          'number': await lease(rep, 'sales_invoice'),
          'customerGlobalId': Demo.cust2Gid,
          'lines': [
            {'productGlobalId': Demo.prodBreadGid, 'quantity': 3, 'unitPrice': 1},
          ],
          'paid': 3,
        },
      ]);
      expect(r.single['status'], 'accepted', reason: '${r.single}');
      final van = (await h.db.query('''
        SELECT w.global_id FROM rep_resources rr JOIN warehouses w ON w.id = rr.van_warehouse_id
        JOIN employees e ON e.id = rr.employee_id WHERE e.global_id=@e''', {'e': Demo.rep1Gid})).first[0];
      await h.call('POST', '/desktop/master', headers: desk, body: {
        'vanStock': [
          {'warehouseGlobalId': van, 'productGlobalId': Demo.prodBreadGid, 'quantity': 20},
        ],
      });
      final q = await h.db.query('''
        SELECT ib.quantity FROM inventory_balances ib JOIN products p ON p.id = ib.product_id
        JOIN warehouses w ON w.id = ib.warehouse_id WHERE w.global_id=@w AND p.global_id=@p''',
          {'w': van, 'p': Demo.prodBreadGid});
      expect(num0(q.first[0]), 17);
    });
  });
}
