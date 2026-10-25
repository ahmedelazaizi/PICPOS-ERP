// W5 (plan 2026-10-23): the supervisor / manager approvals inbox and label data.
//
//   GET /api/m1/wh/approvals            everything waiting for MY approval       stock_adjust_approve
//   GET /api/m1/wh/labels?kind=&ref=    data for an item / bin label (no cost)   inventory_view
//
// The inbox lists only what the caller may approve under four-eyes: documents
// he authored, dispatched, received or counted are left out. Labels carry
// data only; rendering and printing live in the app (transport independent),
// and a failed print never touches stock.
import 'package:shelf/shelf.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import 'wh_count_service.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_locations.dart';

const _access = WarehousePermissionCodes.warehouseMobileAccess;

class WhApprovalApi {
  WhApprovalApi(this.db)
      : _http = WhHttp(db),
        store = WhDocStore(db) {
    counts = WhCountService(db, store);
  }
  final AppDatabase db;
  final WhHttp _http;
  final WhDocStore store;
  late final WhCountService counts;

  Future<Response> inbox(Request request) =>
      _http.run(request, [_access, WarehousePermissionCodes.stockAdjustApprove], (ctx) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        int age(Object? createdAt) => createdAt is num ? ((now - createdAt.toInt()) / 60000).floor() : 0;
        final items = <Map<String, Object?>>[];

        for (final d in await store.list(kind: 'transfer', states: ['requested'], warehouseIds: ctx.scope.warehouseIds)) {
          // The approval needs the SOURCE warehouse in scope (WH-027): a request into
          // my warehouse from elsewhere is not mine to approve.
          if (d.createdBy == ctx.userId || !ctx.scope.allows(d.warehouseId)) continue;
          items.add({'type': 'transfer_request', 'ref': d.gid, 'warehouseId': d.warehouseId,
            'toWarehouseId': d.toWarehouseId, 'lines': (await store.lines(d.id)).length, 'ageMinutes': age(d.row['created_at'])});
        }
        for (final d in await store.list(kind: 'transfer', states: ['received_short'], warehouseIds: ctx.scope.warehouseIds)) {
          final data = d.data;
          if ({d.createdBy, data['dispatchedBy'], data['receivedBy']}.contains(ctx.userId) || !ctx.scope.allows(d.warehouseId)) continue;
          items.add({'type': 'transfer_shortage', 'ref': d.gid, 'warehouseId': d.warehouseId,
            'toWarehouseId': d.toWarehouseId, 'ageMinutes': age(d.row['created_at'])});
        }
        for (final d in await store.list(kind: 'voucher', states: ['pending'], warehouseIds: ctx.scope.warehouseIds)) {
          if (d.createdBy == ctx.userId) continue;
          items.add({'type': 'voucher', 'ref': d.gid, 'voucherType': d.data['type'], 'reason': d.reason,
            'warehouseId': d.warehouseId, 'lines': (await store.lines(d.id)).length, 'ageMinutes': age(d.row['created_at'])});
        }
        for (final s in await counts.tasksIn(ctx.scope.warehouseIds)) {
          if (!s.readyForApproval || s.counters.contains(ctx.userId) || s.task.assignedTo == ctx.userId) continue;
          items.add({'type': 'count', 'ref': s.ref, 'warehouseId': s.warehouseId, 'ageMinutes': 0});
        }
        return WhHttp.json({'approvals': items, 'count': items.length});
      });

  Future<Response> label(Request request) => _http.run(request, [_access, 'inventory_view'], (ctx) async {
        final q = request.requestedUri.queryParameters;
        final kind = q['kind'] ?? '';
        final ref = (q['ref'] ?? '').trim();
        if (ref.isEmpty) throw WhError('bad_request', 400);
        if (kind == 'item') {
          final id = int.tryParse(ref);
          final p = (id != null ? await db.getProductById(id) : null) ?? await db.getProductByBarcode(ref);
          if (p == null) throw WhError('item_not_found', 404);
          final code = (p.barcode ?? '').trim();
          if (code.isEmpty) throw WhError('no_barcode', 422);
          return WhHttp.json({'kind': 'item', 'productId': p.id, 'code': p.code, 'name': p.name, 'barcode': code});
        }
        if (kind == 'location') {
          final loc = await locationByBarcode(db, ref);
          if (loc == null || !ctx.scope.allows(loc.warehouseId)) throw WhError('location_not_found', 404);
          return WhHttp.json({'kind': 'location', 'id': loc.id, 'warehouseId': loc.warehouseId,
            'binCode': loc.binCode, 'barcode': loc.barcode});
        }
        throw WhError('bad_request', 400);
      });
}
