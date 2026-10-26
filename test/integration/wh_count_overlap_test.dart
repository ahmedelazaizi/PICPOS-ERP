// WH-014 (owner decision 2026-10-26): overlapping count tasks and the manager's
// recount.
//   * a task cannot be approved while an OLDER open task on the same
//     (warehouse, product) holds counts - both would settle the same stock;
//   * a task whose product was settled by another task AFTER its count was
//     submitted is stale: its approval is refused until it is recounted;
//   * the manager can send a submitted count back (`recount`): the passes are
//     retired (never posted), the task stays open, and the retired counters do
//     not count it again.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk, plan, t1, t2;

  Future<int> newTask(List<int> products) async {
    final id = await h.db.into(h.db.cycleCountTasks).insert(CycleCountTasksCompanion.insert(planId: plan, taskDate: DateTime.now()));
    for (final p in products) {
      await h.db.into(h.db.cycleCountItems).insert(CycleCountItemsCompanion.insert(taskId: id, productId: p, expectedQty: 0));
    }
    return id;
  }

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', barcode: '6221234567890');
    milk = await h.product('MILK', barcode: '6229999999999');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: 5, type: 'purchase', unitCost: 10);
    plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: h.a1));
    t1 = await newTask([rice]);
    t2 = await newTask([rice, milk]);
  });
  tearDown(() => h.dispose());

  Future<WhReply> count(int task, int user, String doc, Map<int, String> qty) async {
    final e = await h.call('POST', '/api/m1/wh/counts/$task/entries', user: user, body: {
      'globalId': doc,
      'entries': [for (final x in qty.entries) {'lineGlobalId': 'l-$doc-${x.key}', 'productId': x.key, 'quantity': x.value}],
    });
    expect(e.status, 200, reason: e.text);
    return h.call('POST', '/api/m1/wh/counts/$task/submit', user: user, body: {'globalId': doc});
  }

  Future<WhReply> approve(int task, int user) => h.call('POST', '/api/m1/wh/counts/$task/approve', user: user, body: {});
  Future<WhReply> recount(int task, int user, {String? key}) =>
      h.call('POST', '/api/m1/wh/counts/$task/recount', user: user, body: {'reason': 'moved'}, key: key);

  Future<String> status(int task) async =>
      (await (h.db.select(h.db.cycleCountTasks)..where((t) => t.id.equals(task))).getSingle()).status;

  Future<List<String>> docStates() async =>
      [for (final r in await h.db.customSelect("SELECT state FROM wh_mobile_docs WHERE kind = 'count_submission' ORDER BY id").get()) '${r.data['state']}'];

  group('overlap', () {
    test('the newer task cannot be approved while the older one on the same product holds counts', () async {
      expect((await count(t1, h.clerk, 'doc-t1-0001', {rice: '10'})).status, 200);
      expect((await count(t2, h.clerk2, 'doc-t2-0001', {rice: '10', milk: '5'})).status, 200);

      final r = await approve(t2, h.supervisor);
      expect(r.status, 409, reason: r.text);
      expect(r.error, 'overlapping_count_task');
      expect(await status(t2), isNot('completed'));
      expect(await docStates(), ['submitted', 'submitted'], reason: 'nothing posted');
      expect(await h.stock(rice, h.a1), 10);

      expect((await approve(t1, h.supervisor)).status, 200);
      expect(await status(t1), 'completed');
    });

    test('a task whose product was settled by another task after its count is stale until recounted', () async {
      expect((await count(t2, h.clerk2, 'doc-t2-0001', {rice: '10', milk: '5'})).status, 200);
      // the older task counts and settles rice (stock really is 9) AFTER t2 was counted
      expect((await count(t1, h.clerk, 'doc-t1-0001', {rice: '9'})).status, 200);
      expect((await count(t1, h.clerk2, 'doc-t1-0002', {rice: '9'})).status, 200);
      expect((await approve(t1, h.supervisor)).status, 200);
      expect(await h.stock(rice, h.a1), 9);

      final r = await approve(t2, h.supervisor);
      expect(r.status, 409, reason: r.text);
      expect(r.error, 'stale_overlap_count');
      expect(await status(t2), isNot('completed'));
      expect(await h.stock(rice, h.a1), 9, reason: 'the stale count of 10 must not overwrite the settled 9');

      // the manager sends it back; a counter who did not count it takes the new pass
      expect((await recount(t2, h.supervisor)).status, 200);
      expect((await count(t2, h.clerk, 'doc-t2-0002', {rice: '9', milk: '5'})).status, 200);
      final ok = await approve(t2, h.supervisor);
      expect(ok.status, 200, reason: ok.text);
      expect(await status(t2), 'completed');
    });

    test('tasks on different products of one warehouse do not block each other', () async {
      final t3 = await newTask([milk]);
      expect((await count(t1, h.clerk, 'doc-t1-0001', {rice: '10'})).status, 200);
      expect((await count(t3, h.clerk2, 'doc-t3-0001', {milk: '5'})).status, 200);
      expect((await approve(t3, h.supervisor)).status, 200);
    });
  });

  group('recount', () {
    test('sends a submitted count back: retired, not posted, task open, stock untouched', () async {
      expect((await count(t1, h.clerk, 'doc-t1-0001', {rice: '10'})).status, 200);
      final r = await recount(t1, h.supervisor);
      expect(r.status, 200, reason: r.text);
      expect(await docStates(), ['superseded']);
      expect(await status(t1), isNot('completed'));
      expect(await h.stock(rice, h.a1), 10);
      expect((await approve(t1, h.supervisor2)).error, 'count_not_submitted', reason: 'nothing to approve until it is counted again');
    });

    test('the retired counter is not offered the task again; another counter is, and the new pass is approved', () async {
      await count(t1, h.clerk, 'doc-t1-0001', {rice: '8'});
      expect((await recount(t1, h.supervisor2)).status, 200);
      expect(((await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk)).json['tasks'] as List), hasLength(1), reason: 'only the untouched t2');
      expect(((await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk2)).json['tasks'] as List), hasLength(2), reason: 't1 (recount) and t2');

      // E-4: a pass that differs from the system still needs its second counter
      expect((await count(t1, h.clerk2, 'doc-t1-0002', {rice: '9'})).status, 200);
      expect((await count(t1, h.supervisor, 'doc-t1-0003', {rice: '9'})).status, 200);
      final ok = await approve(t1, h.supervisor2);
      expect(ok.status, 200, reason: ok.text);
      expect(await h.stock(rice, h.a1), 9);
      expect(await docStates(), ['superseded', 'posted', 'posted']);
    });

    test('works after the second pass too (a third opinion), and a replay is idempotent', () async {
      await count(t1, h.clerk, 'doc-t1-0001', {rice: '8'});
      await count(t1, h.clerk2, 'doc-t1-0002', {rice: '9'});
      final first = await recount(t1, h.supervisor, key: 'recount-key-0001');
      expect(first.status, 200, reason: first.text);
      final replay = await recount(t1, h.supervisor, key: 'recount-key-0001');
      expect(replay.status, 200);
      expect(replay.json['replayed'], true);
      expect(await docStates(), ['superseded', 'superseded']);
    });

    test('refusals: nothing submitted, a counter, a non-approver, a finished task', () async {
      expect((await recount(t1, h.supervisor)).error, 'count_not_submitted');
      await count(t1, h.supervisor, 'doc-t1-0001', {rice: '10'});
      final self = await recount(t1, h.supervisor);
      expect(self.status, 403);
      expect(self.error, 'self_approval');
      expect((await recount(t1, h.clerk2)).status, 403, reason: 'a counter has no stock_adjust_approve');
      expect(await docStates(), ['submitted']);

      expect((await approve(t1, h.supervisor2)).status, 200);
      final done = await recount(t1, h.supervisor2);
      expect(done.status, 409);
      expect(done.error, 'already_finalized');
    });

    test('two counters drafting the first pass at once: the second submit is refused when the first needs no recount', () async {
      final a = await h.call('POST', '/api/m1/wh/counts/$t1/entries', user: h.clerk, body: {
        'globalId': 'doc-t1-0001', 'entries': [{'lineGlobalId': 'line-a-0001', 'productId': rice, 'quantity': '10'}]});
      final b = await h.call('POST', '/api/m1/wh/counts/$t1/entries', user: h.clerk2, body: {
        'globalId': 'doc-t1-0002', 'entries': [{'lineGlobalId': 'line-b-0001', 'productId': rice, 'quantity': '10'}]});
      expect([a.status, b.status], [200, 200], reason: 'each counter has a private draft');
      expect((await h.call('POST', '/api/m1/wh/counts/$t1/submit', user: h.clerk, body: {'globalId': 'doc-t1-0001'})).status, 200);
      final late = await h.call('POST', '/api/m1/wh/counts/$t1/submit', user: h.clerk2, body: {'globalId': 'doc-t1-0002'});
      expect(late.status, 409, reason: late.text);
      expect(late.error, 'count_not_open');
      expect(await docStates(), ['submitted', 'draft']);
    });
  });
}
