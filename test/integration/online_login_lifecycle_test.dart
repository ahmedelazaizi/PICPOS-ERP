// Users/login/sync plan P2 + P3 over a REAL socket: the real AuthRepositoryImpl,
// AuthSessionGate, ServerProxy and credential stamps on a branch device talk to
// the real host router (LanHost / shelf_io). The host is the single source of
// truth; the device's "no" or "yes" comes from it whenever it can be reached.
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/device_identity_service.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/sync/strategies/user_branch_access_sync_strategy.dart';

import '../helpers/lan_host_harness.dart';
import '../unit/auth/stamp_test_support.dart';

class _ClientInterceptor extends SyncInterceptor {
  _ClientInterceptor({this.mirror = false});
  final bool mirror;
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => mirror;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Adds permission [code] to [roleId] on the DEVICE database only.
Future<void> _grantOnDevice(AppDatabase db, int? roleId, String code) async {
  final all = await db.getAllPermissions();
  final held = (await db.getPermissionsForRole(roleId!)).map((p) => p.id).toSet()
    ..add(all.firstWhere((p) => p.code == code).id);
  await db.setRolePermissions(roleId, held.toList());
}

void main() {
  // No TestWidgetsFlutterBinding: it turns every real dart:io request into a 400.
  late LanHost host;
  late HostFixture fx;
  late String base;
  late int port;
  late DateTime now;
  late MemSecure secure;
  final devices = <LanDevice>[];

  /// A paired branch device with its own database, in client mode.
  Future<({LanDevice dev, AppDatabase db})> pairDevice(String id,
      {bool mirror = false}) async {
    final offer = mirror
        ? await host.issue(kind: 'mirror')
        : await host.issue(kind: 'client', branchId: fx.branch1);
    final d = LanDevice(host.overHttp(base), id, rolesFrom: host.db);
    devices.add(d);
    expect((await d.pair(offer.code)).status, 200);
    // the reference sync (branches, roles) precedes the users sync on a real device
    for (final b in await host.db.select(host.db.branches).get()) {
      await d.db.into(d.db.branches).insert(
          BranchesCompanion(id: Value(b.id), name: Value(b.name), code: Value(b.code), globalId: Value(b.globalId)),
          mode: InsertMode.insertOrIgnore);
    }
    for (final r in await host.db.select(host.db.roles).get()) {
      await d.db.into(d.db.roles).insert(
          RolesCompanion(id: Value(r.id), name: Value(r.name)),
          mode: InsertMode.insertOrIgnore);
    }
    // ...and so does the role -> permission sync: a console device decides
    // `mirror_console` (AuthRepositoryImpl._requireConsole) from ITS copy of the
    // role's permissions, exactly as the fleet harness delivers them.
    final devPermByCode = {
      for (final p in await d.db.getAllPermissions()) p.code: p.id,
    };
    for (final r in await host.db.getAllRoles()) {
      final codes = (await host.db.getPermissionsForRole(r.id)).map((p) => p.code);
      await d.db.setRolePermissions(r.id, [
        for (final c in codes)
          if (devPermByCode[c] != null) devPermByCode[c]!,
      ]);
    }
    DeviceIdentityService.instance.adoptForPairing(id);
    ServerProxy.instance.setApiToken(d.deviceToken);
    NetworkService.instance.setServerAddress('127.0.0.1', port: port);
    NetworkService.instance
        .debugSetModeForTests(mirror ? NetworkMode.mirror : NetworkMode.client);
    SyncInterceptor.instance = _ClientInterceptor(mirror: mirror);
    ServerProxy.instance.clearSessions();
    return (dev: d, db: d.db);
  }

  AuthRepositoryImpl repoFor(AppDatabase db) => AuthRepositoryImpl(
        db,
        offlinePolicy: OfflineLoginPolicy(
          store: secure,
          stamps: CredentialStampStore.forDb(db, clock: () => now),
          readGraceDays: () async => null,
          clock: () => now,
        ),
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async {},
      );

  /// The first sync as the plan defines it: the first user (admin) is verified
  /// on the host, and with that session the device receives its branch's users
  /// WITH credentials (no manual pairing window).
  Future<void> provision(LanDevice d) async {
    expect((await d.login('admin', kHostAdminPw)).status, 200);
    expect((await d.syncUsers()).status, 200);
    // the device only holds the users it was delivered: rows of others are not applicable
    final access = (await d.get('/api/user-branch-access')).json;
    final mine = {for (final u in await d.db.select(d.db.users).get()) u.id};
    access['user_branch_access'] = [
      for (final r in (access['user_branch_access'] as List))
        if (mine.contains((r as Map)['userId'])) r,
    ];
    await UserBranchAccessSyncStrategy(d.db).syncFromJson(access);
    ServerProxy.instance.clearSessions(); // the first user's session is not kept
  }

  void hostDown() => NetworkService.instance.setServerAddress('127.0.0.1', port: 1);
  void hostUp() => NetworkService.instance.setServerAddress('127.0.0.1', port: port);

  CredentialStampStore stamps(AppDatabase db) =>
      CredentialStampStore.forDb(db, clock: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugResetKnownSessionKeyId();
    ServerProxy.requestTimeout = const Duration(seconds: 5);
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
    port = Uri.parse(base).port;
    SharedPreferences.setMockInitialValues({'client_branch_id': fx.branch1});
    now = DateTime.now().toUtc();
    CredentialStampStore.debugClock = () => now;
    secure = MemSecure();
  });

  tearDown(() async {
    CredentialStampStore.debugClock = null;
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    ServerProxy.instance.setApiToken(null);
    ServerProxy.instance.clearSessions();
    ServerProxy.requestTimeout = const Duration(seconds: 8);
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  Future<void> expectRejected(Future<Object?> f, String part) => expectLater(
      f,
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains(part))));

  group('provisioned device, host reachable', () {
    test('a user created on the host logs in on the FIRST attempt (verified '
        'on the host, pulled with his token, stamped)', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      final id = await host.db.createUser(
          username: 'newbie',
          password: 'Newb#Pass1234',
          displayName: 'n',
          roleId: (await host.db.getUserByUsername('acct1'))!.user.roleId);
      await host.db.setUserBranchAccess(id, [fx.branch1]);
      expect(await dv.db.getUserByUsername('newbie'), isNull);

      final u = await repoFor(dv.db).authenticateUser('newbie', 'Newb#Pass1234');
      expect(u, isNotNull);
      expect(ServerProxy.instance.hasSessionToken(u!.user.id), isTrue);
      final s = (await stamps(dv.db).readAll())[u.user.id]!;
      expect(s.fp, credentialFingerprint(u.user.passwordHash));
    });

    test('a password changed on the host is binding at once: the old one '
        '(still matching the local hash) is refused, the new one works',
        () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      final repo = repoFor(dv.db);
      expect(await repo.authenticateUser('acct1', HostFixture.acctPw), isNotNull);

      await host.db.updateUserPassword(userId: fx.acctId, newPassword: 'Rotated#Pw123');
      expect(await dv.db.authenticateUser('acct1', HostFixture.acctPw), isNotNull,
          reason: 'the device has not pulled yet: local hash still matches');

      await expectRejected(repo.authenticateUser('acct1', HostFixture.acctPw),
          'تغيّرت على النظام الرئيسي');
      expect((await stamps(dv.db).read(fx.acctId))!.src, StampSource.rejected);

      // new password: stale locally -> asked on the host -> pulled -> in
      final ok = await repo.authenticateUser('acct1', 'Rotated#Pw123');
      expect(ok, isNotNull);
      expect(await dv.db.authenticateUser('acct1', HostFixture.acctPw), isNull);
      expect((await stamps(dv.db).read(fx.acctId))!.src, isNot(StampSource.rejected));
    });

    test('the refusal is remembered when the host goes away afterwards '
        '(shadow mode, within the grace)', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      await host.db.updateUserPassword(userId: fx.acctId, newPassword: 'Rotated#Pw123');
      await expectRejected(
          repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw), 'النظام الرئيسي');
      hostDown();
      await expectRejected(
          repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw), 'النظام الرئيسي');
    });

    test('a user deactivated on the host is refused online although the '
        'device still holds an active row', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      await host.db.toggleUserActive(userId: fx.acctId, isActive: false);
      await expectRejected(
          repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw), 'النظام الرئيسي');
    });

    test('a user locked on the host is refused online', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      await host.db.setUserLocked(fx.acctId, true);
      await expectRejected(
          repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw), 'النظام الرئيسي');
    });

    test('a user removed from this branch on the host is refused with the '
        'branch message', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      await host.db.setUserBranchAccess(fx.acctId, [fx.branch2]);
      await expectRejected(repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw),
          'ليس لديك صلاحية الدخول لهذا الفرع');
    });

    test('a user of another branch (never delivered) cannot get in: the host '
        'refuses him for THIS device with the branch message and nothing is '
        'written locally', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      expect(await dv.db.getUserByUsername('outsider'), isNull);
      await expectRejected(
          repoFor(dv.db).authenticateUser('outsider', HostFixture.outsiderPw),
          'ليس لديك صلاحية الدخول لهذا الفرع');
      expect(await dv.db.getUserByUsername('outsider'), isNull);
    });
  });
  group('temporary password: changed on the host from the device', () {
    test('REPRO-R6-a/d end to end: flag delivered, change reaches the host, '
        'the next sync does not undo it, a second device sees it', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      expect((await dv.db.getUserById(fx.cashierId))!.user.forcePasswordChange,
          isTrue,
          reason: 'REPRO-R6-a: the host flag reaches the device');
      final repo = repoFor(dv.db);

      await expectLater(repo.authenticateUser('cashier1', kInitialPw),
          throwsA(isA<PasswordChangeRequired>()));

      // a rejected attempt first: wrong current password
      await expectRejected(
          repo.changeOwnPassword(
              username: 'cashier1',
              currentPassword: 'wrong-current',
              newPassword: 'Brand#New1234'),
          'غير صحيحة');
      await expectRejected(
          repo.changeOwnPassword(
              username: 'cashier1', currentPassword: kInitialPw, newPassword: 'short'),
          '8');
      await expectRejected(
          repo.changeOwnPassword(
              username: 'cashier1',
              currentPassword: kInitialPw,
              newPassword: HostFixture.acctPw), // already used by acct1
          'غير مقبولة');
      expect(await host.db.authenticateUser('cashier1', kInitialPw), isNotNull,
          reason: 'nothing changed on the host');

      await repo.changeOwnPassword(
          username: 'cashier1',
          currentPassword: kInitialPw,
          newPassword: 'Brand#New1234');

      // host has it, flag cleared
      final onHost = await host.db.authenticateUser('cashier1', 'Brand#New1234');
      expect(onHost, isNotNull);
      expect(onHost!.user.forcePasswordChange, isFalse);
      // device has the host's hash (not a locally derived one)
      final local = (await dv.db.getUserById(fx.cashierId))!.user;
      expect(local.passwordHash, onHost.user.passwordHash);
      expect(local.forcePasswordChange, isFalse);

      // REPRO-R6-d: the next sync from the host does not silently undo it
      expect((await dv.dev.login('admin', kHostAdminPw)).status, 200);
      expect((await dv.dev.syncUsers()).status, 200);
      expect(await dv.db.authenticateUser('cashier1', 'Brand#New1234'), isNotNull);
      expect(await dv.db.authenticateUser('cashier1', kInitialPw), isNull);

      // and the cashier can now work
      expect(await repo.authenticateUser('cashier1', 'Brand#New1234'), isNotNull);

      // a second branch device: verified on the host, pulled, in
      SharedPreferences.setMockInitialValues({'client_branch_id': fx.branch1});
      final dv2 = await pairDevice('pos-2');
      await provision(dv2.dev);
      expect(await repoFor(dv2.db).authenticateUser('cashier1', 'Brand#New1234'),
          isNotNull);
      expect(await dv2.db.authenticateUser('cashier1', kInitialPw), isNull);
    });

    test('a fresh device that never saw the user: the temporary password gets '
        'PasswordChangeRequired, then the change pulls the row in', () async {
      final dv = await pairDevice('pos-1');
      // no provisioning at all: the device has only its seeded admin
      final repo = repoFor(dv.db);
      await expectLater(repo.authenticateUser('cashier1', kInitialPw),
          throwsA(isA<PasswordChangeRequired>()));
      await repo.changeOwnPassword(
          username: 'cashier1',
          currentPassword: kInitialPw,
          newPassword: 'Brand#New1234');
      expect(await dv.db.getUserByUsername('cashier1'), isNotNull);
      expect(await repo.authenticateUser('cashier1', 'Brand#New1234'), isNotNull);
    });

    test('offline: no change is possible and nothing is stored locally',
        () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      hostDown();
      final before = (await dv.db.getUserById(fx.cashierId))!.user.passwordHash;
      await expectRejected(
          repoFor(dv.db).changeOwnPassword(
              username: 'cashier1',
              currentPassword: kInitialPw,
              newPassword: 'Brand#New1234'),
          'يتطلب اتصالًا بالنظام الرئيسي');
      expect((await dv.db.getUserById(fx.cashierId))!.user.passwordHash, before);
      expect((await dv.db.select(dv.db.syncOutbox).get()), isEmpty,
          reason: 'never queued: no plaintext password on disk');
    });

    test('the same change replayed (lost answer) is idempotent', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      final repo = repoFor(dv.db);
      await repo.changeOwnPassword(
          username: 'cashier1', currentPassword: kInitialPw, newPassword: 'Brand#New1234');
      await repo.changeOwnPassword(
          username: 'cashier1', currentPassword: kInitialPw, newPassword: 'Brand#New1234');
      expect(await host.db.authenticateUser('cashier1', 'Brand#New1234'), isNotNull);
    });
  });

  group('a "no" that is not about the user', () {
    test('a re-initialised host (different signing key) does not lock the '
        'cashier out: the device policy decides', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      final repo = repoFor(dv.db);
      expect(await repo.authenticateUser('acct1', HostFixture.acctPw), isNotNull);
      // another install answers on the same address: unknown user there
      await host.db.updateUserPassword(userId: fx.acctId, newPassword: 'Rotated#Pw123');
      ApiSessionToken.setKeyForTesting('a-completely-different-host-key');
      final u = await repo.authenticateUser('acct1', HostFixture.acctPw);
      expect(u, isNotNull, reason: 'not binding: policy (stamped, in grace)');
      expect((await stamps(dv.db).read(fx.acctId))!.src, isNot(StampSource.rejected));
    });

    test('a revoked device is refused online and offline until re-paired',
        () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      await host.pairing.revoke('pos-1', actorUserId: 1);
      final repo = repoFor(dv.db);
      await expectRejected(repo.authenticateUser('acct1', HostFixture.acctPw),
          'أُلغي اعتماد هذا الجهاز');
      hostDown();
      await expectRejected(repo.authenticateUser('acct1', HostFixture.acctPw),
          'أُلغي اعتماد هذا الجهاز');
    });
  });

  group('outage after a good provisioning', () {
    test('within the grace: every provisioned user (admin included) works; '
        'after it: expired; a reconnect renews', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      hostDown();
      final repo = repoFor(dv.db);
      now = now.add(const Duration(days: 5));
      expect(await repo.authenticateUser('acct1', HostFixture.acctPw), isNotNull);
      expect(await repo.authenticateUser('admin', kHostAdminPw), isNotNull);
      now = now.add(const Duration(days: 3));
      await expectRejected(repo.authenticateUser('acct1', HostFixture.acctPw),
          'انتهت مدة الدخول دون اتصال');
      hostUp();
      expect(await repo.authenticateUser('acct1', HostFixture.acctPw), isNotNull,
          reason: 'online again: the host confirms, a new period starts');
      hostDown();
      now = now.add(const Duration(days: 6));
      expect(await repo.authenticateUser('acct1', HostFixture.acctPw), isNotNull);
    });

    test('stolen device: it works offline only inside the grace, and the '
        'first reconnection after the revocation ends it for good', () async {
      final dv = await pairDevice('pos-1');
      await provision(dv.dev);
      hostDown();
      now = now.add(const Duration(days: 9));
      await expectRejected(repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw),
          'انتهت مدة الدخول دون اتصال');
      await host.pairing.revoke('pos-1', actorUserId: 1);
      hostUp();
      await expectRejected(repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw),
          'أُلغي اعتماد هذا الجهاز');
      hostDown();
      now = now.subtract(const Duration(days: 9)); // even a rolled-back clock
      await expectRejected(repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw), '');
    });
  });

  group('mirror console (multi-branch manager)', () {
    test('the manager of branches 1+2 signs in on a mirror, receives the '
        'users of BOTH branches with their credentials, and a user without '
        'the console permission is refused by the host', () async {
      SharedPreferences.setMockInitialValues({}); // a mirror has no branch
      final dv = await pairDevice('mirror-1', mirror: true);
      expect((await dv.dev.login('mgr1', HostFixture.mgrPw)).status, 200);
      expect((await dv.dev.syncUsers()).status, 200);
      for (final n in ['cashier1', 'acct1', 'b2cashier', 'mgr1']) {
        expect(await dv.db.getUserByUsername(n), isNotNull, reason: n);
      }
      expect(await dv.db.getUserByUsername('outsider'), isNull,
          reason: 'branch 3 is outside his scope');
      ServerProxy.instance.clearSessions();

      // A STALE role copy on the device: it still believes the accountant's
      // role holds `mirror_console` (the host revoked/never granted it). The
      // device-side guard (M2 `_requireConsole`) therefore lets him through and
      // it is the HOST that must refuse - the authority this test pins. (With a
      // truthful copy the device refuses first: see the next test.)
      await _grantOnDevice(dv.db, (await host.db.getUserByUsername('acct1'))!.user.roleId,
          'mirror_console');

      final repo = repoFor(dv.db);
      final mgr = await repo.authenticateUser('mgr1', HostFixture.mgrPw);
      expect(mgr, isNotNull);
      expect(ServerProxy.instance.hasSessionToken(mgr!.user.id), isTrue);
      expect((await stamps(dv.db).read(mgr.user.id))!.fp,
          credentialFingerprint(mgr.user.passwordHash));

      await expectRejected(repo.authenticateUser('acct1', HostFixture.acctPw),
          'كونسول مدير الفروع');
      expect((await stamps(dv.db).read(fx.acctId))!.src, StampSource.rejected);
    });

    test('with a truthful role copy the console refuses a user without '
        '`mirror_console` on the device itself (M2), before asking the host',
        () async {
      SharedPreferences.setMockInitialValues({});
      final dv = await pairDevice('mirror-1', mirror: true);
      expect((await dv.dev.login('mgr1', HostFixture.mgrPw)).status, 200);
      expect((await dv.dev.syncUsers()).status, 200);
      ServerProxy.instance.clearSessions();
      await expectRejected(
          repoFor(dv.db).authenticateUser('acct1', HostFixture.acctPw),
          'كونسول مدير الفروع');
      expect((await stamps(dv.db).read(fx.acctId))!.src, isNot(StampSource.rejected),
          reason: 'the host was never asked');
    });

    test('the mirror follows the same grace when the host is away', () async {
      SharedPreferences.setMockInitialValues({});
      final dv = await pairDevice('mirror-1', mirror: true);
      expect((await dv.dev.login('mgr1', HostFixture.mgrPw)).status, 200);
      expect((await dv.dev.syncUsers()).status, 200);
      ServerProxy.instance.clearSessions();
      hostDown();
      final repo = repoFor(dv.db);
      now = now.add(const Duration(days: 2));
      expect(await repo.authenticateUser('mgr1', HostFixture.mgrPw), isNotNull);
      now = now.add(const Duration(days: 6));
      await expectRejected(repo.authenticateUser('mgr1', HostFixture.mgrPw),
          'انتهت مدة الدخول دون اتصال');
    });
  });

  test('B.8 unaffected: nothing here runs for the host itself', () async {
    final hostRepo = AuthRepositoryImpl(host.db);
    NetworkService.instance.debugSetModeForTests(NetworkMode.server);
    SyncInterceptor.instance = null;
    expect(await hostRepo.authenticateUser('admin', kHostAdminPw), isNotNull);
    expect(await stamps(host.db).readAll(), isEmpty);
  });
}
