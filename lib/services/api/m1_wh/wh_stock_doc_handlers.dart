// W3 HTTP surface (plan 2026-10-23): staged transfers and stock vouchers.
//
//   POST /api/m1/wh/transfers                      request            inventory_transfer
//   GET  /api/m1/wh/transfers[?state=]             list (scope)       inventory_transfer
//   POST /api/m1/wh/transfers/<gid>/approve|reject                    stock_adjust_approve
//   POST /api/m1/wh/transfers/<gid>/dispatch                          inventory_transfer
//   POST /api/m1/wh/transfers/<gid>/receive                           inventory_transfer
//   POST /api/m1/wh/transfers/<gid>/resolve                           stock_adjust_approve
//   POST /api/m1/wh/vouchers                       create (reason)    inventory_edit
//   GET  /api/m1/wh/vouchers[?state=]              list (scope)       inventory_edit
//   POST /api/m1/wh/vouchers/<gid>/approve|reject                     stock_adjust_approve
//
// Every write needs `X-Idempotency-Key`. Approvals are four-eyes (approver !=
// author / dispatcher / receiver); a P5 `x-approval-proof` lets a supervisor's
// phone carry a manager's approval. No route here touches `POST /api/inventory/transfer`.
import 'package:shelf/shelf.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_transfer_service.dart';
import 'wh_voucher_service.dart';

const _access = WarehousePermissionCodes.warehouseMobileAccess;
const _approve = WarehousePermissionCodes.stockAdjustApprove;

class WhStockDocApi {
  WhStockDocApi(this.db)
      : _http = WhHttp(db),
        store = WhDocStore(db) {
    transfers = WhTransferService(db, store);
    vouchers = WhVoucherService(db, store);
  }
  final AppDatabase db;
  final WhHttp _http;
  final WhDocStore store;
  late final WhTransferService transfers;
  late final WhVoucherService vouchers;

  bool _visible(WhCtx ctx, WhDoc d) =>
      ctx.scope.allows(d.warehouseId) || (d.toWarehouseId != null && ctx.scope.allows(d.toWarehouseId!));

  Future<Response> _act(
    Request request,
    String gid,
    String kind,
    String action,
    List<String> perms,
    Future<WhDoc> Function(WhCtx ctx, WhDoc doc, Map<String, Object?> body) run,
  ) =>
      _http.run(request, [_access, ...perms], (ctx) async {
        final body = await WhHttp.body(request);
        final out = await store.command(ctx, action: '$kind:$action', body: {'gid': gid, ...body}, effect: () async {
          if (kind == 'transfer') await transfers.requireEnabled();
          final doc = await store.mustGet(gid);
          if (doc.kind != kind || !_visible(ctx, doc)) throw WhError('doc_not_found', 404);
          final res = await run(ctx, doc, body);
          return (docId: doc.id, result: {'doc': await store.toJson(res)});
        });
        return WhHttp.json(out);
      });

  Future<Response> _create(
    Request request,
    String kind,
    String perm,
    Future<WhDoc> Function(WhCtx ctx, Map<String, Object?> body) make,
  ) =>
      _http.run(request, [_access, perm], (ctx) async {
        final body = await WhHttp.body(request);
        final out = await store.command(ctx, action: '$kind:create', body: body, effect: () async {
          if (kind == 'transfer') await transfers.requireEnabled();
          final doc = await make(ctx, body);
          return (docId: doc.id, result: {'doc': await store.toJson(doc)});
        });
        return WhHttp.json(out);
      });

  Future<Response> _list(Request request, String kind, String perm) => _http.run(request, [_access, perm], (ctx) async {
        if (kind == 'transfer') await transfers.requireEnabled();
        final state = request.requestedUri.queryParameters['state'];
        final docs = await store.list(
          kind: kind,
          states: state == null || state.isEmpty ? null : state.split(','),
          warehouseIds: ctx.scope.warehouseIds,
        );
        return WhHttp.json({'docs': [for (final d in docs) await store.toJson(d)]});
      });

  // ── transfers ──
  Future<Response> transferCreate(Request r) =>
      _create(r, 'transfer', 'inventory_transfer', (ctx, body) => transfers.request(ctx, body));
  Future<Response> transferList(Request r) => _list(r, 'transfer', 'inventory_transfer');

  Future<Response> transferApprove(Request r, String gid) => _act(r, gid, 'transfer', 'approve', [_approve], (ctx, doc, body) async {
        if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return transfers.approve(doc, await _http.approverOf(ctx, _approve), expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });

  Future<Response> transferReject(Request r, String gid) => _act(r, gid, 'transfer', 'reject', [_approve], (ctx, doc, body) async {
        if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return transfers.reject(doc, await _http.approverOf(ctx, _approve), expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });

  Future<Response> transferDispatch(Request r, String gid) =>
      _act(r, gid, 'transfer', 'dispatch', ['inventory_transfer'], (ctx, doc, body) async => transfers.dispatch(
            doc, ctx,
            expectedVersion: (body['expectedVersion'] as num?)?.toInt(),
          ));

  Future<Response> transferReceive(Request r, String gid) =>
      _act(r, gid, 'transfer', 'receive', ['inventory_transfer'], (ctx, doc, body) async {
        final raw = body['lines'];
        if (raw is! List) throw WhError('bad_request', 400);
        final map = <String, ({double ok, double damaged})>{};
        for (final x in raw) {
          final l = (x as Map).cast<String, Object?>();
          final g = '${l['lineGlobalId'] ?? ''}';
          if (g.isEmpty || map.containsKey(g)) throw WhError('bad_request', 400);
          map[g] = (ok: parseQty(l['received'] ?? '0', allowZero: true), damaged: parseQty(l['damaged'] ?? '0', allowZero: true));
        }
        return transfers.receive(doc, ctx, map, expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });

  Future<Response> transferResolve(Request r, String gid) => _act(r, gid, 'transfer', 'resolve', [_approve], (ctx, doc, body) async {
        if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return transfers.resolve(doc, await _http.approverOf(ctx, _approve), '${body['resolution'] ?? ''}',
            expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });

  // ── vouchers ──
  Future<Response> voucherCreate(Request r) => _create(r, 'voucher', 'inventory_edit', (ctx, body) => vouchers.create(ctx, body));
  Future<Response> voucherList(Request r) => _list(r, 'voucher', 'inventory_edit');

  Future<Response> voucherApprove(Request r, String gid) => _act(r, gid, 'voucher', 'approve', [_approve], (ctx, doc, body) async {
        if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return vouchers.approve(doc, await _http.approverOf(ctx, _approve),
            viewerId: ctx.userId,
            expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });

  Future<Response> voucherReject(Request r, String gid) => _act(r, gid, 'voucher', 'reject', [_approve], (ctx, doc, body) async {
        if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
        return vouchers.reject(doc, await _http.approverOf(ctx, _approve), expectedVersion: (body['expectedVersion'] as num?)?.toInt());
      });
}
