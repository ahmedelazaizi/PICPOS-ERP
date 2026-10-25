// W4 (plan 2026-10-23 ADR-W7, ADR-MC3): blind cycle counts over the EXISTING
// cycle-count tasks. A counter's DTO never carries an expected quantity, a
// variance, a value or another counter's numbers; whether a recount is needed
// is computed here and never reported to him. Adjustments are posted only by
// `finalizeCycleCountTask`, once, after a user who is none of the counters
// approves.
//
//   pass 1 (any counter) -> if it differs from the system: pass 2 by ANOTHER
//   counter (plan E-4 default: any variance forces a second count) -> approval.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_locations.dart';
import 'wh_stock_guard.dart';

const _openStatuses = ['pending', 'in_progress'];

class WhCountTaskState {
  WhCountTaskState(this.task, this.warehouseId, this.submitted);
  final CycleCountTaskData task;
  final int warehouseId;
  final List<WhDoc> submitted;

  String get ref => task.globalId ?? '${task.id}';
  bool get open => _openStatuses.contains(task.status);
  bool get recountNeeded => submitted.length == 1 && submitted.first.data['variance'] == true;
  bool get readyForApproval => open && (submitted.length >= 2 || (submitted.length == 1 && !recountNeeded));
  Set<int> get counters => {for (final d in submitted) d.createdBy};

  /// Can [userId] still count it (open, and either first pass or a recount he did not do)?
  bool countableBy(int userId) {
    if (!open) return false;
    if (task.assignedTo != null && task.assignedTo != userId) return false;
    if (submitted.isEmpty) return true;
    return recountNeeded && !counters.contains(userId);
  }
}

class WhCountService {
  WhCountService(this.db, this.store);
  final AppDatabase db;
  final WhDocStore store;

  Future<WhCountTaskState> state(String ref) async {
    final id = int.tryParse(ref);
    final task = await (db.select(db.cycleCountTasks)
          ..where((t) => id == null ? t.globalId.equals(ref) : (t.id.equals(id) | t.globalId.equals(ref)))
          ..limit(1))
        .getSingleOrNull();
    if (task == null) throw WhError('task_not_found', 404);
    return _state(task);
  }

  Future<WhCountTaskState> _state(CycleCountTaskData task) async {
    final plan = await (db.select(db.cycleCountPlans)..where((p) => p.id.equals(task.planId))).getSingle();
    final docs = await store.list(
        kind: 'count_submission', states: ['submitted'], refType: 'cycle_count_task', refId: '${task.id}');
    return WhCountTaskState(task, plan.warehouseId, docs.reversed.toList());
  }

  Future<List<WhCountTaskState>> tasksIn(Set<int> warehouseIds) async {
    final tasks = await (db.select(db.cycleCountTasks)
          ..where((t) => t.status.isIn(_openStatuses) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(100))
        .get();
    final out = <WhCountTaskState>[];
    for (final t in tasks) {
      final s = await _state(t);
      if (warehouseIds.contains(s.warehouseId)) out.add(s);
    }
    return out;
  }

  /// What a COUNTER may see of a task. No expected / variance / value.
  Future<Map<String, Object?>> counterDto(WhCountTaskState s, int userId) async {
    final items = await db.getCycleCountItems(s.task.id);
    final products = await db.getProductsByIds([for (final i in items) i.productId]);
    final wh = await db.getWarehouseById(s.warehouseId);
    final draft = await store.list(
        kind: 'count_submission', states: ['draft'], refType: 'cycle_count_task', refId: '${s.task.id}', createdBy: userId);
    return {
      'ref': s.ref,
      'warehouseId': s.warehouseId,
      'warehouse': wh?.name,
      'date': s.task.taskDate.toIso8601String(),
      if (draft.isNotEmpty) 'draftGlobalId': draft.first.gid,
      'items': [
        for (final i in items)
          {
            'productId': i.productId,
            'code': products[i.productId]?.code,
            'name': products[i.productId]?.name,
            'barcode': products[i.productId]?.barcode,
          },
      ],
    };
  }

  Future<WhDoc> appendEntries(WhCtx ctx, WhCountTaskState s, String docGid, List<Object?> raw) async {
    if (!s.countableBy(ctx.userId)) throw WhError('count_not_open', 409);
    var doc = await store.byGid(docGid);
    if (doc == null) {
      doc = await store.create(
        gid: docGid, kind: 'count_submission', state: 'draft', warehouseId: s.warehouseId,
        createdBy: ctx.userId, deviceId: ctx.deviceId, refType: 'cycle_count_task', refId: '${s.task.id}',
        data: {'pass': s.submitted.length + 1},
      );
    } else if (doc.kind != 'count_submission' || doc.refId != '${s.task.id}' || doc.createdBy != ctx.userId) {
      throw WhError('doc_mismatch', 409);
    } else if (doc.state != 'draft') {
      throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'append'});
    }
    final bins = await db.getSettingValue('warehouse_bins_enabled') == 'true';
    for (final r in raw) {
      final e = (r as Map).cast<String, Object?>();
      final pid = (e['productId'] as num?)?.toInt();
      final lineGid = '${e['lineGlobalId'] ?? ''}'.trim();
      if (pid == null || lineGid.length < 8) throw WhError('bad_request', 400);
      if (await db.getProductById(pid) == null) throw WhError('product_not_found', 422);
      int? loc;
      final bin = (e['locationBarcode'] as String?)?.trim();
      if (bin != null && bin.isNotEmpty) {
        if (!bins) throw WhError('bins_disabled', 422);
        final l = await locationByBarcode(db, bin);
        if (l == null || l.warehouseId != s.warehouseId) throw WhError('location_not_found', 422);
        loc = l.id;
      }
      await store.addLine(doc, lineGid: lineGid, productId: pid, qty: parseQty(e['quantity'], allowZero: true),
          locationId: loc, batchNumber: (e['batchNumber'] as String?)?.trim(),
          pass: s.submitted.length + 1, counterUserId: ctx.userId);
    }
    return doc;
  }

  /// Sums the draft per product, writes the task's items through the existing
  /// `submitCount`, and records (privately) whether the result differs from
  /// the system. The counter only learns `submitted`.
  Future<void> submit(WhCtx ctx, WhCountTaskState s, WhDoc doc, {int? expectedVersion}) async {
    if (doc.kind != 'count_submission' || doc.refId != '${s.task.id}') throw WhError('doc_not_found', 404);
    if (doc.createdBy != ctx.userId) throw WhError('not_owner', 403);
    if (!s.countableBy(ctx.userId)) throw WhError('count_not_open', 409);
    final sums = <int, double>{};
    for (final l in await store.lines(doc.id)) {
      sums[l.productId] = (sums[l.productId] ?? 0) + l.qty;
    }
    final items = await db.getCycleCountItems(s.task.id);
    final missing = [for (final i in items) if (!sums.containsKey(i.productId)) i.productId];
    if (missing.isNotEmpty) throw WhError('incomplete_count', 422, {'missing': missing});

    var differs = false;
    final byProduct = {for (final i in items) i.productId: i};
    for (final e in sums.entries) {
      var item = byProduct[e.key];
      if (item == null) {
        // Not on the task: add it with the CURRENT system quantity as expected.
        final id = await db.into(db.cycleCountItems).insert(CycleCountItemsCompanion.insert(
            taskId: s.task.id, productId: e.key, expectedQty: await availableQty(db, e.key, s.warehouseId)));
        item = await (db.select(db.cycleCountItems)..where((i) => i.id.equals(id))).getSingle();
      }
      if (s.task.status == 'pending') {
        await db.startCycleCountTask(s.task.id);
      }
      await db.submitCount(itemId: item.id, countedQty: e.value);
      if ((e.value - await availableQty(db, e.key, s.warehouseId)).abs() > 1e-6) differs = true;
    }
    await store.transition(doc, 'submit',
        expectedVersion: expectedVersion, data: {...doc.data, 'variance': differs});
  }

  /// Manager DTO: the numbers a counter must never get.
  Future<Map<String, Object?>> managerReview(WhCountTaskState s) async {
    final items = await db.getCycleCountItems(s.task.id);
    final products = await db.getProductsByIds([for (final i in items) i.productId]);
    final since = s.submitted.isEmpty ? null : s.submitted.first.createdAt;
    final rows = <Map<String, Object?>>[];
    for (final i in items) {
      final system = await availableQty(db, i.productId, s.warehouseId);
      final moved = since == null
          ? 0
          : (await (db.select(db.stockMovements)
                    ..where((m) =>
                        m.productId.equals(i.productId) &
                        m.warehouseId.equals(s.warehouseId) &
                        // stock_movements.created_at has second precision: a
                        // movement in the same second counts (advice only).
                        m.createdAt.isBiggerOrEqualValue(DateTime.fromMillisecondsSinceEpoch(since.millisecondsSinceEpoch ~/ 1000 * 1000))))
                  .get())
              .length;
      rows.add({
        'productId': i.productId,
        'name': products[i.productId]?.name,
        'expected': fmtQty(system),
        'counted': i.countedQty == null ? null : fmtQty(i.countedQty!),
        'variance': i.countedQty == null ? null : fmtQty(i.countedQty! - system),
        'movementsSinceCount': moved,
        if (moved > 0) 'recountAdvised': true,
      });
    }
    return {
      'ref': s.ref,
      'warehouseId': s.warehouseId,
      'status': s.task.status,
      'passes': s.submitted.length,
      'recountNeeded': s.recountNeeded,
      'readyForApproval': s.readyForApproval,
      'items': rows,
    };
  }

  Future<void> approve(WhCountTaskState s, int approver) async {
    if (s.task.status == 'completed') throw WhError('already_finalized', 409);
    if (s.submitted.isEmpty) throw WhError('count_not_submitted', 409);
    if (s.recountNeeded) throw WhError('recount_required', 409);
    requireDistinct(approver, [...s.counters, ...s.submitted.map((d) => d.createdBy), s.task.assignedTo]);
    await db.finalizeCycleCountTask(s.task.id);
    for (final d in s.submitted) {
      await store.transition(d, 'post', approvedBy: approver, postedRefType: 'cycle_count_task', postedRefId: '${s.task.id}');
    }
  }
}
