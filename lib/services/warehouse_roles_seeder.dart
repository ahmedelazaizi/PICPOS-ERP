// Creates the warehouse-app roles of plan 2026-10-23 §B.4 («موظف مخزن» and
// «مشرف مخزن») when missing. `RoleGrantPreflightService.grantMissingDefaults`
// only GRANTS to roles that already exist, so the roles are created here first.
// Idempotent: a role with the same name (operator-created or earlier boot) is
// left untouched, including its grants.
import 'package:drift/drift.dart';

import '../core/permissions/role_grant_matrix.dart';
import '../core/utils/uuid_v7.dart';
import '../data/database/database.dart';

const _warehouseRoles = <String, String>{
  kWarehouseClerkRole: 'عدّ واستلام المخزون من تطبيق المخازن',
  kWarehouseSupervisorRole: 'الإشراف على المخزن واعتماد الحركات من تطبيق المخازن',
};

/// Returns the number of roles created (0 on a repeat run).
Future<int> ensureWarehouseRoles(AppDatabase db) async {
  var created = 0;
  for (final entry in _warehouseRoles.entries) {
    final existing = await (db.select(db.roles)
          ..where((r) => r.name.equals(entry.key))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) continue;
    await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: entry.key,
            description: Value(entry.value),
            isSystemRole: const Value(true),
            globalId: Value(UuidV7.generate()),
          ),
          onConflict: DoNothing(target: []),
        );
    created++;
  }
  return created;
}