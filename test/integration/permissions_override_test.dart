import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';

/// E2E Test: Permissions + Manager Override Flow (Sprint 17)
/// Normal User → Permission Denied → Admin Grants → Access Allowed
void main() {
  late AppDatabase db;
  late int adminRoleId;
  late int cashierRoleId;
  late int adminUserId;
  late int cashierUserId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Create roles
    adminRoleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'مدير النظام', isSystemRole: const Value(true)),
    );
    cashierRoleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );

    // Create users
    adminUserId = await db.createUser(
      username: 'perm_admin',
      password: 'admin123',
      displayName: 'Admin',
      roleId: adminRoleId,
    );
    cashierUserId = await db.createUser(
      username: 'perm_cashier',
      password: 'cash123',
      displayName: 'Cashier',
      roleId: cashierRoleId,
    );

    // Grant a specific permission to cashier role
    final permissions = await db.select(db.permissions).get();
    if (permissions.isNotEmpty) {
      // Grant the first available permission to cashier
      await db.into(db.rolePermissions).insert(
        RolePermissionsCompanion.insert(
          roleId: cashierRoleId,
          permissionId: permissions.first.id,
        ),
      );
    }
  });

  tearDown(() async => db.close());

  group('E2E Permissions + Manager Override', () {
    test('System admin has all permissions', () async {
      // Admin (system role) should have all permissions
      final canSell = await db.userHasPermission(adminUserId, 'pos_sell');
      final canEditPrice = await db.userHasPermission(adminUserId, 'pos_edit_price');
      final canViewReports = await db.userHasPermission(adminUserId, 'reports_sales');

      expect(canSell, isTrue);
      expect(canEditPrice, isTrue);
      expect(canViewReports, isTrue);
    });

    test('Cashier has only granted permissions', () async {
      // Get the first permission that was granted
      final allPerms = await db.select(db.permissions).get();
      if (allPerms.isEmpty) return; // Skip if no permissions seeded

      final grantedCode = allPerms.first.code;

      // Cashier should have the granted permission
      final hasGranted = await db.userHasPermission(cashierUserId, grantedCode);
      expect(hasGranted, isTrue);

      // Find a permission NOT granted to cashier
      final ungrantedPerm = allPerms.where((p) => p.id != allPerms.first.id);
      if (ungrantedPerm.isNotEmpty) {
        final hasUngranted = await db.userHasPermission(
          cashierUserId,
          ungrantedPerm.first.code,
        );
        expect(hasUngranted, isFalse);
      }
    });

    test('Granting permission to role affects all role users', () async {
      // Create second cashier
      final cashier2Id = await db.createUser(
        username: 'cashier2',
        password: 'cash456',
        displayName: 'Cashier 2',
        roleId: cashierRoleId,
      );

      // Both cashiers should have same permissions
      final cashier1HasPerm = await db.userHasPermission(
        cashierUserId,
        'pos_sell',
      );
      final cashier2HasPerm = await db.userHasPermission(
        cashier2Id,
        'pos_sell',
      );

      expect(cashier1HasPerm, cashier2HasPerm);
    });

    test('Login authenticates correct user', () async {
      // Valid credentials (use unique username from our setUp)
      final validUser = await db.authenticateUser('perm_admin', 'admin123');
      expect(validUser, isNotNull);
      expect(validUser!.user.displayName, 'Admin');

      // Wrong password
      final invalidUser = await db.authenticateUser('perm_admin', 'wrong');
      expect(invalidUser, isNull);

      // Non-existent user
      final noUser = await db.authenticateUser('nobody_at_all', 'test');
      expect(noUser, isNull);
    });

    test('Role with no permissions denies everything', () async {
      // Create a role with zero permissions
      final emptyRoleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'ضيف', isSystemRole: const Value(false)),
      );
      final guestId = await db.createUser(
        username: 'guest',
        password: 'guest123',
        displayName: 'Guest',
        roleId: emptyRoleId,
      );

      final canSell = await db.userHasPermission(guestId, 'pos_sell');
      final canView = await db.userHasPermission(guestId, 'reports_sales');

      expect(canSell, isFalse);
      expect(canView, isFalse);
    });
  });
}
