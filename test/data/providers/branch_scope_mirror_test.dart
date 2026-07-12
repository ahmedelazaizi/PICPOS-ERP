// ═══════════════════════════════════════════════════════════════════════════
// Feature 006 (MM.B) — Mirror-mode override on branchScopeProvider
// ═══════════════════════════════════════════════════════════════════════════
//
// Verifies the device-level short-circuit added at the top of
// branchScopeProvider: when NetworkMode.mirror + MirrorState.isConfigured,
// any logged-in user (admin or otherwise) gets BranchScope.fullAccess so
// the HQ console can read every branch through the local cache. Mirror
// must take precedence over the existing per-user narrowing — even for a
// cashier whose user_branch_access table restricts them to a single
// branch on a non-mirror device.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/mirror_state.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

UserWithRole _cashier({required int userId, required int roleId}) {
  final role = Role(
    id: roleId,
    name: 'كاشير',
    isSystemRole: false,
    createdAt: DateTime.now(),
    rowVersion: 0,
  );
  final user = User(
    id: userId,
    username: 'cashier_$userId',
    passwordHash: 'h',
    passwordSalt: 's',
    displayName: 'cashier_$userId',
    roleId: roleId,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime.now(),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int branchA;
  late int branchB;
  late int cashierId;
  late int cashierRoleId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    WebSocketSyncClient.instance.connected.value = false;
    ElevationSnapshot.isCrossBranchElevated = false;

    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_A',
            globalId: const drift.Value('gid-br-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_B',
            globalId: const drift.Value('gid-br-b'),
          ),
        );

    // Insert a cashier role + user, then restrict the cashier to branchA
    // via user_branch_access. This makes the non-mirror baseline a scope
    // of `{branchA}` — exactly the scope the mirror short-circuit must
    // replace with fullAccess.
    cashierRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير'),
        );
    cashierId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'cashier_a',
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: 'Cashier A',
            roleId: drift.Value(cashierRoleId),
          ),
        );
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(
            userId: cashierId,
            branchId: branchA,
          ),
        );

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    // Force-build authProvider so the WS listener wires up before login.
    container.read(authProvider);
    container.read(authProvider.notifier).login(
          _cashier(userId: cashierId, roleId: cashierRoleId),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('branchScopeProvider — mirror mode', () {
    test('non-mirror baseline: cashier is restricted to branchA only',
        () async {
      // Sanity check: without mirror, the cashier sees one branch only.
      // If this assertion fails, the rest of the suite is meaningless —
      // we'd be matching fullAccess against an already-fullAccess baseline.
      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isFalse,
          reason: 'cashier with user_branch_access row must be scoped');
      expect(scope.allowedBranchIds, equals({branchA}));
      expect(scope.isAllowed(branchB), isFalse,
          reason: 'branchB must be hidden from this cashier on a non-mirror device');
    });

    test('mirror + configured: cashier gets fullAccess', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.example.com:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      // Re-read after flipping the global state; FutureProvider doesn't
      // self-invalidate when the singletons it reads change, so we rebuild
      // the container's binding by invalidating the provider explicitly.
      container.invalidate(branchScopeProvider);

      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isTrue,
          reason: 'mirror is a device-level assertion — overrides per-user scope');
      expect(scope.isAllowed(branchB), isTrue,
          reason: 'every branch must be visible on a mirror device');
    });

    test('mirror but NOT configured: short-circuit must NOT apply', () async {
      // Half-state: NetworkMode.mirror is set but the wizard handshake
      // never completed (MirrorState.isConfigured == false). The branch
      // scope must fall through to the regular per-user narrowing —
      // unconfigured mirror is an invalid runtime state, not an
      // implicit fullAccess grant.
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      // Leave MirrorState empty (no setPaired, no debugSetForTests args)
      MirrorState.instance.debugSetForTests();
      expect(MirrorState.instance.isConfigured, isFalse);

      container.invalidate(branchScopeProvider);
      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isFalse,
          reason: 'unconfigured mirror must not bypass the per-user scope');
      expect(scope.allowedBranchIds, equals({branchA}));
    });

    test('configured but mode is client (not mirror): no short-circuit',
        () async {
      // Defensive: MirrorState left over from a previous mirror session
      // must not leak into a device that has since been re-paired as a
      // regular client. The gate must be conjunctive — both flags
      // required.
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.example.com:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(MirrorState.instance.isConfigured, isTrue);

      container.invalidate(branchScopeProvider);
      final scope = await container.read(branchScopeProvider.future);
      // In client mode, branch isolation is the default unless the
      // client_pulls_transactional flag flips. Either way this user's
      // scope must remain {branchA} — fullAccess would mean the mirror
      // short-circuit fired despite being in client mode.
      expect(scope.hasFullAccess, isFalse,
          reason: 'mirror gate must require BOTH isMirror AND isConfigured');
    });
  });
}
