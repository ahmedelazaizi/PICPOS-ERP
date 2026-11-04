// S-03 — POST /api/sales enforces price / discount policy on the SERVER.
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
  late int warehouseId;
  var seq = 0;

  Future<void> grant(String code) async {
    final perm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(code)))
        .getSingle();
    await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: cashierRoleId, permissionId: perm.id));
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    AuditLog.configure(ActivityLogger(db));
    cashierRoleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    cashierId = await db.createUser(
        username: 's03_cashier',
        password: 'pw123456',
        displayName: 'S03',
        roleId: cashierRoleId);
    await grant(PermissionCodes.salesCreate);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'S03-P',
      name: 'S03 item',
      salePrice: const Value(100.0),
      costPrice: const Value(60.0),
      currentStock: const Value(1000),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'purchase',
      unitCost: 60,
    );
    handler = ApiSalesHandler(db, {});
  });

  tearDown(() async => db.close());

  Future<Response> post({
    required int userId,
    double price = 100,
    double lineDiscountPercent = 0,
    String saleType = 'default',
    int? originalInvoiceId,
  }) {
    final discount = price * lineDiscountPercent / 100;
    final n = ++seq;
    return handler.postSale(Request(
      'POST',
      Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': 'S03-$n',
        'globalId': 's03-gid-$n',
        'subtotal': price,
        'discount': discount,
        'tax': 0.0,
        'total': price - discount,
        'paid': price - discount,
        'paymentMethod': 'cash',
        'saleType': saleType,
        'originalInvoiceId': ?originalInvoiceId,
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [
          {
            'productId': productId,
            'quantity': 1.0,
            'unitPrice': price,
            'discount': lineDiscountPercent,
            'total': price - discount,
            'costPrice': 60.0,
          },
        ],
      }),
      headers: {'Content-Type': 'application/json'},
      context: {ApiUserCtx.userIdKey: userId},
    ));
  }

  Future<int> invoiceCount() async =>
      (await db.select(db.salesInvoices).get()).length;

  test('cashier: catalog price + discount within cap → 200 and saved', () async {
    final r = await post(userId: cashierId, lineDiscountPercent: 10);
    expect(r.statusCode, 200, reason: await r.readAsString());
    expect(await invoiceCount(), 1);
  });

  test('cashier: discount above cap → 403, nothing saved, critical audit',
      () async {
    final r = await post(userId: cashierId, lineDiscountPercent: 40);
    expect(r.statusCode, 403);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    expect(body['code'], 'price_discount_policy_violation');
    expect(body['error'], contains('الحد'));
    expect(await invoiceCount(), 0);

    final logs = await (db.select(db.activityLogs)
          ..where((l) => l.action.equals('sale_price_discount_rejected')))
        .get();
    expect(logs, hasLength(1));
    expect(logs.single.userId, cashierId);
    expect(logs.single.newValue, contains('"level":"critical"'));
  });

  test('cashier: price below cost → 403; holder of pos_price_edit passes',
      () async {
    final r = await post(userId: cashierId, price: 30);
    expect(r.statusCode, 403);
    expect(await invoiceCount(), 0);

    await grant(PermissionCodes.posPriceEdit);
    final ok = await post(userId: cashierId, price: 30);
    expect(ok.statusCode, 200, reason: await ok.readAsString());
  });

  test('system admin at catalog price and ordinary discount passes', () async {
    final r = await post(userId: 1, lineDiscountPercent: 5);
    expect(r.statusCode, 200, reason: await r.readAsString());
  });

  test('return without invoice at an off-catalog price → 403 without '
      'pos_return_price_edit', () async {
    final r = await post(userId: cashierId, price: 500, saleType: 'return');
    expect(r.statusCode, 403);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final kinds = [
      for (final v in body['violations'] as List)
        (v as Map<String, dynamic>)['kind']
    ];
    expect(kinds, ['returnPriceNotCatalog']);
    expect(await invoiceCount(), 0);

    // pos_price_edit alone is not a substitute.
    await grant(PermissionCodes.posPriceEdit);
    expect((await post(userId: cashierId, price: 500, saleType: 'return'))
        .statusCode, 403);

    // …while the dedicated permission clears the guard.
    await grant(PermissionCodes.posReturnPriceEdit);
    final ok = await post(userId: cashierId, price: 500, saleType: 'return');
    expect(ok.statusCode, isNot(403), reason: await ok.readAsString());
  });
}
