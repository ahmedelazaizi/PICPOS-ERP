@Tags(['postgres'])
library;

// E2E: رحلة المندوب كاملة عبر HTTP حقيقي على خادم السحابة (عملية منفصلة) —
// اقتران برمز+PIN ← إقلاع ← مستندات أُنشئت دون إنترنت ← دفعها دفعة واحدة عند
// العودة ← إعادة التشغيل (replay) ← رفض وإعادة المحاولة ← تغذية المكتب (pending/ack)
// ← حل التعارض (فشل ثم نجاح) ← إلغاء الجهاز من المكتب.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/e2e_cloud.dart';

const _uuid = Uuid();

void main() {
  late E2eCloud cloud;
  late Map<String, String> desk;

  setUpAll(() async {
    cloud = await E2eCloud.start();
    desk = await cloud.desktopLink(cloud.companyA);
  });
  tearDownAll(() async => cloud.stop());

  /// جهاز مندوب مقترن ومسجَّل الدخول.
  Future<({String deviceId, Map<String, String> headers, Map<String, String> deviceHeaders})> repDevice(
      {String rep = E2eCloud.demoRep1, String pin = E2eCloud.rep1Pin}) async {
    final deviceId = _uuid.v4();
    final pair = await cloud.call('POST', '/mobile/pair',
        body: {'code': await cloud.repPairingCode(rep), 'deviceId': deviceId, 'deviceName': 'e2e-van'});
    expect(pair.status, 200, reason: '$pair');
    final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': deviceId};
    final login = await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': pin});
    expect(login.status, 200, reason: '$login');
    return (deviceId: deviceId, deviceHeaders: dh, headers: {...dh, 'x-session-token': login.json['sessionToken'] as String});
  }

  Future<List<Map<String, dynamic>>> push(Map<String, String> h, List<Map<String, Object?>> docs) async {
    final r = await cloud.call('POST', '/mobile/sync/push', headers: h, body: {'documents': docs});
    expect(r.status, 200, reason: '$r');
    return (r.json['results'] as List).cast<Map<String, dynamic>>();
  }

  test('الرحلة الكاملة: أوفلاين ← مزامنة ← replay ← رفض/إعادة ← المكتب ← إلغاء الجهاز', () async {
    // ── 1) اقتران: PIN خاطئ يُرفض، الصحيح يُقبل.
    final deviceId = _uuid.v4();
    final pair = await cloud.call('POST', '/mobile/pair',
        body: {'code': await cloud.repPairingCode(E2eCloud.demoRep1), 'deviceId': deviceId, 'deviceName': 'van'});
    expect(pair.status, 200, reason: '$pair');
    expect(pair.json['employeeGlobalId'], E2eCloud.demoRep1);
    final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': deviceId};
    final bad = await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': '0000'});
    expect(bad.status, 401, reason: '$bad');
    final ok = await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': E2eCloud.rep1Pin});
    expect(ok.status, 200);
    final h = {...dh, 'x-session-token': ok.json['sessionToken'] as String};

    // ── 2) إقلاع: عملاء الخط، مخزون السيارة، الدفاتر، الأرقام المحجوزة.
    final boot = await cloud.call('GET', '/mobile/bootstrap', headers: h);
    expect(boot.status, 200, reason: '$boot');
    final customers = {for (final c in boot.json['customers'] as List) (c as Map)['globalId']};
    expect(customers, containsAll([E2eCloud.cust1, E2eCloud.cust2]));
    expect(customers, isNot(contains(E2eCloud.cust3)), reason: 'عميل مندوب آخر خارج الخط');
    String lease(String t) {
      final l = (boot.json['leases'] as List).firstWhere((l) => l['docType'] == t);
      return '${l['prefix']}${l['nextNumber']}';
    }

    num stockOf(Map<String, dynamic> payload, String product) => ((payload['vanStock'] as List)
            .cast<Map>()
            .firstWhere((s) => s['productGlobalId'] == product)['quantity'] as num);
    final stock0 = stockOf(boot.json, E2eCloud.water);

    // ── 3) «أوفلاين»: المندوب يُنشئ مستندات محليًا (لا اتصال)، ثم يدفعها دفعة واحدة.
    final saleGid = _uuid.v4();
    final sale = {
      'kind': 'sales_invoice',
      'globalId': saleGid,
      'number': lease('sales_invoice'),
      'date': DateTime.now().toUtc().toIso8601String(),
      'customerGlobalId': E2eCloud.cust2,
      'lines': [
        {'productGlobalId': E2eCloud.water, 'quantity': 4, 'unitPrice': 2.5},
      ],
      'paid': 0,
    };
    final collection = {
      'kind': 'collection',
      'globalId': _uuid.v4(),
      'customerGlobalId': E2eCloud.cust2,
      'amount': 5,
      'bookGlobalId': '00000000-0000-4000-8000-0000000000d1',
      'bookNumber': 1001,
    };
    final expense = {
      'kind': 'expense',
      'globalId': _uuid.v4(),
      'date': DateTime.now().toUtc().toIso8601String(),
      'categoryGlobalId': '00000000-0000-4000-8000-00000000ef01',
      'amount': 12.5,
      'bookGlobalId': '00000000-0000-4000-8000-0000000000d3',
      'bookNumber': 5001,
    };
    final visit = {'kind': 'visit', 'globalId': _uuid.v4(), 'customerGlobalId': E2eCloud.cust1, 'outcome': 'visited'};
    final noSale = {
      'kind': 'visit',
      'globalId': _uuid.v4(),
      'customerGlobalId': E2eCloud.cust2,
      'outcome': 'no_sale',
      'noSaleReason': 'closed',
    };
    final foreign = {...visit, 'globalId': _uuid.v4(), 'customerGlobalId': E2eCloud.cust3};
    final batch = [sale, collection, expense, visit, noSale, foreign];

    final first = await push(h, batch);
    expect([for (final r in first) r['status']],
        ['accepted', 'accepted', 'accepted', 'accepted', 'accepted', 'rejected'],
        reason: '$first');
    expect(first[5]['code'], 'customer_not_on_route');
    expect(first[2]['number'], 'P-5001');

    // ── 4) replay: نفس الدفعة مرة ثانية ← duplicate، بلا أثر مضاعف.
    final again = await push(h, batch.sublist(0, 5));
    expect([for (final r in again) r['status']], everyElement('duplicate'));
    final pull1 = await cloud.call('GET', '/mobile/sync/pull?since=0', headers: h);
    expect(pull1.status, 200, reason: '$pull1');
    expect(stockOf(pull1.json, E2eCloud.water), stock0 - 4, reason: 'خُصم مرة واحدة فقط');
    final cust2 = (pull1.json['customers'] as List).cast<Map>().firstWhere((c) => c['globalId'] == E2eCloud.cust2);
    expect(cust2['balance'], closeTo(11.6 - 5, 1e-9), reason: '(فاتورة 11.6 − سند قبض 5) مرة واحدة');
    final docs = (pull1.json['documents'] as List).cast<Map>();
    expect(docs.map((d) => d['globalId']), containsAll([saleGid, collection['globalId'], expense['globalId']]));

    // ── 5) الرفض لا يترك أثرًا: إصلاح المستند وإعادة المحاولة بنفس globalId تنجح.
    final fixed = await push(h, [
      {...foreign, 'customerGlobalId': E2eCloud.cust1},
    ]);
    expect(fixed.single['status'], 'accepted', reason: '${fixed.single}');

    // ── 6) المكتب: ping + pending (كل الأنواع) + ack مختلط (تعارض).
    final ping = await cloud.call('GET', '/desktop/ping', headers: desk);
    expect(ping.json['pending'], containsPair('sales_invoice', 1));
    expect(ping.json['pending'], containsPair('expense', 1));
    final pend = await cloud.call('GET', '/desktop/documents/pending', headers: desk);
    final kinds = [for (final d in pend.json['documents'] as List) (d as Map)['kind']];
    expect(kinds, containsAll(['sales_invoice', 'collection', 'expense', 'visit']));
    final pendSale = (pend.json['documents'] as List).cast<Map>().firstWhere((d) => d['kind'] == 'sales_invoice');
    expect(pendSale['total'], 11.6);
    expect(pendSale['repEmployeeGlobalId'], E2eCloud.demoRep1);

    final collGid = collection['globalId'] as String;
    final ack1 = await cloud.call('POST', '/desktop/documents/ack', headers: desk, body: {
      'results': [
        {'kind': 'sales_invoice', 'globalId': saleGid, 'status': 'posted', 'desktopId': '9', 'desktopNumber': 'INV-9'},
        {'kind': 'collection', 'globalId': collGid, 'status': 'failed', 'reason': 'period_closed'},
      ],
    });
    expect(ack1.status, 200, reason: '$ack1');
    expect([for (final r in ack1.json['results'] as List) (r as Map)['status']], ['posted', 'failed_recorded']);
    var pend2 = await cloud.call('GET', '/desktop/documents/pending', headers: desk);
    var list2 = (pend2.json['documents'] as List).cast<Map>();
    expect(list2.where((d) => d['globalId'] == saleGid), isEmpty, reason: 'المرحَّل يخرج من الطابور');
    expect(list2.firstWhere((d) => d['globalId'] == collGid)['lastDesktopError'], 'period_closed');

    // حل التعارض: المكتب يعيد الترحيل بعد إصلاح السبب ← posted نهائي.
    final ack2 = await cloud.call('POST', '/desktop/documents/ack', headers: desk, body: {
      'results': [
        {'kind': 'collection', 'globalId': collGid, 'status': 'posted', 'desktopId': '4', 'desktopNumber': 'RC-4'},
      ],
    });
    expect((ack2.json['results'] as List).single['status'], 'posted', reason: '$ack2');
    pend2 = await cloud.call('GET', '/desktop/documents/pending', headers: desk);
    list2 = (pend2.json['documents'] as List).cast<Map>();
    expect(list2.where((d) => d['globalId'] == collGid), isEmpty);

    // ── 7) المكتب يلغي الجهاز: كل نداءات الجهاز والجلسة تُرفض.
    final rev = await cloud.call('POST', '/desktop/devices/$deviceId/revoke', headers: desk);
    expect(rev.status, 200, reason: '$rev');
    for (final r in [
      await cloud.call('GET', '/mobile/bootstrap', headers: h),
      await cloud.call('GET', '/mobile/sync/pull?since=0', headers: h),
      await cloud.call('POST', '/mobile/sync/push', headers: h, body: {'documents': []}),
      await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': E2eCloud.rep1Pin}),
    ]) {
      expect(r.status, 401, reason: '$r');
      expect(r.error, 'device_revoked');
    }
    // إعادة اقتران جهاز جديد للمندوب نفسه تعمل وترى المستندات المقبولة سابقًا.
    final d2 = await repDevice();
    final pull2 = await cloud.call('GET', '/mobile/sync/pull?since=0', headers: d2.headers);
    expect(pull2.status, 200, reason: '$pull2');
  });

  test('ترقيم المستندات: لا يمكن استخدام رقم خارج النطاق أو رقم مستخدم لمستند آخر', () async {
    final d = await repDevice();
    final boot = await cloud.call('GET', '/mobile/bootstrap', headers: d.headers);
    final l = (boot.json['leases'] as List).firstWhere((l) => l['docType'] == 'sales_invoice');
    final number = '${l['prefix']}${l['nextNumber']}';
    Map<String, Object?> sale(String n, {String? gid}) => {
          'kind': 'sales_invoice',
          'globalId': gid ?? _uuid.v4(),
          'number': n,
          'date': DateTime.now().toUtc().toIso8601String(),
          'customerGlobalId': E2eCloud.cust1,
          'lines': [
            {'productGlobalId': E2eCloud.bread, 'quantity': 1, 'unitPrice': 1.0},
          ],
          'paid': 1,
        };
    final r = await push(d.headers, [sale(number), sale(number), sale('${l['prefix']}999999')]);
    expect(r[0]['status'], 'accepted', reason: '${r[0]}');
    expect(r[1]['status'], 'rejected');
    expect(r[1]['code'], anyOf('number_already_used', 'global_id_conflict'));
    expect(r[2]['code'], 'number_out_of_range');
  });
}
