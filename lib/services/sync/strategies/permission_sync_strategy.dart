// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:picpos_erp/services/sync_event_bus.dart';

class PermissionSyncStrategy extends SyncStrategy {
  PermissionSyncStrategy(super.db);

  @override
  String get tableName => 'permissions';

  @override
  String get apiEndpoint => '/api/permissions';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final perms = json['permissions'] as List;
    if (perms.isEmpty) return;

    // History: the previous implementation wiped `role_permissions` and
    // `permissions` then re-inserted every server row with the server-side
    // id. The wipe was needed because the original RolePermissionSyncStrategy
    // matched by id only — divergent ids between server and client meant
    // mappings would silently drop. That motivation is **obsolete**:
    // RolePermissionSyncStrategy now resolves by `permissionCode` /
    // `roleName` (see role_permission_sync_strategy.dart lines 22-41), so
    // local ids no longer need to match server ids for the join to work.
    //
    // Field-report 2026-05-14 (Feature 054 v134): the wipe-and-reinsert
    // approach left a Tier-0 → Tier-1 window where `role_permissions` was
    // EMPTY between the end of this strategy's commit and the completion
    // of RolePermissionSyncStrategy in Tier 1. Riverpod's
    // `userAllowedScreensProvider` watches `role_permissions` and during
    // that window briefly emitted `allowedIndices=[0]` — the active
    // cashier's NAV momentarily collapsed to the dashboard and any
    // dialog/save in flight at that moment could be dropped. The pattern
    // fires every ~5 min (periodic fullSync) and lined up exactly with
    // the user's "screen refreshes mid-sale" complaint.
    //
    // Fix: upsert `permissions` BY CODE without touching `role_permissions`.
    // Local ids stay stable, no FK cascade is needed, no empty window for
    // watchers to observe.
    await db.transaction(() async {
      final localPerms = await db.select(db.permissions).get();
      final byCode = {for (final p in localPerms) p.code: p};

      for (final p in perms) {
        final code = p['code'] as String;
        final name = p['name'] as String;
        final category = p['category'] as String;
        final existing = byCode[code];

        if (existing == null) {
          // New code → insert. Use the server id if it's free locally;
          // otherwise let SQLite auto-assign (RolePermissionSyncStrategy
          // resolves by code so the actual id doesn't matter for joins).
          final serverId = parseInt(p['id']);
          final idFree = !localPerms.any((lp) => lp.id == serverId);
          await db.into(db.permissions).insert(
            PermissionsCompanion.insert(
              id: idFree ? Value(serverId) : const Value.absent(),
              code: code,
              name: name,
              category: category,
            ),
          );
        } else if (existing.name != name || existing.category != category) {
          // Existing code → patch name/category only (keep local id).
          await (db.update(db.permissions)
                ..where((t) => t.id.equals(existing.id)))
              .write(PermissionsCompanion(
            name: Value(name),
            category: Value(category),
          ));
        }
      }
    });
    db.markTablesUpdated({db.permissions});
    // Bridge: notify Riverpod listeners (PermissionSyncBridge) so the
    // permission caches invalidate immediately.
    SyncEventBus.instance.emit(SyncTablePulled('permissions', perms.length));
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.permissions).insertOnConflictUpdate(record as PermissionsCompanion);
  }
}