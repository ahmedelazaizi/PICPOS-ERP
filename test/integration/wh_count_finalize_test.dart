// Plan 2026-10-23 W4: count passes, recount threshold, four-eyes, and
// posting through the existing finalizeCycleCountTask exactly once.
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk, taskId;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    milk = await h.product('MILK');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: 5, type: 'purchase', unitCost: 10);
    final plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: h.a1));
    taskId = await h.db.generateCycleCountTask(planId: plan, warehouseId: h.a1, productsPerTask: 20);
  });
  tearDown(() => h.dispose());

  Future<WhReply> count(int user, String doc, Map<int, String> qty) async {
    final e = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: user, body: {
      'globalId': doc,
      'entries': [for (final x in qty.entries) {'lineGlobalId': 'l-$doc-${x.key}', 'productId': x.key, 'quantity': x.value}],
    });
    expect(e.status, 200, reason: e.text);
    return h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: user, body: {'globalId': doc});
  }

  Future<WhReply> approve(int user) => h.call('POST', '/api/m1/wh/counts/$taskId/approve', user: user, body: {});

  Future<int> movements(String type) async =>
      (await h.db.customSelect("SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = ?",
              variables: [Variable<String>(type)]).getSingle())
          .data['n'] as int;

  test('a matching first count needs no recount and the approval changes nothing', () async {
    expect((await count(h.clerk, 'doc-count-0001', {rice: '10', milk: '5'})).status, 200);
    final a = await approve(h.supervisor);
    expect(a.status, 200, reason: a.text);
    expect(await h.stock(rice, h.a1), 10);
    expect(await movements('cycle_count'), 0);
  });

  test('any difference forces a second count by ANOTHER counter, then one posting', () async {
    await count(h.clerk, 'doc-count-0001', {rice: '8', milk: '5'});
    // The first counter no longer sees it; approval is refused until pass 2.
    expect((await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk)).json['tasks'], isEmpty);
    expect((await approve(h.supervisor)).error, 'recount_required');
    final tasks = await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk2);
    expect((tasks.json['tasks'] as List), hasLength(1), reason: 'recount offered to a different counter');

    final again = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: {
      'globalId': 'doc-count-0002', 'entries': [{'lineGlobalId': 'x-0002-aaa', 'productId': rice, 'quantity': '8'}],
    });
    expect(again.error, 'count_not_open', reason: 'the same person may not recount');

    expect((await count(h.clerk2, 'doc-count-0003', {rice: '9', milk: '5'})).status, 200);
    final review = await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.supervisor);
    final riceRow = (review.json['items'] as List).cast<Map>().firstWhere((i) => i['productId'] == rice);
    expect(riceRow['expected'], '10');
    expect(riceRow['counted'], '9');
    expect(riceRow['variance'], '-1');

    expect((await approve(h.supervisor)).status, 200);
    expect(await h.stock(rice, h.a1), 9, reason: 'posted from the second count');
    expect(await movements('cycle_count'), 1, reason: 'one movement for the one differing line');
    expect((await approve(h.supervisor2)).error, 'already_finalized');
    expect(await movements('cycle_count'), 1);
  });

  test('the approver is none of the counters, administrator included', () async {
    await count(h.supervisor, 'doc-count-0001', {rice: '10', milk: '5'});
    final self = await approve(h.supervisor);
    expect(self.status, 403);
    expect(self.error, 'self_approval');
    final byAdmin = await approve(h.admin);
    expect(byAdmin.status, 200, reason: byAdmin.text);
    expect((await approve(h.supervisor2)).error, 'already_finalized');
  });

  test('a counter without stock_adjust_approve can never approve his own count', () async {
    await count(h.clerk, 'doc-count-0001', {rice: '10', milk: '5'});
    expect((await approve(h.clerk)).status, 403);
    expect((await approve(h.keeper)).status, 403);
  });

  test('a count must cover every item; extra products are added with the current balance', () async {
    final partial = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: {
      'globalId': 'doc-count-0001', 'entries': [{'lineGlobalId': 'l-1-aaaa', 'productId': rice, 'quantity': '10'}],
    });
    expect(partial.status, 200);
    final r = await h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: h.clerk, body: {'globalId': 'doc-count-0001'});
    expect(r.error, 'incomplete_count');

    final extra = await h.product('EXTRA');
    await h.db.adjustStock(productId: extra, warehouseId: h.a1, quantity: 2, type: 'purchase', unitCost: 1);
    final ok = await count(h.clerk2, 'doc-count-0009', {rice: '10', milk: '5', extra: '2'});
    expect(ok.status, 200, reason: ok.text);
    final items = await h.db.getCycleCountItems(taskId);
    expect(items.firstWhere((i) => i.productId == extra).expectedQty, 2);
  });

  test('movements after the count are flagged for the approver', () async {
    await count(h.clerk, 'doc-count-0001', {rice: '10', milk: '5'});
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 1, type: 'purchase', unitCost: 10);
    final review = await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.supervisor);
    final row = (review.json['items'] as List).cast<Map>().firstWhere((i) => i['productId'] == rice);
    expect(row['movementsSinceCount'], greaterThan(0));
    expect(row['recountAdvised'], isTrue);
  });

  test('replaying a count command with the same key does not duplicate entries', () async {
    final body = {
      'globalId': 'doc-count-0001',
      'entries': [
        {'lineGlobalId': 'l-1-aaaa', 'productId': rice, 'quantity': '10'},
        {'lineGlobalId': 'l-1-bbbb', 'productId': milk, 'quantity': '5'},
      ],
    };
    await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: body, key: 'count-key-0001');
    final replay = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: body, key: 'count-key-0001');
    expect(replay.json['replayed'], isTrue);
    expect(replay.json['entries'], 2);
  });
}
