// W3 (plan 2026-10-23): stock vouchers - in / out / damage - created on the
// phone with a mandatory reason, posted ONLY after an approval by a different
// user, through the existing `adjustStock` (type `adjustment` / `damage`, which
// the stock layer already journals). Stock never goes negative: the balance is
// re-read inside the posting transaction and a shortfall is `409 stock_changed`
// whatever `enable_negative_sales` says. Expiry-tracked goods leave through
// the lot ledger (fail closed on expired lots) and enter with batch + expiry.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_stock_guard.dart';

const kVoucherTypes = {'in', 'out', 'damage'};

class WhVoucherService {
  WhVoucherService(this.db, this.store);
  final AppDatabase db;
  final WhDocStore store;

  Future<WhDoc> create(WhCtx ctx, Map<String, Object?> body) async {
    final gid = '${body['globalId'] ?? ''}'.trim();
    final type = '${body['type'] ?? ''}';
    final wh = (body['warehouseId'] as num?)?.toInt();
    final reason = '${body['reason'] ?? ''}'.trim();
    final lines = body['lines'];
    if (gid.length < 8 || wh == null || lines is! List || lines.isEmpty || !kVoucherTypes.contains(type)) {
      throw WhError('bad_request', 400);
    }
    if (reason.isEmpty) throw WhError('reason_required', 422);
    if (!ctx.scope.allows(wh)) throw WhError('warehouse_forbidden', 403);
    final doc = await store.create(
      gid: gid, kind: 'voucher', state: 'pending', warehouseId: wh, createdBy: ctx.userId,
      deviceId: ctx.deviceId, reason: reason, data: {'type': type},
    );
    for (final raw in lines) {
      final l = (raw as Map).cast<String, Object?>();
      final pid = (l['productId'] as num?)?.toInt();
      final lineGid = '${l['lineGlobalId'] ?? ''}'.trim();
      if (pid == null || lineGid.length < 8) throw WhError('bad_request', 400);
      final product = await db.getProductById(pid);
      if (product == null) throw WhError('product_not_found', 422);
      final batch = (l['batchNumber'] as String?)?.trim();
      final expiry = l['expiryDate'] == null ? null : DateTime.tryParse('${l['expiryDate']}');
      if (type == 'in' && product.trackExpiry && (batch == null || batch.isEmpty || expiry == null)) {
        throw WhError('batch_required', 422, {'productId': pid});
      }
      await store.addLine(doc, lineGid: lineGid, productId: pid, qty: parseQty(l['quantity']),
          batchNumber: batch, expiry: expiry, counterUserId: ctx.userId);
    }
    return doc;
  }

  Future<WhDoc> reject(WhDoc doc, int approver, {int? expectedVersion}) {
    requireDistinct(approver, [doc.createdBy]);
    return store.transition(doc, 'reject', expectedVersion: expectedVersion, approvedBy: approver);
  }

  Future<WhDoc> approve(WhDoc doc, int approver, {required int viewerId, int? expectedVersion}) async {
    requireDistinct(approver, [doc.createdBy]);
    if (doc.state != 'pending') throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'approve'});
    final type = doc.data['type'] as String;
    for (final l in await store.lines(doc.id)) {
      final product = (await db.getProductById(l.productId))!;
      if (type == 'in') {
        await db.adjustStock(
          productId: l.productId, warehouseId: doc.warehouseId, quantity: l.qty, type: 'adjustment',
          referenceType: 'wh_voucher', referenceId: doc.id, userId: approver, unitCost: l.unitCost ?? product.costPrice,
          notes: 'Voucher in (${doc.gid}): ${doc.reason}',
        );
        if (l.batchNumber != null && l.expiry != null) {
          await db.insertBatch(ProductBatchesCompanion.insert(
            productId: l.productId, warehouseId: doc.warehouseId, batchNumber: l.batchNumber!,
            expiryDate: l.expiry!, quantity: Value(l.qty), initialQuantity: Value(l.qty),
            unitCost: Value(l.unitCost ?? product.costPrice),
          ));
        }
        continue;
      }
      final bal = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(l.productId) & b.warehouseId.equals(doc.warehouseId)))
          .getSingleOrNull();
      await requireCoveredStock(db,
          productId: l.productId, warehouseId: doc.warehouseId, qty: l.qty, viewerId: viewerId);
      await requireValidBatchCoverage(db, productId: l.productId, warehouseId: doc.warehouseId, qty: l.qty);
      if (product.trackExpiry) {
        try {
          await db.consumeBatchesForIssue(productId: l.productId, warehouseId: doc.warehouseId, quantity: l.qty);
        } on Object {
          throw WhError('batch_expired', 409, {'productId': l.productId});
        }
      }
      await db.adjustStock(
        productId: l.productId, warehouseId: doc.warehouseId, quantity: -l.qty,
        type: type == 'damage' ? 'damage' : 'adjustment', referenceType: 'wh_voucher', referenceId: doc.id,
        userId: approver, unitCost: bal != null && bal.averageCost > 0 ? bal.averageCost : product.costPrice,
        notes: 'Voucher $type (${doc.gid}): ${doc.reason}',
      );
    }
    return store.transition(doc, 'approve', expectedVersion: expectedVersion, approvedBy: approver);
  }
}
