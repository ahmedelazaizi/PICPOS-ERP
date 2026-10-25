// Offline login on a paired branch device (users/login/sync plan P3).
//
// Promoted + rewritten from test/repro_mirror (REPRO-R5-f, CHAR-R5-a..h): the
// REAL AuthRepositoryImpl + OfflineLoginPolicy + CredentialStampStore, an
// injected clock, and a host that is unreachable (127.0.0.1:1).
//
// What changed vs the repro file (explained, assertions NOT weakened):
//  * `recordVerified(id)` -> `recordVerified(id, passwordHash:)`: a stamp is
//    bound to the hash it confirms.
//  * The device is provisioned by the production sync (which now stamps the
//    delivered credentials), so "verified N days ago" is expressed by
//    provisioning N days ago. An older explicit stamp could not be "older than
//    the sync that delivered the hash" in reality.
//  * CHAR-R5-e (`neverVerified` admitted forever) is replaced by
//    `notProvisioned`: logged in shadow, rejected in enforce.
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/daos/user_credential_dao.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mirror_peer_harness.dart';

class _MemStore implements OfflineLoginStore {
  String? v;
  bool failing = false;
  @override
  Future<String?> read() async {
    if (failing) throw StateError('no secure storage');
    return v;
  }

  @override
  Future<void> write(String json) async {
    if (failing) throw StateError('no secure storage');
    v = json;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;
  late _MemStore store;
  late DateTime now;
  var mode = 'shadow';

  OfflineLoginPolicy policy() => OfflineLoginPolicy(
        store: store,
        stamps: CredentialStampStore.forDb(p.client),
        readGraceDays: () async => null, // default 7 days
        clock: () => now,
      );

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        p.client,
        offlinePolicy: policy(),
        fetchUserBranchAccess: (_) async => false, // no live host
        refreshUsers: () async {},
      );

  /// Delivers the host's users WITH credentials (what a session-bearing pull
  /// does) at the current test time.
  Future<void> provisionClient() async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    ApiAuthMiddleware.closePairingWindow();
    for (final u in [p.cashierId, p.accountantId]) {
      await p.client.into(p.client.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: u, branchId: p.branch1),
          mode: InsertMode.insertOrIgnore);
    }
    ClientWriteInterceptor.initialize(p.client);
    // The synced cashier carries the host's temporary-password flag; these
    // tests are about the offline policy, so use a user that changed it.
    await p.client.clearForcePasswordChangeFlag(p.cashierId);
    await p.client.setSetting(OfflineLoginMode.settingKey, mode);
  }

  Future<void> provisionDaysAgo(int days) async {
    now = now.subtract(Duration(days: days));
    await provisionClient();
    now = now.add(Duration(days: days));
  }

  setUp(() async {
    mode = 'shadow';
    p = await createPeers();
    store = _MemStore();
    now = DateTime.utc(2026, 10, 24, 12);
    CredentialStampStore.debugClock = () => now;
    p.asClient();
  });
  tearDown(() async {
    CredentialStampStore.debugClock = null;
    SyncInterceptor.currentUserId = null;
    // updateUserPassword fires a password-collision scan without awaiting it
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await p.dispose();
  });

  group('delivered credentials are stamped by the sync that delivered them', () {
    test('a synced cashier verified 1 day ago logs in offline', () async {
      await provisionDaysAgo(1);
      expect(await repo().authenticateUser('cashier1', kCashierInitialPw),
          isNotNull);
    });

    test('REPRO-R5-b: last confirmed 8 days ago (grace 7) -> REJECTED, in '
        'shadow AND enforce', () async {
      for (final m in ['shadow', 'enforce']) {
        mode = m;
        await provisionDaysAgo(8);
        await expectLater(
            repo().authenticateUser('cashier1', kCashierInitialPw),
            throwsA(isA<StateError>()),
            reason: m);
      }
    });

    test('grace is counted from the stamp: 6d23h allowed, 7d+ rejected',
        () async {
      await provisionClient();
      now = now.add(const Duration(days: 6, hours: 23));
      expect(await repo().authenticateUser('cashier1', kCashierInitialPw),
          isNotNull);
      now = now.add(const Duration(hours: 2));
      await expectLater(repo().authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });

    test('REPRO-R5-f: a device that never reached the host cannot log in '
        'offline forever - the clock starts at the sync that delivered the '
        'hash (day 60 is rejected)', () async {
      await provisionClient();
      expect(await repo().authenticateUser('cashier1', kCashierInitialPw),
          isNotNull);
      now = now.add(const Duration(days: 60));
      await expectLater(repo().authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });

    test('a later sync that re-delivers the hash renews the period', () async {
      await provisionClient();
      now = now.add(const Duration(days: 6));
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      ApiAuthMiddleware.closePairingWindow();
      now = now.add(const Duration(days: 6));
      expect(await repo().authenticateUser('acct1', kAccountantInitialPw),
          isNotNull,
          reason: '12 days after the first sync but 6 after the renewal');
    });

    test('a pull WITHOUT credentials never renews (and never wipes) a stamp',
        () async {
      await provisionClient();
      now = now.add(const Duration(days: 6));
      await p.syncUsersFull(); // window closed: rows only, no hashes
      now = now.add(const Duration(days: 2));
      await expectLater(
          repo().authenticateUser('acct1', kAccountantInitialPw),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('انتهت مدة'))),
          reason: 'still 8 days since credentials were last delivered');
    });
  });
  group('R5-g: admin follows the same grace (offline allowed within it)', () {
    test('admin delivered by the sync logs in offline within grace and not '
        'after', () async {
      await provisionClient();
      now = now.add(const Duration(days: 3));
      expect(await repo().authenticateUser('admin', kAdminCustomPw), isNotNull);
      now = now.add(const Duration(days: 6));
      await expectLater(repo().authenticateUser('admin', kAdminCustomPw),
          throwsA(isA<StateError>()));
    });

    test('the seeded admin/admin stops working once the host password reached '
        'the device', () async {
      await provisionClient();
      expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse);
    });
  });

  group('mirror (handshake done) is subject to the same policy', () {
    test('CHAR-R5-h: expired after 10 days', () async {
      SharedPreferences.setMockInitialValues({}); // mirror: no client_branch_id
      p.asMirror();
      await provisionDaysAgo(10);
      await expectLater(repo().authenticateUser('admin', kAdminCustomPw),
          throwsA(isA<StateError>()));
    });
  });

  group('clock handling', () {
    test('CHAR-R5-d: a clock rolled back is rejected', () async {
      await provisionClient();
      expect(await repo().authenticateUser('cashier1', kCashierInitialPw),
          isNotNull); // records the highest time seen
      now = now.subtract(const Duration(hours: 3));
      await expectLater(repo().authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });

    test('wiping the secure store does not remove the rollback protection '
        '(second store in the device-local setting)', () async {
      await provisionClient();
      await repo().authenticateUser('cashier1', kCashierInitialPw);
      store.v = null; // secure storage cleared
      now = now.subtract(const Duration(hours: 3));
      await expectLater(repo().authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });

    test('a stamp dated in the future is a rollback signal', () async {
      now = now.add(const Duration(days: 3)); // device clock was ahead...
      await provisionClient();
      now = now.subtract(const Duration(days: 3)); // ...and is corrected back
      await expectLater(repo().authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });
  });

  group('shadow vs enforce for users the host never delivered', () {
    Future<void> addLocalOnlyUser() async {
      await p.client.createUser(
          username: 'ghost',
          password: 'Gh0st#Pass123',
          displayName: 'g',
          roleId: p.cashierRoleId);
      await p.client.setUserBranchAccess(
          (await p.userOn(p.client, 'ghost'))!.id, [p.branch1]);
    }

    test('CHAR-R5-c: a user that never synced is unknown (null)', () async {
      await provisionClient();
      expect(await repo().authenticateUser('nobody', 'x'), isNull);
    });

    test('shadow: a locally created, never-delivered user is admitted but '
        'logged as "would be rejected"', () async {
      await provisionClient();
      await addLocalOnlyUser();
      final ghost = (await p.userOn(p.client, 'ghost'))!;
      final v = await policy().check(ghost.id, passwordHash: ghost.passwordHash);
      expect(v.decision, OfflineLoginDecision.notProvisioned);
      expect(v.rejectedIn(OfflineLoginMode.shadow), isFalse);
      expect(v.rejectedIn(OfflineLoginMode.enforce), isTrue);
      expect(await repo().authenticateUser('ghost', 'Gh0st#Pass123'), isNotNull);
    });

    test('enforce: the same user is REJECTED with the "not delivered" message',
        () async {
      mode = 'enforce';
      await provisionClient();
      await addLocalOnlyUser();
      await expectLater(
          repo().authenticateUser('ghost', 'Gh0st#Pass123'),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('غير مُسلَّم'))));
    });

    test('REPRO-R5-e (was CHAR "neverVerified admitted"): no stamp -> '
        'notProvisioned, not allowed', () async {
      final v = await policy().check(p.cashierId, passwordHash: 'x');
      expect(v.decision, OfflineLoginDecision.notProvisioned);
      expect(v.allowed, isFalse);
    });

    test('a hash changed locally after the stamp -> credentialChanged: '
        'admitted in shadow, rejected in enforce', () async {
      await provisionClient();
      // local-only rewrite of the hash (what the admin self-heal / a tampered
      // DB does): the stamp no longer matches it
      await p.client.updateUserPassword(
          userId: p.accountantId, newPassword: 'LocalOnly#Pw99');
      final u = (await p.userOn(p.client, 'acct1'))!;
      final v = await policy().check(u.id, passwordHash: u.passwordHash);
      expect(v.decision, OfflineLoginDecision.credentialChanged);
      expect(await repo().authenticateUser('acct1', 'LocalOnly#Pw99'),
          isNotNull,
          reason: 'shadow');
      await p.client.setSetting(OfflineLoginMode.settingKey, 'enforce');
      await expectLater(repo().authenticateUser('acct1', 'LocalOnly#Pw99'),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('لم تُؤكَّد'))));
    });

    test('enforce: a storage failure is "not provisioned", never a silent '
        'pass', () async {
      mode = 'enforce';
      await provisionClient();
      final failing = OfflineLoginPolicy(
        store: store,
        stamps: CredentialStampStore(_ThrowingBacking()),
        readGraceDays: () async => null,
        clock: () => now,
      );
      final u = (await p.userOn(p.client, 'cashier1'))!;
      final repo2 = AuthRepositoryImpl(p.client,
          offlinePolicy: failing,
          fetchUserBranchAccess: (_) async => false,
          refreshUsers: () async {});
      expect(u.isActive, isTrue);
      await expectLater(repo2.authenticateUser('cashier1', kCashierInitialPw),
          throwsA(isA<StateError>()));
    });
  });

  group('B.8 standalone / main never use the policy', () {
    test('standalone with enforce on and no stamps still logs in', () async {
      SyncInterceptor.instance = null;
      await p.client.setSetting(OfflineLoginMode.settingKey, 'enforce');
      final r = AuthRepositoryImpl(p.client, offlinePolicy: policy());
      expect(await r.authenticateUser('admin', 'admin'), isNotNull);
      expect(await CredentialStampStore.forDb(p.client).readAll(), isEmpty,
          reason: 'no stamps are written on a standalone/main device');
    });

    test('a users sync on a standalone device writes no stamps', () async {
      SyncInterceptor.instance = null;
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      expect(await CredentialStampStore.forDb(p.client).readAll(), isEmpty);
    });
  });
}

class _ThrowingBacking implements StampBacking {
  @override
  Future<String?> read(String key) async => throw StateError('disk gone');
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('disk gone');
}
