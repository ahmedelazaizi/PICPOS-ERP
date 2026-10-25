// Upgrade stamping (plan P3 / B.5, owner decision: nobody is locked out by the
// upgrade). The database looks like an INSTALLED branch device that has never
// seen credential stamps: real hashes, the seeded admin/admin, an unusable
// credential, a user with a temporary password, an inactive and a locked user.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/data/repositories/auth_session_gate.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/unusable_credential.dart';

import 'stamp_test_support.dart';

/// The host cannot be reached.
class _Down implements SessionAuthorityPort {
  @override
  Future<SessionMintResult> acquire(
          {required int userId, String? username, String? password, String? cardCode}) async =>
      const SessionMintResult(SessionMintOutcome.unreachable);
  @override
  Future<SessionMintResult> mintDirect(
          {String? username, String? password, String? cardCode}) async =>
      const SessionMintResult(SessionMintOutcome.unreachable);
  @override
  Future<PasswordChangeResult> changeOwnPassword(
          {String? username, String? currentPassword, String? cardCode, required String newPassword}) async =>
      const PasswordChangeResult(PasswordChangeOutcome.unreachable);
  @override
  Future<bool> pullCredentialFeeds(AppDatabase db, String token) async => false;
  @override
  bool hasSessionToken(int userId) => false;
}

class _Interceptor extends SyncInterceptor {
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
  late DateTime now;
  late MemSecure secure;
  late int branch;
  var ids = <String, int>{};

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        db,
        offlinePolicy: OfflineLoginPolicy(
          store: secure,
          stamps: CredentialStampStore.forDb(db, clock: () => now),
          readGraceDays: () async => null,
          clock: () => now,
        ),
        authority: _Down(),
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async {},
      );

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SyncInterceptor.instance = _Interceptor();
    db = AppDatabase.forTesting();
    secure = MemSecure();
    now = DateTime.utc(2026, 11, 1, 8);
    branch = (await db.select(db.branches).get()).first.id;
    SharedPreferences.setMockInitialValues({'client_branch_id': branch});
    final role = await db.into(db.roles).insert(RolesCompanion.insert(
        name: 'cashier-upg', isSystemRole: const Value(false)));
    Future<int> mk(String name, String pw,
        {bool force = false, bool active = true, bool locked = false}) async {
      final id = await db.createUser(
          username: name,
          password: pw,
          displayName: name,
          roleId: role,
          forcePasswordChange: force);
      await db.setUserBranchAccess(id, [branch]);
      if (!active) await db.toggleUserActive(userId: id, isActive: false);
      if (locked) await db.setUserLocked(id, true);
      return id;
    }

    ids = {
      'cashier': await mk('cashier', 'Cash#Pass123'),
      'acct': await mk('acct', 'Acct#Pass123'),
      'temp': await mk('temp', 'Temp#Pass123', force: true),
      'inactive': await mk('inactive', 'Inact#Pass123', active: false),
      'locked': await mk('locked', 'Lock#Pass1234', locked: true),
      'unusable': await mk('unusable', 'Gone#Pass1234'),
    };
    final u = await UnusableCredential.mint();
    await (db.update(db.users)..where((t) => t.id.equals(ids['unusable']!)))
        .write(UsersCompanion(
            passwordHash: Value(u.hash), passwordSalt: Value(u.salt)));
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    ServerProxy.instance.clearSessions();
    await db.close();
  });

  CredentialStampStore stamps() => CredentialStampStore.forDb(db, clock: () => now);

  test('a device with NO stamps and NO flag: the first login stamps every user '
      'who could log in before (src=upgrade, at=now), exactly once', () async {
    expect(await stamps().readAll(), isEmpty);
    expect(await db.getSettingValue(CredentialStampStore.bootstrappedKey), isNull);

    expect(await repo().authenticateUser('cashier', 'Cash#Pass123'), isNotNull);

    final all = await stamps().readAll();
    expect(all.keys, containsAll([ids['cashier'], ids['acct']]));
    for (final s in all.values) {
      expect(s.src, StampSource.upgrade);
      expect(s.at, now);
    }
    expect(await db.getSettingValue(CredentialStampStore.bootstrappedKey), 'true');
  });

  test('NOT stamped: unusable credential, temporary-password user, inactive, '
      'locked, and the seeded admin/admin', () async {
    await repo().authenticateUser('cashier', 'Cash#Pass123');
    final all = await stamps().readAll();
    for (final k in ['unusable', 'temp', 'inactive', 'locked']) {
      expect(all.containsKey(ids[k]), isFalse, reason: k);
    }
    expect(all.containsKey(1), isFalse, reason: 'seeded admin/admin');
    expect(await db.authenticateUser('unusable', 'Gone#Pass1234'), isNull);
  });

  test('nobody is locked out by the upgrade: allowed offline for the whole '
      'grace, expired after it (shadow and enforce)', () async {
    await db.setSetting(OfflineLoginMode.settingKey, 'enforce');
    await repo().authenticateUser('cashier', 'Cash#Pass123');
    now = now.add(const Duration(days: 6));
    expect(await repo().authenticateUser('acct', 'Acct#Pass123'), isNotNull);
    now = now.add(const Duration(days: 2));
    await expectLater(repo().authenticateUser('acct', 'Acct#Pass123'),
        throwsA(isA<StateError>()));
  });

  test('idempotent: a second run stamps nothing and never renews `at`',
      () async {
    await repo().authenticateUser('cashier', 'Cash#Pass123');
    final first = await stamps().readAll();
    now = now.add(const Duration(days: 3));
    expect(await stamps().bootstrapIfNeeded(db), 0);
    await repo().authenticateUser('acct', 'Acct#Pass123');
    expect((await stamps().readAll()).length, first.length);
    expect((await stamps().readAll())[ids['cashier']]!.at,
        DateTime.utc(2026, 11, 1, 8));
  });

  test('interrupted before the flag was written: the rerun completes without '
      'renewing the stamps that already exist', () async {
    final backing = MemBacking();
    var s = CredentialStampStore(backing, clock: () => now);
    backing.failOnWrite = 2; // write 1 = stamps JSON, write 2 = the flag
    await expectLater(s.bootstrapIfNeeded(db), throwsA(isA<StateError>()));
    expect(backing.values[CredentialStampStore.bootstrappedKey], isNull);
    final partial = Map.of(await s.readAll());
    expect(partial, isNotEmpty);

    now = now.add(const Duration(days: 2));
    backing.failOnWrite = null;
    s = CredentialStampStore(backing, clock: () => now);
    expect(await s.bootstrapIfNeeded(db), 0, reason: 'nothing left to stamp');
    expect(backing.values[CredentialStampStore.bootstrappedKey], 'true');
    expect(await s.readAll(), partial);
  });

  test('a hash changed AFTER the bootstrap is not blessed: enforce rejects it',
      () async {
    await repo().authenticateUser('cashier', 'Cash#Pass123');
    await db.updateUserPassword(userId: ids['acct']!, newPassword: 'Tamper#Pass99');
    await db.setSetting(OfflineLoginMode.settingKey, 'enforce');
    await expectLater(repo().authenticateUser('acct', 'Tamper#Pass99'),
        throwsA(isA<StateError>()));
  });
}

