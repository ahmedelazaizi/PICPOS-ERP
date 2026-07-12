// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:ural_erp/services/sync_event_bus.dart';

class RolePermissionSyncStrategy extends SyncStrategy {
  RolePermissionSyncStrategy(super.db);

  @override
  String get tableName => 'role_permissions';

  @override
  String get apiEndpoint => '/api/role_permissions';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final rps = json['role_permissions'] as List;
    debugPrint('[RolePermSync] received ${rps.length} rows from server');

    // ──────────────────────────────────────────────────────────────────────
    // CRITICAL: Resolve incoming rows by CODE, not by id.
    //
    // The numeric ids in `permissions` and `roles` are auto-increment and
    // routinely diverge between server and client (different seeding order,
    // ON CONFLICT DO NOTHING races during startup, phase-additions of new
    // permission codes that the older node already had). The CODES, however,
    // are universal — they come from the same `PermissionCodes.masterList`.
    //
    // The previous implementation matched on id only, so a server row like
    //   {roleId: 54, permissionId: 10 (pos_save on server)}
    // arriving at a client where pos_save has local id=15 was silently
    // dropped (existingPermIds.contains(10) returned false). The cashier
    // then opened POS, the cache showed only 25 codes (no pos_save), and
    // the manager-override dialog fired even though the server had granted
    // pos_save. The operator's exact symptom.
    //
    // We now build local lookup maps by code/name and use those to translate
    // each server row into local ids. Falling back to raw id keeps backward
    // compatibility with older servers that don't yet emit codes.
    // ──────────────────────────────────────────────────────────────────────
    final localPerms = await db.select(db.permissions).get();
    final permIdByCode = <String, int>{
      for (final p in localPerms) p.code: p.id,
    };
    final permIdSet = localPerms.map((p) => p.id).toSet();

    final localRoles = await db.select(db.roles).get();
    final roleIdByName = <String, int>{
      for (final r in localRoles) r.name: r.id,
    };
    final roleIdSet = localRoles.map((r) => r.id).toSet();

    debugPrint('[RolePermSync] local permissions=${permIdSet.length}, '
        'roles=${roleIdSet.length}');

    // Feature 006 #7: switched from blanket DELETE+INSERT to UPSERT+diff-delete
    // (mirrors user_branch_access_sync_strategy). The previous implementation
    // wiped the entire role_permissions table inside the transaction; a local
    // grant happening between an admin's "Save" and the next sync pull could
    // be silently overwritten when the server snapshot didn't yet include it.
    // Composite PK (roleId, permissionId) makes insertOnConflictUpdate idempotent
    // and lets us diff server keys against local keys for deletion semantics.
    int upserted = 0;
    int skipped = 0;
    int resolvedByCode = 0;
    final serverKeys = <String>{};
    final serverRows = <RolePermissionsCompanion>[];

    for (final rp in rps) {
      final serverRoleId = parseInt(rp['roleId']);
      final serverPermId = parseInt(rp['permissionId']);
      final permCode = rp['permissionCode'] as String?;
      final roleName = rp['roleName'] as String?;

      int? localPermId;
      if (permCode != null && permIdByCode.containsKey(permCode)) {
        localPermId = permIdByCode[permCode];
        if (localPermId != serverPermId) resolvedByCode++;
      } else if (permIdSet.contains(serverPermId)) {
        localPermId = serverPermId;
      }

      int? localRoleId;
      if (roleName != null && roleIdByName.containsKey(roleName)) {
        localRoleId = roleIdByName[roleName];
      } else if (roleIdSet.contains(serverRoleId)) {
        localRoleId = serverRoleId;
      }

      if (localPermId == null || localRoleId == null) {
        skipped++;
        if (kDebugMode) {
          debugPrint('[RolePermSync] skipped: role=$serverRoleId('
              '${roleName ?? "?"}) perm=$serverPermId(${permCode ?? "?"}) — '
              'localRoleId=$localRoleId localPermId=$localPermId');
        }
        continue;
      }

      serverKeys.add('${localRoleId}_$localPermId');
      serverRows.add(RolePermissionsCompanion(
        roleId: Value(localRoleId),
        permissionId: Value(localPermId),
      ));
    }

    int diffDeleted = 0;
    await db.transaction(() async {
      // Step 1: UPSERT every resolved server row (no race window — local
      // rows that haven't reached the server yet survive the pull).
      for (final row in serverRows) {
        try {
          await db.into(db.rolePermissions).insertOnConflictUpdate(row);
          upserted++;
        } catch (e) {
          debugPrint('[RolePermSync] upsert failed '
              'role=${row.roleId.value} perm=${row.permissionId.value}: $e');
          skipped++;
        }
      }

      // Step 2: diff-delete — remove only rows the server clearly dropped.
      final localRows = await db.select(db.rolePermissions).get();
      for (final local in localRows) {
        final key = '${local.roleId}_${local.permissionId}';
        if (!serverKeys.contains(key)) {
          await (db.delete(db.rolePermissions)
                ..where((rp) =>
                    rp.roleId.equals(local.roleId) &
                    rp.permissionId.equals(local.permissionId)))
              .go();
          diffDeleted++;
        }
      }
    });
    debugPrint('[RolePermSync] upserted=$upserted skipped=$skipped '
        'diffDeleted=$diffDeleted resolvedByCode=$resolvedByCode');
    final inserted = upserted; // keep downstream signal name unchanged
    if (rps.isNotEmpty) {
      db.markTablesUpdated({db.rolePermissions});
      // Bridge: notify Riverpod listeners (PermissionSyncBridge) so the
      // currentUserPermissionsProvider / userAllowedScreensProvider /
      // userNavItemsProvider caches invalidate immediately and the UI reflects
      // the new permissions without requiring a manual sync or app restart.
      SyncEventBus.instance.emit(SyncTablePulled('role_permissions', inserted));
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    // Upsert not directly applicable for many-to-many join table usually
    await db.into(db.rolePermissions).insert(record as RolePermissionsCompanion);
  }
}