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

import '../../../core/utils/financial_utils.dart';
import '../../../data/database/database.dart';
import 'wh_constants.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_locations.dart';

class WhReceiptPosting {
  WhReceiptPosting(this.db, this.store);
  final AppDatabase db;
  final WhDocStore store;

  Future<Map<String, Object?>> convert(WhDoc doc, int userId, {int? expectedVersion}) async {
    store.requireVersion(doc, expectedVersion); // WH-019
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
    // WH-003: the invoice carries the PO line's discount and tax in the same
    // proportion as the accepted quantity (a half-received line takes half of
    // its discount and half of its tax), and the PO's cost centre.
    double share(PurchaseOrderItem i, double qty) => i.quantity <= 0 ? 0 : qty / i.quantity;
    final items = <PurchaseInvoiceItemsCompanion>[
      for (final g in grouped.values)
        () {
          final pi = poItems[g.first.poItemId]!;
          final f = share(pi, g.qty);
          return PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: g.first.productId,
            quantity: g.qty,
            unitCost: pi.unitCost,
            total: g.qty * pi.unitCost,
            discount: Value(FinancialUtils.round(pi.discount * f)),
            taxRate: Value(pi.taxRate),
            taxAmount: Value(FinancialUtils.round(pi.taxAmount * f)),
            batchNumber: Value(g.first.batchNumber),
            expiryDate: Value(g.first.expiry),
          );
        }(),
    ];
    // Header discount of the order, in proportion to the gross invoiced now.
    final poGross = poItems.values.fold<double>(0, (s, i) => s + i.quantity * i.unitCost);
    final invGross = grouped.values.fold<double>(0, (s, g) => s + g.qty * poItems[g.first.poItemId]!.unitCost);
    final headerDiscount = poGross <= 0 ? 0.0 : FinancialUtils.round(po.discount * invGross / poGross);

    final complete = poItems.values.every((i) => i.receivedQuantity + 1e-9 >= i.quantity);
    final others = await store.list(kind: 'po_receipt', states: ['draft', 'submitted'], refType: 'purchase_order', refId: doc.refId);
    final stillWaiting = others.any((d) => d.id != doc.id);

    // One transaction: invoice, PO stamp, bin moves and the document state move
    // together or not at all (a failure may not leave a posted invoice behind a
    // receipt that is still `submitted`, which a retry would post twice).
    return db.transaction(() async {
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: po.supplierId,
      warehouseId: po.warehouseId,
      items: items,
      paid: 0,
      paymentMethod: 'credit',
      notes: '${WhConstants.receiptJournalNote} ${doc.gid}',
      userId: userId,
      // `discount` is the document TOTAL (it must not be below the sum of the
      // line discounts), so the line discounts are part of it.
      discount: FinancialUtils.round(headerDiscount +
          [for (final i in items) i.discount.value].fold<double>(0, (s, d) => s + d)),
      costCenterId: po.costCenterId,
    );
    // The PO is consumed through the receipt path only (WH-001), never by
    // handing `sourceOrderId` to the legacy full-quantity guard.
    if (complete && !stillWaiting) await db.markPurchaseOrderConvertedByReceipts(poId, invoiceId);

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
    });
  }
}
