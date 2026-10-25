// F9 - SECURITY NEGATIVES on the fleet: a stolen device token is confined to
// its kind's routes; the admin credential never reaches a non-admin session;
// the legacy shared bearer is counted; lockouts survive a restart.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';
import 'package:picpos_erp/services/login_lockout_store.dart';
import 'package:picpos_erp/services/login_rate_limiter.dart';

import '../helpers/fleet_harness.dart';
import '../helpers/lan_host_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async {
    ApiAuthMiddleware.closePairingWindow();
    LegacyTokenTelemetry.instance.reset();
    LoginRateLimiter.reset();
    LoginLockoutStore.detachForTesting();
    fleet = await Fleet.build();
  });
  tearDown(() async {
    LoginRateLimiter.reset();
    LoginLockoutStore.detachForTesting();
    await fleet.dispose();
  });

  test('F9.1 a stolen device token cannot leave its kind: warehouse -> only '
      'its own routes; mirror -> no POS; a token under another id is dead',
      () async {
    final wh = LanDevice(fleet.main.overHttp(fleet.base), 'wh-phone-1');
    final code = await fleet.main.issue(kind: 'warehouse', branchId: fleet.branch1, fingerprint: 'AB:CD:EF:01');
    expect((await wh.pair(code.code, kind: 'warehouse')).status, 200);
    for (final path in ['/api/users', '/api/products', '/api/sales', '/api/settings']) {
      final r = await wh.get(path, withSession: false);
      expect(r.status, 403, reason: '$path: $r');
      expect(r.body, contains('device_scope'));
    }

    final mirror = await fleet.peer(fleet.mirror);
    await mirror.login('manager', kManagerFleetPw);
    for (final path in ['/api/sales/held', '/api/sales/held-items']) {
      expect((await mirror.get(path)).status, 403, reason: path);
    }
    expect((await mirror.post('/api/pos-terminals/register', {})).status, 403);

    final cashier = await fleet.peer(fleet.cashier);
    final stolen = LanDevice(fleet.main.overHttp(fleet.base), 'someone-elses-id')
      ..deviceToken = cashier.deviceToken;
    expect((await stolen.get('/api/users', withSession: false)).status, isNot(200));
    final noToken = LanDevice(fleet.main.overHttp(fleet.base), cashier.id);
    expect((await noToken.get('/api/users', withSession: false)).status, isNot(200));
    await wh.dispose();
  });

  test('F9.2 the admin credential is never delivered to a non-admin session '
      '(users feed, settings feed, device databases)', () async {
    final adminHash = (await fleet.main.db.getUserByUsername('admin'))!.user.passwordHash;
    expect(adminHash, startsWith(r'$argon2'));

    for (final entry in {
      fleet.cashier: ['cashier', kCashPw],
      fleet.accountant: ['accountant', kAcctPw],
      fleet.mirror: ['manager', kManagerFleetPw],
    }.entries) {
      final peer = await fleet.peer(entry.key);
      expect((await peer.login(entry.value[0], entry.value[1])).status, 200,
          reason: entry.key.label);
      final users = await peer.get('/api/users');
      expect(users.body, isNot(contains(adminHash)), reason: '${entry.key.label}: /api/users');
      final admin = (users.json['users'] as List)
          .cast<Map>()
          .where((u) => u['username'] == 'admin');
      for (final a in admin) {
        expect('${a['passwordHash'] ?? ''}', isNot(startsWith(r'$argon2')),
            reason: '${entry.key.label}: admin row carries no usable hash');
      }
      final settings = await peer.get('/api/settings');
      expect(settings.body, isNot(contains('admin_password_hash')));
      expect(settings.body, isNot(contains('developer_password_hash')));
      expect(settings.body, isNot(contains(adminHash)));
      expect(await entry.key.db.authenticateUser('admin', kMainAdminPw), isNull,
          reason: '${entry.key.label}: the admin cannot sign in on a branch device');
    }
  });

  test('F9.3 the legacy shared bearer is counted per device; paired fleet '
      'devices are not on it; closing the window is refused while it is used',
      () async {
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    final old = LanDevice(fleet.main.overHttp(fleet.base), 'old-tablet');
    for (var i = 0; i < 3; i++) {
      final r = await old.transport('GET', '/api/users',
          old.headers(bearer: 'legacy-shared-token'), null);
      expect(r.status, 200, reason: '$r');
    }
    final usage = await fleet.main.pairing.legacyUsage();
    expect(usage.inUse, isTrue);
    expect(usage.devices.map((d) => d.deviceId), ['old-tablet']);
    expect(usage.requestsSinceStart, greaterThanOrEqualTo(3));
    expect(LegacyTokenTelemetry.instance.requestsByDevice.keys,
        isNot(anyOf(contains(fleet.cashier.deviceId), contains(fleet.mirror.deviceId))));
    expect(await fleet.main.pairing.endLegacyTransitionIfUnused(), isFalse);
    await old.dispose();
  });

  test('F9.4 a device lockout (5 wrong passwords) survives a restart of the '
      'app', () async {
    await fleet.use(fleet.cashier);
    final repo = fleet.repo(fleet.cashier);
    for (var i = 0; i < 4; i++) {
      expect(await repo.authenticateUser('cashier', 'wrong-Password$i'), isNull);
    }
    await expectLater(repo.authenticateUser('cashier', 'wrong-Password-final'),
        throwsA(isA<AuthRejectedException>()));
    await expectLater(repo.authenticateUser('cashier', kCashPw),
        throwsA(isA<AuthRejectedException>()),
        reason: 'locked even with the right password');

    // restart: the process forgets everything in memory, the database stays
    LoginRateLimiter.reset();
    LoginLockoutStore.detachForTesting();
    await expectLater(fleet.repo(fleet.cashier).authenticateUser('cashier', kCashPw),
        throwsA(isA<AuthRejectedException>()),
        reason: 'the lockout was reloaded from the device database');
  });

  test('F9.5 the main\'s login lockout survives a restart of the main',
      () async {
    ServerLoginThrottle.reset();
    final peer = await fleet.peer(fleet.cashier);
    for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
      expect((await peer.login('cashier', 'wrong-Password$i')).status, 401);
    }
    expect((await peer.login('cashier', kCashPw)).status, 429,
        reason: 'locked on the main even with the right password');
    // restart of the main: process memory is gone, its database stays
    await ServerLoginThrottle.restartForTesting();
    ServerLoginThrottle.configure(fleet.main.db);
    await ServerLoginThrottle.flush();
    expect((await peer.login('cashier', kCashPw)).status, 429,
        reason: 'the lockout must be persisted by the main');
  });
}