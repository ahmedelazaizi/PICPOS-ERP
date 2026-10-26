// WH-001 (critical) through a REAL host and a REAL client peer (fleet harness,
// real HTTP): the purchase-order quantity accounting is authoritative on the
// HOST. A client/mirror "pull PO" or convertPOToInvoice sends the order's global
// id; the host refuses an order with phone receipts, an already consumed order
// and an invoice above the ordered quantity, and consumes a healthy order in the
// invoice's own transaction. Every assertion is on host DB rows / HTTP status.
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/repositories/purchase_orders_repository_impl.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';

import '../helpers/fleet_harness.dart';
import '../helpers/lan_host_harness.dart' show ApiResp;

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  late int productId;
  late int supplierId;
  late int whId;
  setUp(() async {
    fleet = await Fleet.startMain();
    await fleet.useMain();
    final db = fleet.main.db;
    await Fleet.grantPermissions(db, 'محاسب', ['purchases_create']);
    whId = (await db.select(db.warehouses).get()).first.id;
    supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Supp', isSupplier: const Value(true)));
    productId = await db.insertProduct(ProductsCompanion.insert(
        code: 'RICE', name: 'Rice', salePrice: const Value(20.0),
        costPrice: const Value(10), trackInventory: const Value(true)));
    // installed AFTER the seed so the first sync carries supplier + product
    expect((await fleet.installClient(fleet.accountant, 'accountant', kAcctPw)).ok,
        isTrue, reason: '${fleet.accountant.report}');
  });
  tearDown(() => fleet.dispose());

  Future<int> hostPo({double qty = 12}) async {
    await fleet.useMain();
    final db = fleet.main.db;
    final id = await db.createPurchaseOrder(
      supplierId: supplierId,
      warehouseId: whId,
      orderDate: DateTime(2026, 9, 1),
      items: [
        PurchaseOrderItemsCompanion.insert(
            orderId: 0, productId: productId, quantity: qty, unitCost: 40, total: 40 * qty),
      ],
    );
    await db.updatePurchaseOrderStatus(id, 'confirmed');
    return id;
  }

  Future<void> pullToAccountant() async {
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    await fleet.deltaPull(fleet.accountant,
        ['parties', 'products', 'purchase_orders', 'purchase_order_items']);
  }

  Future<double> hostStock() async {
    final db = fleet.main.db;
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(whId)))
        .getSingleOrNull();
    return b?.quantity ?? 0;
  }

  Future<double> hostSupplierBalance() async {
    final db = fleet.main.db;
    return (await (db.select(db.parties)..where((p) => p.id.equals(supplierId))).getSingle()).balance;
  }

  /// Raw `POST /api/purchases` as the accountant device (what the client sends).
  Future<ApiResp> postPurchase(String orderGid, double qty, {String? gid}) async {
    final peer = await fleet.peer(fleet.accountant);
    expect((await peer.login('accountant', kAcctPw)).status, 200);
    final host = fleet.main.db;
    final prod = await (host.select(host.products)..where((p) => p.id.equals(productId))).getSingle();
    return peer.post('/api/purchases', {
      'globalId': gid ?? 'inv-${DateTime.now().microsecondsSinceEpoch}',
      'supplierId': supplierId,
      'warehouseId': whId,
      'paid': 0,
      'paymentMethod': 'credit',
      'sourceOrderGlobalId': orderGid,
      'items': [
        {
          'productId': productId,
          'productGlobalId': prod.globalId,
          'quantity': qty,
          'unitCost': 40,
          'total': qty * 40,
        }
      ],
    });
  }

  test('partial phone receipt, then a client convert / pull-PO: host refuses, '
      'nothing is invoiced, stock and AP unchanged', () async {
    final po = await hostPo();
    final db = fleet.main.db;
    final order = (await db.getPurchaseOrderById(po))!;
    await pullToAccountant(); // the client now holds a copy with received = 0

    // the phone receives 6 of 12 AFTER the client pulled (its copy is stale)
    final item = (await db.getPurchaseOrderItems(po)).single;
    await (db.update(db.purchaseOrderItems)..where((i) => i.id.equals(item.id)))
        .write(const PurchaseOrderItemsCompanion(receivedQuantity: Value(6)));

    final r = await postPurchase(order.globalId!, 12);
    expect(r.status, 409, reason: '$r');
    expect(r.json['error'], 'po_has_receipts');

    // the accountant's own Â«receive and convertÂ» button (convertPOToInvoice)
    await fleet.use(fleet.accountant);
    final localPo = (await fleet.accountant.db.select(fleet.accountant.db.purchaseOrders).get())
        .firstWhere((p) => p.globalId == order.globalId);
    await PurchaseOrdersRepositoryImpl(fleet.accountant.db).convertPOToInvoice(localPo.id);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if ((await fleet.accountant.db.select(fleet.accountant.db.syncOutbox).get()).isNotEmpty) break;
    }

    expect(await db.select(db.purchaseInvoices).get(), isEmpty);
    expect(await hostStock(), 0);
    expect(await hostSupplierBalance(), 0);
    expect((await db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNull);
    expect((await db.getPurchaseOrderItems(po)).single.receivedQuantity, 6);
    expect(
        await fleet.accountant.db.select(fleet.accountant.db.purchaseInvoices).get(), isEmpty,
        reason: 'the client never invoices from its own stale copy');
  });

  test('a healthy order is consumed on the host in the invoice transaction; '
      'amounts exact; a second invoice, a replay-with-new-id and an excess are refused',
      () async {
    final po = await hostPo();
    final db = fleet.main.db;
    final order = (await db.getPurchaseOrderById(po))!;
    await pullToAccountant();
    await fleet.use(fleet.accountant);
    final localPo = (await fleet.accountant.db.select(fleet.accountant.db.purchaseOrders).get())
        .firstWhere((p) => p.globalId == order.globalId);

    await PurchaseOrdersRepositoryImpl(fleet.accountant.db).convertPOToInvoice(localPo.id);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if ((await db.select(db.purchaseInvoices).get()).isNotEmpty) break;
    }
    final invoices = await db.select(db.purchaseInvoices).get();
    expect(invoices, hasLength(1));
    final items = await db.select(db.purchaseInvoiceItems).get();
    expect(items.single.quantity, 12);
    expect(items.single.unitCost, 40);
    expect(await hostStock(), 12);
    expect(await hostSupplierBalance(), 480);
    final consumed = (await db.getPurchaseOrderById(po))!;
    expect(consumed.convertedToInvoiceId, invoices.single.id);
    expect(consumed.status, 'received');
    expect((await db.getPurchaseOrderItems(po)).single.receivedQuantity, 12);

    final again = await postPurchase(order.globalId!, 12);
    expect(again.status, 409, reason: '$again');
    expect(again.json['error'], 'po_already_converted');
    expect(await hostStock(), 12);
    expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
  });

  test('an invoice above the ordered quantity is refused (409 po_over_invoiced)', () async {
    final po = await hostPo();
    final db = fleet.main.db;
    final order = (await db.getPurchaseOrderById(po))!;
    final r = await postPurchase(order.globalId!, 13);
    expect(r.status, 409, reason: '$r');
    expect(r.json['error'], 'po_over_invoiced');
    expect(await hostStock(), 0);
    expect(await db.select(db.purchaseInvoices).get(), isEmpty);
    expect((await db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNull);
  });

  test('pull-PO through ClientWriteInterceptor.submitPurchase carries the order '
      'global id and the host consumes it', () async {
    final po = await hostPo(qty: 5);
    final db = fleet.main.db;
    final order = (await db.getPurchaseOrderById(po))!;
    await pullToAccountant();
    await fleet.use(fleet.accountant);
    final ok = await ClientWriteInterceptor.submitPurchase(
      supplierId: supplierId,
      warehouseId: whId,
      items: [
        {'productId': productId, 'quantity': 5.0, 'unitCost': 40.0, 'total': 200.0}
      ],
      paid: 0,
      paymentMethod: 'credit',
      globalId: 'inv-pull-1',
      userId: fleet.userIds['accountant'],
      sourceOrderGlobalId: order.globalId,
    );
    expect(ok, isTrue);
    expect(await hostStock(), 5);
    expect(await hostSupplierBalance(), 200);
    expect((await db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNotNull);
    expect(jsonEncode(await db.select(db.purchaseInvoices).get().then((r) => r.length)), '1');
  });
}
