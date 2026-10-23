// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// Phase 6 follow-up — symmetric to [UserBranchAccessSyncStrategy].
/// Without this strategy, per-user warehouse restrictions set on the
/// server never reach paired clients. A user paired to branch X but
/// restricted to "POS warehouse" inside X would still see (and could
/// post invoices against) other warehouses in X — the silent
/// misposting risk the user flagged.
///
/// **Race-fix (2026-05-03)** — same fix as `UserBranchAccessSyncStrategy`:
/// avoid the blanket `DELETE` that races with concurrent local writes by
/// using UPSERT and a delta-based deletion pass. See that file for the
/// full rationale.
class UserWarehouseAccessSyncStrategy extends SyncStrategy {
  UserWarehouseAccessSyncStrategy(super.db);

  @override
  String get tableName => 'user_warehouse_access';

  @override
  String get apiEndpoint => '/api/user-warehouse-access';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final accesses = json['user_warehouse_access'] as List;

    final serverKeys = <String>{};
    final serverRows = <UserWarehouseAccessCompanion>[];
    for (final a in accesses) {
      final userId = parseInt(a['userId']);
      final warehouseId = parseInt(a['warehouseId']);
      serverKeys.add('${userId}_$warehouseId');
      serverRows.add(UserWarehouseAccessCompanion(
        userId: Value(userId),
        warehouseId: Value(warehouseId),
      ));
    }

    await db.transaction(() async {
      // UPSERT every row in the server snapshot — never wipes locals.
      for (final row in serverRows) {
        await db.into(db.userWarehouseAccess).insertOnConflictUpdate(row);
      }

      // Mirror server-side deletions by computing a diff and removing
      // rows the snapshot no longer contains.
      final localRows = await db.select(db.userWarehouseAccess).get();
      for (final local in localRows) {
        final key = '${local.userId}_${local.warehouseId}';
        if (!serverKeys.contains(key)) {
          await (db.delete(db.userWarehouseAccess)
                ..where((a) =>
                    a.userId.equals(local.userId) &
                    a.warehouseId.equals(local.warehouseId)))
              .go();
        }
      }
    });

    if (accesses.isNotEmpty) {
      db.markTablesUpdated({db.userWarehouseAccess});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Full snapshot only — table is tiny.
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.userWarehouseAccess)
        .insertOnConflictUpdate(record as UserWarehouseAccessCompanion);
  }
}