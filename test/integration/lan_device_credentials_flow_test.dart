// P1 + M1 (plan 2026-10-24) over a REAL socket (`shelf_io`) with TWO peers:
// the host database and a device database (and a mirror database).
//
//  * pairing -> credentials delivery -> login on the paired device, with the
//    manual 5-minute pairing window CLOSED (SETUP-001);
//  * forced password change from the device (POST /api/auth/change-password);
//  * administrative reset that really applies (PUT /api/users/<id>);
//  * multi-branch user list for a manager on a mirror (MIR-010);
//  * revocation of a mirror / client device;
//  * legacy shared-token telemetry (SEC-006 closing gate).
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late String base;
  final devices = <LanDevice>[];

  LanDevice newDevice(String id) {
    final d = LanDevice(host.overHttp(base), id, rolesFrom: host.db);
    devices.add(d);
    return d;
  }

  setUp(() async {
    ApiAuthMiddleware.closePairingWindow();
    LegacyTokenTelemetry.instance.reset();
    host = await LanHost.start(legacyToken: true);
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
  });

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  Future<LanDevice> pairedClient(String id, {int? branch}) async {
    final offer = await host.issue(kind: 'client', branchId: branch ?? fx.branch1);
    final d = newDevice(id);
    final r = await d.pair(offer.code);
    expect(r.status, 200, reason: '$r');
    return d;
  }

  group('pairing -> credentials delivery -> login (no pairing window)', () {
    test('a client code carries kind + branch; the device never chooses them',
        () async {
      final offer = await host.issue(kind: 'client', branchId: fx.branch1);
      final d = newDevice('dev-1');
      // The device asks for another branch: ignored, the code decides.
      final r = await d.pair(offer.code, branchId: fx.branch2);
      expect(r.status, 200, reason: '$r');
      expect(r.json['deviceKind'], 'client');
      expect(r.json['branchId'], fx.branch1);
      final row = await host.pairing.deviceById('dev-1');
      expect(row!.deviceKind, 'client');
      expect(row.branchId, fx.branch1);
      // one-time code
      final again = await newDevice('dev-2').pair(offer.code);
      expect(again.status, 401);
    });

    test('without a session the feed carries NO credentials; the first user\'s '
        'session delivers his branch\'s credentials', () async {
      expect(ApiAuthMiddleware.isPairingOpen, isFalse);
      final d = await pairedClient('dev-1');

      // 1. reference/tokenless sync: rows arrive, hashes do not.
      final blind = await d.syncUsers(withSession: false);
      expect(blind.status, 200);
      expect(await d.canLogin('acct1', HostFixture.acctPw), isFalse);

      // 2. the first user is verified ON THE HOST (admin = program owner).
      final s = await d.login('admin', kHostAdminPw);
      expect(s.status, 200, reason: '$s');

      // 3. with that session the device receives its branch's credentials.
      final feed = await d.syncUsers();
      final names = [
        for (final u in (feed.json['users'] as List).cast<Map<String, dynamic>>())
          u['username']
      ];
      expect(names, containsAll(['admin', 'cashier1', 'acct1']));
      expect(names, isNot(contains('b2cashier')),
          reason: 'a device is bound to its branch: other branches\' users '
              'and credentials are not delivered');
      expect(names, isNot(contains('outsider')));
      expect(feed.json['serverTime'], isA<int>());

      // 4. login on the paired device now works from its own database.
      expect(await d.canLogin('acct1', HostFixture.acctPw), isTrue);
      expect(await d.canLogin('admin', kHostAdminPw), isTrue);
      expect(await d.canLogin('b2cashier', HostFixture.b2Pw), isFalse);
    });

    test('a user of another branch cannot get a session on this device',
        () async {
      final d = await pairedClient('dev-1');
      final r = await d.login('b2cashier', HostFixture.b2Pw);
      expect(r.status, 403);
      expect(r.code, 'branch_access_denied');
    });

    test('the manual pairing window is not needed (and stays closed)',
        () async {
      final d = await pairedClient('dev-1');
      await d.login('admin', kHostAdminPw);
      await d.syncUsers();
      expect(ApiAuthMiddleware.isPairingOpen, isFalse);
      expect(await d.canLogin('acct1', HostFixture.acctPw), isTrue);
    });
  });

  group('forced change from the device (POST /api/auth/change-password)', () {
    test('cashier1 gets 403 password_change_required, changes his password '
        'on the host, then logs in; the other device receives the new hash',
        () async {
      final a = await pairedClient('dev-a');
      final b = await pairedClient('dev-b');

      final blocked = await a.login('cashier1', kInitialPw);
      expect(blocked.status, 403);
      expect(blocked.code, 'password_change_required');

      final ch = await a.post('/api/auth/change-password', {
        'username': 'cashier1',
        'currentPassword': kInitialPw,
        'newPassword': 'My#NewPass456',
      }, withSession: false);
      expect(ch.status, 200, reason: '$ch');
      expect(ch.json['token'], isNotEmpty);
      expect(ch.json['alreadyApplied'], isFalse);
      expect(ch.json['passwordHash'], startsWith(r'$argon2id$'));

      // the host really holds the new password and cleared the flag
      expect(await host.db.authenticateUser('cashier1', 'My#NewPass456'),
          isNotNull);
      expect(await host.db.authenticateUser('cashier1', kInitialPw), isNull);
      final row = await host.db.getUserByUsername('cashier1');
      expect(row!.user.forcePasswordChange, isFalse);

      // the token it returned is a working session
      a.session = ch.json['token'] as String;
      expect((await a.get('/api/users')).status, 200);

      // a second device syncs (with a session) and can log in with the new one
      expect((await b.login('acct1', HostFixture.acctPw)).status, 200);
      await b.syncUsers();
      expect(await b.canLogin('cashier1', 'My#NewPass456'), isTrue);
      expect(await b.canLogin('cashier1', kInitialPw), isFalse);
    });

    test('a lost answer is retried safely (idempotent replay)', () async {
      final d = await pairedClient('dev-a');
      final body = {
        'username': 'cashier1',
        'currentPassword': kInitialPw,
        'newPassword': 'My#NewPass456',
      };
      expect((await d.post('/api/auth/change-password', body)).status, 200);
      final replay = await d.post('/api/auth/change-password', body);
      expect(replay.status, 200, reason: '$replay');
      expect(replay.json['alreadyApplied'], isTrue);
    });
  });

  group('administrative reset really applies (PUT /api/users/<id>)', () {
    test('password + forcePasswordChange from an admin session', () async {
      final d = await pairedClient('dev-a');
      expect((await d.login('admin', kHostAdminPw)).status, 200);

      final r = await d.put('/api/users/${fx.acctId}',
          {'password': 'Reset#Pass123', 'forcePasswordChange': true});
      expect(r.status, 200, reason: '$r');
      expect(await host.db.authenticateUser('acct1', HostFixture.acctPw), isNull,
          reason: 'the old password must stop working (it used to be ignored)');
      final user = await host.db.authenticateUser('acct1', 'Reset#Pass123');
      expect(user!.user.forcePasswordChange, isTrue);

      // propagation: the feed shows the flag, the temporary password is
      // refused a session until it is changed.
      final feed = await d.get('/api/users');
      final acct = (feed.json['users'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((u) => u['username'] == 'acct1');
      expect(acct['forcePasswordChange'], isTrue);
      final other = await pairedClient('dev-b');
      final s = await other.login('acct1', 'Reset#Pass123');
      expect(s.status, 403);
      expect(s.code, 'password_change_required');
    });

    test('a non-admin cannot reset; a bad body is rejected, not ignored',
        () async {
      final d = await pairedClient('dev-a');
      expect((await d.login('acct1', HostFixture.acctPw)).status, 200);
      final denied = await d.put('/api/users/${fx.cashierId}', {'password': 'x'});
      expect(denied.status, 403);
      expect(await host.db.authenticateUser('cashier1', kInitialPw), isNotNull);

      final admin = await pairedClient('dev-b');
      await admin.login('admin', kHostAdminPw);
      final empty = await admin.put('/api/users/${fx.acctId}', {'password': ''});
      expect(empty.status, 400);
      final dup = await admin.put(
          '/api/users/${fx.acctId}', {'password': HostFixture.b2Pw});
      expect(dup.status, 409);
      expect(dup.body, isNot(contains('b2cashier')),
          reason: 'never names who holds the password');
    });
  });

  group('mirror: per-device pairing, mirror_console, multi-branch list', () {
    test('a mirror pairs by code (no branch), a manager lists ALL his '
        'branches\' users, a user without mirror_console is refused', () async {
      final offer = await host.issue(kind: 'mirror');
      final m = newDevice('mirror-1');
      final r = await m.pair(offer.code);
      expect(r.status, 200, reason: '$r');
      expect(r.json['deviceKind'], 'mirror');
      expect(r.json.containsKey('branchId'), isFalse);

      final no = await m.login('acct1', HostFixture.acctPw);
      expect(no.status, 403);
      expect(no.code, 'mirror_console_denied');

      expect((await m.login('mgr1', HostFixture.mgrPw)).status, 200);
      final feed = await m.syncUsers();
      final names = [
        for (final u in (feed.json['users'] as List).cast<Map<String, dynamic>>())
          u['username']
      ];
      expect(names, containsAll(['mgr1', 'cashier1', 'acct1', 'b2cashier']),
          reason: 'users of BOTH granted branches');
      expect(names, isNot(contains('outsider')));
      expect(await m.canLogin('b2cashier', HostFixture.b2Pw), isTrue);

      // no POS on the console
      final held = await m.get('/api/sales/held');
      expect(held.status, 403);
      expect(held.body, contains('device_scope'));
      expect((await m.get('/api/products')).status, isNot(403));
    });

    test('revoking a mirror kills it at once, other devices are unaffected',
        () async {
      final offer = await host.issue(kind: 'mirror');
      final m = newDevice('mirror-1');
      await m.pair(offer.code);
      final c = await pairedClient('dev-1');
      expect((await m.get('/api/users', withSession: false)).status, 200);

      await host.pairing.revoke('mirror-1', actorUserId: 1);
      final after = await m.get('/api/users', withSession: false);
      expect(after.status, 401);
      expect(after.body, contains('device_revoked'));
      expect((await c.get('/api/users', withSession: false)).status, 200);
    });

    test('the mirror works on a server whose legacy window has ENDED',
        () async {
      await host.pairing.endLegacyTransition();
      final offer = await host.issue(kind: 'mirror');
      final m = newDevice('mirror-1');
      expect((await m.pair(offer.code)).status, 200);
      expect((await m.get('/api/users', withSession: false)).status, 200);
    });
  });

  group('legacy shared-token telemetry (SEC-006 gate)', () {
    test('legacy use is counted per device; closing is refused while in use '
        'and paired devices are not counted', () async {
      final shared = LanDevice(host.overHttp(base), 'old-tablet');
      devices.add(shared);
      final hit = await shared.transport(
          'GET', '/api/users', shared.headers(bearer: 'legacy-shared-token'), null);
      expect(hit.status, 200, reason: '$hit');
      await shared.transport(
          'GET', '/api/users', shared.headers(bearer: 'legacy-shared-token'), null);

      await pairedClient('dev-1'); // a paired device never hits the shared path
      final usage = await host.pairing.legacyUsage();
      expect(usage.inUse, isTrue);
      expect(usage.deviceCount, 1);
      expect(usage.devices.single.deviceId, 'old-tablet');
      expect(usage.requestsSinceStart, greaterThanOrEqualTo(2));
      expect(LegacyTokenTelemetry.instance.requestsByDevice['old-tablet'],
          greaterThanOrEqualTo(2));

      expect(await host.pairing.endLegacyTransitionIfUnused(), isFalse);
      expect(await host.pairing.legacyAllowed(), isTrue,
          reason: 'still open: a device uses it');
    });

    test('with no legacy use the window may be closed, but nothing closes '
        'it by itself', () async {
      expect((await host.pairing.legacyUsage()).inUse, isFalse);
      expect(await host.pairing.legacyAllowed(), isTrue);
      expect(await host.pairing.endLegacyTransitionIfUnused(), isTrue);
      expect(await host.pairing.legacyAllowed(), isFalse);
    });
  });
}
