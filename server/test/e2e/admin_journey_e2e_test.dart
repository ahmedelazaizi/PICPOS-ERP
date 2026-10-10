@Tags(['postgres'])
library;

// E2E: «PicPos إدارة» عبر HTTP حقيقي — المكتب يدفع المفتاح والمستخدمين واللقطات
// الموقّعة، الجوال يقترن ويسجل الدخول ويقرأ ما تسمح به صلاحياته، المكتب يحدّث
// اللقطات (الأحدث يفوز)، ثم إلغاء الاقتران/إبطال الجلسة.
// (التحقق من توقيع Ed25519 نفسه مغطى في packages/picpos_api_client وmobile_admin.)

import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart' show hashPin;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/e2e_cloud.dart';

const _uuid = Uuid();

void main() {
  late E2eCloud cloud;
  late Map<String, String> desk;
  final pub = base64.encode(List<int>.generate(32, (i) => i + 1));
  const ownerGid = 'e2e-owner';
  const clerkGid = 'e2e-clerk';
  const password = 'mobile-pass-1';

  // بصمة PBKDF2 (1000 دورة) كما يولّدها المكتب.
  late String passwordHash;

  Map<String, Object?> user(String gid, String username,
          {bool enabled = true, List<String>? perms, List<int> scope = const [], int version = 1}) =>
      {
        'globalId': gid,
        'username': username,
        'displayName': 'User $username',
        'locale': 'ar',
        'mobileEnabled': enabled,
        'mobilePasswordHash': passwordHash,
        'permissions': perms ??
            ['mobile_admin_access', 'dashboard_sales_today', 'treasury_view', 'sales_return_approve'],
        'branchScope': scope,
        'require2fa': false,
        'version': version,
      };

  Map<String, Object?> snap(String kind, Object payload, {String scope = 'all', DateTime? asOf}) => {
        'kind': kind,
        'scope': scope,
        'asOf': (asOf ?? DateTime.now().toUtc()).toIso8601String(),
        'payload': payload,
        'signature': 'ed25519:${base64.encode(List<int>.filled(64, 9))}',
      };

  setUpAll(() async {
    cloud = await E2eCloud.start();
    desk = await cloud.desktopLink(cloud.companyA);
    passwordHash = hashPin(password, iterations: 1000);
    final key = await cloud.call('POST', '/desktop/link/signing-key',
        headers: desk, body: {'publicKey': pub, 'decimals': 3});
    expect(key.status, 204, reason: '$key');
  });
  tearDownAll(() async => cloud.stop());

  Future<(String, Map<String, String>, Map<String, String>)> phone(String gid, String username) async {
    final code = await cloud.call('POST', '/desktop/admin-pairing-codes', headers: desk, body: {'userGlobalId': gid});
    expect(code.status, 201, reason: '$code');
    final deviceId = _uuid.v4();
    final pair = await cloud.call('POST', '/manage/pair',
        body: {'code': code.json['code'], 'deviceId': deviceId, 'deviceName': 'Pixel', 'appVersion': '0.2.0'});
    expect(pair.status, 200, reason: '$pair');
    expect(pair.json['desktopSigningKey'], pub, reason: 'المفتاح العام يأتي من المكتب لا من الجوال');
    final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': deviceId};
    final login = await cloud.call('POST', '/manage/login', headers: dh, body: {'username': username, 'password': password});
    expect(login.status, 200, reason: '$login');
    return (deviceId, dh, {...dh, 'x-session-token': login.json['sessionToken'] as String});
  }

  test('رحلة المدير: مستخدمون + لقطات موقّعة ← اقتران ← لوحة ← موافقات ← تحديث ← إلغاء', () async {
    final push = await cloud.call('POST', '/desktop/users', headers: desk, body: {
      'users': [
        user(ownerGid, 'owner'),
        user(clerkGid, 'clerk', perms: ['mobile_admin_access', 'dashboard_sales_today'], scope: [2]),
      ],
    });
    expect(push.status, 200, reason: '$push');

    final approvals = {
      'items': [
        {'ref': 'SR-1', 'summary': 'مرتجع مبيعات', 'amount': '12.500'},
        {'ref': 'SR-2', 'summary': 'مرتجع مبيعات', 'amount': '3.000'},
      ],
    };
    final snaps = await cloud.call('POST', '/desktop/snapshots', headers: desk, body: {
      'items': [
        snap('kpi.today', {'netSales': '51.000', 'invoiceCount': 2}),
        snap('kpi.today', {'netSales': '9.000'}, scope: 'branch:2'),
        snap('kpi.today', {'netSales': '7.000'}, scope: 'branch:3'),
        snap('approvals.sales_returns', approvals),
        snap('approvals.payroll', {'items': []}),
      ],
    });
    expect(snaps.status, 200, reason: '$snaps');
    expect(snaps.json['stored'], 5);

    // المالك: كل الفروع + الموافقات التي يملك صلاحيتها فقط (لا payroll).
    final (ownerDevice, ownerDh, owner) = await phone(ownerGid, 'owner');
    var read = await cloud.call('GET', '/manage/snapshots', headers: owner);
    expect(read.status, 200, reason: '$read');
    final seen = {for (final i in read.json['items'] as List) '${(i as Map)['kind']}@${i['scope']}'};
    expect(seen, {'kpi.today@all', 'kpi.today@branch:2', 'kpi.today@branch:3', 'approvals.sales_returns@all'});
    final appr = (read.json['items'] as List).cast<Map>().firstWhere((i) => i['kind'] == 'approvals.sales_returns');
    expect((appr['payload'] as Map)['items'], hasLength(2));
    expect(appr['signature'], startsWith('ed25519:'));

    // الموظف ذو نطاق الفرع 2: لقطة الفرع 2 فقط.
    final (_, _, clerk) = await phone(clerkGid, 'clerk');
    read = await cloud.call('GET', '/manage/snapshots', headers: clerk);
    expect([for (final i in read.json['items'] as List) '${(i as Map)['kind']}@${i['scope']}'], ['kpi.today@branch:2']);

    // المكتب يدفع لقطة أحدث ← الجوال يراها؛ لقطة أقدم تُتجاهل.
    await cloud.call('POST', '/desktop/snapshots', headers: desk, body: {
      'items': [
        snap('approvals.sales_returns', {
          'items': [
            {'ref': 'SR-2', 'summary': 'مرتجع مبيعات', 'amount': '3.000'},
          ],
        }, asOf: DateTime.now().toUtc().add(const Duration(seconds: 5))),
        snap('approvals.sales_returns', approvals, asOf: DateTime.now().toUtc().subtract(const Duration(hours: 3))),
      ],
    });
    read = await cloud.call('GET', '/manage/snapshots?kinds=approvals.sales_returns', headers: owner);
    expect((((read.json['items'] as List).single as Map)['payload'] as Map)['items'], hasLength(1),
        reason: 'الأحدث يفوز والأقدم يُتجاهل');

    // تسجيل الخروج يبطل الجلسة فقط؛ الجهاز يبقى مقترنًا.
    expect((await cloud.call('POST', '/manage/logout', headers: owner)).status, 204);
    final reLogin = await cloud.call('POST', '/manage/login', headers: ownerDh, body: {'username': 'owner', 'password': password});
    expect(reLogin.status, 200, reason: '$reLogin');
    final owner2 = {...ownerDh, 'x-session-token': reLogin.json['sessionToken'] as String};

    // إلغاء الاقتران من الجوال: idempotent، ويرفض كل شيء بعده، والمكتب يرى revoked.
    for (var i = 0; i < 2; i++) {
      expect((await cloud.call('POST', '/manage/unpair', headers: ownerDh)).status, 204);
    }
    for (final r in [
      await cloud.call('GET', '/manage/snapshots', headers: owner2),
      await cloud.call('POST', '/manage/login', headers: ownerDh, body: {'username': 'owner', 'password': password}),
    ]) {
      expect(r.status, 401, reason: '$r');
      expect(r.error, 'device_revoked');
    }
    final devices = await cloud.call('GET', '/desktop/admin-devices', headers: desk);
    final row = (devices.json['devices'] as List).cast<Map>().firstWhere((d) => d['deviceId'] == ownerDevice);
    expect(row['revoked'], true);

    // إبطال من المكتب: جهاز الموظف.
    final clerkId = (devices.json['devices'] as List).cast<Map>().firstWhere((d) => d['revoked'] == false)['deviceId'];
    expect((await cloud.call('POST', '/desktop/admin-devices/$clerkId/revoke', headers: desk)).status, 200);
    final after = await cloud.call('GET', '/manage/snapshots', headers: clerk);
    expect(after.status, 401);
    expect(after.error, 'device_revoked');
  });

  test('تعطيل المستخدم على المكتب يبطل أجهزته عند دفع المستخدمين التالي', () async {
    await cloud.call('POST', '/desktop/users', headers: desk, body: {
      'users': [user('e2e-temp', 'temp')],
    });
    final (_, _, temp) = await phone('e2e-temp', 'temp');
    final dis = await cloud.call('POST', '/desktop/users', headers: desk, body: {
      'users': [user('e2e-temp', 'temp', enabled: false, version: 2)],
    });
    expect(dis.json['devicesRevoked'], 1, reason: '$dis');
    final r = await cloud.call('GET', '/manage/snapshots', headers: temp);
    expect(r.status, 401);
    expect(r.error, 'device_revoked');
  });
}
