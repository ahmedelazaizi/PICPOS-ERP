// WH-021 through a REAL host and a REAL client peer (fleet harness, real HTTP):
// a phone receipt raises `purchase_order_items.received_quantity` ON THE HOST
// (authoritative, WH-001). The client desktop must SEE it after its normal delta
// pull - without a Drift table change - and must not offer for «pull PO» an
// order that already has warehouse receipts (the host would refuse it).
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/repositories/purchase_orders_repository_impl.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_stock_guard.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  late int productId, supplierId, whId;

  setUp(() async {
    fleet = await Fleet.startMain();
    await fleet.useMain();
    final db = fleet.main.db;
    whId = (await db.select(db.warehouses).get()).first.id;
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(name: 'Supp', isSupplier: const Value(true)));
    productId = await db.insertProduct(ProductsCompanion.insert(
        code: 'RICE', name: 'Rice', salePrice: const Value(20.0), costPrice: const Value(10), trackInventory: const Value(true)));
    expect((await fleet.installClient(fleet.accountant, 'accountant', kAcctPw)).ok, isTrue, reason: '${fleet.accountant.report}');
  });
  tearDown(() => fleet.dispose());

  Future<int> hostPo(double qty) async {
    await fleet.useMain();
    final db = fleet.main.db;
    final id = await db.createPurchaseOrder(
      supplierId: supplierId,
      warehouseId: whId,
      orderDate: DateTime(2026, 9, 1),
      items: [PurchaseOrderItemsCompanion.insert(orderId: 0, productId: productId, quantity: qty, unitCost: 40, total: 40 * qty)],
    );
    await db.updatePurchaseOrderStatus(id, 'confirmed');
    return id;
  }

  Future<void> pull() async {
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    await fleet.deltaPull(fleet.accountant, ['parties', 'products', 'purchase_orders', 'purchase_order_items']);
  }

  Future<double> clientReceived(String orderGid) async {
    final cdb = fleet.accountant.db;
    final o = (await cdb.select(cdb.purchaseOrders).get()).firstWhere((p) => p.globalId == orderGid);
    return (await cdb.getPurchaseOrderItems(o.id)).single.receivedQuantity;
  }

  /// What the phone's receipt submit does on the host (the production primitive).
  Future<void> phoneReceives(int po, double qty) async {
    // the delta pull's checkpoint has a one-second resolution: a real receipt happens later than the pull
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await fleet.useMain();
    final db = fleet.main.db;
    final item = (await db.getPurchaseOrderItems(po)).single;
    expect(await addReceivedQuantity(db, item.id, qty, item.quantity), isTrue);
  }

  test('a partial phone receipt reaches the client by its next delta pull: received quantity is exact', () async {
    final po = await hostPo(12);
    final gid = (await fleet.main.db.getPurchaseOrderById(po))!.globalId!;
    await pull();
    expect(await clientReceived(gid), 0);

    await phoneReceives(po, 6);
    await pull();
    expect(await clientReceived(gid), 6, reason: 'the client sees the host receipt after its delta pull');

    await phoneReceives(po, 4);
    await pull();
    expect(await clientReceived(gid), 10);
  });

  test('«pull PO» on the client offers only orders WITHOUT warehouse receipts; the host stays authoritative', () async {
    final partial = await hostPo(12);
    final untouched = await hostPo(5);
    final db = fleet.main.db;
    final partialGid = (await db.getPurchaseOrderById(partial))!.globalId!;
    final untouchedGid = (await db.getPurchaseOrderById(untouched))!.globalId!;
    await phoneReceives(partial, 6);
    await pull();

    await fleet.use(fleet.accountant);
    final repo = PurchaseOrdersRepositoryImpl(fleet.accountant.db);
    final cdb = fleet.accountant.db;
    final withReceipts = await repo.orderIdsWithReceipts();
    final localPartial = (await cdb.select(cdb.purchaseOrders).get()).firstWhere((p) => p.globalId == partialGid).id;
    final localUntouched = (await cdb.select(cdb.purchaseOrders).get()).firstWhere((p) => p.globalId == untouchedGid).id;
    expect(withReceipts, {localPartial}, reason: 'only the partially received order is excluded');
    expect(withReceipts.contains(localUntouched), isFalse);
    expect((await cdb.getPurchaseOrderItems(localPartial)).single.receivedQuantity, 6);
  });
}
