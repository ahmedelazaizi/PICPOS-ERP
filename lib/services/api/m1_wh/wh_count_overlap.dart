// WH-014 (owner decision 2026-10-26): overlapping count tasks.
//
// The plan (§B.2-5) wants ONE active task per (warehouse, product). Tasks are
// created on the desktop, so the rule is enforced where the stock is settled -
// the approval - with two refusals, both `409`:
//
//   overlapping_count_task  an OLDER task of the same warehouse that shares a
//                           product is still open and in progress: it settles
//                           first (two settlements of one product from two
//                           different counts would each overwrite the other).
//   stale_overlap_count     another task that shares a product was COMPLETED
//                           after this task's count was submitted: that count
//                           no longer describes the shelf. Recount first.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import 'wh_count_service.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';

Future<void> requireNoCountOverlap(AppDatabase db, WhDocStore store, WhCountTaskState s) async {
  final items = await db.getCycleCountItems(s.task.id);
  final products = {for (final i in items) i.productId};
  if (products.isEmpty || s.submitted.isEmpty) return;
  final submittedAt = s.submitted.first.createdAt;
  final since = submittedAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(submittedAt.millisecondsSinceEpoch ~/ 1000 * 1000);

  final tasks = db.cycleCountTasks;
  final rows = await (db.select(tasks).join([
    innerJoin(db.cycleCountPlans, db.cycleCountPlans.id.equalsExp(tasks.planId)),
    innerJoin(db.cycleCountItems, db.cycleCountItems.taskId.equalsExp(tasks.id)),
  ])
        ..where(db.cycleCountPlans.warehouseId.equals(s.warehouseId) &
            tasks.id.equals(s.task.id).not() &
            tasks.deletedAt.isNull() &
            tasks.status.isIn(const ['in_progress', 'completed']) &
            db.cycleCountItems.productId.isIn(products)))
      .get();

  for (final other in {for (final r in rows) r.readTable(tasks).id: r.readTable(tasks)}.values) {
    final ref = other.globalId ?? '${other.id}';
    if (other.status == 'in_progress' && other.id < s.task.id) {
      throw WhError('overlapping_count_task', 409, {'otherRef': ref});
    }
    if (other.status == 'completed' && submittedAt != null && await _completedAfter(store, other, submittedAt, since!)) {
      throw WhError('stale_overlap_count', 409, {'otherRef': ref});
    }
  }
}

/// `completed_at` has second precision, so a task that has phone passes is
/// timed by its posted documents (milliseconds); a desktop-only task by its
/// second, counting the same second as "after" (the conservative side).
Future<bool> _completedAfter(WhDocStore store, CycleCountTaskData other, DateTime submittedAt, DateTime sinceSecond) async {
  final posted = await store.list(
      kind: 'count_submission', states: ['posted'], refType: 'cycle_count_task', refId: '${other.id}', limit: 20);
  if (posted.isNotEmpty) {
    final at = posted.map((d) => (d.row['updated_at'] as num).toInt()).reduce((a, b) => a > b ? a : b);
    return at > submittedAt.millisecondsSinceEpoch;
  }
  final done = other.completedAt;
  return done != null && !done.isBefore(sinceSecond);
}
