// Accountant step of W2 (plan §B.2-3, R-A): turn a SUBMITTED phone receipt into
// the purchase invoice through the existing pipeline, then put the goods in
// the scanned bins (ADR-W6: post, then put-away; bin moves post no ledger).
//
//   * only `ok` lines are posted - damaged goods never enter good stock;
//   * the invoice carries the real user (not `convertPOToInvoice`'s "first
//     user") and each line's batch/expiry;
//   * the PO is stamped converted ONLY when the order is fully received and no
//     other receipt of it is still waiting; otherwise it stays open.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_locations.dart';

class WhReceiptPosting {
  WhReceiptPosting(this.db, this.store);
  final AppDatabase db;
  final WhDocStore store;

  Future<Map<String, Object?>> convert(WhDoc doc, int userId) async {
    if (doc.state != 'submitted') {
      throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'convert'});
    }
    final poId = int.parse(doc.refId!);
    final po = await db.getPurchaseOrderById(poId);
    if (po == null) throw WhError('po_not_found', 404);
    if (po.convertedToInvoiceId != null) throw WhError('po_not_receivable', 409);
    final poItems = {for (final i in await db.getPurchaseOrderItems(poId)) i.id: i};
    final ok = [for (final l in await store.lines(doc.id)) if (l.condition == 'ok') l];
    if (ok.isEmpty) throw WhError('nothing_to_post', 409);

    // One invoice row per (PO item, batch, expiry).
    final grouped = <String, ({WhLine first, double qty})>{};
    for (final l in ok) {
      final k = '${l.poItemId}|${l.batchNumber}|${l.expiry?.millisecondsSinceEpoch}';
      final g = grouped[k];
      grouped[k] = (first: g?.first ?? l, qty: (g?.qty ?? 0) + l.qty);
    }
    final items = <PurchaseInvoiceItemsCompanion>[
      for (final g in grouped.values)
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: g.first.productId,
          quantity: g.qty,
          unitCost: poItems[g.first.poItemId]!.unitCost,
          total: g.qty * poItems[g.first.poItemId]!.unitCost,
          batchNumber: Value(g.first.batchNumber),
          expiryDate: Value(g.first.expiry),
        ),
    ];

    final complete = poItems.values.every((i) => i.receivedQuantity + 1e-9 >= i.quantity);
    final others = await store.list(kind: 'po_receipt', states: ['draft', 'submitted'], refType: 'purchase_order', refId: doc.refId);
    final stillWaiting = others.any((d) => d.id != doc.id);

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: po.supplierId,
      warehouseId: po.warehouseId,
      items: items,
      paid: 0,
      paymentMethod: 'credit',
      notes: 'استلام من تطبيق المخازن ${doc.gid}',
      userId: userId,
      sourceOrderId: complete && !stillWaiting ? poId : null,
    );

    if (await db.getSettingValue('warehouse_bins_enabled') == 'true') {
      final home = await defaultLocationId(db, po.warehouseId);
      for (final l in ok) {
        if (l.locationId == null || l.locationId == home || home == null) continue;
        int? batchId;
        if (l.batchNumber != null) {
          final b = await (db.select(db.productBatches)
                ..where((x) =>
                    x.purchaseInvoiceId.equals(invoiceId) &
                    x.productId.equals(l.productId) &
                    x.batchNumber.equals(l.batchNumber!))
                ..limit(1))
              .getSingleOrNull();
          batchId = b?.id;
        }
        await db.moveStockBetweenBins(
          fromLocationId: home, toLocationId: l.locationId!, productId: l.productId, quantity: l.qty, batchId: batchId,
        );
      }
    }

    final posted = await store.transition(doc, 'convert',
        approvedBy: userId, postedRefType: 'purchase_invoice', postedRefId: '$invoiceId');
    return {'receipt': await store.toJson(posted), 'invoiceId': invoiceId, 'orderClosed': complete && !stillWaiting};
  }
}
