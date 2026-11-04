// S-03 (part 2) — POST /api/sales/return and /api/sales/exchange enforce the
// price / quantity policy on the SERVER (not only in the UI).
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/activity_logger.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/audit_log.dart';

void main() {
  late AppDatabase db;
  late ApiSalesHandler handler;
  late int cashierId;
  late int cashierRoleId;
  late int productId;
  late int otherProductId;
  late int warehouseId;
  late int originalId;
  var seq = 0;

  Future<void> grant(String code) async {
    final perm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(code)))
        .getSingle();
    await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: cashierRoleId, permissionId: perm.id));
  }

  setUp(() async {
    seq = 0;
    db = AppDatabase.forTesting();
    AuditLog.configure(ActivityLogger(db));
    cashierRoleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    cashierId = await db.createUser(
        username: 's03b_cashier',
        password: 'pw123456',
        displayName: 'S03b',
        roleId: cashierRoleId);
    await grant(PermissionCodes.salesCreate);
    await grant(PermissionCodes.salesReturnCreate);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    Future<int> product(String code) async {
      final id = await db.insertProduct(ProductsCompanion.insert(
        code: code,
        name: code,
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(1000),
        trackInventory: const Value(true),
      ));
      await db.adjustStock(
          productId: id,
          warehouseId: warehouseId,
          quantity: 1000,
          type: 'purchase',
          unitCost: 60);
      return id;
    }

    productId = await product('S03B-P');
    otherProductId = await product('S03B-Q');
    // Original sale: 10 × 100 with a 100 invoice-level discount carried on the
    // line (the UI keeps the price and freezes the discount on the line).
    originalId = await db.createSalesInvoice(
      invoiceNumber: 'S03B-ORIG',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: 1000,
      discount: 100,
      tax: 0,
      total: 900,
      paid: 900,
      paymentMethod: 'cash',
      globalId: 's03b-orig-gid',
      items: [
        SalesInvoiceItemsCompanion(
          productId: Value(productId),
          quantity: const Value(10),
          unitPrice: const Value(100),
          discount: const Value(100),
          total: const Value(900),
          costPrice: const Value(60),
        ),
      ],
    );
    handler = ApiSalesHandler(db, {});
  });

  tearDown(() async => db.close());

  Request req(String path, Map<String, dynamic> body, int userId) => Request(
        'POST',
        Uri.parse('http://localhost/api/sales/$path'),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: userId},
      );

  Map<String, dynamic> item(int pid, double qty, double price,
          {double discount = 0}) =>
      {
        'productId': pid,
        'quantity': qty,
        'unitPrice': price,
        'discount': discount,
        'total': qty * price - discount,
        'costPrice': 60.0,
      };

  Future<Response> postReturn({
    int? userId,
    int? pid,
    double qty = 1,
    double price = 100,
    bool withInvoice = true,
  }) {
    final n = ++seq;
    return handler.postSalesReturn(req(
        'return',
        {
          'globalId': 's03b-ret-$n',
          'invoiceNumber': 'S03B-R$n',
          if (withInvoice) 'originalInvoiceId': originalId,
          'subtotal': qty * price,
          'discount': 0,
          'tax': 0,
          'total': qty * price,
          'paid': 0,
          'paymentMethod': 'cash',
          'warehouseId': warehouseId,
          'userId': userId ?? cashierId,
          'items': [item(pid ?? productId, qty, price, discount: 0)],
        },
        userId ?? cashierId));
  }

  Future<Response> postExchange({
    double retQty = 1,
    double retPrice = 100,
    double salePrice = 100,
    double saleDiscountPercent = 0,
  }) {
    final n = ++seq;
    final disc = salePrice * saleDiscountPercent / 100;
    return handler.postSalesExchange(req(
        'exchange',
        {
          'exchangeKey': 's03b-ex-$n',
          'originalInvoiceId': originalId,
          'isFullReturn': false,
          'returnLegs': [
            {
              'globalId': 's03b-exr-$n',
              'invoiceNumber': 'S03B-XR$n',
              'warehouseId': warehouseId,
              'userId': cashierId,
              'subtotal': retQty * retPrice,
              'total': retQty * retPrice,
              'paid': 0,
              'items': [item(productId, retQty, retPrice)],
            }
          ],
          'sale': {
            'globalId': 's03b-exs-$n',
            'invoiceNumber': 'S03B-XS$n',
            'warehouseId': warehouseId,
            'userId': cashierId,
            'subtotal': salePrice,
            'discount': disc,
            'total': salePrice - disc,
            'paid': salePrice - disc,
            'paymentMethod': 'cash',
            'items': [
              item(otherProductId, 1, salePrice, discount: saleDiscountPercent)
            ],
          },
        },
        cashierId));
  }

  Future<int> invoiceCount() async =>
      (await db.select(db.salesInvoices).get()).length;

  Future<List<String>> kinds(Response r) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    expect(body['code'], 'price_discount_policy_violation');
    return [
      for (final v in body['violations'] as List)
        (v as Map<String, dynamic>)['kind'] as String
    ];
  }

  group('return', () {
    test('at the original price (line discount carried) → 200', () async {
      final before = await invoiceCount();
      final r = await postReturn(qty: 3);
      expect(r.statusCode, 200, reason: await r.readAsString());
      expect(await invoiceCount(), before + 1);
    });

    test('price above the original sale price → 403, audit critical; '
        'pos_return_price_edit clears it', () async {
      final before = await invoiceCount();
      final r = await postReturn(price: 150);
      expect(r.statusCode, 403);
      expect(await kinds(r), ['returnPriceOverOriginal']);
      expect(await invoiceCount(), before);
      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('sale_price_discount_rejected')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.newValue, contains('"level":"critical"'));

      await grant(PermissionCodes.posReturnPriceEdit);
      final ok = await postReturn(price: 150);
      expect(ok.statusCode, 200, reason: await ok.readAsString());
    });

    test('quantity beyond what is left → 403 even with pos_return_price_edit',
        () async {
      await grant(PermissionCodes.posReturnPriceEdit);
      expect((await postReturn(qty: 8)).statusCode, 200);
      final before = await invoiceCount();
      final r = await postReturn(qty: 3); // only 2 left
      expect(r.statusCode, 403);
      expect(await kinds(r), ['returnQtyOverRemaining']);
      expect(await invoiceCount(), before);
      // exactly what is left still passes
      expect((await postReturn(qty: 2)).statusCode, 200);
    });

    test('product that is not on the original invoice → 403', () async {
      final r = await postReturn(pid: otherProductId);
      expect(r.statusCode, 403);
      expect(await kinds(r), ['returnProductNotOnInvoice']);
    });

    test('without an invoice: off-catalog price needs pos_return_price_edit',
        () async {
      final ok = await postReturn(withInvoice: false, price: 100);
      expect(ok.statusCode, 200, reason: await ok.readAsString());

      final r = await postReturn(withInvoice: false, price: 500);
      expect(r.statusCode, 403);
      expect(await kinds(r), ['returnPriceNotCatalog']);

      await grant(PermissionCodes.posReturnPriceEdit);
      final ok2 = await postReturn(withInvoice: false, price: 500);
      expect(ok2.statusCode, 200, reason: await ok2.readAsString());
    });
  });

  group('exchange', () {
    test('return at original price + sale at catalog price → 200', () async {
      final r = await postExchange(retQty: 2);
      expect(r.statusCode, 200, reason: await r.readAsString());
      expect(await invoiceCount(), 3); // original + return leg + sale
    });

    test('new sale line below cost → 403 and nothing is written; '
        'pos_price_edit clears it', () async {
      final r = await postExchange(salePrice: 30);
      expect(r.statusCode, 403);
      expect(await kinds(r), ['priceBelowCost']);
      expect(await invoiceCount(), 1);

      await grant(PermissionCodes.posPriceEdit);
      final ok = await postExchange(salePrice: 30);
      expect(ok.statusCode, 200, reason: await ok.readAsString());
    });

    test('new sale discount above the cap → 403, nothing written', () async {
      final r = await postExchange(saleDiscountPercent: 40);
      expect(r.statusCode, 403);
      expect(await kinds(r), contains('lineDiscountOverCap'));
      expect(await invoiceCount(), 1);
    });

    test('return leg above the sold price or the remaining quantity → 403',
        () async {
      final price = await postExchange(retPrice: 150);
      expect(price.statusCode, 403);
      expect(await kinds(price), ['returnPriceOverOriginal']);

      final qty = await postExchange(retQty: 11);
      expect(qty.statusCode, 403);
      expect(await kinds(qty), ['returnQtyOverRemaining']);
      expect(await invoiceCount(), 1);
    });
  });
}
