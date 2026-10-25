// W2 (plan 2026-10-23): receive goods against purchase orders from the phone.
//
//   GET  /api/m1/wh/po?warehouse=&status=open     open POs in scope (no cost)
//   GET  /api/m1/wh/po/<ref>                      one PO with ordered/received
//   POST /api/m1/wh/po/<ref>/receipts             create / append a DRAFT receipt
//   POST /api/m1/wh/receipts/<gid>/submit         draft -> submitted (+received_quantity)
//   GET  /api/m1/wh/receipts?state=               receipts in scope
//   GET  /api/m1/wh/locations/by-barcode/<code>   bin lookup (BIN-...)
//   POST /api/m1/wh/receipts/<gid>/convert        accountant: receipt -> purchase invoice
//
// R-A (plan §B.2-3): a receipt moves NO stock and posts NO ledger entry. Only
// `convert` (permission `purchases_create`) does, through the existing
// `createPurchaseInvoice`, with the accepted quantities, batch and expiry.
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_locations.dart';
import 'wh_receipt_posting.dart';

const _receivable = ['sent', 'confirmed'];

class WhReceiptApi {
  WhReceiptApi(this.db) : _http = WhHttp(db), store = WhDocStore(db);
  final AppDatabase db;
  final WhHttp _http;
  final WhDocStore store;

  static const _receive = WarehousePermissionCodes.goodsReceiptMobile;

  Future<PurchaseOrderData> _po(String ref) async {
    final id = int.tryParse(ref);
    final po = await (db.select(db.purchaseOrders)
          ..where((p) => id == null ? p.globalId.equals(ref) : (p.id.equals(id) | p.globalId.equals(ref)))
          ..limit(1))
        .getSingleOrNull();
    return po ?? (throw WhError('po_not_found', 404));
  }

  Future<Map<String, Object?>> _poJson(PurchaseOrderData po) async {
    final items = await db.getPurchaseOrderItems(po.id);
    final products = await db.getProductsByIds([for (final i in items) i.productId]);
    return {
      'ref': po.globalId ?? '${po.id}',
      'id': po.id,
      'orderNumber': po.orderNumber,
      'status': po.status,
      'warehouseId': po.warehouseId,
      'items': [
        for (final i in items)
          {
            'itemId': i.id,
            'productId': i.productId,
            'name': products[i.productId]?.name,
            'barcode': products[i.productId]?.barcode,
            'trackExpiry': products[i.productId]?.trackExpiry ?? false,
            'ordered': fmtQty(i.quantity),
            'received': fmtQty(i.receivedQuantity),
          },
      ],
    };
  }

  void _requireOpen(PurchaseOrderData po, WhCtx ctx) {
    if (!ctx.scope.allows(po.warehouseId)) throw WhError('warehouse_forbidden', 403);
    if (po.convertedToInvoiceId != null || !_receivable.contains(po.status)) {
      throw WhError('po_not_receivable', 409, {'status': po.status});
    }
  }

  Future<Response> listPo(Request request) => _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, _receive], (ctx) async {
        final q = request.requestedUri.queryParameters;
        final wh = int.tryParse(q['warehouse'] ?? '');
        if (wh != null && !ctx.scope.allows(wh)) throw WhError('warehouse_forbidden', 403);
        final ids = wh != null ? [wh] : ctx.scope.warehouseIds.toList();
        final rows = ids.isEmpty
            ? <PurchaseOrderData>[]
            : await (db.select(db.purchaseOrders)
                  ..where((p) =>
                      p.warehouseId.isIn(ids) &
                      p.status.isIn(_receivable) &
                      p.convertedToInvoiceId.isNull() &
                      p.deletedAt.isNull())
                  ..orderBy([(p) => OrderingTerm.desc(p.id)])
                  ..limit(100))
                .get();
        return WhHttp.json({'orders': [for (final po in rows) await _poJson(po)]});
      });

  Future<Response> getPo(Request request, String ref) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, _receive], (ctx) async {
        final po = await _po(ref);
        if (!ctx.scope.allows(po.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return WhHttp.json(await _poJson(po));
      });

  Future<Response> createOrAppend(Request request, String ref) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, _receive], (ctx) async {
        final body = await WhHttp.body(request);
        final rawLines = body['lines'];
        final docGid = '${body['globalId'] ?? ''}'.trim();
        if (docGid.length < 8 || rawLines is! List || rawLines.isEmpty) throw WhError('bad_request', 400);
        final out = await store.command(ctx, action: 'receipt_lines', body: {'ref': ref, ...body}, effect: () async {
          final po = await _po(ref);
          _requireOpen(po, ctx);
          var doc = await store.byGid(docGid);
          if (doc == null) {
            doc = await store.create(
              gid: docGid, kind: 'po_receipt', state: 'draft', warehouseId: po.warehouseId,
              createdBy: ctx.userId, deviceId: ctx.deviceId, refType: 'purchase_order', refId: '${po.id}',
              reason: body['note'] as String?,
            );
          } else if (doc.kind != 'po_receipt' || doc.refId != '${po.id}' || doc.createdBy != ctx.userId) {
            throw WhError('doc_mismatch', 409);
          } else if (doc.state != 'draft') {
            throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'append'});
          }
          final items = {for (final i in await db.getPurchaseOrderItems(po.id)) i.productId: i};
          final products = await db.getProductsByIds(items.keys.toList());
          for (final raw in rawLines) {
            final l = (raw as Map).cast<String, Object?>();
            final item = items[(l['productId'] as num?)?.toInt()];
            if (item == null) throw WhError('product_not_in_order', 422);
            final qty = parseQty(l['quantity']);
            final cond = '${l['condition'] ?? 'ok'}';
            if (cond != 'ok' && cond != 'damaged') throw WhError('invalid_condition', 422);
            final batch = (l['batchNumber'] as String?)?.trim();
            final expiry = l['expiryDate'] == null ? null : DateTime.tryParse('${l['expiryDate']}');
            if (cond == 'ok' && (products[item.productId]?.trackExpiry ?? false)) {
              if (batch == null || batch.isEmpty || expiry == null) {
                throw WhError('batch_required', 422, {'productId': item.productId});
              }
            }
            final lineGid = '${l['lineGlobalId'] ?? ''}'.trim();
            if (lineGid.length < 8) throw WhError('bad_request', 400);
            int? locationId;
            final bin = (l['locationBarcode'] as String?)?.trim();
            if (bin != null && bin.isNotEmpty) {
              if (await db.getSettingValue('warehouse_bins_enabled') != 'true') throw WhError('bins_disabled', 422);
              final loc = await locationByBarcode(db, bin);
              if (loc == null || loc.warehouseId != po.warehouseId) throw WhError('location_not_found', 422);
              locationId = loc.id;
            }
            await store.addLine(doc, lineGid: lineGid, productId: item.productId, qty: qty,
                locationId: locationId, batchNumber: batch, expiry: expiry, condition: cond,
                poItemId: item.id, counterUserId: ctx.userId);
          }
          return (docId: doc.id, result: {'receipt': await store.toJson(await store.mustGet(docGid))});
        });
        return WhHttp.json(out);
      });

  Future<Response> submit(Request request, String gid) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, _receive], (ctx) async {
        final body = await WhHttp.body(request);
        final out = await store.command(ctx, action: 'receipt_submit', body: {'gid': gid, ...body}, effect: () async {
          var doc = await store.mustGet(gid);
          if (doc.kind != 'po_receipt' || !ctx.scope.allows(doc.warehouseId)) throw WhError('doc_not_found', 404);
          if (doc.createdBy != ctx.userId) throw WhError('not_owner', 403);
          final lines = await store.lines(doc.id);
          if (lines.isEmpty) throw WhError('empty_document', 422);
          final po = await _po(doc.refId!);
          _requireOpen(po, ctx);
          final tolerance = double.tryParse(await db.getSettingValue('wh_receipt_overage_pct') ?? '') ?? 0;
          final incoming = <int, double>{};
          for (final l in lines) {
            incoming[l.poItemId!] = (incoming[l.poItemId!] ?? 0) + l.qty;
          }
          final items = {for (final i in await db.getPurchaseOrderItems(po.id)) i.id: i};
          for (final e in incoming.entries) {
            final item = items[e.key]!;
            final allowed = item.quantity * (1 + tolerance / 100);
            if (item.receivedQuantity + e.value > allowed + 1e-9) {
              // The excess does not enter stock and is not recorded as received.
              throw WhError('over_receipt', 409, {
                'productId': item.productId,
                'ordered': fmtQty(item.quantity),
                'alreadyReceived': fmtQty(item.receivedQuantity),
              });
            }
          }
          for (final e in incoming.entries) {
            final item = items[e.key]!;
            await (db.update(db.purchaseOrderItems)..where((i) => i.id.equals(item.id)))
                .write(PurchaseOrderItemsCompanion(receivedQuantity: Value(item.receivedQuantity + e.value)));
          }
          doc = await store.transition(doc, 'submit', expectedVersion: (body['expectedVersion'] as num?)?.toInt());
          return (docId: doc.id, result: {'receipt': await store.toJson(doc)});
        });
        return WhHttp.json(out);
      });

  Future<Response> listReceipts(Request request) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, _receive], (ctx) async {
        final state = request.requestedUri.queryParameters['state'];
        final docs = await store.list(
          kind: 'po_receipt',
          states: state == null || state.isEmpty ? null : state.split(','),
          warehouseIds: ctx.scope.warehouseIds,
          createdBy: ctx.userId,
        );
        return WhHttp.json({'receipts': [for (final d in docs) await store.toJson(d)]});
      });

  Future<Response> locationLookup(Request request, String code) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, 'inventory_view'], (ctx) async {
        final loc = await locationByBarcode(db, Uri.decodeComponent(code));
        if (loc == null || !ctx.scope.allows(loc.warehouseId)) throw WhError('location_not_found', 404);
        return WhHttp.json({
          'id': loc.id, 'warehouseId': loc.warehouseId, 'binCode': loc.binCode, 'barcode': loc.barcode,
          'isDefault': loc.isDefault,
        });
      });

  Future<Response> convert(Request request, String gid) =>
      _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess, 'purchases_create'], (ctx) async {
        final out = await store.command(ctx, action: 'receipt_convert', body: {'gid': gid}, effect: () async {
          final doc = await store.mustGet(gid);
          if (doc.kind != 'po_receipt' || !ctx.scope.allows(doc.warehouseId)) throw WhError('doc_not_found', 404);
          final r = await WhReceiptPosting(db, store).convert(doc, ctx.userId);
          return (docId: doc.id, result: r);
        });
        return WhHttp.json(out);
      });
}
