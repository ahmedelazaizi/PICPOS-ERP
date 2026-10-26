// Blind count rule (plan ADR-MC3 / W4): while a cycle-count task that covers a
// product is open in a warehouse, a COUNTER must not learn the system quantity
// of that product from ANY endpoint (items, refusal details, ...).
//
// A counter = holds `stock_count_submit` but NOT `stock_adjust_approve`
// (approvers must see the numbers to decide). Every quantity-bearing response
// asks [canSeeQuantity] for each (product, warehouse) it is about to reveal.
import 'package:drift/drift.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import '../../../data/database/wh_mobile_docs_schema.dart';

/// Is a cycle-count task open (pending / in progress) for [productId] in [warehouseId]?
Future<bool> underActiveCount(AppDatabase db, int productId, int warehouseId) async {
  final r = await db.customSelect(
    'SELECT 1 AS x FROM cycle_count_items i '
    'JOIN cycle_count_tasks t ON t.id = i.task_id '
    'JOIN cycle_count_plans p ON p.id = t.plan_id '
    "WHERE i.product_id = ? AND p.warehouse_id = ? AND t.status IN ('pending','in_progress') "
    'AND t.deleted_at IS NULL LIMIT 1',
    variables: [Variable<int>(productId), Variable<int>(warehouseId)],
  ).get();
  return r.isNotEmpty;
}

Future<bool> isBlindCounter(AppDatabase db, int userId) async =>
    await db.userHasPermission(userId, WarehousePermissionCodes.stockCountSubmit) &&
    !await db.userHasPermission(userId, WarehousePermissionCodes.stockAdjustApprove);

/// Has [userId] started or submitted a phone count of an OPEN task that covers
/// [productId] in [warehouseId]? Whoever counts is blind on those items,
/// supervisors and managers included (WH-009): the role alone is not enough.
Future<bool> isCountingItem(AppDatabase db, int userId, int productId, int warehouseId) async {
  await db.ensureWhMobileDocsSchema();
  final r = await db.customSelect(
    'SELECT 1 AS x FROM wh_mobile_docs d '
    'JOIN cycle_count_tasks t ON d.ref_id = CAST(t.id AS TEXT) '
    'JOIN cycle_count_items i ON i.task_id = t.id '
    'JOIN cycle_count_plans p ON p.id = t.plan_id '
    "WHERE d.kind = 'count_submission' AND d.ref_type = 'cycle_count_task' AND d.created_by = ? "
    "AND d.state IN ('draft','submitted') AND i.product_id = ? AND p.warehouse_id = ? "
    "AND t.status IN ('pending','in_progress') AND t.deleted_at IS NULL LIMIT 1",
    variables: [Variable<int>(userId), Variable<int>(productId), Variable<int>(warehouseId)],
  ).get();
  return r.isNotEmpty;
}

/// May [userId] be told the system quantity of [productId] in [warehouseId]?
Future<bool> canSeeQuantity(AppDatabase db, int userId, int productId, int warehouseId) async {
  if (!await db.userHasPermission(userId, 'inventory_view')) return false;
  if (await isCountingItem(db, userId, productId, warehouseId)) return false;
  if (!await isBlindCounter(db, userId)) return true;
  return !await underActiveCount(db, productId, warehouseId);
}
