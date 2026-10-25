// M2 (plan 2026-10-24, MIR-003): the branch-manager console admits only users
// holding `mirror_console`, checked on the DEVICE as well as on the main.
//  * a user without the permission is refused on a mirror, with the console
//    sentence, BEFORE any credential reaches the main;
//  * a holder is admitted; the same user is admitted on a branch device (the
//    gate is a mirror-only rule);
//  * a device that has not received the permission catalogue leaves the decision
//    to the main (it does not lock every manager out).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

import 'fake_authority.dart';
import 'stamp_test_support.dart';

class _Mirror extends SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeAuthority host;
  const pw = 'Cons#Pass123';
  const pwAcct = 'Acct#Pass4567';
  const consoleSentence = 'هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له.';

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        db,
        offlinePolicy: OfflineLoginPolicy(
          store: MemSecure(),
          stamps: CredentialStampStore.forDb(db),
          readGraceDays: () async => null,
        ),
        authority: host,
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async {},
      );

  Future<void> addUser(String name,
      {required bool console, String password = pw}) async {
    final role = await db.into(db.roles).insert(RolesCompanion.insert(
        name: 'role-$name', isSystemRole: const Value(false)));
    if (console) {
      final perm = (await db.getAllPermissions())
          .firstWhere((p) => p.code == 'mirror_console');
      await db.setRolePermissions(role, [perm.id]);
    }
    await db.createUser(
        username: name, password: password, displayName: name, roleId: role);
  }

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    SyncInterceptor.instance = _Mirror();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    host = FakeAuthority();
    host.acquireOutcome = SessionMintOutcome.ok;
    await addUser('manager', console: true);
    await addUser('accountant', console: false, password: pwAcct);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    ServerProxy.instance.clearSessions();
    await db.close();
  });

  test('a user without mirror_console is refused on a mirror, before the main '
      'is asked anything', () async {
    await expectLater(
      repo().authenticateUser('accountant', pwAcct),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains(consoleSentence))),
    );
    expect(host.acquireCalls, isEmpty,
        reason: 'the credential never left the device');
  });

  test('a holder of mirror_console is admitted', () async {
    final u = await repo().authenticateUser('manager', pw);
    expect(u, isNotNull);
    expect(host.acquireCalls.single.username, 'manager');
  });

  test('the same user without the permission is NOT refused on a branch '
      'device (mirror-only rule)', () async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SyncInterceptor.instance = _Client();
    final u = await repo().authenticateUser('accountant', pwAcct);
    expect(u, isNotNull);
  });

  test('a device without the permission catalogue leaves the decision to the '
      'main', () async {
    await db.customStatement('DELETE FROM role_permissions');
    await db.customStatement('DELETE FROM permissions WHERE code = ?1',
        ['mirror_console']);
    final u = await repo().authenticateUser('accountant', pwAcct);
    expect(u, isNotNull);
  });
}

class _Client extends SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
