// WH-005 / WH-011 / WH-018 (review 2026-10-25): refusals that come from the
// books (closed period, unmapped inventory account) or from the data (duplicate
// document id) must surface as stable 4xx codes - never a bare 500 the phone
// retries forever - and nothing may be half-applied.
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_error_classifier.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
  });
  tearDown(() => h.dispose());

  Future<WhReply> voucher(String gid, {String type = 'damage', String qty = '2', int? user, String? key}) =>
      h.call('POST', '/api/m1/wh/vouchers', user: user ?? h.keeper, key: key, body: {
        'globalId': gid,
        'type': type,
        'warehouseId': h.a1,
        'reason': 'broken',
        'lines': [
          {'lineGlobalId': 'vline-$gid', 'productId': rice, 'quantity': qty},
        ],
      });

  Future<WhReply> approve(String gid) => h.call('POST', '/api/m1/wh/vouchers/$gid/approve', user: h.supervisor);

  Future<String> voucherState(String gid) async =>
      (await h.db.customSelect('SELECT state FROM wh_mobile_docs WHERE global_id = ?',
              variables: [Variable.withString(gid)]).getSingle())
          .data['state'] as String;

  test('a closed accounting period is 409 period_closed, nothing is posted, the voucher stays pending', () async {
    expect((await voucher('voucher-0001')).status, 200);
    final now = DateTime.now();
    await (h.db.update(h.db.accountingPeriods)..where((p) => p.month.equals(now.month) & p.year.equals(now.year)))
        .write(const AccountingPeriodsCompanion(isClosed: Value(true)));

    final r = await approve('voucher-0001');
    expect(r.status, 409, reason: r.text);
    expect(r.error, 'period_closed');
    expect(await h.stock(rice, h.a1), 10, reason: 'the stock move rolled back with the refused entry');
    expect(await voucherState('voucher-0001'), 'pending');
    // The queue behind it is not blocked: another command still works.
    expect((await voucher('voucher-0002', type: 'in', qty: '1')).status, 200);
  });

  test('an unmapped inventory account is 409 accounts_not_mapped (not 500)', () async {
    expect((await voucher('voucher-0001')).status, 200);
    await (h.db.delete(h.db.accountMappings)..where((m) => m.purpose.equals('inventory'))).go();
    await (h.db.update(h.db.accounts)..where((a) => a.code.equals('1136'))).write(const AccountsCompanion(code: Value('X1136')));
    final r = await approve('voucher-0001');
    expect(r.status, 409, reason: r.text);
    expect(r.error, 'accounts_not_mapped');
    expect(await h.stock(rice, h.a1), 10);
  });

  test('re-creating a document under another command id but the same document id is 409 duplicate_document', () async {
    expect((await voucher('voucher-0001')).status, 200);
    final again = await voucher('voucher-0001');
    expect(again.status, 409, reason: again.text);
    expect(again.error, 'duplicate_document');
  });

  test('a line id that belongs to ANOTHER document is 409 doc_mismatch and leaves no empty document (double tap)', () async {
    expect((await voucher('voucher-0001')).status, 200);
    final second = await h.call('POST', '/api/m1/wh/vouchers', user: h.keeper, body: {
      'globalId': 'voucher-0002',
      'type': 'damage',
      'warehouseId': h.a1,
      'reason': 'broken',
      'lines': [
        {'lineGlobalId': 'vline-voucher-0001', 'productId': rice, 'quantity': '2'},
      ],
    });
    expect(second.status, 409, reason: second.text);
    expect(second.error, 'doc_mismatch');
    final docs = await h.db.customSelect("SELECT global_id FROM wh_mobile_docs WHERE kind = 'voucher'").get();
    expect(docs.map((d) => d.data['global_id']), ['voucher-0001'], reason: 'no empty second document');
  });

  test('every state change is written to the activity log with user and device (WH-018)', () async {
    await voucher('voucher-0001');
    await approve('voucher-0001');
    final rows = await (h.db.select(h.db.activityLogs)..where((l) => l.entityType.equals('wh_mobile_doc'))).get();
    expect(rows.map((r) => r.action), containsAll(['wh_voucher:create', 'wh_voucher:approve']));
    expect(rows.every((r) => r.deviceInfo == 'wh-A'), isTrue);
    expect(rows.map((r) => r.userId), containsAll([h.keeper, h.supervisor]));
  });

  test('classifier: transient lock is 503 busy, unknown is 500 internal, known WhError passes through', () {
    expect(classifyWhFailure(Exception('database is locked')).status, 503);
    expect(classifyWhFailure(Exception('boom')).code, 'internal');
    expect(classifyWhFailure(Exception('boom')).status, 500);
    expect(classifyWhFailure(Exception('SqliteException: UNIQUE constraint failed: x')).code, 'duplicate_document');
  });
}
