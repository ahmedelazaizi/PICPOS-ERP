// Plan 2026-10-23 W4 / ADR-MC3: a counter must never learn the system
// quantity. Every response a counter can obtain while a count is open - task
// list, entries, submit, item lookup, refusals - is searched for the real
// (distinctive) quantities and for the field names that would carry them.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk;
  late int taskId;
  const riceSystem = 137, milkSystem = 29;
  final leaks = RegExp(r'expected|variance|system|"available"|"quantity":"(137|29)', caseSensitive: false);

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', barcode: '6221234567890');
    milk = await h.product('MILK', barcode: '6229999999999');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: riceSystem.toDouble(), type: 'purchase', unitCost: 10);
    await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: milkSystem.toDouble(), type: 'purchase', unitCost: 10);
    final plan = await h.db.into(h.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'Weekly', warehouseId: h.a1));
    taskId = await h.db.generateCycleCountTask(planId: plan, warehouseId: h.a1, productsPerTask: 20);
  });
  tearDown(() => h.dispose());

  void clean(WhReply r, String what) {
    expect(leaks.hasMatch(r.text), isFalse, reason: '$what leaked: ${r.text}');
    expect(r.text.contains('137'), isFalse, reason: '$what carries the rice quantity');
    expect(r.text.contains('"29"') || r.text.contains(':29'), isFalse, reason: '$what carries the milk quantity');
  }

  test('the task list a counter receives has items but no quantity of any kind', () async {
    final r = await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk);
    expect(r.status, 200);
    final task = (r.json['tasks'] as List).single as Map;
    expect((task['items'] as List).map((i) => (i as Map).keys.toSet()).first, {'productId', 'code', 'name', 'barcode'});
    clean(r, 'tasks');
  });

  test('item lookup hides the quantity of goods under an open count and says so', () async {
    final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.clerk);
    expect(r.status, 200);
    final stock = ((r.json['items'] as List).single as Map)['stock'] as List;
    expect((stock.single as Map)['blind'], isTrue);
    expect((stock.single as Map).containsKey('quantity'), isFalse);
    clean(r, 'items');
    final text = await h.call('GET', '/api/m1/wh/items?q=Item', user: h.keeper);
    clean(text, 'items?q (keeper is also a counter)');
  });

  test('an approver still sees the numbers (he needs them to decide)', () async {
    final r = await h.call('GET', '/api/m1/wh/items?barcode=6221234567890', user: h.supervisor);
    expect(r.text, contains('137'));
  });

  test('a blind counter is not told the available quantity when a transfer is refused', () async {
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
    await h.call('POST', '/api/m1/wh/transfers', user: h.keeper, body: {
      'globalId': 'transfer-0001', 'fromWarehouseId': h.a1, 'toWarehouseId': h.a2,
      'lines': [{'lineGlobalId': 'tline-0001', 'productId': rice, 'quantity': '999'}],
    });
    await h.call('POST', '/api/m1/wh/transfers/transfer-0001/approve', user: h.supervisor, body: {});
    final r = await h.call('POST', '/api/m1/wh/transfers/transfer-0001/dispatch', user: h.keeper, body: {});
    expect(r.status, 409);
    expect(r.error, 'stock_changed');
    clean(r, 'refusal');
  });

  test('entries, a premature submit and a bad request answer with codes only', () async {
    final entries = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: {
      'globalId': 'count-doc-0001',
      'entries': [{'lineGlobalId': 'cline-0001', 'productId': rice, 'quantity': '120'}],
    });
    expect(entries.status, 200, reason: entries.text);
    clean(entries, 'entries');
    final early = await h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: h.clerk, body: {'globalId': 'count-doc-0001'});
    expect(early.error, 'incomplete_count');
    clean(early, 'incomplete submit');
    final bad = await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: {'globalId': 'count-doc-0001', 'entries': [{'productId': rice, 'quantity': '-3', 'lineGlobalId': 'cline-0009'}]});
    expect(bad.status, 422);
    clean(bad, 'bad quantity');
  });

  test('submit tells the counter "submitted" and nothing about a recount', () async {
    await h.call('POST', '/api/m1/wh/counts/$taskId/entries', user: h.clerk, body: {
      'globalId': 'count-doc-0001',
      'entries': [
        {'lineGlobalId': 'cline-0001', 'productId': rice, 'quantity': '120'},
        {'lineGlobalId': 'cline-0002', 'productId': milk, 'quantity': '29'},
      ],
    });
    final r = await h.call('POST', '/api/m1/wh/counts/$taskId/submit', user: h.clerk, body: {'globalId': 'count-doc-0001'});
    expect(r.status, 200, reason: r.text);
    expect(r.json['state'], 'submitted');
    expect(r.json.keys.toSet(), {'globalId', 'state'});
    clean(r, 'submit');
    final after = await h.call('GET', '/api/m1/wh/counts/tasks', user: h.clerk);
    expect(after.json['tasks'], isEmpty, reason: 'the counter does not see a task he already counted');
  });

  test('counters cannot reach the review or the approval', () async {
    expect((await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.clerk)).status, 403);
    expect((await h.call('POST', '/api/m1/wh/counts/$taskId/approve', user: h.clerk, body: {})).status, 403);
    expect((await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.keeper)).status, 403);
  });

  test('a task in another warehouse is invisible', () async {
    final r = await h.call('GET', '/api/m1/wh/counts/$taskId/review', user: h.supervisor, device: 'wh-B');
    expect(r.status, anyOf(403, 404));
  });
}
