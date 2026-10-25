// Plan 2026-10-23 W2-W5: the REAL `WarehouseLanClient` (package
// picpos_api_client) over a real socket to the REAL router + middleware on an
// in-memory database. Pair -> sign in -> receive a PO, replay after the main
// went down, staged transfer between two phones, blind count, approvals.
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';

import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late String base;
  late int branch, a1, a2, rice;
  late WarehouseLanClient clerk, keeper, sup;
  String pw(String user) => 'Wh#$user-Pass12345'; // two equal passwords are refused by the system

  Future<int> user(String name, String role) async {
    final r = await (host.db.select(host.db.roles)..where((x) => x.name.equals(role))).getSingle();
    final id = await host.db.createUser(username: name, password: pw(name), displayName: name, roleId: r.id);
    await host.db.setUserBranchAccess(id, [branch]);
    for (final w in [a1, a2]) {
      await host.db.into(host.db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: id, warehouseId: w));
    }
    return id;
  }

  Future<WarehouseLanClient> phone(String deviceId, String username) async {
    final c = WarehouseLanClient(
      transport: HttpApiTransport(kind: TransportKind.lan, baseUri: Uri.parse(base), policy: UrlPolicy.development),
      headers: const ApiHeaderBuilder(appVersion: 'e2e'),
    );
    final offer = await host.issue(kind: 'warehouse', branchId: branch, fingerprint: 'ab' * 32);
    await c.pair(code: offer.code, deviceId: deviceId, deviceName: deviceId);
    await c.login(username: username, password: pw(username));
    return c;
  }

  setUp(() async {
    host = await LanHost.start();
    base = await host.serve();
    await RoleGrantPreflightService(host.db).grantMissingDefaults();
    await host.db.syncDefaultAccounts();
    branch = (await host.db.select(host.db.branches).get()).first.id;
    a1 = await host.db.into(host.db.warehouses).insert(WarehousesCompanion.insert(name: 'A1', branchId: Value(branch)));
    a2 = await host.db.into(host.db.warehouses).insert(WarehousesCompanion.insert(name: 'A2', branchId: Value(branch)));
    rice = await host.db.insertProduct(ProductsCompanion.insert(
        code: 'RICE', name: 'Rice', barcode: const Value('6221234567890'), costPrice: const Value(10), trackInventory: const Value(true)));
    await user('clerk', kWarehouseClerkRole);
    await user('keeper', 'مخزني');
    await user('sup', kWarehouseSupervisorRole);
    clerk = await phone('phone-clerk', 'clerk');
    keeper = await phone('phone-keeper', 'keeper');
    sup = await phone('phone-sup', 'sup');
  });
  tearDown(() => host.close());

  Future<double> stock(int wh) async =>
      (await (host.db.select(host.db.inventoryBalances)..where((b) => b.productId.equals(rice) & b.warehouseId.equals(wh))).getSingleOrNull())
          ?.quantity ??
      0;

  test('receive a PO; a lost answer is replayed with the same command id and counts once', () async {
    final supplier = await host.db.into(host.db.parties).insert(PartiesCompanion.insert(name: 'S', isSupplier: const Value(true)));
    final po = await host.db.createPurchaseOrder(supplierId: supplier, warehouseId: a1, orderDate: DateTime(2026, 9, 1), items: [
      PurchaseOrderItemsCompanion.insert(orderId: 0, productId: rice, quantity: 10, unitCost: 5, total: 50),
    ]);
    await host.db.updatePurchaseOrderStatus(po, 'sent');

    final order = (await clerk.purchaseOrders()).single;
    expect(order.items.single.ordered, '10');
    final lines = [WhReceiptLineInput(lineGlobalId: 'line-e2e-0001', productId: rice, quantity: '6')];
    await clerk.saveReceiptLines(poRef: order.ref, receiptGlobalId: 'receipt-e2e-0001', lines: lines, commandId: 'cmd-e2e-0001');

    // The main goes down before the answer to "submit" arrives; the phone retries later.
    await host.stopServing();
    await expectLater(clerk.submitReceipt('receipt-e2e-0001', commandId: 'cmd-e2e-0002'), throwsA(isA<ApiError>()));
    base = await host.serve();
    final c2 = WarehouseLanClient(
      transport: HttpApiTransport(kind: TransportKind.lan, baseUri: Uri.parse(base), policy: UrlPolicy.development),
      headers: const ApiHeaderBuilder(appVersion: 'e2e'),
      credentials: clerk.credentials,
    );
    final first = await c2.submitReceipt('receipt-e2e-0001', commandId: 'cmd-e2e-0002');
    final again = await c2.submitReceipt('receipt-e2e-0001', commandId: 'cmd-e2e-0002');
    expect(first.doc!.state, 'submitted');
    expect(again.replayed, isTrue);
    expect((await host.db.getPurchaseOrderItems(po)).single.receivedQuantity, 6);
    expect(await stock(a1), 0, reason: 'a receipt posts nothing until the accountant converts it');
  });

  test('staged transfer across two phones: request -> approve -> dispatch -> receive', () async {
    await host.db.setSetting('wh_staged_transfers_enabled', 'true');
    await host.db.adjustStock(productId: rice, warehouseId: a1, quantity: 10, type: 'purchase', unitCost: 10);
    final req = await keeper.requestTransfer({
      'globalId': 'transfer-e2e-0001', 'fromWarehouseId': a1, 'toWarehouseId': a2,
      'lines': [{'lineGlobalId': 'tline-e2e-0001', 'productId': rice, 'quantity': '4'}],
    }, commandId: 'cmd-transfer-1');
    expect(req.doc!.state, 'requested');

    expect((await sup.approvals()).single.type, 'transfer_request');
    await sup.transferAction('transfer-e2e-0001', 'approve', commandId: 'cmd-transfer-2');
    await keeper.transferAction('transfer-e2e-0001', 'dispatch', commandId: 'cmd-transfer-3');
    expect(await stock(a1), 6);
    final done = await sup.transferAction('transfer-e2e-0001', 'receive', commandId: 'cmd-transfer-4', body: {
      'lines': [{'lineGlobalId': 'tline-e2e-0001', 'received': '4'}],
    });
    expect(done.doc!.state, 'received');
    expect(await stock(a2), 4);
    expect(await stock(a1) + await stock(a2), 10);
  });

  test('blind count: the counter\'s client never receives a quantity; the supervisor reviews', () async {
    await host.db.adjustStock(productId: rice, warehouseId: a1, quantity: 137, type: 'purchase', unitCost: 10);
    final plan = await host.db.into(host.db.cycleCountPlans).insert(CycleCountPlansCompanion.insert(name: 'W', warehouseId: a1));
    await host.db.generateCycleCountTask(planId: plan, warehouseId: a1, productsPerTask: 5);

    final task = (await clerk.countTasks()).single;
    expect(task.items.single.productId, rice);
    final item = (await clerk.itemsByBarcode('6221234567890')).single;
    expect(item.stock.single.blind, isTrue);
    expect(item.stock.single.quantity, isEmpty);

    await clerk.countEntries(task.ref, 'count-e2e-0001', [
      {'lineGlobalId': 'cline-e2e-0001', 'productId': rice, 'quantity': '130'},
    ], commandId: 'cmd-count-1');
    final submitted = await clerk.countSubmit(task.ref, 'count-e2e-0001', commandId: 'cmd-count-2');
    expect(submitted.body.keys.toSet(), {'globalId', 'state'});

    final review = await sup.countReview(task.ref);
    expect(review.rows.single.expected, '137');
    expect(review.rows.single.variance, '-7');
    expect(review.recountNeeded, isTrue);
    await expectLater(keeper.countReview(task.ref), throwsA(isA<ApiError>()), reason: 'a counter cannot review');
  });

  test('a warehouse phone cannot use the legacy stock routes', () async {
    final t = HttpApiTransport(kind: TransportKind.lan, baseUri: Uri.parse(base), policy: UrlPolicy.development);
    final h = const ApiHeaderBuilder(appVersion: 'e2e').build(sup.credentials, idempotencyKey: 'x-legacy-1');
    await expectLater(
      t.send(ApiRequest('POST', '/api/inventory/transfer', headers: h, body: {})),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'device_scope')),
    );
  });
}
