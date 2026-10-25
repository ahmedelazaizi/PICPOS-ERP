// A1 end to end against a REAL in-process host (shelf_io on loopback, the real
// middleware chain, the real ApiHandler):
//
//   pairing code (kind + branch from the host) -> device pairing over HTTP
//   -> tokenless user rows (no hashes) -> FIRST USER verified ON THE MAIN
//   (temporary password changed on the main) -> that session delivers the
//   branch's credentials -> seeded admin/admin retired -> login on the paired
//   device works for the delivered users, offline, and for nobody else.
import 'dart:io' show HttpOverrides;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/setup/first_user_verifier.dart';
import 'package:picpos_erp/services/setup/main_auth_port.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  // The widget-test binding stubs every dart:io HttpClient with a 400; this test
  // talks to a REAL loopback server.
  setUpAll(() => HttpOverrides.global = null);

  late LanHost host;
  late HostFixture fx;
  late String base;
  late LanDevice device;

  Future<FirstUserVerifier> pairedVerifier({required int branch}) async {
    final offer = await host.issue(kind: 'client', branchId: branch);
    device = LanDevice(host.overHttp(base), 'dev-real-1', name: 'POS-REAL');
    final paired = await device.pair(offer.code, kind: 'client');
    expect(paired.status, 200, reason: '$paired');
    expect(paired.json['deviceKind'], 'client');
    expect(paired.json['branchId'], branch);

    // what the first sync already brought: roles, then the tokenless user rows
    for (final role in await host.db.select(host.db.roles).get()) {
      await device.db.into(device.db.roles).insert(
          RolesCompanion.insert(name: role.name, id: Value(role.id)),
          mode: InsertMode.insertOrIgnore);
    }
    final tokenless = await device.syncUsers(withSession: false);
    expect(tokenless.status, 200, reason: '$tokenless');

    return FirstUserVerifier(
      db: device.db,
      port: HttpMainAuthPort(
        baseUrl: base,
        deviceToken: device.deviceToken!,
        deviceId: device.id,
        deviceName: device.name,
      ),
      permissionCodes: (_) async => const ['pos_access', 'pos_save'],
    );
  }

  setUp(() async {
    ActivationHints.clear();
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
  });

  tearDown(() async {
    await host.close();
    await device.dispose();
    ActivationHints.clear();
  });

  test('pairing -> first-user verification -> credentials delivery -> login on '
      'the paired device, with the seeded admin disabled', () async {
    final v = await pairedVerifier(branch: fx.branch1);

    // BEFORE: a fresh device only has the seeded admin/admin; nobody else can
    // sign in (the tokenless rows carry no hashes)
    expect(await device.canLogin('admin', 'admin'), isTrue);
    expect(await device.canLogin('cashier1', kInitialPw), isFalse);

    // 1. the first user holds a TEMPORARY password: the main demands a change
    final needs = await v.verify(
        username: 'cashier1', password: kInitialPw, branchId: fx.branch1);
    expect(needs.ok, isFalse);
    expect(needs.needsPasswordChange, isTrue);
    expect(await device.canLogin('admin', 'admin'), isTrue,
        reason: 'nothing happens before a verified first user');

    // 2. the change is made ON THE MAIN, then the session delivers credentials
    final ok = await v.verify(
        username: 'cashier1',
        password: kInitialPw,
        branchId: fx.branch1,
        newPassword: 'Cash#Brand-New1');
    expect(ok.ok, isTrue, reason: '${ok.error}');
    expect(ok.permissionCount, 2);
    expect(ActivationHints.credentialsDeliveredAt, isNotNull);
    expect(await host.db.authenticateUser('cashier1', 'Cash#Brand-New1'),
        isNotNull,
        reason: 'the main holds the new password');

    // 3. AFTER: the delivered credentials are the only logins
    expect(await device.canLogin('cashier1', 'Cash#Brand-New1'), isTrue);
    expect(await device.canLogin('acct1', HostFixture.acctPw), isTrue,
        reason: 'another user of the same branch');
    expect(await device.canLogin('admin', 'admin'), isFalse,
        reason: 'the seeded admin is disabled');
    expect(await device.canLogin('admin', kHostAdminPw), isFalse,
        reason: 'a cashier session never receives the admin hash');
    expect(await device.canLogin('cashier1', kInitialPw), isFalse);

    // 4. a branch-bound device never received other branches' users' hashes
    for (final name in ['b2cashier', 'outsider']) {
      final row = await (device.db.select(device.db.users)
            ..where((u) => u.username.equals(name)))
          .getSingleOrNull();
      expect(row?.passwordHash ?? '', anyOf(isEmpty, isNot(contains('\$argon2'))),
          reason: '$name must not be loginable here');
    }
    expect(await device.canLogin('b2cashier', HostFixture.b2Pw), isFalse);
    expect(await device.canLogin('outsider', HostFixture.outsiderPw), isFalse);
  });

  test('a user of ANOTHER branch is refused by the main; nothing is delivered '
      'and the seeded admin is not retired', () async {
    final v = await pairedVerifier(branch: fx.branch1);
    final r = await v.verify(
        username: 'b2cashier', password: HostFixture.b2Pw, branchId: fx.branch1);
    expect(r.ok, isFalse);
    expect(r.error, isNotEmpty);
    expect(await device.canLogin('b2cashier', HostFixture.b2Pw), isFalse);
    expect(await device.canLogin('admin', 'admin'), isTrue);
    expect(ActivationHints.credentialsDeliveredAt, isNull);
  });

  test('a wrong password is refused and delivers nothing', () async {
    final v = await pairedVerifier(branch: fx.branch1);
    final r = await v.verify(
        username: 'acct1', password: 'not-the-password', branchId: fx.branch1);
    expect(r.ok, isFalse);
    expect(await device.canLogin('acct1', HostFixture.acctPw), isFalse);
    expect(await device.canLogin('admin', 'admin'), isTrue);
  });

  test('the administrator as first user (branch exempt): gets the full set, '
      'with the custom admin password, and admin/admin is gone', () async {
    final v = await pairedVerifier(branch: fx.branch2);
    final r = await v.verify(
        username: 'admin', password: kHostAdminPw, branchId: fx.branch2);
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(await device.canLogin('admin', kHostAdminPw), isTrue);
    expect(await device.canLogin('admin', 'admin'), isFalse);
  });

  test('a revoked device can no longer verify anyone', () async {
    final v = await pairedVerifier(branch: fx.branch1);
    await host.pairing.revoke(device.id, actorUserId: 1);
    final r = await v.verify(
        username: 'acct1', password: HostFixture.acctPw, branchId: fx.branch1);
    expect(r.ok, isFalse);
    expect(await device.canLogin('acct1', HostFixture.acctPw), isFalse);
  });
}
