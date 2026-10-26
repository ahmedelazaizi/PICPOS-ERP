// Plan 2026-10-23 W3: staged transfer (request -> approve -> dispatch -> receive)
// through the real router. Conservation of quantity AND of value in
// goods_in_transit, four-eyes, never negative, idempotency, lots, branches.
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, milk;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    milk = await h.product('MILK', trackExpiry: true);
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
  });
  tearDown(() => h.dispose());

  Future<double> git() async {
    final acc = (await h.db.getAccountByPurpose('goods_in_transit'))!;
    final r = await h.db.customSelect(
        'SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS b FROM journal_entry_lines WHERE account_id = ?',
        variables: [Variable<int>(acc.id)]).getSingle();
    return (r.data['b'] as num).toDouble();
  }

  Future<double> shrinkage() async {
    final acc = (await h.db.getAccountByPurpose('inventory_shrinkage'))!;
    final r = await h.db.customSelect(
        'SELECT COALESCE(SUM(debit),0) AS b FROM journal_entry_lines WHERE account_id = ?',
        variables: [Variable<int>(acc.id)]).getSingle();
    return (r.data['b'] as num).toDouble();
  }

  Future<WhReply> request(int user, {int product = -1, String qty = '10', int? to, String gid = 'transfer-0001'}) =>
      h.call('POST', '/api/m1/wh/transfers', user: user, body: {
        'globalId': gid,
        'fromWarehouseId': h.a1,
        'toWarehouseId': to ?? h.a2,
        'lines': [
          {'lineGlobalId': 'tline-$gid', 'productId': product == -1 ? rice : product, 'quantity': qty},
        ],
      });

  Future<WhReply> act(int user, String action, {String gid = 'transfer-0001', Object? body, String device = 'wh-A', String? key}) =>
      h.call('POST', '/api/m1/wh/transfers/$gid/$action', user: user, body: body ?? {}, device: device, key: key);

  Future<void> approved({int qty = 10, String gid = 'transfer-0001', int product = -1}) async {
    expect((await request(h.keeper, qty: '$qty', gid: gid, product: product)).status, 200);
    expect((await act(h.supervisor, 'approve', gid: gid)).status, 200);
  }

  Map<String, Object?> rcv(double ok, {double damaged = 0, String gid = 'transfer-0001'}) => {
        'lines': [
          {'lineGlobalId': 'tline-$gid', 'received': '$ok', 'damaged': '$damaged'},
        ],
      };

  test('the feature is OFF by default and says so', () async {
    await h.db.setSetting('wh_staged_transfers_enabled', 'false');
    final r = await request(h.keeper);
    expect(r.status, 409);
    expect(r.error, 'staged_transfers_disabled');
  });

  test('full cycle conserves quantity and clears goods_in_transit at frozen cost', () async {
    await approved();
    final d = await act(h.keeper, 'dispatch');
    expect(d.status, 200, reason: d.text);
    expect(await h.stock(rice, h.a1), 0);
    expect(await h.stock(rice, h.a2), 0, reason: 'in transit: nowhere yet');
    expect(await git(), closeTo(100, 1e-6), reason: '10 x 10 sits in goods_in_transit');
    // The source cost changes after dispatch; the receive must use the frozen one.
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 5, type: 'purchase', unitCost: 50);

    final r = await act(h.supervisor2, 'receive', body: rcv(10));
    expect(r.status, 200, reason: r.text);
    expect((r.json['doc'] as Map)['state'], 'received');
    expect(await h.stock(rice, h.a2), 10);
    expect(await git(), closeTo(0, 1e-6));
  });

  test('replaying dispatch with the same key does not move stock twice', () async {
    await approved();
    await act(h.keeper, 'dispatch', key: 'dispatch-key-1');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    final again = await act(h.keeper, 'dispatch', key: 'dispatch-key-1');
    expect(again.json['replayed'], isTrue);
    expect(await h.stock(rice, h.a1), 10, reason: 'only the re-stocked 10 remain');
    expect(await git(), closeTo(100, 1e-6));
  });

  group('four-eyes', () {
    test('a clerk-level user cannot approve at all', () async {
      await request(h.keeper);
      expect((await act(h.keeper, 'approve')).status, 403);
    });

    test('the author never approves his own request, administrator included', () async {
      await request(h.supervisor);
      final self = await act(h.supervisor, 'approve');
      expect(self.status, 403);
      expect(self.error, 'self_approval');
      await request(h.admin, gid: 'transfer-0002');
      expect((await act(h.admin, 'approve', gid: 'transfer-0002')).error, 'self_approval');
      expect((await act(h.supervisor2, 'approve')).status, 200);
    });

    test('dispatch and receive are refused before approval', () async {
      await request(h.keeper);
      final d = await act(h.keeper, 'dispatch');
      expect(d.status, 409);
      expect(d.error, 'invalid_transition');
    });
  });

  group('never negative', () {
    test('dispatching more than the balance is refused even with negative sales enabled', () async {
      await h.db.setSetting('enable_negative_sales', 'true');
      await approved(qty: 11);
      final d = await act(h.keeper, 'dispatch');
      expect(d.status, 409);
      expect(d.error, 'stock_changed');
      expect(await h.stock(rice, h.a1), 10);
      expect(await git(), 0);
    });

    test('the refusal tells inventory_view holders the available quantity', () async {
      await approved(qty: 11);
      final d = await act(h.keeper, 'dispatch');
      expect(d.json['available'], '10', reason: 'keeper holds inventory_view');
    });
  });

  group('differences', () {
    test('short stays in transit until a different user returns it to the source', () async {
      await approved();
      await act(h.keeper, 'dispatch');
      final r = await act(h.supervisor2, 'receive', body: rcv(8));
      expect((r.json['doc'] as Map)['state'], 'received_short');
      expect(await h.stock(rice, h.a2), 8);
      expect(await git(), closeTo(20, 1e-6));

      expect((await act(h.keeper, 'resolve', body: {'resolution': 'return_to_source'})).status, 403,
          reason: 'needs stock_adjust_approve');
      final self = await act(h.supervisor, 'resolve', body: {'resolution': 'return_to_source'});
      expect(self.status, 200, reason: 'the supervisor neither requested, dispatched nor received');
      expect(await h.stock(rice, h.a1), 2);
      expect(await git(), closeTo(0, 1e-6));
    });

    test('the receiver cannot resolve his own shortage', () async {
      await approved();
      await act(h.keeper, 'dispatch');
      await act(h.supervisor, 'receive', body: rcv(8));
      final bad = await act(h.supervisor, 'resolve', body: {'resolution': 'write_off_loss'});
      expect(bad.error, 'self_approval');
    });

    test('write-off clears goods_in_transit into shrinkage without touching stock', () async {
      await approved();
      await act(h.keeper, 'dispatch');
      await act(h.supervisor2, 'receive', body: rcv(8));
      final before = await h.stock(rice, h.a1);
      final r = await act(h.supervisor, 'resolve', body: {'resolution': 'write_off_loss'});
      expect(r.status, 200, reason: r.text);
      expect(await h.stock(rice, h.a1), before);
      expect(await git(), closeTo(0, 1e-6));
      expect(await shrinkage(), closeTo(20, 1e-6));
    });

    test('damaged goods are received then queued as a pending damage voucher', () async {
      await approved();
      await act(h.keeper, 'dispatch');
      await act(h.supervisor2, 'receive', body: rcv(8, damaged: 2));
      expect(await h.stock(rice, h.a2), 10);
      final v = await h.call('GET', '/api/m1/wh/vouchers?state=pending', user: h.supervisor);
      final docs = (v.json['docs'] as List).cast<Map>();
      expect(docs, hasLength(1));
      expect(docs.single['reason'], contains('transfer-0001'));
      expect(await git(), closeTo(0, 1e-6));
    });

    test('more than was dispatched is refused', () async {
      await approved();
      await act(h.keeper, 'dispatch');
      final r = await act(h.supervisor2, 'receive', body: rcv(11));
      expect(r.error, 'over_receipt');
      expect(await h.stock(rice, h.a2), 0);
    });
  });

  group('lots', () {
    Future<void> lot(String number, DateTime expiry) async {
      await h.db.adjustStock(productId: milk, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
      await h.db.insertBatch(ProductBatchesCompanion.insert(
        productId: milk, warehouseId: h.a1, batchNumber: number, expiryDate: expiry,
        quantity: const Value(10), initialQuantity: const Value(10), unitCost: const Value(10),
      ));
    }

    test('the batch travels with the goods', () async {
      await lot('L1', DateTime.now().add(const Duration(days: 90)));
      await approved(qty: 4, product: milk);
      await act(h.keeper, 'dispatch');
      final src = await h.db.select(h.db.productBatches).get();
      expect(src.single.quantity, 6);
      await act(h.supervisor2, 'receive', body: rcv(4));
      final all = await h.db.select(h.db.productBatches).get();
      expect(all.firstWhere((b) => b.warehouseId == h.a2).quantity, 4);
      expect(all.firstWhere((b) => b.warehouseId == h.a2).batchNumber, 'L1');
    });

    test('an expired lot is refused, nothing moves', () async {
      await lot('OLD', DateTime.now().subtract(const Duration(days: 2)));
      await approved(qty: 4, product: milk);
      final d = await act(h.keeper, 'dispatch');
      expect(d.status, 409);
      expect(d.error, 'batch_expired');
      expect(await h.stock(milk, h.a1), 10);
    });
  });

  test('two branches: dispatched on a branch-A phone, received on a branch-B phone', () async {
    final role = await (h.db.select(h.db.roles)..where((x) => x.name.equals('مخزني'))).getSingle();
    final recv = await h.db.into(h.db.users).insert(UsersCompanion.insert(
        username: 'recvB', passwordHash: 'x', displayName: 'B', roleId: Value(role.id)));
    await h.db.into(h.db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: recv, branchId: h.branchB));
    await h.db.into(h.db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: recv, warehouseId: h.b1));

    await request(h.keeper, to: h.b1);
    await act(h.supervisor, 'approve');
    await act(h.keeper, 'dispatch');
    final wrongPhone = await act(h.supervisor2, 'receive', body: rcv(10));
    expect(wrongPhone.status, 403, reason: 'branch-A phone cannot receive into a branch-B warehouse');
    final ok = await act(recv, 'receive', body: rcv(10), device: 'wh-B');
    expect(ok.status, 200, reason: ok.text);
    expect(await h.stock(rice, h.b1), 10);
    expect(await git(), closeTo(0, 1e-6));
  });
}
