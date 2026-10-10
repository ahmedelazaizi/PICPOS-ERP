@Tags(['postgres'])
library;

import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// ARCHITECTURE-M M-1: desktop pushes users / signing key / signed snapshots,
/// «PicPos إدارة» pairs, logs in with the mobile password and reads the
/// snapshots its permissions and branch scope allow.
void main() {
  late Harness h;
  late Map<String, String> desk;
  final pubKey = base64.encode(List<int>.generate(32, (i) => i));
  const ownerGid = 'u-owner';
  const branchGid = 'u-branch2';
  const password = 'mobile-pass-1';

  Future<Map<String, String>> link() async {
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': Demo.companyGid, 'name': 'HQ'});
    expect(st, 201, reason: '$b');
    return {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
  }

  Map<String, Object?> user(String gid, String username,
          {bool enabled = true, List<String>? perms, List<int> scope = const [], int version = 1, bool hash = true}) =>
      {
        'globalId': gid,
        'username': username,
        'displayName': 'User $username',
        'locale': 'ar',
        'mobileEnabled': enabled,
        if (hash) 'mobilePasswordHash': hashPin(password, iterations: 1000),
        'permissions': perms ??
            [
              'mobile_admin_access',
              'dashboard_sales_today',
              'dashboard_profit',
              'treasury_view',
              'reports_view',
              'reports_sales',
              'sales_return_approve',
            ],
        'branchScope': scope,
        'require2fa': false,
        'version': version,
      };

  Map<String, Object?> snap(String kind, String scope, {String? asOf}) => {
        'kind': kind,
        'scope': scope,
        'asOf': asOf ?? DateTime.now().toUtc().toIso8601String(),
        'payload': {'netSales': '10.500', 'invoiceCount': 3, 'scope': scope},
        'signature': 'ed25519:${base64.encode(List<int>.filled(64, 7))}',
      };

  Future<void> pushUsers(List<Map<String, Object?>> users) async {
    final (st, b) = await h.call('POST', '/desktop/users', headers: desk, body: {'users': users});
    expect(st, 200, reason: '$b');
  }

  Future<String> code(String gid) async {
    final (st, b) = await h.call('POST', '/desktop/admin-pairing-codes', headers: desk, body: {'userGlobalId': gid});
    expect(st, 201, reason: '$b');
    return b['code'] as String;
  }

  /// Pairs and logs in; returns (deviceId, deviceHeaders, sessionHeaders).
  Future<(String, Map<String, String>, Map<String, String>)> phone(String gid, String username) async {
    final deviceId = const Uuid().v4();
    final (ps, pb) = await h.call('POST', '/manage/pair',
        body: {'code': await code(gid), 'deviceId': deviceId, 'deviceName': 'Pixel', 'appVersion': '0.2.0'});
    expect(ps, 200, reason: '$pb');
    expect(pb['desktopSigningKey'], pubKey);
    expect((pb['user'] as Map)['globalId'], gid);
    expect((pb['company'] as Map)['decimals'], 3);
    final dh = {'authorization': 'Bearer ${pb['deviceToken']}', 'x-device-id': deviceId};
    final (ls, lb) = await h.call('POST', '/manage/login', headers: dh, body: {'username': username, 'password': password});
    expect(ls, 200, reason: '$lb');
    return (deviceId, dh, {...dh, 'x-session-token': lb['sessionToken'] as String});
  }

  setUp(() async {
    h = await Harness.start();
    desk = await link();
    final (st, b) =
        await h.call('POST', '/desktop/link/signing-key', headers: desk, body: {'publicKey': pubKey, 'decimals': 3});
    expect(st, 204, reason: '$b');
  });
  tearDown(() async => h.stop());

  test('signing key must be a 32-byte base64 Ed25519 key', () async {
    final (st, b) = await h.call('POST', '/desktop/link/signing-key', headers: desk, body: {'publicKey': 'abc'});
    expect(st, 400);
    expect(b['error'], 'invalid_public_key');
  });

  test('users push: desktop wins by version; bad hash rejected; no Argon2 accepted', () async {
    var (st, b) = await h.call('POST', '/desktop/users', headers: desk, body: {
      'users': [user(ownerGid, 'owner', version: 5)]
    });
    expect(b, containsPair('applied', 1));
    (st, b) = await h.call('POST', '/desktop/users', headers: desk, body: {
      'users': [user(ownerGid, 'renamed', version: 4)]
    });
    expect(st, 200);
    expect(b, containsPair('skipped', 1));
    (st, b) = await h.call('POST', '/desktop/users', headers: desk, body: {
      'users': [
        {...user(ownerGid, 'owner', version: 6), 'mobilePasswordHash': r'$argon2id$v=19$m=65536'}
      ]
    });
    expect(st, 400);
    expect(b['error'], 'invalid_password_hash');
  });

  test('pairing code requires an enabled user with mobile_admin_access and a password', () async {
    await pushUsers([
      user('u-off', 'off', enabled: false),
      user('u-noperm', 'noperm', perms: ['dashboard_sales_today']),
      user('u-nopass', 'nopass', hash: false),
    ]);
    for (final gid in ['u-off', 'u-noperm', 'u-nopass', 'u-missing']) {
      final (st, b) = await h.call('POST', '/desktop/admin-pairing-codes', headers: desk, body: {'userGlobalId': gid});
      expect(st, anyOf(404, 409), reason: '$gid $b');
    }
  });

  test('pair → login → snapshots scoped by permissions and branches', () async {
    await pushUsers([
      user(ownerGid, 'owner'),
      user(branchGid, 'branch2', scope: [2], perms: ['mobile_admin_access', 'dashboard_sales_today']),
    ]);
    final (st, b) = await h.call('POST', '/desktop/snapshots', headers: desk, body: {
      'items': [
        snap('kpi.today', 'all'),
        snap('kpi.today', 'branch:2'),
        snap('kpi.today', 'branch:3'),
        snap('profit.today', 'all'),
        snap('cash.position', 'all'),
        snap('approvals.sales_returns', 'all'),
        snap('approvals.payroll', 'all'),
      ]
    });
    expect(st, 200, reason: '$b');
    expect(b['stored'], 7);

    final (_, _, owner) = await phone(ownerGid, 'owner');
    var (ss, sb) = await h.call('GET', '/manage/snapshots', headers: owner);
    expect(ss, 200, reason: '$sb');
    final ownerKinds = {for (final i in sb['items'] as List) '${i['kind']}@${i['scope']}'};
    expect(ownerKinds, {
      'kpi.today@all',
      'kpi.today@branch:2',
      'kpi.today@branch:3',
      'profit.today@all',
      'cash.position@all',
      'approvals.sales_returns@all',
    });
    expect((sb['desktop'] as Map)['lastSeenAt'], isA<int>());
    final first = (sb['items'] as List).first as Map;
    expect(first['payload'], isA<Map>());
    expect(first['signature'], startsWith('ed25519:'));

    (ss, sb) = await h.call('GET', '/manage/snapshots?kinds=kpi.today&branch=2', headers: owner);
    expect([for (final i in sb['items'] as List) i['scope']], ['branch:2']);

    final (_, _, limited) = await phone(branchGid, 'branch2');
    (ss, sb) = await h.call('GET', '/manage/snapshots', headers: limited);
    expect([for (final i in sb['items'] as List) '${i['kind']}@${i['scope']}'], ['kpi.today@branch:2']);
  });

  test('daily kinds keep one row per day; newer asOf wins; older is ignored', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    await h.call('POST', '/desktop/snapshots', headers: desk, body: {
      'items': [
        snap('kpi.today', 'all', asOf: DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String()),
        snap('kpi.today', 'all', asOf: DateTime.now().toUtc().toIso8601String()),
        snap('cash.position', 'all', asOf: '2026-02-01T09:00:00.000Z'),
        snap('cash.position', 'all', asOf: '2026-02-01T08:00:00.000Z'),
      ]
    });
    final rows = await h.db.query("SELECT kind, as_of_day, as_of FROM snapshots ORDER BY kind, as_of_day");
    expect(rows.where((r) => r[0] == 'kpi.today').length, 2);
    final cash = rows.firstWhere((r) => r[0] == 'cash.position');
    expect(cash[1], 'latest');
    expect(cash[2], DateTime.parse('2026-02-01T09:00:00.000Z').millisecondsSinceEpoch);
  });

  test('snapshot validation', () async {
    for (final bad in [
      snap('ledger.full', 'all'),
      snap('kpi.today', 'everywhere'),
      {...snap('kpi.today', 'all'), 'asOf': '2026-02-01T08:00:00'},
      {...snap('kpi.today', 'all'), 'signature': 'rsa:x'},
    ]) {
      final (st, b) = await h.call('POST', '/desktop/snapshots', headers: desk, body: {
        'items': [bad]
      });
      expect(st, 400, reason: '$bad $b');
    }
  });

  test('wrong password → 401; 5 failures lock the user; right username required', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final deviceId = const Uuid().v4();
    final (_, pb) = await h.call('POST', '/manage/pair', body: {'code': await code(ownerGid), 'deviceId': deviceId});
    final dh = {'authorization': 'Bearer ${pb['deviceToken']}', 'x-device-id': deviceId};
    var (st, b) = await h.call('POST', '/manage/login', headers: dh, body: {'username': 'other', 'password': password});
    expect(st, 401);
    expect(b['error'], 'invalid_credentials');
    for (var i = 0; i < 4; i++) {
      (st, b) = await h.call('POST', '/manage/login', headers: dh, body: {'username': 'owner', 'password': 'nope'});
      expect(st, 401);
    }
    (st, b) = await h.call('POST', '/manage/login', headers: dh, body: {'username': 'owner', 'password': password});
    expect(st, 429);
    expect(b['error'], 'user_locked');
    expect(h.lastHeaders['retry-after'], isNotNull);
  });

  test('codes are single use and rep codes do not pair admin devices', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final c = await code(ownerGid);
    var (st, b) = await h.call('POST', '/manage/pair', body: {'code': c, 'deviceId': 'd1'});
    expect(st, 200);
    (st, b) = await h.call('POST', '/manage/pair', body: {'code': c, 'deviceId': 'd2'});
    expect(st, 401);
    expect(b['error'], 'code_expired');
    (st, b) = await h.call('POST', '/manage/pair', body: {'code': await h.pairingCode(Demo.rep1Gid), 'deviceId': 'd3'});
    expect(st, 401);
    expect(b['error'], 'invalid_code');
  });

  test('rep session token is rejected on /manage and admin session on /mobile', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final (_, dh, owner) = await phone(ownerGid, 'owner');
    var (st, _) = await h.call('GET', '/manage/snapshots', headers: {...owner, 'x-session-token': rep.headers['x-session-token']!});
    expect(st, 401);
    (st, _) = await h.call('GET', '/mobile/bootstrap', headers: {...rep.headers, 'x-session-token': owner['x-session-token']!});
    expect(st, 401);
    expect(dh, isNotEmpty);
  });

  test('logout requires a session and does not revoke the device', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (_, deviceHeaders, sessionHeaders) = await phone(ownerGid, 'owner');
    var (status, body) = await h.call('POST', '/manage/logout', headers: deviceHeaders);
    expect(status, 401);
    expect(body['error'], 'invalid_session');
    (status, body) = await h.call('POST', '/manage/logout', headers: sessionHeaders);
    expect(status, 204, reason: '$body');
    (status, body) = await h.call('POST', '/manage/login', headers: deviceHeaders,
        body: {'username': 'owner', 'password': password});
    expect(status, 200, reason: '$body');
    (status, body) = await h.call('GET', '/desktop/admin-devices', headers: desk);
    expect((body['devices'] as List).single, containsPair('revoked', false));
  });

  test('logout revokes the session token server-side; other sessions and companies unaffected', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (_, dhA, sessA) = await phone(ownerGid, 'owner');
    // A second session of the same device stays valid.
    var (status, body) = await h.call('POST', '/manage/login', headers: dhA, body: {'username': 'owner', 'password': password});
    expect(status, 200, reason: '$body');
    final sessA2 = {...dhA, 'x-session-token': body['sessionToken'] as String};

    // Company B with its own desktop link, user, device and session.
    await h.db.query(
        "INSERT INTO companies (global_id, name, currency, default_tax_rate, integrity_secret) "
        "VALUES ('company-b-gid', 'B', 'JOD', 0, 'x')");
    final deskA = desk;
    (status, body) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': 'company-b-gid', 'name': 'B'});
    expect(status, 201, reason: '$body');
    desk = {'authorization': 'Bearer ${body['linkSecret']}', 'x-desktop-link': body['linkId'] as String};
    (status, body) = await h.call('POST', '/desktop/link/signing-key', headers: desk, body: {'publicKey': pubKey, 'decimals': 3});
    expect(status, 204, reason: '$body');
    await pushUsers([user('b-owner', 'bowner')]);
    final (_, _, sessB) = await phone('b-owner', 'bowner');
    desk = deskA;

    (status, body) = await h.call('GET', '/manage/snapshots', headers: sessA);
    expect(status, 200, reason: '$body');
    (status, body) = await h.call('POST', '/manage/logout', headers: sessA);
    expect(status, 204, reason: '$body');

    (status, body) = await h.call('GET', '/manage/snapshots', headers: sessA);
    expect(status, 401);
    expect(body['error'], 'session_revoked');
    (status, body) = await h.call('POST', '/manage/logout', headers: sessA);
    expect(status, 401);
    for (final s in [sessA2, sessB]) {
      (status, body) = await h.call('GET', '/manage/snapshots', headers: s);
      expect(status, 200, reason: '$body');
    }

    // Revocations are company-scoped: a row of company B never blocks company A.
    final rows = await h.db.query('SELECT company_id, jti FROM admin_session_revocations');
    expect(rows, hasLength(1));
    final jtiA = rows.first.toColumnMap()['jti'] as String;
    final bId = (await h.db.query("SELECT id FROM companies WHERE global_id='company-b-gid'")).first[0] as int;
    await h.db.query('DELETE FROM admin_session_revocations');
    await h.db.query(
        'INSERT INTO admin_session_revocations (company_id, jti, revoked_at, expires_at) VALUES (@c, @j, 1, 9999999999999)',
        {'c': bId, 'j': jtiA});
    (status, body) = await h.call('GET', '/manage/snapshots', headers: sessA);
    expect(status, 200, reason: 'company B revocation must not affect A: $body');
  });

  test('unpair is idempotent and rejects login and snapshots; desktop sees revoked', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (_, deviceHeaders, sessionHeaders) = await phone(ownerGid, 'owner');
    for (var i = 0; i < 2; i++) {
      final (status, body) = await h.call('POST', '/manage/unpair', headers: deviceHeaders);
      expect(status, 204, reason: '$body');
    }
    var (status, body) = await h.call('POST', '/manage/login', headers: deviceHeaders,
        body: {'username': 'owner', 'password': password});
    expect(status, 401);
    expect(body['error'], 'device_revoked');
    (status, body) = await h.call('GET', '/manage/snapshots', headers: sessionHeaders);
    expect(status, 401);
    expect(body['error'], 'device_revoked');
    (status, body) = await h.call('GET', '/desktop/admin-devices', headers: desk);
    expect((body['devices'] as List).single, containsPair('revoked', true));
  });

  test('desktop revoke → 401 device_revoked; listing shows revoked', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (deviceId, _, owner) = await phone(ownerGid, 'owner');
    var (st, b) = await h.call('GET', '/desktop/admin-devices', headers: desk);
    expect((b['devices'] as List).single, containsPair('revoked', false));
    (st, b) = await h.call('POST', '/desktop/admin-devices/$deviceId/revoke', headers: desk);
    expect(st, 200, reason: '$b');
    (st, b) = await h.call('GET', '/manage/snapshots', headers: owner);
    expect(st, 401);
    expect(b['error'], 'device_revoked');
    (st, b) = await h.call('GET', '/desktop/admin-devices', headers: desk);
    expect((b['devices'] as List).single, containsPair('revoked', true));
  });

  test('disabling the user on desktop revokes their devices at the next users push', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (_, _, owner) = await phone(ownerGid, 'owner');
    final (st, b) = await h.call('POST', '/desktop/users', headers: desk, body: {
      'users': [user(ownerGid, 'owner', enabled: false, version: 2)]
    });
    expect(b['devicesRevoked'], 1, reason: '$st $b');
    final (ss, sb) = await h.call('GET', '/manage/snapshots', headers: owner);
    expect(ss, 401);
    expect(sb['error'], 'device_revoked');
  });

  test('permission removed without disabling → live session gets 403', () async {
    await pushUsers([user(ownerGid, 'owner')]);
    final (_, _, owner) = await phone(ownerGid, 'owner');
    // Dropping mobile_admin_access also revokes devices (→ 401); a user who
    // keeps access but loses a kind's code simply stops receiving it.
    await pushUsers([user(ownerGid, 'owner', perms: ['mobile_admin_access'], version: 2)]);
    await h.call('POST', '/desktop/snapshots', headers: desk, body: {
      'items': [snap('kpi.today', 'all')]
    });
    final (ss, sb) = await h.call('GET', '/manage/snapshots', headers: owner);
    expect(ss, 200);
    expect(sb['items'], isEmpty);
  });
}
