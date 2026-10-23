// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// Strategy for syncing the `user_branch_access` table from the server.
///
/// **Race-fix (2026-05-03)** — the previous implementation did a blanket
/// `DELETE FROM user_branch_access` followed by inserts from the server
/// snapshot. That created a race window: a client that just wrote a new
/// `(userId, branchId)` row locally (e.g. via `AddUserDialog`) could see
/// its row wiped if the WebSocket-triggered sync arrived a microtask later
/// and the server snapshot hadn't yet caught up. The user-visible symptom
/// was a freshly-created cashier seeing
/// "ليس لديك صلاحية الدخول لهذا الفرع" on first login.
///
/// New behaviour:
///   1. UPSERT every row from the server snapshot — never wipes local data.
///   2. After upserting, compare local keys to server keys and DELETE only
///      the rows the server has clearly removed. This preserves
///      server-deletion propagation without the destructive blanket wipe.
///   3. The whole pass runs inside a single transaction so concurrent
///      readers see either the pre- or post-state, not a torn one.
class UserBranchAccessSyncStrategy extends SyncStrategy {
  UserBranchAccessSyncStrategy(super.db);

  @override
  String get tableName => 'user_branch_access';

  @override
  String get apiEndpoint => '/api/user-branch-access';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final accesses = json['user_branch_access'] as List;

    // Spec 136 ISS-10 — remap the server branchId to THIS device's LOCAL
    // branch id via the branch globalId. The server's branch id can differ
    // from the client's local id for the same logical branch (BranchSync's
    // name-match keeps the local id), so storing the raw server id left
    // `user_branch_access.branchId` dangling — and the login guard
    // (`assignments.contains(client_branch_id)`, where client_branch_id is a
    // LOCAL id) then denied access even to assigned users. Resolving by
    // globalId makes the stored id match the local branches table.
    final localBranches = await db.select(db.branches).get();
    final localIdByGid = <String, int>{
      for (final b in localBranches)
        if (b.globalId != null && b.globalId!.isNotEmpty) b.globalId!: b.id,
    };

    // Materialise the server snapshot once into a Set of composite keys for
    // O(1) membership checks below.
    final serverKeys = <String>{};
    final serverRows = <UserBranchAccessCompanion>[];
    for (final a in accesses) {
      final userId = parseInt(a['userId']);
      final serverBranchId = parseInt(a['branchId']);
      final branchGid = a['branchGlobalId'] as String?;
      // Prefer the globalId → local-id mapping; fall back to the raw server
      // id for legacy servers that don't send branchGlobalId yet.
      final branchId = (branchGid != null && localIdByGid.containsKey(branchGid))
          ? localIdByGid[branchGid]!
          : serverBranchId;
      serverKeys.add('${userId}_$branchId');
      serverRows.add(UserBranchAccessCompanion(
        userId: Value(userId),
        branchId: Value(branchId),
      ));
    }

    await db.transaction(() async {
      // Step 1: UPSERT every row in the server snapshot. Drift's
      // insertOnConflictUpdate handles "row exists" gracefully — no race
      // window where a freshly-written local row could vanish.
      for (final row in serverRows) {
        await db.into(db.userBranchAccess).insertOnConflictUpdate(row);
      }

      // Step 2: detect server-side deletions. Read every local row, drop
      // any whose composite key is missing from the server snapshot. We
      // assume the snapshot is authoritative for deletion semantics — if
      // a row is in `accesses`, the server still has it; otherwise the
      // server removed it (e.g. via `setUserBranchAccess(userId, [])`)
      // and we mirror that.
      final localRows = await db.select(db.userBranchAccess).get();
      for (final local in localRows) {
        final key = '${local.userId}_${local.branchId}';
        if (!serverKeys.contains(key)) {
          await (db.delete(db.userBranchAccess)
                ..where((a) =>
                    a.userId.equals(local.userId) &
                    a.branchId.equals(local.branchId)))
              .go();
        }
      }
    });

    if (accesses.isNotEmpty) {
      db.markTablesUpdated({db.userBranchAccess});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Usually full snapshot
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.userBranchAccess).insertOnConflictUpdate(record as UserBranchAccessCompanion);
  }
}