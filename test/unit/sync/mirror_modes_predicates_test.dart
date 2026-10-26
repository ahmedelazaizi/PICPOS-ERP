// ═══════════════════════════════════════════════════════════════════════════
// REPRO R3 — NetworkMode.mirror vs client: predicate matrix, per-site guards,
// permission source, branch scope, write routing (users/login focus).
//
// `REPRO-*` = documents a BUG (asserts the CORRECT behaviour → fails today).
// `CHAR-*`  = characterization of current behaviour (passes today).
// Static-site tests read the product source (read-only) and assert the guard
// next to a known `isClient` site also covers mirror.
//
// Promoted from test/repro_mirror (all passing) - permanent test.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart' as prov;
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/websocket_sync_client.dart';
import 'package:picpos_erp/services/write_router.dart';

import '../../helpers/peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async => p.dispose());

  group('R3-A predicate matrix (what each mode answers)', () {
    String row() => [
          'NS.isClient=${NetworkService.instance.isClient}',
          'ServerProxy.isClientMode=${ServerProxy.isClientMode}',
          'SI.isClientMode=${SyncInterceptor.isClientMode}',
          'SI.isMirrorMode=${SyncInterceptor.isMirrorMode}',
          'WR.isMirrorActive=${WriteRouter.isMirrorActive}',
        ].join(' | ');

    test('CHAR-R3-a client', () {
      p.asClient();
      expect(row(),
          'NS.isClient=true | ServerProxy.isClientMode=true | SI.isClientMode=true | SI.isMirrorMode=false | WR.isMirrorActive=false');
    });

    test('CHAR-R3-b mirror (handshake done)', () {
      p.asMirror();
      expect(row(),
          'NS.isClient=false | ServerProxy.isClientMode=false | SI.isClientMode=true | SI.isMirrorMode=true | WR.isMirrorActive=true',
          reason: 'NS.isClient / ServerProxy.isClientMode EXCLUDE mirror; '
              'SyncInterceptor.isClientMode includes it (R9)');
    });

    test('CHAR-R3-c mirror persisted but NOT configured (no handshake)', () {
      p.asMirror(configured: false);
      expect(row(),
          'NS.isClient=false | ServerProxy.isClientMode=false | SI.isClientMode=false | SI.isMirrorMode=false | WR.isMirrorActive=false',
          reason: 'mode=mirror behaves like STANDALONE: no session, no branch '
              'gate, no offline policy, writes local. Only reconcileWithDb '
              '(next boot) stops it.');
    });

    test('CHAR-R3-d server / standalone', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);
      expect(SyncInterceptor.isClientMode, isFalse);
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      expect(SyncInterceptor.isClientMode, isFalse);
    });
  });

  group('R3-B per-site guards: does the `isClient` branch also cover mirror?',
      () {
    // REPRO-R3-e/f/g moved to test/unit/auth/mirror_login_gates_test.dart (green).

    test('CHAR-R3-h SyncInterceptor.isClientMode users (auth repo, session '
        'minting, branch gate, offline policy) DO cover mirror', () {
      for (final f in const [
        'lib/data/repositories/auth_repository_impl.dart',
        'lib/services/server_proxy.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('SyncInterceptor.isClientMode'), isTrue, reason: f);
      }
    });
  });

  group('R3-C users who arrive on a mirror', () {
    test('CHAR-R3-i mirror admin session: ALL users + credentials arrive',
        () async {
      p.asMirror();
      final json = await p.syncUsersFull(asUser: 1);
      final names = [
        for (final u in (json['users'] as List).cast<Map<String, dynamic>>())
          u['username']
      ];
      expect(names, containsAll(['admin', 'cashier1', 'acct1', 'mgr1']));
      expect(await p.canLogin(p.client, 'mgr1', kManagerPw), isTrue);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
    });

    // REPRO-R3-j moved to test/unit/api/users_feed_full_scope_test.dart (green).
    test('CHAR-R3-j2 same manager via delta pull (sync/pull?table=users): '
        'users are NOT branch-scoped — everyone arrives', () async {
      final json =
          await p.hostGet('/api/sync/pull?table=users', userId: p.managerId);
      final names = [
        for (final r in json['rows'] as List) (r as Map)['username']
      ];
      expect(names, containsAll(['admin', 'cashier1', 'acct1', 'mgr1']));
    });
    // REPRO-R3-k moved to test/unit/auth/mirror_login_gates_test.dart (green).
  });

  group('R3-D permission resolution for a mirror login', () {
    test('CHAR-R3-l role & permission codes come from the LOCAL db '
        '(role_permissions) — stale until a pull', () async {
      p.asMirror();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      final repo = AuthRepositoryImpl(p.client);
      final before = await repo.getUserPermissionCodes(p.cashierId);
      expect(before, isNotEmpty);

      // HQ revokes one permission from the cashier role.
      final perms = await p.host.getPermissionsForRole(p.cashierRoleId);
      await p.host.setRolePermissions(
          p.cashierRoleId, [for (final x in perms.skip(1)) x.id]);
      final hostCodes = await AuthRepositoryImpl(p.host)
          .getUserPermissionCodes(p.cashierId);
      final mirrorCodes = await repo.getUserPermissionCodes(p.cashierId);
      expect(hostCodes.length, lessThan(before.length));
      expect(mirrorCodes, before, reason: 'no refresh at login on mirror');
    });
  });

  group('R3-E branch scope for a two-branch user', () {
    Future<ProviderContainer> loginAs(int userId) async {
      WebSocketSyncClient.instance.connected.value = false;
      ElevationSnapshot.isCrossBranchElevated = false;
      final c = ProviderContainer(
          overrides: [prov.databaseProvider.overrideWithValue(p.client)]);
      c.read(prov.authProvider);
      final uwr = (await p.client.getUserById(userId))!;
      c.read(prov.authProvider.notifier).login(uwr);
      return c;
    }

    Future<void> giveClientTheAccessRows() async {
      await p.client.into(p.client.branches).insert(
          BranchesCompanion.insert(
              name: 'فرع ثانٍ',
              id: Value(p.branch2),
              globalId: const Value('gid-br-repro-2')),
          mode: InsertMode.insertOrIgnore);
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      ApiAuthMiddleware.closePairingWindow();
      for (final b in [p.branch1, p.branch2]) {
        await p.client.into(p.client.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: p.managerId, branchId: b),
            mode: InsertMode.insertOrIgnore);
      }
    }

    test('CHAR-R3-m MIRROR (configured): manager keeps BOTH assigned branches',
        () async {
      SharedPreferences.setMockInitialValues({});
      p.asMirror();
      await giveClientTheAccessRows();
      final c = await loginAs(p.managerId);
      final scope = await c.read(prov.branchScopeProvider.future);
      expect(scope.hasFullAccess, isFalse);
      expect(scope.allowedBranchIds, {p.branch1, p.branch2});
      c.dispose();
    });

    test('CHAR-R3-n CLIENT bound to branch 1: branchScopeProvider gives the '
        'same two branches (device narrowing lives elsewhere)', () async {
      p.asClient();
      await giveClientTheAccessRows();
      final c = await loginAs(p.managerId);
      final scope = await c.read(prov.branchScopeProvider.future);
      expect(scope.allowedBranchIds, {p.branch1, p.branch2});
      c.dispose();
    });
  });

  group('R3-F write operations (users/permissions) from client vs mirror', () {
    Future<AuthRepositoryImpl> repoWithSyncedUsers() async {
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      ApiAuthMiddleware.closePairingWindow();
      ClientWriteInterceptor.initialize(p.client);
      return AuthRepositoryImpl(p.client);
    }

    test('CHAR-R3-o MIRROR + unreachable HQ: branch-access write is REJECTED '
        '(MirrorOfflineException), nothing queued', () async {
      p.asMirror();
      final repo = await repoWithSyncedUsers();
      await expectLater(
          repo.setUserBranchAccess(p.cashierId, [p.branch1, p.branch2]),
          throwsA(isA<MirrorOfflineException>()));
    });

    test('CHAR-R3-p CLIENT + unreachable HQ: same write is QUEUED in the '
        'outbox (no exception)', () async {
      p.asClient();
      final repo = await repoWithSyncedUsers();
      await repo.setUserBranchAccess(p.cashierId, [p.branch1, p.branch2]);
      final n = await p.client
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(n.read<int>('n'), greaterThan(0));
    });

    // REPRO-R3-q moved to test/unit/auth/admin_user_ops_routing_test.dart (green).
  });
}
