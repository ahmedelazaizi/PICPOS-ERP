// Plan 2026-10-23 §B.4: the four warehouse personas and the pairing permission.
//   «موظف مخزن» (new) · «مخزني» · «مشرف مخزن» (new) · «مدير مخزون»
// `devices_pair_manage` belongs to «مدير النظام» only and to none of the four.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';
import 'package:picpos_erp/services/warehouse_roles_seeder.dart';

Set<String> _grants(String role) => RoleGrantMatrix.defaultGrants[role]!;

void main() {
  test('the matrix gives each persona exactly the implemented warehouse codes', () {
    expect(_grants(kWarehouseClerkRole),
        {'warehouse_mobile_access', 'inventory_view', 'goods_receipt_mobile', 'stock_count_submit'});
    expect(_grants(kWarehouseSupervisorRole), {
      'warehouse_mobile_access', 'inventory_view', 'inventory_edit', 'inventory_transfer',
      'goods_receipt_mobile', 'stock_count_submit', 'stock_adjust_approve',
    });
    expect(_grants('مخزني'), containsAll(['warehouse_mobile_access', 'inventory_transfer', 'inventory_view',
      'goods_receipt_mobile', 'stock_count_submit']));
    expect(_grants('مدير مخزون'), containsAll(['warehouse_mobile_access', 'inventory_transfer', 'products_cost_view',
      'goods_receipt_mobile', 'stock_count_submit', 'stock_adjust_approve']));
  });

  test('the approval code is held by the supervisor and manager only, never by clerk or keeper', () {
    final holders = [
      for (final e in RoleGrantMatrix.defaultGrants.entries)
        if (e.value.contains('stock_adjust_approve')) e.key,
    ];
    expect(holders, unorderedEquals([kWarehouseSupervisorRole, 'مدير مخزون']));
  });

  test('the clerk has no transfer, no edit and no cost view', () {
    final clerk = _grants(kWarehouseClerkRole);
    for (final c in ['inventory_transfer', 'inventory_edit', 'products_cost_view', 'devices_pair_manage']) {
      expect(clerk, isNot(contains(c)), reason: c);
    }
  });

  test('devices_pair_manage is granted to «مدير النظام» and to no other default role', () {
    final holders = [
      for (final e in RoleGrantMatrix.defaultGrants.entries)
        if (e.value.contains('devices_pair_manage')) e.key,
    ];
    expect(holders, ['مدير النظام']);
  });

  test('all warehouse codes are in the master list under one category', () {
    final byCode = {for (final e in PermissionCodes.masterList) e['code']!: e['category']};
    for (final c in ['devices_pair_manage', 'warehouse_mobile_access', 'goods_receipt_mobile', 'stock_count_submit', 'stock_adjust_approve']) {
      expect(byCode[c], 'warehouse_mobile', reason: c);
    }
    expect(PermissionCodes.categoryNames.containsKey('warehouse_mobile'), isTrue);
  });

  group('seeding', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('ensureWarehouseRoles is idempotent and never touches an existing role', () async {
      await ensureWarehouseRoles(db);
      for (final n in [kWarehouseClerkRole, kWarehouseSupervisorRole]) {
        await db.customStatement('DELETE FROM role_permissions WHERE role_id IN (SELECT id FROM roles WHERE name = ?)', [n]);
        await db.customStatement('DELETE FROM roles WHERE name = ?', [n]);
      }
      expect(await ensureWarehouseRoles(db), 2);
      expect(await ensureWarehouseRoles(db), 0);
      final roles = await db.select(db.roles).get();
      expect(roles.where((r) => r.name == kWarehouseClerkRole), hasLength(1));
      expect(roles.where((r) => r.name == kWarehouseSupervisorRole), hasLength(1));
    });

    test('grantMissingDefaults creates the roles and grants them; a second run adds nothing', () async {
      await RoleGrantPreflightService(db).grantMissingDefaults();
      final svc = RoleGrantPreflightService(db);
      expect(await svc.grantMissingDefaults(), 0);
      final report = await svc.scanMissingGrants();
      expect(report.totalMissingPairs, 0);

      final clerk = await (db.select(db.roles)..where((r) => r.name.equals(kWarehouseClerkRole))).getSingle();
      expect(clerk.isSystemRole, isTrue);
      for (final code in _grants(kWarehouseClerkRole)) {
        final user = await db.into(db.users).insert(UsersCompanionHelper.forRole(clerk.id, 'u_$code'));
        expect(await db.userHasPermission(user, code), isTrue, reason: code);
      }
      final u = await db.into(db.users).insert(UsersCompanionHelper.forRole(clerk.id, 'u_probe'));
      expect(await db.userHasPermission(u, 'devices_pair_manage'), isFalse);
      expect(await db.userHasPermission(u, 'inventory_transfer'), isFalse);
    });
  });
}

/// Minimal user row for permission lookups.
class UsersCompanionHelper {
  static UsersCompanion forRole(int roleId, String name) => UsersCompanion.insert(
        username: name,
        passwordHash: 'x',
        displayName: name,
        roleId: Value(roleId),
      );
}
