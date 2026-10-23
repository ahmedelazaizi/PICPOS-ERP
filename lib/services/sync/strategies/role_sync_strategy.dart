// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:picpos_erp/services/sync_event_bus.dart';

class RoleSyncStrategy extends SyncStrategy {
  RoleSyncStrategy(super.db);

  @override
  String get tableName => 'roles';

  @override
  String get apiEndpoint => '/api/roles';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final roles = json['roles'] as List;
    for (final r in roles) {
      await db.into(db.roles).insertOnConflictUpdate(
        RolesCompanion(
          id: Value(parseInt(r['id'])),
          name: Value(r['name'] as String),
          description: Value(r['description'] as String?),
          isSystemRole: Value(parseBool(r['isSystemRole'], false)),
        ),
      );
    }
    // Force UI refresh after sync
    if (roles.isNotEmpty) {
      db.markTablesUpdated({db.roles});
      // Bridge: notify Riverpod listeners (PermissionSyncBridge) so the
      // permission caches invalidate immediately if a role rename or
      // isSystemRole flag affects the admin bypass.
      SyncEventBus.instance.emit(SyncTablePulled('roles', roles.length));
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.roles).insertOnConflictUpdate(record as RolesCompanion);
  }
}