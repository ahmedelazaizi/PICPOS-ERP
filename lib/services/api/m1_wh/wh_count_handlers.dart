// W4 HTTP surface (plan 2026-10-23): blind counts.
//
//   GET  /api/m1/wh/counts/tasks             open tasks the caller may count   stock_count_submit
//   POST /api/m1/wh/counts/<ref>/entries     append entries to a draft          stock_count_submit
//   POST /api/m1/wh/counts/<ref>/submit      draft -> submitted                 stock_count_submit
//   GET  /api/m1/wh/counts/<ref>/review      expected/counted/variance          stock_adjust_approve
//   POST /api/m1/wh/counts/<ref>/recount     send the submitted passes back     stock_adjust_approve
//   POST /api/m1/wh/counts/<ref>/approve     finalizeCycleCountTask, once       stock_adjust_approve
//
// <ref> is the task's globalId, or its numeric id. The counter-facing
// responses (tasks, entries, submit) are built from `counterDto` and plain
// states only; the numbers live in `review`, which a counter cannot call.
import 'package:shelf/shelf.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import 'wh_count_service.dart';
import 'wh_doc_approval.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';

const _access = WarehousePermissionCodes.warehouseMobileAccess;
const _count = WarehousePermissionCodes.stockCountSubmit;
const _approve = WarehousePermissionCodes.stockAdjustApprove;

class WhCountApi {
  WhCountApi(this.db)
      : _http = WhHttp(db),
        store = WhDocStore(db) {
    counts = WhCountService(db, store);
  }
  final AppDatabase db;
  final WhHttp _http;
  final WhDocStore store;
  late final WhCountService counts;

  Future<WhCountTaskState> _scoped(WhCtx ctx, String ref) async {
    final s = await counts.state(ref);
    if (!ctx.scope.allows(s.warehouseId)) throw WhError('task_not_found', 404);
    return s;
  }

  Future<Response> tasks(Request request) => _http.run(request, [_access, _count], (ctx) async {
        final all = await counts.tasksIn(ctx.scope.warehouseIds);
        return WhHttp.json({
          'tasks': [
            for (final s in all)
              if (s.countableBy(ctx.userId)) await counts.counterDto(s, ctx.userId),
          ],
        });
      });

  Future<Response> entries(Request request, String ref) => _http.run(request, [_access, _count], (ctx) async {
        final body = await WhHttp.body(request);
        final docGid = '${body['globalId'] ?? ''}'.trim();
        final raw = body['entries'];
        if (docGid.length < 8 || raw is! List || raw.isEmpty) throw WhError('bad_request', 400);
        final out = await store.command(ctx, action: 'count_entries', body: {'ref': ref, ...body}, effect: () async {
          final s = await _scoped(ctx, ref);
          final doc = await counts.appendEntries(ctx, s, docGid, raw);
          return (docId: doc.id, result: {'globalId': doc.gid, 'state': doc.state, 'entries': (await store.lines(doc.id)).length});
        });
        return WhHttp.json(out);
      });

  Future<Response> submit(Request request, String ref) => _http.run(request, [_access, _count], (ctx) async {
        final body = await WhHttp.body(request);
        final docGid = '${body['globalId'] ?? ''}'.trim();
        if (docGid.length < 8) throw WhError('bad_request', 400);
        final out = await store.command(ctx, action: 'count_submit', body: {'ref': ref, ...body}, effect: () async {
          final s = await _scoped(ctx, ref);
          final doc = await store.mustGet(docGid);
          await counts.submit(ctx, s, doc, expectedVersion: (body['expectedVersion'] as num?)?.toInt());
          // Counter-facing answer: the state, nothing computed from the system.
          return (docId: doc.id, result: {'globalId': doc.gid, 'state': 'submitted'});
        });
        return WhHttp.json(out);
      });

  Future<Response> review(Request request, String ref) => _http.run(request, [_access, _approve], (ctx) async {
        final s = await _scoped(ctx, ref);
        // WH-009: whoever counted (or started to count) this task does not read
        // its system quantities, whatever his role.
        if (await counts.countedBy(ctx.userId, s)) throw WhError('self_approval', 403);
        return WhHttp.json(await counts.managerReview(s));
      });

  /// WH-014: the manager sends the submitted count(s) back for another pass.
  Future<Response> recount(Request request, String ref) => _http.run(request, [_access, _approve], (ctx) async {
        final body = await WhHttp.body(request);
        final reason = (body['reason'] as String?)?.trim();
        final out = await store.command(ctx, action: 'count_recount', body: {'ref': ref, 'reason': reason}, effect: () async {
          final s = await _scoped(ctx, ref);
          if (await counts.countedBy(ctx.userId, s)) throw WhError('self_approval', 403);
          final n = await counts.recount(s, ctx.userId, reason: reason);
          return (docId: null, result: {'ref': s.ref, 'status': s.task.status, 'retired': n});
        });
        return WhHttp.json(out);
      });

  Future<Response> approve(Request request, String ref) => _http.run(request, [_access, _approve], (ctx) async {
        final out = await store.command(ctx, action: 'count_approve', body: {'ref': ref}, effect: () async {
          final s = await _scoped(ctx, ref);
          await counts.approve(s, await _http.approverOf(ctx, _approve, WhApprovalTarget(ref: s.ref, op: 'count:approve', warehouseId: s.warehouseId)));
          return (docId: null, result: {'ref': s.ref, 'status': 'completed'});
        });
        return WhHttp.json(out);
      });
}
