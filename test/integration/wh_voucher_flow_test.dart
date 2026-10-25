// Plan 2026-10-23 W3: stock vouchers (in / out / damage) from the phone.
// Reason mandatory, posted only after a DIFFERENT user approves, never
// negative (even with enable_negative_sales), idempotent, P5 proof honoured.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/approval_proof.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    milk = await h.product('MILK', trackExpiry: true);
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
  });
  tearDown(() => h.dispose());

  Future<WhReply> create(int user, String type, String qty,
          {String gid = 'voucher-0001', String reason = 'count correction', int? product, Map<String, Object?>? extra}) =>
      h.call('POST', '/api/m1/wh/vouchers', user: user, body: {
        'globalId': gid,
        'type': type,
        'warehouseId': h.a1,
        'reason': reason,
        'lines': [
          {'lineGlobalId': 'vline-$gid', 'productId': product ?? rice, 'quantity': qty, ...?extra},
        ],
      });

  Future<WhReply> approve(int user, {String gid = 'voucher-0001', Map<String, String> headers = const {}}) =>
      h.call('POST', '/api/m1/wh/vouchers/$gid/approve', user: user, headers: headers);

  test('a reason is mandatory and the clerk cannot create vouchers', () async {
    expect((await create(h.keeper, 'out', '1', reason: '  ')).error, 'reason_required');
    expect((await create(h.clerk, 'out', '1')).status, 403, reason: 'clerk lacks inventory_edit');
  });

  test('nothing moves while pending; the approval by another user posts it once', () async {
    expect((await create(h.keeper, 'out', '3')).status, 200);
    expect(await h.stock(rice, h.a1), 10);
    final r = await approve(h.supervisor);
    expect(r.status, 200, reason: r.text);
    expect(await h.stock(rice, h.a1), 7);
    expect((await approve(h.supervisor2)).status, 409, reason: 'already posted');
    expect(await h.stock(rice, h.a1), 7);
  });

  test('the author never approves his own voucher', () async {
    await create(h.supervisor, 'out', '3');
    final r = await approve(h.supervisor);
    expect(r.status, 403);
    expect(r.error, 'self_approval');
    expect(await h.stock(rice, h.a1), 10);
  });

  test('a creator without the approval code is refused', () async {
    await create(h.keeper, 'out', '3');
    expect((await approve(h.keeper)).status, 403);
  });

  test('a manager approval proof (P5) lets a keeper-phone carry the approval; self-use is still blocked', () async {
    await create(h.keeper, 'out', '2');
    final proof = ApprovalProof.mint(
        permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: h.manager, deviceId: 'wh-A');
    final ok = await approve(h.keeper, headers: {'x-approval-proof': proof!});
    expect(ok.status, 200, reason: ok.text);
    expect(await h.stock(rice, h.a1), 8);

    await create(h.supervisor, 'out', '2', gid: 'voucher-0002');
    final own = ApprovalProof.mint(
        permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: h.supervisor, deviceId: 'wh-A');
    // The proof's approver IS the voucher's author: refused whoever carries it.
    final self = await h.call('POST', '/api/m1/wh/vouchers/voucher-0002/approve',
        user: h.keeper, headers: {'x-approval-proof': own!});
    expect(self.error, 'self_approval');
    expect(await h.stock(rice, h.a1), 8);
  });

  test('stock never goes negative from a voucher, even with negative sales enabled', () async {
    await h.db.setSetting('enable_negative_sales', 'true');
    await create(h.keeper, 'out', '11');
    final r = await approve(h.supervisor);
    expect(r.status, 409);
    expect(r.error, 'stock_changed');
    expect(r.json['available'], '10');
    expect(await h.stock(rice, h.a1), 10);
  });

  test('damage is journalled through the stock layer; reject leaves stock alone', () async {
    await create(h.keeper, 'damage', '2');
    expect((await approve(h.supervisor)).status, 200);
    expect(await h.stock(rice, h.a1), 8);
    final moves = await h.db.customSelect("SELECT movement_type FROM stock_movements WHERE reference_type = 'wh_voucher'").get();
    expect(moves.single.data['movement_type'], 'damage');

    await create(h.keeper, 'out', '5', gid: 'voucher-0002');
    final rej = await h.call('POST', '/api/m1/wh/vouchers/voucher-0002/reject', user: h.supervisor);
    expect(rej.status, 200);
    expect(await h.stock(rice, h.a1), 8);
  });

  test('an incoming voucher for an expiry-tracked item needs batch and expiry and creates the lot', () async {
    expect((await create(h.keeper, 'in', '5', product: milk)).error, 'batch_required');
    final ok = await create(h.keeper, 'in', '5',
        product: milk, extra: {'batchNumber': 'L9', 'expiryDate': '2030-01-01'});
    expect(ok.status, 200);
    expect((await approve(h.supervisor)).status, 200);
    expect(await h.stock(milk, h.a1), 5);
    expect((await h.db.select(h.db.productBatches).get()).single.batchNumber, 'L9');
  });

  test('a replayed create (same key) answers from the log; a different body under that key conflicts', () async {
    final body = {
      'globalId': 'voucher-0001', 'type': 'out', 'warehouseId': h.a1, 'reason': 'x',
      'lines': [
        {'lineGlobalId': 'vline-1111', 'productId': rice, 'quantity': '1'},
      ],
    };
    expect((await h.call('POST', '/api/m1/wh/vouchers', user: h.keeper, body: body, key: 'voucher-key-1')).status, 200);
    expect((await h.call('POST', '/api/m1/wh/vouchers', user: h.keeper, body: body, key: 'voucher-key-1')).json['replayed'], isTrue);
    final changed = {...body, 'reason': 'y'};
    expect((await h.call('POST', '/api/m1/wh/vouchers', user: h.keeper, body: changed, key: 'voucher-key-1')).error,
        'idempotency_conflict');
  });
}
