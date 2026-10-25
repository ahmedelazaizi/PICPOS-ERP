// Credential stamps are bound to the hash (plan P3 / B.3): anything that changes
// a hash locally WITHOUT the main system invalidates its stamp.
//  * the boot-time admin self-heal (HEAL-001) on a branch device;
//  * the background PBKDF2 -> Argon2id rewrite (disabled on branch devices);
//  * a hash swapped for one the attacker knows, a brand-new local user, a stamp
//    copied from another user.
// (An attacker who holds the SQLCipher key can forge the stamps too; that is
// the documented limit of a per-device design - the mitigation is revoking the
// device, covered in test/integration/online_login_lifecycle_test.dart.)
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/security_service.dart';

import '../helpers/mirror_peer_harness.dart';
import '../unit/auth/stamp_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;
  late DateTime now;

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        p.client,
        offlinePolicy: OfflineLoginPolicy(
          store: MemSecure(),
          stamps: CredentialStampStore.forDb(p.client),
          readGraceDays: () async => null,
          clock: () => now,
        ),
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async {},
      );

  Future<void> provision() async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    ApiAuthMiddleware.closePairingWindow();
    for (final u in [p.cashierId, p.accountantId]) {
      await p.client.into(p.client.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: u, branchId: p.branch1),
          mode: InsertMode.insertOrIgnore);
    }
    ClientWriteInterceptor.initialize(p.client);
    await p.client.setSetting(OfflineLoginMode.settingKey, 'enforce');
  }

  Future<OfflineLoginVerdict> verdictOf(String username) async {
    final u = (await p.userOn(p.client, username))!;
    return OfflineLoginPolicy(
      store: MemSecure(),
      stamps: CredentialStampStore.forDb(p.client),
      readGraceDays: () async => null,
      clock: () => now,
    ).check(u.id, passwordHash: u.passwordHash);
  }

  setUp(() async {
    p = await createPeers();
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

  test('healed admin on a branch device: the self-heal hash (admin/admin + '
      'forced change) is NOT the delivered one -> credentialChanged, and it '
      'cannot log in offline (HEAL-001 is closed on clients)', () async {
    await provision();
    expect(await verdictOf('admin'), isA<OfflineLoginVerdict>().having(
        (v) => v.decision, 'decision', OfflineLoginDecision.allowed));
    // what database_startup's heal does when it finds a structurally damaged hash
    final healed = await SecurityService.hashPasswordArgon2('admin');
    await (p.client.update(p.client.users)..where((u) => u.id.equals(1))).write(
        UsersCompanion(
            passwordHash: Value(healed),
            passwordSalt: const Value(''),
            forcePasswordChange: const Value(true)));
    expect((await verdictOf('admin')).decision,
        OfflineLoginDecision.credentialChanged);
    await expectLater(repo().authenticateUser('admin', 'admin'),
        throwsA(isA<StateError>()));
    expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isFalse,
        reason: 'the delivered hash is gone: only the host can restore it');
  });

  test('a hash swapped for one the attacker knows is rejected in enforce',
      () async {
    await provision();
    final mine = await SecurityService.hashPasswordArgon2('Attacker#Pw99');
    await (p.client.update(p.client.users)..where((u) => u.id.equals(p.accountantId)))
        .write(UsersCompanion(passwordHash: Value(mine), passwordSalt: const Value('')));
    expect((await verdictOf('acct1')).decision,
        OfflineLoginDecision.credentialChanged);
    await expectLater(repo().authenticateUser('acct1', 'Attacker#Pw99'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('لم تُؤكَّد'))));
  });

  test('a user created locally on a branch device is never delivered -> '
      'rejected in enforce', () async {
    await provision();
    final id = await p.client.createUser(
        username: 'backdoor',
        password: 'Back#Door1234',
        displayName: 'b',
        roleId: p.cashierRoleId);
    await p.client.setUserBranchAccess(id, [p.branch1]);
    expect((await verdictOf('backdoor')).decision,
        OfflineLoginDecision.notProvisioned);
    await expectLater(repo().authenticateUser('backdoor', 'Back#Door1234'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('غير مُسلَّم'))));
  });

  test('the background PBKDF2 -> Argon2id rewrite does not run on a branch '
      'device (it would orphan the stamp and be overwritten by the next sync)',
      () async {
    await provision();
    final salt = SecurityService.generateSalt();
    final legacy = SecurityService.hashPassword('Legacy#Pw1234', salt);
    await (p.client.update(p.client.users)..where((u) => u.id.equals(p.accountantId)))
        .write(UsersCompanion(passwordHash: Value(legacy), passwordSalt: Value(salt)));
    await CredentialStampStore.forDb(p.client).stampFromSync(p.accountantId, legacy);
    expect(await p.client.authenticateUser('acct1', 'Legacy#Pw1234'), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final after = (await p.userOn(p.client, 'acct1'))!;
    expect(after.passwordHash, legacy, reason: 'not rewritten on a client');
    expect(after.passwordSalt, salt);
    expect((await verdictOf('acct1')).decision, OfflineLoginDecision.allowed);
  });

  test('...while a standalone device still upgrades the hash (unchanged '
      'behaviour)', () async {
    SyncInterceptor.instance = null;
    final salt = SecurityService.generateSalt();
    final legacy = SecurityService.hashPassword('Legacy#Pw1234', salt);
    final id = await p.client.createUser(
        username: 'oldtimer', password: 'Legacy#Pw1234', displayName: 'o');
    await (p.client.update(p.client.users)..where((u) => u.id.equals(id)))
        .write(UsersCompanion(passwordHash: Value(legacy), passwordSalt: Value(salt)));
    expect(await p.client.authenticateUser('oldtimer', 'Legacy#Pw1234'), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect((await p.userOn(p.client, 'oldtimer'))!.passwordHash.startsWith(r'$argon2'),
        isTrue);
  });

  test('a stamp edited into the future or the far past is treated as a '
      'rollback / expiry, not as a longer grace', () async {
    await provision();
    final raw = (await p.client.getSettingValue(CredentialStampStore.stampsKey))!;
    await p.client.setSetting(CredentialStampStore.stampsKey,
        raw.replaceAll('2026-10-24T12:00:00.000Z', '2031-01-01T00:00:00.000Z'));
    expect((await verdictOf('acct1')).decision, OfflineLoginDecision.clockRolledBack);
    await p.client.setSetting(CredentialStampStore.stampsKey,
        raw.replaceAll('2026-10-24T12:00:00.000Z', '2020-01-01T00:00:00.000Z'));
    expect((await verdictOf('acct1')).decision, OfflineLoginDecision.expired);
  });
}
