@Tags(['postgres'])
library;

// E2E أمان عابر للتطبيقات على خادم حقيقي عبر HTTP:
//  • عزل الشركات: المستأجر B لا يرى ولا يغيّر بيانات المستأجر A (مكتب/مندوب/إدارة).
//  • الرموز: مبطَلة/مزوّرة/خلط أجهزة/رموز اقتران مستعملة تُرفض.
//  • إعادة التشغيل (replay): مستند مدفوع مرتين لا يُطبَّق مرتين، ولا يتسرب بين مندوبين.
//  • القوة الغاشمة: حدّ محاولات الاقتران.

import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart' show hashPin;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/e2e_cloud.dart';

const _uuid = Uuid();

void main() {
  late E2eCloud cloud;
  late Map<String, String> deskA;
  late Map<String, String> deskB;

  // حدّ الاقتران 5 محاولات/عنوان/10 دقائق لكل نسخة خادم، لذا كل مجموعة تشغّل
  // خادمًا (وسكيمًا) خاصًا بها كي لا تستهلك مجموعة ميزانية الأخرى.
  void ownCloud() {
    setUpAll(() async {
      cloud = await E2eCloud.start();
      deskA = await cloud.desktopLink(cloud.companyA, name: 'A');
      deskB = await cloud.desktopLink(cloud.companyB, name: 'B');
    });
    tearDownAll(() async => cloud.stop());
  }

  Future<Map<String, String>> rep(String gid, String pin) async {
    final id = _uuid.v4();
    final p = await cloud.call('POST', '/mobile/pair',
        body: {'code': await cloud.repPairingCode(gid), 'deviceId': id, 'deviceName': 'sec'});
    expect(p.status, 200, reason: '$p');
    final dh = {'authorization': 'Bearer ${p.json['deviceToken']}', 'x-device-id': id};
    final l = await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': pin});
    expect(l.status, 200, reason: '$l');
    return {...dh, 'x-session-token': l.json['sessionToken'] as String};
  }

  group('عزل المستأجرين', () {
    ownCloud();
    test('ربط مكتب B لا يرى أجهزة ولا مستندات A ولا يستطيع إبطالها', () async {
      final h = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final push = await cloud.call('POST', '/mobile/sync/push', headers: h, body: {
        'documents': [
          {'kind': 'visit', 'globalId': _uuid.v4(), 'customerGlobalId': E2eCloud.cust1, 'outcome': 'visited'},
        ],
      });
      expect(((push.json['results'] as List).single as Map)['status'], 'accepted');

      expect((await cloud.call('GET', '/desktop/ping', headers: deskB)).json['company']['globalId'], cloud.companyB);
      expect(((await cloud.call('GET', '/desktop/documents/pending', headers: deskB)).json['documents'] as List), isEmpty);
      expect(((await cloud.call('GET', '/desktop/devices', headers: deskB)).json['devices'] as List), isEmpty);
      expect(((await cloud.call('GET', '/desktop/devices', headers: deskA)).json['devices'] as List), isNotEmpty);

      final devId = h['x-device-id']!;
      final rev = await cloud.call('POST', '/desktop/devices/$devId/revoke', headers: deskB);
      expect(rev.status, 404, reason: '$rev');
      expect((await cloud.call('GET', '/mobile/bootstrap', headers: h)).status, 200, reason: 'جهاز A ما زال يعمل');
    });

    test('B لا يستطيع إصدار رمز اقتران لمندوب A ولا بمفتاح الإدارة باسم B', () async {
      final viaDesk = await cloud.call('POST', '/desktop/pairing-codes',
          headers: deskB, body: {'employeeGlobalId': E2eCloud.demoRep2, 'pin': '1111'});
      expect(viaDesk.status, 404, reason: '$viaDesk');
      final viaAdmin = await cloud.call('POST', '/admin/pairing-codes',
          headers: cloud.adminHeaders,
          body: {'companyGlobalId': cloud.companyB, 'employeeGlobalId': E2eCloud.demoRep2});
      expect(viaAdmin.status, 404, reason: '$viaAdmin');
      // ولم يتغير PIN المندوب 2 (الدخول بالأصلي ما زال يعمل).
      await rep(E2eCloud.demoRep2, E2eCloud.rep2Pin);
    });

    test('دفع بيانات رئيسية من B بمعرّفات A (طرف/صنف) لا يعدّل بيانات A', () async {
      final h = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      Future<Map<String, dynamic>> boot() async => (await cloud.call('GET', '/mobile/bootstrap', headers: h)).json;
      final before = await boot();
      final c1Before = (before['customers'] as List).cast<Map>().firstWhere((c) => c['globalId'] == E2eCloud.cust1);
      final waterBefore = (before['products'] as List).cast<Map>().firstWhere((p) => p['globalId'] == E2eCloud.water);

      final r = await cloud.call('POST', '/desktop/master', headers: deskB, body: {
        'parties': [
          {'globalId': E2eCloud.cust1, 'name': 'HIJACKED', 'balance': 99999, 'creditLimit': 1},
        ],
        'products': [
          {'globalId': E2eCloud.water, 'name': 'HIJACKED', 'salePrice': 999, 'taxRate': 0},
        ],
      });
      // الخادم قد يرفض (4xx) أو يقبل ويتجاهل/ينسخ للمستأجر B؛ المهم ألا يمسّ A.
      expect(r.status, lessThan(500), reason: 'لا يجوز 500: $r');
      final after = await boot();
      final c1After = (after['customers'] as List).cast<Map>().firstWhere((c) => c['globalId'] == E2eCloud.cust1);
      final waterAfter = (after['products'] as List).cast<Map>().firstWhere((p) => p['globalId'] == E2eCloud.water);
      expect(c1After['name'], c1Before['name'], reason: 'اسم عميل A تغيّر بدفعة من B');
      expect(c1After['balance'], c1Before['balance']);
      expect(c1After['creditLimit'], c1Before['creditLimit']);
      expect(waterAfter['name'], waterBefore['name']);
      expect(waterAfter['salePrice'], waterBefore['salePrice']);
    });

    test('ack من B على مستند A لا يرحّله', () async {
      final h = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final gid = _uuid.v4();
      await cloud.call('POST', '/mobile/sync/push', headers: h, body: {
        'documents': [
          {'kind': 'visit', 'globalId': gid, 'customerGlobalId': E2eCloud.cust2, 'outcome': 'visited'},
        ],
      });
      final ack = await cloud.call('POST', '/desktop/documents/ack', headers: deskB, body: {
        'results': [
          {'kind': 'visit', 'globalId': gid, 'status': 'posted', 'desktopId': '1', 'desktopNumber': 'X-1'},
        ],
      });
      expect(ack.status, lessThan(500), reason: '$ack');
      final pending = await cloud.call('GET', '/desktop/documents/pending', headers: deskA);
      expect((pending.json['documents'] as List).map((d) => (d as Map)['globalId']), contains(gid));
    });

    test('إدارة: لقطات A لا تظهر لجهاز مستخدم B حتى لو تطابق globalId المستخدم', () async {
      final hash = hashPin('pw-pass-1', iterations: 1000);
      final pub = base64.encode(List<int>.filled(32, 5));
      Future<Map<String, String>> adminPhone(Map<String, String> desk, String company) async {
        await cloud.call('POST', '/desktop/link/signing-key', headers: desk, body: {'publicKey': pub});
        await cloud.call('POST', '/desktop/users', headers: desk, body: {
          'users': [
            {
              'globalId': 'same-gid',
              'username': 'boss',
              'mobileEnabled': true,
              'mobilePasswordHash': hash,
              'permissions': ['mobile_admin_access', 'dashboard_sales_today'],
              'branchScope': <int>[],
              'version': 1,
            },
          ],
        });
        final code = await cloud.call('POST', '/desktop/admin-pairing-codes', headers: desk, body: {'userGlobalId': 'same-gid'});
        expect(code.status, 201, reason: '$code');
        final id = _uuid.v4();
        final pair = await cloud.call('POST', '/manage/pair', body: {'code': code.json['code'], 'deviceId': id});
        expect(pair.status, 200, reason: '$pair');
        final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': id};
        final login = await cloud.call('POST', '/manage/login', headers: dh, body: {'username': 'boss', 'password': 'pw-pass-1'});
        expect(login.status, 200, reason: '$login');
        return {...dh, 'x-session-token': login.json['sessionToken'] as String};
      }

      Map<String, Object?> snap(String tag) => {
            'kind': 'kpi.today',
            'scope': 'all',
            'asOf': DateTime.now().toUtc().toIso8601String(),
            'payload': {'netSales': tag},
            'signature': 'ed25519:${base64.encode(List<int>.filled(64, 1))}',
          };
      final a = await adminPhone(deskA, cloud.companyA);
      final b = await adminPhone(deskB, cloud.companyB);
      await cloud.call('POST', '/desktop/snapshots', headers: deskA, body: {'items': [snap('A-ONLY')]});
      await cloud.call('POST', '/desktop/snapshots', headers: deskB, body: {'items': [snap('B-ONLY')]});
      String tagOf(E2eResponse r) => (((r.json['items'] as List).single as Map)['payload'] as Map)['netSales'] as String;
      expect(tagOf(await cloud.call('GET', '/manage/snapshots', headers: a)), 'A-ONLY');
      expect(tagOf(await cloud.call('GET', '/manage/snapshots', headers: b)), 'B-ONLY');
    });
  });

  group('الرموز والتوقيع', () {
    ownCloud();
    test('رمز جلسة مزوَّر/مبدَّل/بلا رمز يُرفض على كل نقاط المندوب', () async {
      final h = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final s = h['x-session-token']!;
      final tampered = '${s.substring(0, s.length - 2)}${s.endsWith('AA') ? 'BB' : 'AA'}';
      final flipBody = s.startsWith('a') ? 'b${s.substring(1)}' : 'a${s.substring(1)}';
      for (final bad in [tampered, flipBody, 'garbage', '']) {
        for (final path in ['/mobile/bootstrap', '/mobile/sync/pull?since=0']) {
          final r = await cloud.call('GET', path, headers: {...h, 'x-session-token': bad});
          expect(r.status, 401, reason: '$path بجلسة "$bad": $r');
        }
      }
      final noSession = {...h}..remove('x-session-token');
      expect((await cloud.call('GET', '/mobile/bootstrap', headers: noSession)).status, 401);
    });

    test('رمز جهاز لجهاز آخر، أو بلا رمز، أو رمز عشوائي ← 401', () async {
      final a = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final b = await rep(E2eCloud.demoRep2, E2eCloud.rep2Pin);
      // رمز جهاز a مع معرّف جهاز b، وجلسة b.
      var r = await cloud.call('GET', '/mobile/bootstrap',
          headers: {'authorization': a['authorization']!, 'x-device-id': b['x-device-id']!, 'x-session-token': b['x-session-token']!});
      expect(r.status, 401, reason: '$r');
      // جلسة b مع جهاز a.
      r = await cloud.call('GET', '/mobile/bootstrap', headers: {...a, 'x-session-token': b['x-session-token']!});
      expect(r.status, 401, reason: '$r');
      r = await cloud.call('GET', '/mobile/bootstrap', headers: {'x-device-id': a['x-device-id']!});
      expect(r.status, 401);
      r = await cloud.call('GET', '/mobile/bootstrap',
          headers: {...a, 'authorization': 'Bearer ${base64Url.encode(List.filled(32, 7))}'});
      expect(r.status, 401);
    });

    test('مفتاح الإدارة وربط المكتب: بلا مفتاح/خاطئ/سر مخلوط مع معرّف آخر ← مرفوض', () async {
      final noKey = await cloud.call('POST', '/admin/pairing-codes',
          body: {'companyGlobalId': cloud.companyA, 'employeeGlobalId': E2eCloud.demoRep1});
      expect(noKey.status, anyOf(401, 403));
      final wrong = await cloud.call('POST', '/admin/pairing-codes',
          headers: {'x-admin-key': 'nope'},
          body: {'companyGlobalId': cloud.companyA, 'employeeGlobalId': E2eCloud.demoRep1});
      expect(wrong.status, anyOf(401, 403));
      final mixed = {'authorization': deskA['authorization']!, 'x-desktop-link': deskB['x-desktop-link']!};
      expect((await cloud.call('GET', '/desktop/ping', headers: mixed)).status, 401);
    });

    test('رمز الاقتران وحيد الاستعمال، والقيمة العشوائية لا تقترن', () async {
      final code = await cloud.repPairingCode(E2eCloud.demoRep1);
      final first = await cloud.call('POST', '/mobile/pair', body: {'code': code, 'deviceId': _uuid.v4()});
      expect(first.status, 200);
      final second = await cloud.call('POST', '/mobile/pair', body: {'code': code, 'deviceId': _uuid.v4()});
      expect(second.status, 401, reason: '$second');
      expect(second.error, anyOf('code_expired', 'invalid_code'));
    });

    test('رمز ربط مكتب مبطَل يُرفض فورًا', () async {
      final tmp = await cloud.desktopLink(cloud.companyA, name: 'tmp');
      expect((await cloud.call('GET', '/desktop/ping', headers: tmp)).status, 200);
      expect((await cloud.call('POST', '/admin/desktop-links/${tmp['x-desktop-link']}/revoke', headers: cloud.adminHeaders)).status, 200);
      final r = await cloud.call('GET', '/desktop/ping', headers: tmp);
      expect(r.status, 401);
      expect(r.error, 'desktop_link_revoked');
    });

    test('تسجيل خروج الإدارة يجب أن يُبطل رمز الجلسة نفسه (إعادة استخدام رمز مسروق)', () async {
      final hash = hashPin('pw-logout-1', iterations: 1000);
      final pub = base64.encode(List<int>.filled(32, 5));
      await cloud.call('POST', '/desktop/link/signing-key', headers: deskA, body: {'publicKey': pub});
      await cloud.call('POST', '/desktop/users', headers: deskA, body: {
        'users': [
          {
            'globalId': 'logout-gid',
            'username': 'lo',
            'mobileEnabled': true,
            'mobilePasswordHash': hash,
            'permissions': ['mobile_admin_access'],
            'branchScope': <int>[],
            'version': 1,
          },
        ],
      });
      final code = await cloud.call('POST', '/desktop/admin-pairing-codes', headers: deskA, body: {'userGlobalId': 'logout-gid'});
      final id = _uuid.v4();
      final pair = await cloud.call('POST', '/manage/pair', body: {'code': code.json['code'], 'deviceId': id});
      final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': id};
      final login = await cloud.call('POST', '/manage/login', headers: dh, body: {'username': 'lo', 'password': 'pw-logout-1'});
      final h = {...dh, 'x-session-token': login.json['sessionToken'] as String};
      expect((await cloud.call('POST', '/manage/logout', headers: h)).status, 204);
      final reuse = await cloud.call('GET', '/manage/snapshots', headers: h);
      expect(reuse.status, 401, reason: 'الرمز ما زال صالحًا بعد logout: $reuse');
    }, skip: 'عيب إنتاج مكتشف (لم يُصلَح هنا): AdminService.logout يكتفي بسطر تدقيق، '
        'والجلسة HMAC بلا حالة فتبقى صالحة حتى انتهاء 12 ساعة بعد الخروج (server/lib/src/service/admin_service.dart:400). '
        'يلزم جدول/عمود إبطال جلسات (ترحيل DB) — قرار تصميم. أزل skip بعد الإصلاح.');
  });

  group('replay', () {
    ownCloud();
    test('مستند مندفع مرتين من جهازين للمندوب نفسه = duplicate، ومن مندوب آخر لا يُقبل', () async {
      final a = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final a2 = await rep(E2eCloud.demoRep1, E2eCloud.rep1Pin);
      final doc = {
        'kind': 'collection',
        'globalId': _uuid.v4(),
        'customerGlobalId': E2eCloud.cust2,
        'amount': 2,
        'bookGlobalId': '00000000-0000-4000-8000-0000000000d1',
        'bookNumber': 1020,
      };
      Future<Map> push(Map<String, String> h) async =>
          ((await cloud.call('POST', '/mobile/sync/push', headers: h, body: {'documents': [doc]})).json['results'] as List).single as Map;
      expect((await push(a))['status'], 'accepted');
      expect((await push(a))['status'], 'duplicate');
      expect((await push(a2))['status'], anyOf('duplicate', 'rejected'), reason: 'لا يُطبَّق مرتين');
      final b = await rep(E2eCloud.demoRep2, E2eCloud.rep2Pin);
      final other = await push(b);
      expect(other['status'], isNot('accepted'), reason: 'مندوب آخر لا يسرق/يعيد مستندًا: $other');
      final boot = await cloud.call('GET', '/mobile/sync/pull?since=0', headers: a);
      final c2 = (boot.json['customers'] as List).cast<Map>().firstWhere((c) => c['globalId'] == E2eCloud.cust2);
      // رصيد cust2 أُنقص مرة واحدة فقط بـ 2 (من الأساس).
      final once = (c2['balance'] as num).toDouble();
      expect(await push(a), containsPair('status', 'duplicate'));
      final again = await cloud.call('GET', '/mobile/sync/pull?since=0', headers: a);
      final c2b = (again.json['customers'] as List).cast<Map>().firstWhere((c) => c['globalId'] == E2eCloud.cust2);
      expect((c2b['balance'] as num).toDouble(), once);
    });
  });

  group('القوة الغاشمة', () {
    ownCloud();
    test('محاولات اقتران خاطئة متكررة من العنوان نفسه ← 429 مع Retry-After', () async {
      final codes = <int>[];
      for (var i = 0; i < 12; i++) {
        final r = await cloud.call('POST', '/mobile/pair', body: {'code': 'ZZZZ${i}ZZZ', 'deviceId': _uuid.v4()});
        codes.add(r.status);
        if (r.status == 429) {
          expect(r.headers['retry-after'], isNotNull);
          break;
        }
      }
      expect(codes, contains(429), reason: 'لم يُفعَّل حدّ المعدل: $codes');
    });
  });
}
