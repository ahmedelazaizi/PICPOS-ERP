// Pre-flight checks shared by every warehouse document that takes stock out
// (plan §B.2-1 and §B.2-9). Done inside the posting transaction, BEFORE the
// existing stock layer runs, because that layer lets stock go negative when a
// setting says so and silently accepts an empty lot result.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_blind.dart';
import 'wh_http.dart';

/// WH-006: on PostgreSQL the balance row is locked (`FOR UPDATE`, held to the
/// end of the surrounding transaction) BEFORE it is read, so two concurrent
/// withdrawals queue up and the second one sees the first one's result. On
/// SQLite writers are already serialised.
Future<void> lockBalanceRow(AppDatabase db, int productId, int warehouseId) async {
  if (!db.isPostgres) return;
  await db.customSelect(
    'SELECT id FROM inventory_balances WHERE product_id = ? AND warehouse_id = ? FOR UPDATE',
    variables: [Variable<int>(productId), Variable<int>(warehouseId)],
  ).get();
}

/// Balance of [productId] in [warehouseId] (0 when no row).
Future<double> availableQty(AppDatabase db, int productId, int warehouseId) async {
  final b = await (db.select(db.inventoryBalances)
        ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(warehouseId)))
      .getSingleOrNull();
  return b?.quantity ?? 0;
}

/// Refuses `stock_changed` when the balance cannot cover [qty], whatever
/// `enable_negative_sales` or the product flag say. The available quantity
/// travels in the refusal only to [viewerId] when [canSeeQuantity] (needs
/// inventory_view, and never to a blind counter of that product).
Future<void> requireCoveredStock(
  AppDatabase db, {
  required int productId,
  required int warehouseId,
  required double qty,
  required int viewerId,
}) async {
  await lockBalanceRow(db, productId, warehouseId);
  final available = await availableQty(db, productId, warehouseId);
  if (available + 1e-9 < qty) {
    throw WhError('stock_changed', 409, {
      'productId': productId,
      if (await canSeeQuantity(db, viewerId, productId, warehouseId)) 'available': fmtQty(available),
    });
  }
}

/// Expiry-tracked goods may only leave from lots that have not expired
/// (`batch_expired`), independent of the bins / block-issue settings.
Future<void> requireValidBatchCoverage(
  AppDatabase db, {
  required int productId,
  required int warehouseId,
  required double qty,
}) async {
  final product = await db.getProductById(productId);
  if (product == null || !product.trackExpiry) return;
  final now = DateTime.now();
  final lots = await db.getBatchesForIssue(productId, warehouseId: warehouseId);
  final valid = lots.where((l) => l.expiryDate.isAfter(now)).fold<double>(0, (s, l) => s + l.quantity);
  if (valid + 1e-9 < qty) throw WhError('batch_expired', 409, {'productId': productId});
}

/// Atomically adds [qty] to a PO line's received_quantity iff the result stays
/// within [allowed] (WH-006). False = refused (excess or lost the race).
Future<bool> addReceivedQuantity(AppDatabase db, int poItemId, double qty, double allowed) async {
  // WH-021: the raw UPDATE must also STAMP the row and its order (last_modified_at,
  // row_version) - the clients' delta pull selects changed rows by that stamp, so
  // without it a client that already holds the order never learns the receipt.
  // The stamp must be STRICTLY greater than the previous one: the delta pull asks
  // `last_modified_at > since`, and a receipt in the same second as the previous
  // change would otherwise be skipped for ever.
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const stamp = 'last_modified_at = CASE WHEN last_modified_at IS NULL OR last_modified_at < ? '
      'THEN ? ELSE last_modified_at + 1 END, row_version = row_version + 1';
  final n = await db.customUpdate(
    'UPDATE purchase_order_items SET received_quantity = received_quantity + ?, $stamp '
    'WHERE id = ? AND received_quantity + ? <= ?',
    variables: [
      Variable<double>(qty), Variable<int>(now), Variable<int>(now),
      Variable<int>(poItemId), Variable<double>(qty), Variable<double>(allowed + 1e-9),
    ],
    updates: {db.purchaseOrderItems},
  );
  if (n == 1) {
    await db.customUpdate(
      'UPDATE purchase_orders SET $stamp '
      'WHERE id = (SELECT order_id FROM purchase_order_items WHERE id = ?)',
      variables: [Variable<int>(now), Variable<int>(now), Variable<int>(poItemId)],
      updates: {db.purchaseOrders},
    );
  }
  return n == 1;
}
