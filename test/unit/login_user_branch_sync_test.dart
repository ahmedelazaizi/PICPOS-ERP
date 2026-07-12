// Feature 051 (v132) — Login user_branch_access lazy sync.
//
// Field bug: a user created on the server with branch X assigned cannot
// log in on a fresh mirror — `_verifyBranchAccess` throws because
// `user_branch_access` hasn't synced yet. The LoginScreen's post-auth
// refresh runs *after* this guard, so it can't repair the first login.
//
// Fix: `_verifyBranchAccess` now triggers a targeted `syncTable(
// 'user_branch_access')` when the local assignments list is empty, then
// re-reads. The fetcher is injectable so this test can stub it without a
// real network or SyncService.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/repositories/auth_repository_impl.dart';
import 'package:ural_erp/services/network_service.dart';

// Feature 064 (R9) moved the `_verifyBranchAccess` gate from
// `NetworkService.isClient` to `SyncInterceptor.isClientMode` so mirror mode
// also enforces branch-gating. `SyncInterceptor.isClientMode` is
// `instance?.isClientModeImpl ?? false`, so the gate only fires when an
// interceptor instance is wired. NetworkMode.client alone is no longer enough.
// This fake makes `isClientMode` resolve true; setUp installs it, tearDown
// clears it so it can't leak into sibling test files.
class _FakeInterceptor extends SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int userId;
  late int branchId;

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SyncInterceptor.instance = _FakeInterceptor();

    db = AppDatabase.forTesting();
    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع الاسكندرية',
            globalId: const Value('gid-branch-051'),
          ),
        );
    // Align prefs with whatever id Drift gave the row. setMockInitialValues
    // resets the in-memory store, so the production-side `getInstance()`
    // inside `_verifyBranchAccess` reads this value.
    SharedPreferences.setMockInitialValues({'client_branch_id': branchId});

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-051',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_051',
      password: 'pw-051',
      displayName: 'F051',
      roleId: roleId,
    );
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    await db.close();
  });

  group('AuthRepositoryImpl._verifyBranchAccess — lazy sync', () {
    test('empty local → lazy fetch populates → login passes', () async {
      var fetcherCalled = false;
      final repo = AuthRepositoryImpl(
        db,
        fetchUserBranchAccess: (database) async {
          fetcherCalled = true;
          await database.into(database.userBranchAccess).insert(
                UserBranchAccessCompanion.insert(
                  userId: userId,
                  branchId: branchId,
                ),
              );
          return true;
        },
      );

      final user = await repo.authenticateUser('cashier_051', 'pw-051');
      expect(user, isNotNull,
          reason: 'lazy fetch supplied the missing assignment row, '
              'so _verifyBranchAccess must allow the login through');
      expect(fetcherCalled, isTrue,
          reason: 'an empty local table in client mode is the trigger '
              'for the fetch — without it we know the guard is wrong');
    });

    test('empty local → fetcher returns nothing → login still throws',
        () async {
      final repo = AuthRepositoryImpl(
        db,
        // Simulates server-side confirmed-empty: the fetch ran but the
        // user genuinely has no branch assignments yet.
        fetchUserBranchAccess: (_) async => true,
      );

      expect(
        () => repo.authenticateUser('cashier_051', 'pw-051'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ليس لديك صلاحية'),
        )),
      );
    });

    test('already-populated local → no fetch, login passes', () async {
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(
              userId: userId,
              branchId: branchId,
            ),
          );

      var fetcherCalled = false;
      final repo = AuthRepositoryImpl(
        db,
        fetchUserBranchAccess: (_) async {
          fetcherCalled = true;
          return true;
        },
      );

      final user = await repo.authenticateUser('cashier_051', 'pw-051');
      expect(user, isNotNull);
      expect(fetcherCalled, isFalse,
          reason: 'when local data is already present we must NOT hit '
              'the network — login latency budget matters here');
    });

    test('lazy fetch populates a DIFFERENT branch → still throws', () async {
      final otherBranchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع آخر',
              globalId: const Value('gid-branch-051-other'),
            ),
          );

      final repo = AuthRepositoryImpl(
        db,
        fetchUserBranchAccess: (database) async {
          // Server has assignment, but to a branch this device is not.
          await database.into(database.userBranchAccess).insert(
                UserBranchAccessCompanion.insert(
                  userId: userId,
                  branchId: otherBranchId,
                ),
              );
          return true;
        },
      );

      expect(
        () => repo.authenticateUser('cashier_051', 'pw-051'),
        throwsA(isA<StateError>()),
        reason: 'fail-closed semantics survive the lazy-sync addition: '
            'a user assigned to branch B cannot log in on branch A',
      );
    });

    test('fetcher throws → falls through to empty-result throw', () async {
      final repo = AuthRepositoryImpl(
        db,
        fetchUserBranchAccess: (_) async {
          throw 'simulated network timeout';
        },
      );

      // The guard swallows the fetcher's error and treats local as
      // authoritative — local is empty → throw.
      expect(
        () => repo.authenticateUser('cashier_051', 'pw-051'),
        throwsA(isA<StateError>()),
      );
    });

    test('standalone mode → never fetches, never throws', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      // The gate reads `SyncInterceptor.isClientMode`, not NetworkService, so
      // standalone behaviour requires the interceptor to be absent — clear the
      // fake setUp installed so `isClientMode` resolves false and the guard
      // short-circuits before any fetch.
      SyncInterceptor.instance = null;

      var fetcherCalled = false;
      final repo = AuthRepositoryImpl(
        db,
        fetchUserBranchAccess: (_) async {
          fetcherCalled = true;
          return true;
        },
      );

      final user = await repo.authenticateUser('cashier_051', 'pw-051');
      expect(user, isNotNull,
          reason: 'standalone has no notion of mirror branch-gating');
      expect(fetcherCalled, isFalse);
    });
  });
}
