// WH-007 / WH-008 / WH-009 (review 2026-10-25): the count controls hold on
// every path.
//   * an ASSIGNED task whose first pass differs can still be recounted by
//     another counter and approved (it used to dead-lock);
//   * the desktop «إكمال» of a task that has phone passes follows the same
//     recount + four-eyes rule instead of bypassing it;
//   * blindness follows who COUNTS, not only the role: a supervisor who started
//     counting a task does not see the system quantities of its items.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/cycle_count_repository_impl.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk, taskId;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', barcode: '6221234567890');
    milk = await h.product('MILK', barcode: '6229999999999');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: 5, type: 'purchase', unitCost: 10);
    final plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: h.a1));
    taskId = await h.db.generateCycleCountTask(planId: plan, warehouseId: h.a1, productsPerTask: 20);
  });
  tearDown(() => h.dispose());

  Future<WhReply> entries(int user, String doc, Map<int, String> qty) => h.call(
        'POST', '/api/m1/wh/counts/$taskId/entries',
        user: user,
        body: {
          'globalId': doc,
          'entries': [for (final x in qty.entries) {'lineGlobalId': 'l-$doc-${x.key}', 'productId': x.key, 'quantity': x.value}],
        },
      );

  Future<WhReply> count(int user, String doc, Map<int, String> qty) async {
    final e = await entries(user, doc, qty);
    expect(e.status, 200, reason: e.text);
    return h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: user, body: {'globalId': doc});
  }

  Future<WhReply> approve(int user) => h.call('POST', '/api/m1/wh/counts/$taskId/approve', user: user, body: {});

  group('WH-007 an assigned task can be recounted and approved', () {
    test('assigned to clerk, first pass differs -> clerk2 recounts -> approval posts the second count', () async {
      await (h.db.update(h.db.cycleCountTasks)..where((t) => t.id.equals(taskId)))
          .write(CycleCountTasksCompanion(assignedTo: Value(h.clerk)));

      expect((await count(h.clerk, 'doc-count-0001', {rice: '8', milk: '5'})).status, 200);
      expect((await approve(h.supervisor)).error, 'recount_required');

      final offered = await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk2);
      expect(offered.json['tasks'], hasLength(1), reason: 'the recount is offered to another counter despite the assignment');

      expect((await count(h.clerk2, 'doc-count-0002', {rice: '9', milk: '5'})).status, 200);
      final ok = await approve(h.supervisor);
      expect(ok.status, 200, reason: ok.text);
      expect(await h.stock(rice, h.a1), 9);
    });

    test('a stranger still cannot take the FIRST pass of an assigned task', () async {
      await (h.db.update(h.db.cycleCountTasks)..where((t) => t.id.equals(taskId)))
          .write(CycleCountTasksCompanion(assignedTo: Value(h.clerk)));
      expect((await entries(h.clerk2, 'doc-count-0001', {rice: '10'})).error, 'count_not_open');
    });
  });

  group('WH-008 the desktop «إكمال» follows the same rule', () {
    late CycleCountRepositoryImpl repo;
    setUp(() => repo = CycleCountRepositoryImpl(h.db));

    test('phone pass with a variance: desktop finalize is refused until the recount, stock untouched', () async {
      await count(h.clerk, 'doc-count-0001', {rice: '8', milk: '5'});
      await expectLater(repo.finalizeCycleCountTask(taskId, approverUserId: h.supervisor), throwsA(anything));
      expect(await h.stock(rice, h.a1), 10);
      final t = await (h.db.select(h.db.cycleCountTasks)..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, isNot('completed'));
    });

    test('the counter himself cannot finalize from the desktop (four-eyes)', () async {
      await count(h.supervisor, 'doc-count-0001', {rice: '10', milk: '5'});
      await expectLater(repo.finalizeCycleCountTask(taskId, approverUserId: h.supervisor), throwsA(anything));
      final t = await (h.db.select(h.db.cycleCountTasks)..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, isNot('completed'));
    });

    test('an approver who is none of the counters finalizes once and the phone documents become posted', () async {
      await count(h.clerk, 'doc-count-0001', {rice: '8', milk: '5'});
      await count(h.clerk2, 'doc-count-0002', {rice: '9', milk: '5'});
      await repo.finalizeCycleCountTask(taskId, approverUserId: h.supervisor);
      expect(await h.stock(rice, h.a1), 9);
      final states = await h.db.customSelect("SELECT state FROM wh_mobile_docs WHERE kind = 'count_submission'").get();
      expect(states.map((r) => r.data['state']), everyElement('posted'), reason: 'no orphan submitted documents');
    });

    test('a task with no phone passes keeps the legacy desktop behaviour', () async {
      await repo.finalizeCycleCountTask(taskId);
      final t = await (h.db.select(h.db.cycleCountTasks)..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, 'completed');
    });
  });

  test('WH-014: 150 newer tasks of another branch do not hide this branch\'s task', () async {
    final planB = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'B', warehouseId: h.b1));
    for (var i = 0; i < 150; i++) {
      await h.db.into(h.db.cycleCountTasks).insert(CycleCountTasksCompanion.insert(planId: planB, taskDate: DateTime.now()));
    }
    final r = await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk);
    expect(r.status, 200, reason: r.text);
    expect((r.json['tasks'] as List).map((t) => (t as Map)['warehouseId']), [h.a1],
        reason: 'only the A1 task; the 150 B1 tasks are filtered in the query, not after the limit');
  });

  group('WH-009 blindness follows the one who counts', () {
    int? qtyOf(WhReply r) {
      final stock = (((r.json['items'] as List).single as Map)['stock'] as List).single as Map;
      return stock.containsKey('quantity') ? double.parse('${stock['quantity']}').round() : null;
    }

    test('a supervisor who did not count still sees the quantity (he approves)', () async {
      final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.supervisor);
      expect(qtyOf(r), 10);
    });

    test('a supervisor who has started counting the task is blind on its items', () async {
      expect((await entries(h.supervisor, 'doc-count-0001', {rice: '10'})).status, 200);
      final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.supervisor);
      expect(qtyOf(r), isNull);
      expect(r.text.contains('"10"'), isFalse, reason: r.text);
    });

    test('...and after submitting; the manager review is closed to a counter of that task', () async {
      await count(h.supervisor, 'doc-count-0001', {rice: '10', milk: '5'});
      final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.supervisor);
      expect(qtyOf(r), isNull);
      final review = await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.supervisor);
      expect(review.status, 403);
      expect(review.error, 'self_approval');
    });

    test('another supervisor, who is not counting, is unaffected', () async {
      await count(h.supervisor, 'doc-count-0001', {rice: '10', milk: '5'});
      final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.supervisor2);
      expect(qtyOf(r), 10);
    });
  });
}
