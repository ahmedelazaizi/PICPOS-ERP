// Pre-flight checks shared by every warehouse document that takes stock out
// (plan §B.2-1 and §B.2-9). Done inside the posting transaction, BEFORE the
// existing stock layer runs, because that layer lets stock go negative when a
// setting says so and silently accepts an empty lot result.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_blind.dart';
import 'wh_http.dart';

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
