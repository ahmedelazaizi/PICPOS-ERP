// ADR-W4 (plan 2026-10-23): which warehouses a warehouse-app request may see.
//
//   allowed = warehouses of the DEVICE's branch (active, not deleted)
//           ∩ the signed-in user's warehouse access (null = unrestricted)
//
// and the user must be allowed into that branch at all. Fail-closed: a
// warehouse with no branch, a user with no warehouse rows (and no full
// access) or a branch the user cannot enter yields an empty scope. Checked on
// the server for EVERY /api/m1/wh/* call; the app's UI is not a boundary.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';

class WhScope {
  const WhScope({required this.branchId, required this.warehouses});
  final int branchId;
  final List<Warehouse> warehouses;

  Set<int> get warehouseIds => {for (final w in warehouses) w.id};
  bool allows(int warehouseId) => warehouseIds.contains(warehouseId);
}

Future<WhScope> resolveWhScope(
  AppDatabase db, {
  required int userId,
  required int deviceBranchId,
}) async {
  final empty = WhScope(branchId: deviceBranchId, warehouses: const []);
  if (!await db.isFullBranchAccessUser(userId)) {
    final branches = await db.getUserAccessibleBranchIds(userId);
    if (!branches.contains(deviceBranchId)) return empty;
  }
  final userScope = await db.getWarehouseScopeForUser(userId); // null = all
  final rows = await (db.select(db.warehouses)
        ..where((w) =>
            w.branchId.equals(deviceBranchId) &
            w.isActive.equals(true) &
            w.deletedAt.isNull())
        ..orderBy([(w) => OrderingTerm.asc(w.id)]))
      .get();
  return WhScope(
    branchId: deviceBranchId,
    warehouses: [
      for (final w in rows)
        if (userScope == null || userScope.contains(w.id)) w,
    ],
  );
}