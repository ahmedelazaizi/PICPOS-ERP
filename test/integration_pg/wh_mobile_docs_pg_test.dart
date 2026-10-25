// The warehouse-phone document store (raw-SQL tables outside Drift, plan
// 2026-10-23 ADR-W5) on PostgreSQL: DDL, unique ids, state machine guarded by
// the row version, command log / idempotency, listing filters.
@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_doc_store.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_scope.dart';
import 'package:shelf/shelf.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late WhDocStore store;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.ensureWhMobileDocsSchema();
    store = WhDocStore(fx.db);
  });
  tearDownAll(() => fx.tearDown());

  WhCtx ctx(String key) => WhCtx(
        userId: 1,
        branchId: 1,
        deviceId: 'dev-1',
        scope: const WhScope(branchId: 1, warehouses: []),
        request: Request('POST', Uri.parse('http://x/'), headers: {'x-idempotency-key': key}),
      );

  test('the schema is created once and is idempotent', () async {
    await fx.db.ensureWhMobileDocsSchema();
    final t = await fx.db.customSelect(
        "SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'wh_mobile_%' ORDER BY 1").get();
    expect(t.map((r) => r.data['table_name']), ['wh_mobile_doc_events', 'wh_mobile_doc_lines', 'wh_mobile_docs']);
  });

  test('create / lines / transition guarded by the row version', () async {
    final d = await store.create(kind: 'voucher', state: 'pending', warehouseId: 1, createdBy: 1, deviceId: 'd', reason: 'r', data: {'type': 'out'});
    expect(d.rowVersion, 0);
    expect(await store.addLine(d, lineGid: 'pg-line-0001', productId: 1, qty: 2.5), isTrue);
    expect(await store.addLine(d, lineGid: 'pg-line-0001', productId: 1, qty: 2.5), isFalse, reason: 'unique line id');
    final next = await store.transition(d, 'approve', approvedBy: 2);
    expect(next.state, 'posted');
    expect(next.rowVersion, 1);
    expect(next.approvedBy, 2);
    await expectLater(store.transition(d, 'approve'), throwsA(isA<WhError>().having((e) => e.code, 'code', 'stale')));
    await expectLater(store.transition(next, 'approve'), throwsA(isA<WhError>().having((e) => e.code, 'code', 'invalid_transition')));
    expect((await store.lines(d.id)).single.qty, 2.5);
  });

  test('command log: same id replays, same id with another body conflicts, effect runs once', () async {
    var runs = 0;
    Future<Map<String, Object?>> go(String key, Object body) => store.command(ctx(key), action: 'x', body: body, effect: () async {
          runs++;
          return (docId: null, result: <String, Object?>{'n': runs});
        });
    expect((await go('pg-cmd-0001', {'a': 1}))['n'], 1);
    expect((await go('pg-cmd-0001', {'a': 1}))['replayed'], isTrue);
    await expectLater(go('pg-cmd-0001', {'a': 2}), throwsA(isA<WhError>().having((e) => e.code, 'code', 'idempotency_conflict')));
    expect(runs, 1);
  });

  test('listing filters (state IN, warehouse IN, ref) work on PG', () async {
    await store.create(kind: 'transfer', state: 'requested', warehouseId: 7, toWarehouseId: 8, createdBy: 1, deviceId: 'd', gid: 'pg-transfer-1');
    final r = await store.list(kind: 'transfer', states: ['requested', 'approved'], warehouseIds: [8]);
    expect(r.map((x) => x.gid), contains('pg-transfer-1'));
    expect(await store.list(kind: 'transfer', warehouseIds: <int>[]), isEmpty);
  });
}
