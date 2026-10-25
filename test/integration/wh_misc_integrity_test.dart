// WH-026 (two lines of one product in an order) and WH-027 (the approvals inbox
// shows only what the caller may really approve).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
  });
  tearDown(() => h.dispose());

  test('WH-026: two lines of the same product are received separately, by poItemId', () async {
    final supplier = await h.db.into(h.db.parties).insert(PartiesCompanion.insert(name: 'S', isSupplier: const Value(true)));
    final po = await h.db.createPurchaseOrder(
      supplierId: supplier,
      warehouseId: h.a1,
      orderDate: DateTime(2026, 9, 1),
      items: [
        PurchaseOrderItemsCompanion.insert(orderId: 0, productId: rice, quantity: 5, unitCost: 40, total: 200),
        PurchaseOrderItemsCompanion.insert(orderId: 0, productId: rice, quantity: 5, unitCost: 50, total: 250),
      ],
    );
    await h.db.updatePurchaseOrderStatus(po, 'confirmed');
    final items = await h.db.getPurchaseOrderItems(po);

    final d = await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: {
      'globalId': 'doc-00000001',
      'lines': [
        {'lineGlobalId': 'line-0001-a', 'productId': rice, 'quantity': '5', 'poItemId': items[0].id},
        {'lineGlobalId': 'line-0002-a', 'productId': rice, 'quantity': '5', 'poItemId': items[1].id},
      ],
    });
    expect(d.status, 200, reason: d.text);
    final s = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
    expect(s.status, 200, reason: 'no false over_receipt: ${s.text}');
    final after = await h.db.getPurchaseOrderItems(po);
    expect(after.map((i) => i.receivedQuantity), [5, 5]);

    final c = await h.call('POST', '/api/m1/wh/receipts/doc-00000001/convert', user: h.admin);
    expect(c.status, 200, reason: c.text);
    final inv = (await h.db.select(h.db.purchaseInvoices).get()).single;
    expect(inv.total, closeTo(5 * 40 + 5 * 50, 0.01), reason: 'each line is costed at its own price');
  });

  test('WH-026: a poItemId that is not of that product is refused', () async {
    final other = await h.product('OTHER');
    final po = await h.purchaseOrder(h.a1, {rice: 5, other: 5}, status: 'confirmed');
    final items = await h.db.getPurchaseOrderItems(po);
    final riceLine = items.firstWhere((i) => i.productId == rice);
    final r = await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: {
      'globalId': 'doc-00000001',
      'lines': [
        {'lineGlobalId': 'line-0001-a', 'productId': other, 'quantity': '1', 'poItemId': riceLine.id},
      ],
    });
    expect(r.status, 422);
    expect(r.error, 'product_not_in_order');
  });

  test('WH-027: a transfer request into my warehouse is not offered for approval unless the SOURCE is mine', () async {
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
    // A supervisor who only has the DESTINATION warehouse (a2).
    final role = await (h.db.select(h.db.roles)..where((r) => r.name.equals(kWarehouseSupervisorRole))).getSingle();
    final destOnly = await h.db.into(h.db.users).insert(
        UsersCompanion.insert(username: 'dest', passwordHash: 'x', displayName: 'D', roleId: Value(role.id)));
    await h.db.into(h.db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: destOnly, branchId: h.branchA));
    await h.db.into(h.db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: destOnly, warehouseId: h.a2));

    final req = await h.call('POST', '/api/m1/wh/transfers', user: h.keeper, body: {
      'globalId': 'transfer-0001',
      'fromWarehouseId': h.a1,
      'toWarehouseId': h.a2,
      'lines': [
        {'lineGlobalId': 'tline-0001', 'productId': rice, 'quantity': '1'},
      ],
    });
    expect(req.status, 200, reason: req.text);

    final mine = await h.call('GET', '/api/m1/wh/approvals', user: h.supervisor);
    expect((mine.json['approvals'] as List).map((a) => (a as Map)['type']), contains('transfer_request'));
    final theirs = await h.call('GET', '/api/m1/wh/approvals', user: destOnly);
    expect((theirs.json['approvals'] as List).where((a) => (a as Map)['type'] == 'transfer_request'), isEmpty,
        reason: 'he would get 403 on approve; the inbox must not offer it');
    final approve = await h.call('POST', '/api/m1/wh/transfers/transfer-0001/approve', user: destOnly);
    expect(approve.status, 403);
  });
}
