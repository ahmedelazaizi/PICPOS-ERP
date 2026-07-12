import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    // Migrations and initial seeding happen in onCreate via forTesting's memory db
  });

  tearDown(() async {
    await database.close();
  });

  group('PermissionsDao - RBAC Operations', () {
    test('getAllPermissions - should return seeded permissions', () async {
      final permissions = await database.getAllPermissions();
      
      expect(permissions, isNotEmpty);
      expect(permissions.any((p) => p.code == 'pos_access'), isTrue);
    });

    test('insertRole and roleHasPermission - should manage role permissions', () async {
      // 1. Create a custom role
      final roleId = await database.insertRole(
        name: 'Sales Agent',
        description: 'Limited sales access',
      );

      // 2. Assign permission
      final posAccessPerm = (await database.getAllPermissions())
          .firstWhere((p) => p.code == 'pos_access');
      
      await database.addPermissionToRole(roleId, posAccessPerm.id);

      // 3. Verify
      final hasPermission = await database.roleHasPermission(roleId, 'pos_access');
      final hasNoPermission = await database.roleHasPermission(roleId, 'inventory_edit');

      expect(hasPermission, isTrue);
      expect(hasNoPermission, isFalse);
    });

    test('User Permissions - should correctly authorize users via roles', () async {
      // 1. Create Role & Permission mapping
      final roleId = await database.insertRole(name: 'Cashier');
      final posPerm = (await database.getAllPermissions())
          .firstWhere((p) => p.code == 'pos_access');
      await database.addPermissionToRole(roleId, posPerm.id);

      // 2. Create User and assign role
      final userId = await database.into(database.users).insert(
        UsersCompanion.insert(
          username: 'cashier_user',
          passwordHash: 'dummy',
          displayName: 'Test Cashier',
          roleId: Value(roleId),
        )
      );

      // 3. Verify Authorization
      final canAccessPos = await database.userHasPermission(userId, 'pos_access');
      final canEditInventory = await database.userHasPermission(userId, 'inventory_edit');

      expect(canAccessPos, isTrue);
      expect(canEditInventory, isFalse);
    });

    test('System Admin Role - should have all permissions by default', () async {
      // 1. Find or Create System Admin Role
      final roles = await database.getAllRoles();
      var adminRole = roles.where((r) => r.name == 'مدير النظام').firstOrNull;
      
      if (adminRole == null) {
        final id = await database.insertRole(
          name: 'مدير النظام', 
          isSystemRole: true
        );
        adminRole = await database.getRoleById(id);
      }

      // 2. Create Admin User
      final adminId = await database.into(database.users).insert(
        UsersCompanion.insert(
          username: 'super_admin',
          passwordHash: 'dummy',
          displayName: 'System Admin',
          roleId: Value(adminRole!.id),
        )
      );

      // 3. Verify (Admin should have everything even without explicit mapping if logic allows)
      // Note: PermissionsDao.userHasPermission has a special check for 'مدير النظام'
      final hasInventoryEdit = await database.userHasPermission(adminId, 'inventory_edit');
      expect(hasInventoryEdit, isTrue);
    });
  });
}
