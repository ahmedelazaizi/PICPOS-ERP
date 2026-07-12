// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 Track-3 — branchScopeProvider fail-closed for mis-provisioned users
// ═══════════════════════════════════════════════════════════════════════════
//
// Client-side twin of residual #2 (D-06 fail-open). getUserAccessibleBranchIds
// returns `[]` for TWO different users: a privileged one (admin / financial
// manager / userId=1 → genuine full access) AND a non-privileged one
// mis-provisioned with zero user_branch_access/region rows. The provider used
// to map ANY empty list to fullAccess, so the second user silently inherited
// company-wide access — nullifying every downstream branch-scope cap (reports,
// POS, parties). The fix disambiguates via isFullBranchAccessUser: privileged →
// fullAccess, non-privileged-with-nothing → fail CLOSED (empty set = sees
// nothing until assigned). Mirrors the server-side sentinel in _extractBranchId.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/mirror_state.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

UserWithRole _userWithRole({
  required int userId,
  required int roleId,
  required String roleName,
  required bool isSystemRole,
}) {
  final role = Role(
    id: roleId,
    name: roleName,
    isSystemRole: isSystemRole,
    createdAt: DateTime.now(),
    rowVersion: 0,
  );
  final user = User(
    id: userId,
    username: 'user_$userId',
    passwordHash: 'h',
    passwordSalt: 's',
    displayName: 'user_$userId',
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    WebSocketSyncClient.instance.connected.value = false;
    ElevationSnapshot.isCrossBranchElevated = false;

    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // A branch exists in the world, but the mis-provisioned user has NO
    // user_branch_access row pointing at it.
    await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_A',
            globalId: const drift.Value('gid-fc-a'),
          ),
        );

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    container.read(authProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<(int userId, int roleId)> insertUser(String roleName) async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: roleName),
        );
    final userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'u_$roleName',
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: roleName,
            roleId: drift.Value(roleId),
          ),
        );
    return (userId, roleId);
  }

  group('branchScopeProvider — mis-provisioned fail-closed', () {
    test('non-privileged user with ZERO assignments → fail CLOSED (empty set)',
        () async {
      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(name: 'كاشير'),
          );
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'cashier_noassign',
              passwordHash: 'h',
              passwordSalt: const drift.Value('s'),
              displayName: 'Cashier NoAssign',
              roleId: drift.Value(roleId),
            ),
          );
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'كاشير',
            isSystemRole: false,
          ));

      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isFalse,
          reason: 'a mis-provisioned cashier must NOT inherit company-wide '
              'access — that would nullify every branch-scope cap');
      expect(scope.allowedBranchIds, isEmpty,
          reason: 'empty set = fail closed = sees nothing until assigned');
    });

    test('system admin with ZERO assignments → full access (unchanged)',
        () async {
      final (adminUserId, adminRoleId) = await insertUser('مدير النظام');
      container.read(authProvider.notifier).login(_userWithRole(
            userId: adminUserId,
            roleId: adminRoleId,
            roleName: 'مدير النظام',
            isSystemRole: true,
          ));

      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isTrue,
          reason: 'admin/FM privilege still maps empty-list → full access');
    });

    test('financial manager with ZERO assignments → full access (unchanged)',
        () async {
      final (fmUserId, fmRoleId) = await insertUser('مدير مالي');
      container.read(authProvider.notifier).login(_userWithRole(
            userId: fmUserId,
            roleId: fmRoleId,
            roleName: 'مدير مالي',
            isSystemRole: true,
          ));

      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isTrue);
    });
  });
}
