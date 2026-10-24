// MIR-023 / RESET-001 (users/login/sync plan P0): on a client or mirror device
// the HOST owns user administration. AuthRepositoryImpl must route
// updateUserPassword / toggleUserActive / assignRoleToUser / setUserLocked
// through ClientWriteInterceptor instead of writing straight to the local db
// (a local-only write is reverted by the next pull, and on a mirror it is a
// write HQ never heard of).
//
// Promoted from test/repro_mirror (REPRO-R3-q, REPRO-R6-c/e/g).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/write_router.dart';

import '../../helpers/mirror_peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async {
    SyncInterceptor.currentUserId = null;
    await p.dispose();
  });

  Future<AuthRepositoryImpl> repoWithSyncedUsers() async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    ApiAuthMiddleware.closePairingWindow();
    ClientWriteInterceptor.initialize(p.client);
    return AuthRepositoryImpl(p.client);
  }

  Future<int> outboxCount() async => (await p.client
          .customSelect("SELECT COUNT(*) AS n FROM sync_outbox "
              "WHERE table_name = 'users'")
          .getSingle())
      .read<int>('n');

  group('MIRROR + unreachable HQ', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('all four ops are rejected, none applied locally', () async {
      p.asMirror();
      final repo = await repoWithSyncedUsers();
      final before = (await p.userOn(p.client, 'cashier1'))!;
      for (final op in <Future<void> Function()>[
        () => repo.toggleUserActive(userId: p.cashierId, isActive: false),
        () async => repo.setUserLocked(p.cashierId, true),
        () => repo.assignRoleToUser(p.accountantId, p.cashierRoleId),
        () => repo.updateUserPassword(
            userId: p.accountantId, newPassword: 'New#Pass12345'),
      ]) {
        await expectLater(op(), throwsA(isA<MirrorOfflineException>()));
      }
      final after = (await p.userOn(p.client, 'cashier1'))!;
      expect(after.isActive, before.isActive);
      expect(after.isLocked, before.isLocked);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue,
          reason: 'password untouched locally');
      expect(await p.canLogin(p.client, 'acct1', 'New#Pass12345'), isFalse);
      expect(await outboxCount(), 0, reason: 'a mirror has no outbox');
    });
  });

  group('CLIENT + unreachable HQ', () {
    test('toggle / lock / re-role are queued, not applied locally', () async {
      p.asClient();
      final repo = await repoWithSyncedUsers();
      await repo.toggleUserActive(userId: p.cashierId, isActive: false);
      await repo.setUserLocked(p.cashierId, true);
      await repo.assignRoleToUser(p.accountantId, p.cashierRoleId);
      expect(await outboxCount(), 3);
      final u = (await p.userOn(p.client, 'cashier1'))!;
      expect(u.isActive, isTrue);
      expect(u.isLocked, isFalse);
    });

    test('admin password reset of another user is queued and also usable '
        'locally until the host applies it', () async {
      p.asClient();
      final repo = await repoWithSyncedUsers();
      await repo.updateUserPassword(
          userId: p.cashierId, newPassword: 'Changed#Pass789');
      expect(await outboxCount(), 1);
      expect(await p.canLogin(p.client, 'cashier1', 'Changed#Pass789'), isTrue);
    });

    test('a user changing their OWN password stays local (host route needs '
        'users_manage; dedicated endpoint is plan P2) and queues nothing',
        () async {
      p.asClient();
      final repo = await repoWithSyncedUsers();
      SyncInterceptor.currentUserId = p.cashierId;
      await repo.updateUserPassword(
          userId: p.cashierId, newPassword: 'Changed#Pass789');
      expect(await outboxCount(), 0);
      expect(await p.canLogin(p.client, 'cashier1', 'Changed#Pass789'), isTrue);
    });

    test('the bootstrap admin can still not be disabled or locked (guard kept '
        'before routing; nothing queued)', () async {
      p.asClient();
      final repo = await repoWithSyncedUsers();
      await expectLater(
          repo.toggleUserActive(userId: 1, isActive: false), throwsStateError);
      await expectLater(repo.setUserLocked(1, true), throwsStateError);
      expect(await outboxCount(), 0);
    });
  });

  group('standalone / server devices keep writing locally', () {
    test('no interception, no outbox', () async {
      final repo = await repoWithSyncedUsers(); // standalone
      await repo.toggleUserActive(userId: p.cashierId, isActive: false);
      await repo.assignRoleToUser(p.accountantId, p.cashierRoleId);
      await repo.setUserLocked(p.accountantId, true);
      expect((await p.userOn(p.client, 'cashier1'))!.isActive, isFalse);
      expect((await p.userOn(p.client, 'acct1'))!.isLocked, isTrue);
      expect(await outboxCount(), 0);
    });
  });

  test('ClientWriteInterceptor.updateUserPassword has a production caller '
      '(it used to be orphaned)', () {
    var callers = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      callers += RegExp(r'ClientWriteInterceptor\s*\.\s*updateUserPassword\s*\(')
          .allMatches(f.readAsStringSync())
          .length;
    }
    expect(callers, greaterThan(0));
  });
}
