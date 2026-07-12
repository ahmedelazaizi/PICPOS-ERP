// ═══════════════════════════════════════════════════════════════════════════
// RolePermissionSyncStrategy — race-condition tests (Feature 006 #7)
// ═══════════════════════════════════════════════════════════════════════════
//
// Reproduces the same class of bug fixed for user_branch_access in 005:
// the strategy used to wipe role_permissions then re-insert from the
// server snapshot, so a local grant happening between the wipe and the
// snapshot insert was silently lost.
//
// The fix switches to UPSERT+diff-delete keyed on the composite PK
// (roleId, permissionId).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/role_permission_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late RolePermissionSyncStrategy strategy;
  late int roleAdminId;
  late int roleCashierId;
  late int permPosSaveId;
  late int permPosVoidId;
  late int permReportsId;

  Future<int> seedRole(String name) async {
    return db.into(db.roles).insert(
          RolesCompanion.insert(
            name: name,
            description: const Value('test role'),
          ),
        );
  }

  Future<int> seedPermission(String code, String name) async {
    return db.into(db.permissions).insert(
          PermissionsCompanion.insert(
            code: code,
            name: name,
            category: 'pos',
          ),
        );
  }

  Future<Set<String>> readAllRolePerms() async {
    final rows = await db.select(db.rolePermissions).get();
    return rows.map((r) => '${r.roleId}_${r.permissionId}').toSet();
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = RolePermissionSyncStrategy(db);
    // forTesting() auto-seeds the standard permission/role catalogue, so
    // create unique test fixtures (with prefixed codes/names) to avoid
    // colliding with the seeded UNIQUE keys. Each test gets a fresh
    // in-memory DB so stable names are safe.
    roleAdminId = await seedRole('test_admin');
    roleCashierId = await seedRole('test_cashier');
    permPosSaveId = await seedPermission('test_perm_save', 'Test Save Permission');
    permPosVoidId = await seedPermission('test_perm_void', 'Test Void Permission');
    permReportsId = await seedPermission('test_perm_reports', 'Test Reports Permission');
  });

  tearDown(() => db.close());

  group('syncFromJson', () {
    test('inserts every grant from server snapshot when local is empty',
        () async {
      await strategy.syncFromJson({
        'role_permissions': [
          {
            'roleId': roleAdminId,
            'permissionId': permPosSaveId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_save',
          },
          {
            'roleId': roleAdminId,
            'permissionId': permReportsId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_reports',
          },
          {
            'roleId': roleCashierId,
            'permissionId': permPosSaveId,
            'roleName': 'test_cashier',
            'permissionCode': 'test_perm_save',
          },
        ],
      });

      expect(await readAllRolePerms(), {
        '${roleAdminId}_$permPosSaveId',
        '${roleAdminId}_$permReportsId',
        '${roleCashierId}_$permPosSaveId',
      });
    });

    test('PRESERVES a freshly-granted local row when server snapshot agrees',
        () async {
      // Admin grants pos_save to cashier locally; before the WS broadcast
      // round-trips, a snapshot pull arrives that already includes this
      // grant. The new strategy must NOT churn — old behaviour wiped the
      // table first, leaving a microsecond window where the cashier had
      // no pos_save and the override dialog fired on the next sale.
      await db.into(db.rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: roleCashierId,
              permissionId: permPosSaveId,
            ),
          );

      await strategy.syncFromJson({
        'role_permissions': [
          {
            'roleId': roleCashierId,
            'permissionId': permPosSaveId,
            'roleName': 'test_cashier',
            'permissionCode': 'test_perm_save',
          },
        ],
      });

      expect(await readAllRolePerms(), {
        '${roleCashierId}_$permPosSaveId',
      });
    });

    test('removes server-side revoked rows (deletion propagation)', () async {
      // Local has two grants. Server later revoked the second one —
      // diff-delete must drop only the missing row, not the surviving one.
      await db.into(db.rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: roleAdminId, permissionId: permPosSaveId,
            ),
          );
      await db.into(db.rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: roleAdminId, permissionId: permPosVoidId,
            ),
          );

      await strategy.syncFromJson({
        'role_permissions': [
          {
            'roleId': roleAdminId,
            'permissionId': permPosSaveId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_save',
          },
        ],
      });

      expect(await readAllRolePerms(), {'${roleAdminId}_$permPosSaveId'});
    });

    test('resolves permission by code even when server id differs from local',
        () async {
      // The strategy's documented purpose: server may have permPosSave at
      // id=99 while local has it at permPosSaveId — it should still match
      // by code and grant against the LOCAL id.
      const serverPosSaveId = 999;
      expect(serverPosSaveId, isNot(permPosSaveId));

      await strategy.syncFromJson({
        'role_permissions': [
          {
            'roleId': roleAdminId,
            'permissionId': serverPosSaveId, // server's view
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_save', // resolved to local id
          },
        ],
      });

      // Stored against the LOCAL permission id, not the server one.
      expect(await readAllRolePerms(), {'${roleAdminId}_$permPosSaveId'});
    });

    test('skips rows whose role/permission cannot be resolved locally',
        () async {
      await strategy.syncFromJson({
        'role_permissions': [
          {
            'roleId': roleAdminId,
            'permissionId': permPosSaveId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_save',
          },
          {
            'roleId': 999_999,                     // non-existent local role
            'permissionId': permPosSaveId,
            'roleName': 'ghost_role',
            'permissionCode': 'test_perm_save',
          },
          {
            'roleId': roleAdminId,
            'permissionId': 999_998,
            'roleName': 'test_admin',
            'permissionCode': 'unknown_permission', // non-existent code
          },
        ],
      });

      expect(await readAllRolePerms(), {'${roleAdminId}_$permPosSaveId'});
    });

    test('idempotent: repeated calls with the same snapshot stay stable',
        () async {
      final snapshot = {
        'role_permissions': [
          {
            'roleId': roleAdminId,
            'permissionId': permPosSaveId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_save',
          },
          {
            'roleId': roleAdminId,
            'permissionId': permReportsId,
            'roleName': 'test_admin',
            'permissionCode': 'test_perm_reports',
          },
        ],
      };

      await strategy.syncFromJson(snapshot);
      final firstPass = await readAllRolePerms();

      await strategy.syncFromJson(snapshot);
      final secondPass = await readAllRolePerms();

      expect(secondPass, firstPass);
    });
  });
}
