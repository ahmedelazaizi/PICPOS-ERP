import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';

/// PIR Integration Test 5 — Permission Guard Flow
///
/// Verifies the RBAC (Role-Based Access Control) system:
///   - User without permission → denied
///   - System admin → always allowed (bypass)
///   - Granting permission to role → user gains access
///   - Revoking permission from role → user loses access
///   - Role-based: all users in same role share permissions
void main() {
  late AppDatabase db;
  late int adminRoleId;
  late int cashierRoleId;
  late int adminUserId;
  late int cashierUserId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Create system admin role (isSystemRole = true → bypass all checks)
    adminRoleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'مدير النظام',
        isSystemRole: const Value(true),
      ),
    );

    // Create cashier role (no permissions initially)
    cashierRoleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'كاشير',
        isSystemRole: const Value(false),
      ),
    );

    // Create admin user
    adminUserId = await db.createUser(
      username: 'pir_admin',
      password: 'admin123',
      displayName: 'PIR Admin',
      roleId: adminRoleId,
    );

    // Create cashier user
    cashierUserId = await db.createUser(
      username: 'pir_cashier',
      password: 'cash123',
      displayName: 'PIR Cashier',
      roleId: cashierRoleId,
    );
  });

  tearDown(() async => db.close());

  group('PIR: Permission Guard — RBAC', () {
    test('System admin has all permissions (isSystemRole bypass)', () async {
      // Admin should have ANY permission, even ones not explicitly granted
      final canSell = await db.userHasPermission(adminUserId, 'pos_sell');
      final canEditPrice = await db.userHasPermission(adminUserId, 'pos_edit_price');
      final canViewReports = await db.userHasPermission(adminUserId, 'reports_sales');
      final canManageUsers = await db.userHasPermission(adminUserId, 'manage_users');

      expect(canSell, isTrue, reason: 'System admin bypasses all permission checks');
      expect(canEditPrice, isTrue);
      expect(canViewReports, isTrue);
      expect(canManageUsers, isTrue);
    });

    test('Cashier without permissions is denied', () async {
      // Cashier role has no permissions initially
      final canSell = await db.userHasPermission(cashierUserId, 'pos_sell');
      final canEditPrice = await db.userHasPermission(cashierUserId, 'pos_edit_price');

      expect(canSell, isFalse,
          reason: 'User without granted permission should be denied');
      expect(canEditPrice, isFalse);
    });

    test('Granting permission to role enables access for user', () async {
      // Get the pos_sell permission from seeded permissions
      final allPerms = await db.select(db.permissions).get();
      final posSellPerm = allPerms.where((p) => p.code == 'pos_sell');

      // Skip if permissions haven't been seeded yet
      if (posSellPerm.isEmpty) return;

      // Grant pos_sell to cashier role
      await db.addPermissionToRole(cashierRoleId, posSellPerm.first.id);

      // Now cashier should have pos_sell
      final canSell = await db.userHasPermission(cashierUserId, 'pos_sell');
      expect(canSell, isTrue,
          reason: 'User should gain access after permission is granted to their role');

      // But NOT pos_edit_price (not granted)
      final canEditPrice = await db.userHasPermission(cashierUserId, 'pos_edit_price');
      expect(canEditPrice, isFalse,
          reason: 'Ungranted permissions should still be denied');
    });

    test('Revoking permission from role removes access', () async {
      final allPerms = await db.select(db.permissions).get();
      final posSellPerm = allPerms.where((p) => p.code == 'pos_sell');
      if (posSellPerm.isEmpty) return;

      // Grant then revoke
      await db.addPermissionToRole(cashierRoleId, posSellPerm.first.id);

      // Verify granted
      var canSell = await db.userHasPermission(cashierUserId, 'pos_sell');
      expect(canSell, isTrue);

      // Revoke
      await db.removePermissionFromRole(cashierRoleId, posSellPerm.first.id);

      // Verify revoked
      canSell = await db.userHasPermission(cashierUserId, 'pos_sell');
      expect(canSell, isFalse,
          reason: 'Revoking permission from role should remove access');
    });

    test('All users in same role share permissions', () async {
      // Create second cashier
      final cashier2Id = await db.createUser(
        username: 'pir_cashier2',
        password: 'cash456',
        displayName: 'PIR Cashier 2',
        roleId: cashierRoleId,
      );

      final allPerms = await db.select(db.permissions).get();
      final posSellPerm = allPerms.where((p) => p.code == 'pos_sell');
      if (posSellPerm.isEmpty) return;

      // Grant to role
      await db.addPermissionToRole(cashierRoleId, posSellPerm.first.id);

      // Both cashiers should have access
      final cashier1Can = await db.userHasPermission(cashierUserId, 'pos_sell');
      final cashier2Can = await db.userHasPermission(cashier2Id, 'pos_sell');

      expect(cashier1Can, isTrue);
      expect(cashier2Can, isTrue,
          reason: 'Role-based: all users in same role share permissions');
    });

    test('User with no role has no permissions', () async {
      // Create user without role
      final noRoleUserId = await db.createUser(
        username: 'pir_norole',
        password: 'norole123',
        displayName: 'No Role User',
      );

      final canSell = await db.userHasPermission(noRoleUserId, 'pos_sell');
      expect(canSell, isFalse,
          reason: 'User without a role should have zero permissions');
    });

    test('Admin can authenticate with correct password', () async {
      // Verify admin can authenticate (for manager override flow)
      final auth = await db.authenticateUser('pir_admin', 'admin123');
      expect(auth, isNotNull, reason: 'Valid credentials should authenticate');
      expect(auth!.user.id, adminUserId);

      // Wrong password fails
      final badAuth = await db.authenticateUser('pir_admin', 'wrong');
      expect(badAuth, isNull, reason: 'Invalid password should fail');
    });

    test('Bulk permission assignment via setRolePermissions', () async {
      final allPerms = await db.select(db.permissions).get();
      if (allPerms.length < 3) return;

      // Assign 3 specific permissions
      final permIds = allPerms.take(3).map((p) => p.id).toList();
      await db.setRolePermissions(cashierRoleId, permIds);

      // Verify all 3 are granted
      for (final perm in allPerms.take(3)) {
        final has = await db.userHasPermission(cashierUserId, perm.code);
        expect(has, isTrue, reason: 'Permission ${perm.code} should be granted');
      }

      // Verify other permissions are NOT granted
      if (allPerms.length > 3) {
        final ungrantedPerm = allPerms[3];
        final has = await db.userHasPermission(cashierUserId, ungrantedPerm.code);
        expect(has, isFalse,
            reason: 'Permission ${ungrantedPerm.code} should NOT be granted');
      }
    });
  });
}
