@Tags(['postgres'])
library;

import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// SEC-017: a compromised desktop signing seed must be recoverable. Rotating
/// the key re-publishes the public key AND revokes every paired admin device of
/// that company (they must re-pair and pin the new key); other companies are
/// untouched.
void main() {
  late Harness h;
  late Map<String, String> desk;
  final oldKey = base64.encode(List<int>.generate(32, (i) => i));
  final newKey = base64.encode(List<int>.generate(32, (i) => 100 + i));
  const gid = 'u-owner';
  const password = 'mobile-pass-1';

  Future<Map<String, String>> link(String companyGid) async {
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': companyGid, 'name': 'HQ'});
    expect(st, 201, reason: '$b');
    return {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
  }

  Map<String, Object?> user(String g, String username) => {
        'globalId': g,
        'username': username,
        'displayName': 'User $username',
        'locale': 'ar',
        'mobileEnabled': true,
        'mobilePasswordHash': hashPin(password, iterations: 1000),
        'permissions': ['mobile_admin_access', 'dashboard_sales_today'],
        'branchScope': <int>[],
        'require2fa': false,
        'version': 1,
      };

  Future<(String, Map<String, String>)> pairPhone(Map<String, String> d, String g, String username) async {
    var (st, b) = await h.call('POST', '/desktop/users', headers: d, body: {'users': [user(g, username)]});
    expect(st, 200, reason: '$b');
    (st, b) = await h.call('POST', '/desktop/admin-pairing-codes', headers: d, body: {'userGlobalId': g});
    expect(st, 201, reason: '$b');
    final deviceId = const Uuid().v4();
    (st, b) = await h.call('POST', '/manage/pair',
        body: {'code': b['code'], 'deviceId': deviceId, 'deviceName': 'Pixel', 'appVersion': '0.2.0'});
    expect(st, 200, reason: '$b');
    final dh = {'authorization': 'Bearer ${b['deviceToken']}', 'x-device-id': deviceId};
    return (deviceId, dh);
  }

  Future<void> expectRevoked(Map<String, String> dh) async {
    final (st, b) = await h.call('POST', '/manage/login', headers: dh, body: {'username': 'owner', 'password': password});
    expect(st, 401, reason: '$b');
    expect(b['error'], 'device_revoked');
  }

  setUp(() async {
    h = await Harness.start();
    desk = await link(Demo.companyGid);
    final (st, b) = await h.call('POST', '/desktop/link/signing-key', headers: desk, body: {'publicKey': oldKey, 'decimals': 3});
    expect(st, 204, reason: '$b');
  });
  tearDown(() async => h.stop());

  test('rotate-signing-key publishes the new key and revokes every admin device of the company', () async {
    final (idA, dhA) = await pairPhone(desk, gid, 'owner');
    final (idB, dhB) = await pairPhone(desk, 'u-owner2', 'owner2');

    final (st, b) = await h.call('POST', '/desktop/link/rotate-signing-key', headers: desk, body: {'publicKey': newKey});
    expect(st, 200, reason: '$b');
    expect(b['revokedDevices'], 2);

    await expectRevoked(dhA);
    final (ls, lb) = await h.call('POST', '/manage/login', headers: dhB, body: {'username': 'owner2', 'password': password});
    expect(ls, 401, reason: '$lb');
    expect(lb['error'], 'device_revoked');

    final (lsn, listing) = await h.call('GET', '/desktop/admin-devices', headers: desk);
    expect(lsn, 200);
    final devices = (listing['devices'] as List).cast<Map>();
    expect(devices.map((d) => d['deviceId']), containsAll([idA, idB]));
    expect(devices.every((d) => d['revoked'] == true), isTrue);

    // A fresh pairing receives the NEW key, never the old one.
    var (ps, pb) = await h.call('POST', '/desktop/admin-pairing-codes', headers: desk, body: {'userGlobalId': gid});
    expect(ps, 201, reason: '$pb');
    (ps, pb) = await h.call('POST', '/manage/pair',
        body: {'code': pb['code'], 'deviceId': const Uuid().v4(), 'deviceName': 'New', 'appVersion': '0.2.0'});
    expect(ps, 200, reason: '$pb');
    expect(pb['desktopSigningKey'], newKey);
  });

  test('an invalid new key is rejected and nothing is revoked', () async {
    final (_, dh) = await pairPhone(desk, gid, 'owner');
    final (st, b) = await h.call('POST', '/desktop/link/rotate-signing-key', headers: desk, body: {'publicKey': 'abc'});
    expect(st, 400);
    expect(b['error'], 'invalid_public_key');
    final (ls, lb) = await h.call('POST', '/manage/login', headers: dh, body: {'username': 'owner', 'password': password});
    expect(ls, 200, reason: '$lb');
  });

  test('rotation never touches another company', () async {
    final (_, dhA) = await pairPhone(desk, gid, 'owner');
    await h.db.query(
        "INSERT INTO companies (global_id, name, currency, default_tax_rate, integrity_secret) "
        "VALUES ('company-b-gid', 'B', 'JOD', 0, 'x')");
    final deskB = await link('company-b-gid');
    final (st0, b0) = await h.call('POST', '/desktop/link/signing-key', headers: deskB, body: {'publicKey': oldKey, 'decimals': 3});
    expect(st0, 204, reason: '$b0');
    final (_, dhB) = await pairPhone(deskB, 'b-owner', 'bowner');

    final (st, b) = await h.call('POST', '/desktop/link/rotate-signing-key', headers: desk, body: {'publicKey': newKey});
    expect(st, 200, reason: '$b');
    expect(b['revokedDevices'], 1);
    await expectRevoked(dhA);
    final (ls, lb) = await h.call('POST', '/manage/login', headers: dhB, body: {'username': 'bowner', 'password': password});
    expect(ls, 200, reason: '$lb');
  });

  test('revoke-all revokes every admin device without touching the key', () async {
    final (_, dh) = await pairPhone(desk, gid, 'owner');
    final (st, b) = await h.call('POST', '/desktop/admin-devices/revoke-all', headers: desk);
    expect(st, 200, reason: '$b');
    expect(b['revokedDevices'], 1);
    await expectRevoked(dh);
    // idempotent: nothing left to revoke
    final (st2, b2) = await h.call('POST', '/desktop/admin-devices/revoke-all', headers: desk);
    expect(st2, 200);
    expect(b2['revokedDevices'], 0);
  });

  test('both routes need a desktop link', () async {
    for (final path in ['/desktop/link/rotate-signing-key', '/desktop/admin-devices/revoke-all']) {
      final (st, _) = await h.call('POST', path, body: {'publicKey': newKey});
      expect(st, 401, reason: path);
    }
  });

  test('the rotation is audited', () async {
    await pairPhone(desk, gid, 'owner');
    await h.call('POST', '/desktop/link/rotate-signing-key', headers: desk, body: {'publicKey': newKey});
    final rows = await h.db.query("SELECT count(*) FROM audit_log WHERE action='admin_signing_key_rotated'");
    expect(rows.single[0], 1);
  });
}
