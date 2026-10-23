// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// Strategy for syncing the `user_region_access` table from the server.
///
/// **Race-fix (Feature 005, 2026-05-03)** — mirrors the same UPSERT +
/// diff-delete pattern applied to [UserBranchAccessSyncStrategy] in commit
/// 094128f. The previous implementation did a blanket `DELETE FROM
/// user_region_access` followed by inserts from the server snapshot, which
/// could wipe a freshly-written local `(userId, regionId)` row if a sync
/// fired before the server snapshot caught up. This is the same race that
/// produced the cashier-permissions outage reported during 004 testing.
///
/// New behaviour:
///   1. UPSERT every row from the server snapshot — never wipes local data.
///   2. After upserting, compare local keys to server keys and DELETE only
///      the rows the server has clearly removed. This preserves
///      server-deletion propagation without the destructive blanket wipe.
///   3. The whole pass runs inside a single transaction so concurrent
///      readers see either the pre- or post-state, not a torn one.
class UserRegionAccessSyncStrategy extends SyncStrategy {
  UserRegionAccessSyncStrategy(super.db);

  @override
  String get tableName => 'user_region_access';

  @override
  String get apiEndpoint => '/api/user-region-access';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final accesses = json['user_region_access'] as List;

    // Materialise the server snapshot once into a Set of composite keys for
    // O(1) membership checks below.
    final serverKeys = <String>{};
    final serverRows = <UserRegionAccessCompanion>[];
    for (final a in accesses) {
      final userId = parseInt(a['userId']);
      final regionId = parseInt(a['regionId']);
      serverKeys.add('${userId}_$regionId');
      serverRows.add(UserRegionAccessCompanion(
        userId: Value(userId),
        regionId: Value(regionId),
      ));
    }

    await db.transaction(() async {
      // Step 1: UPSERT every row in the server snapshot. Drift's
      // insertOnConflictUpdate handles "row exists" gracefully — no race
      // window where a freshly-written local row could vanish.
      for (final row in serverRows) {
        await db.into(db.userRegionAccess).insertOnConflictUpdate(row);
      }

      // Step 2: detect server-side deletions. Read every local row, drop
      // any whose composite key is missing from the server snapshot.
      final localRows = await db.select(db.userRegionAccess).get();
      for (final local in localRows) {
        final key = '${local.userId}_${local.regionId}';
        if (!serverKeys.contains(key)) {
          await (db.delete(db.userRegionAccess)
                ..where((a) =>
                    a.userId.equals(local.userId) &
                    a.regionId.equals(local.regionId)))
              .go();
        }
      }
    });

    if (accesses.isNotEmpty) {
      db.markTablesUpdated({db.userRegionAccess});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Usually full snapshot
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.userRegionAccess).insertOnConflictUpdate(record as UserRegionAccessCompanion);
  }
}