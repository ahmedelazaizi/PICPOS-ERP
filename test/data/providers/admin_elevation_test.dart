// ═══════════════════════════════════════════════════════════════════════════
// Feature 004 (Multi-Branch Governance, US3) — Admin elevation tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers spec.md FRs:
//   FR-018      — elevation triple (role + paired client + live)
//   FR-020      — logout clears elevation
//   FR-022      — role downgrade re-runs the recomputation
//   FR-023      — connection drop flips canMutate to false
//   FR-023a     — connection restore flips canMutate back to true
//   FR-024      — Branch Manager never elevated even on paired client
//   FR-024a     — System Admin BOUND to a specific branch is NOT elevated
//                 cross-branch (only HQ-style admins with empty
//                 user_branch_access mirror the server)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/mutation_guard_provider.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/websocket_sync_client.dart';

UserWithRole _userWithRole({
  required String roleName,
  required bool isSystemRole,
}) {
  final role = Role(
    id: 1,
    name: roleName,
    isSystemRole: isSystemRole,
    createdAt: DateTime.now(),
    rowVersion: 0,
  );
  final user = User(
    id: 42,
    username: 'tester',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: 'tester',
    roleId: 1,
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
  late ProviderContainer container;

  setUp(() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    WebSocketSyncClient.instance.connected.value = false;
    ElevationSnapshot.isCrossBranchElevated = false;
    MutationGuard.current = MutationGuard.allow();
    container = ProviderContainer();
    // Force-build authProvider so AuthNotifier subscribes to the WS notifier.
    container.read(authProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('AuthState.isCrossBranchElevated', () {
    test('(a) System Admin on standalone is NOT elevated', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      WebSocketSyncClient.instance.connected.value = true;

      container.read(authProvider.notifier).login(
            _userWithRole(roleName: 'مدير النظام', isSystemRole: true),
          );

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.isCrossBranchElevated, isFalse,
          reason: 'standalone bypasses the paired-client requirement');
      expect(ElevationSnapshot.isCrossBranchElevated, isFalse);
    });

    test('(b) System Admin on paired client + live connection + HQ-bound IS elevated',
        () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      WebSocketSyncClient.instance.connected.value = true;

      final notifier = container.read(authProvider.notifier);
      notifier.login(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true),
      );
      // HQ-bound admin: empty user_branch_access ⇒ unrestricted ⇒ elevates.
      notifier.debugSetActorUnrestricted(true);

      expect(container.read(authProvider).isCrossBranchElevated, isTrue);
      expect(ElevationSnapshot.isCrossBranchElevated, isTrue,
          reason: 'static mirror feeds DAOs that write activity logs');
    });

    test('(c)+(d) connection drop flips MutationGuard.canMutate; restore flips back', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      WebSocketSyncClient.instance.connected.value = true;

      final notifier = container.read(authProvider.notifier);
      notifier.login(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true),
      );
      notifier.debugSetActorUnrestricted(true);

      // Force the provider to evaluate so MutationGuard.current mirrors.
      expect(container.read(mutationGuardProvider).canMutate, isTrue);
      expect(MutationGuard.current.canMutate, isTrue);

      // Drop the connection — Provider self-invalidates via the WS listener
      // and mutationGuardProvider re-runs synchronously on next read.
      WebSocketSyncClient.instance.connected.value = false;
      final guardDown = container.read(mutationGuardProvider);
      expect(guardDown.canMutate, isFalse,
          reason: 'FR-023 — banner & writes denied while disconnected');
      expect(guardDown.reason, isNotEmpty);

      // Restore the connection.
      WebSocketSyncClient.instance.connected.value = true;
      expect(container.read(mutationGuardProvider).canMutate, isTrue,
          reason: 'FR-023a — guard recovers automatically on reconnect');
    });

    test('(e) logout clears elevation', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      WebSocketSyncClient.instance.connected.value = true;

      final notifier = container.read(authProvider.notifier);
      notifier.login(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true),
      );
      notifier.debugSetActorUnrestricted(true);
      expect(container.read(authProvider).isCrossBranchElevated, isTrue);

      notifier.logout();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).isCrossBranchElevated, isFalse,
          reason: 'FR-020 — logout drops the elevation flag');
    });

    test('(f) Branch Manager on paired client is NEVER elevated (FR-024)', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      WebSocketSyncClient.instance.connected.value = true;

      final notifier = container.read(authProvider.notifier);
      notifier.login(
        _userWithRole(roleName: 'مدير الفرع', isSystemRole: false),
      );
      // Even if a Branch Manager somehow had unrestricted access, the role
      // gate alone must block elevation.
      notifier.debugSetActorUnrestricted(true);

      expect(container.read(authProvider).isCrossBranchElevated, isFalse,
          reason: 'FR-024 — only "مدير النظام" with isSystemRole=true elevates');
      expect(ElevationSnapshot.isCrossBranchElevated, isFalse);
    });

    test('(g) System Admin BOUND to a specific branch is NOT elevated (FR-024a)',
        () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      WebSocketSyncClient.instance.connected.value = true;

      final notifier = container.read(authProvider.notifier);
      notifier.login(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true),
      );
      // Branch-bound: user_branch_access has 1+ row ⇒ NOT unrestricted.
      notifier.debugSetActorUnrestricted(false);

      expect(container.read(authProvider).isCrossBranchElevated, isFalse,
          reason:
              'FR-024a — only an HQ-bound admin (no branch restriction) '
              'mirrors the server. A System Admin assigned to a specific '
              'branch manages that branch only.');
      expect(ElevationSnapshot.isCrossBranchElevated, isFalse);
      // Branch-scope provider for this user falls back to standard narrowing
      // (no fullAccess override). This is verified indirectly here via the
      // elevation flag and explicitly in branch_scope_provider tests.
    });
  });
}
