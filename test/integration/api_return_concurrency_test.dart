// Concurrent returns of the same original invoice line must not over-return:
// the "remaining" read and the insert are serialized per original invoice.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/activity_logger.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/api/server_return_exchange_guard.dart';
import 'package:picpos_erp/services/audit_log.dart';

void main() {
  late AppDatabase db;
  late ApiSalesHandler handler;
  late int userId;
  late int roleId;
  late int productId;
  late int otherProductId;
  late int warehouseId;
  late int originalId;
  var seq = 0;

  Future<void> grant(String code) async {
    final perm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(code)))
        .getSingle();
    await db.into(db.rolePermissions).insert(
        RolePermissionsCompanion.insert(roleId: roleId, permissionId: perm.id));
  }

  setUp(() async {
    seq = 0;
    db = AppDatabase.forTesting();
    AuditLog.configure(ActivityLogger(db));
    roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    userId = await db.createUser(
        username: 'conc_cashier',
        password: 'pw123456',
        displayName: 'Conc',
        roleId: roleId);
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

    productId = await product('CONC-P');
    otherProductId = await product('CONC-Q');
    originalId = await db.createSalesInvoice(
      invoiceNumber: 'CONC-ORIG',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: 1000,
      discount: 0,
      tax: 0,
      total: 1000,
      paid: 1000,
      paymentMethod: 'cash',
      globalId: 'conc-orig-gid',
      items: [
        SalesInvoiceItemsCompanion(
          productId: Value(productId),
          quantity: const Value(10),
          unitPrice: const Value(100),
          discount: const Value(0),
          total: const Value(1000),
          costPrice: const Value(60),
        ),
      ],
    );
    handler = ApiSalesHandler(db, {});
  });

  tearDown(() async => db.close());

  Request req(String path, Map<String, dynamic> body) => Request(
        'POST',
        Uri.parse('http://localhost/api/sales/$path'),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: userId},
      );

  Map<String, dynamic> item(int pid, double qty) => {
        'productId': pid,
        'quantity': qty,
        'unitPrice': 100.0,
        'discount': 0.0,
        'total': qty * 100,
        'costPrice': 60.0,
      };

  Future<Response> postReturn(double qty) {
    final n = ++seq;
    return handler.postSalesReturn(req('return', {
      'globalId': 'conc-ret-$n',
      'invoiceNumber': 'CONC-R$n',
      'originalInvoiceId': originalId,
      'subtotal': qty * 100,
      'discount': 0,
      'tax': 0,
      'total': qty * 100,
      'paid': 0,
      'paymentMethod': 'cash',
      'warehouseId': warehouseId,
      'userId': userId,
      'items': [item(productId, qty)],
    }));
  }

  Future<Response> postExchange(double qty) {
    final n = ++seq;
    return handler.postSalesExchange(req('exchange', {
      'exchangeKey': 'conc-ex-$n',
      'originalInvoiceId': originalId,
      'isFullReturn': false,
      'returnLegs': [
        {
          'globalId': 'conc-exr-$n',
          'invoiceNumber': 'CONC-XR$n',
          'warehouseId': warehouseId,
          'userId': userId,
          'subtotal': qty * 100,
          'total': qty * 100,
          'paid': 0,
          'items': [item(productId, qty)],
        }
      ],
      'sale': {
        'globalId': 'conc-exs-$n',
        'invoiceNumber': 'CONC-XS$n',
        'warehouseId': warehouseId,
        'userId': userId,
        'subtotal': 100,
        'discount': 0,
        'total': 100,
        'paid': 100,
        'paymentMethod': 'cash',
        'items': [item(otherProductId, 1)],
      },
    }));
  }

  Future<double> returnedTotal() async {
    final original = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(originalId)))
        .getSingle();
    return (await returnedBaseQtyByProduct(db, original))[productId] ?? 0;
  }

  test('two simultaneous returns of the full remaining qty: one 200, one 403',
      () async {
    final rs = await Future.wait([postReturn(10), postReturn(10)]);
    final codes = rs.map((r) => r.statusCode).toList()..sort();
    expect(codes, [200, 403]);
    final rejected = rs.firstWhere((r) => r.statusCode == 403);
    final body = jsonDecode(await rejected.readAsString()) as Map;
    expect(body['code'], 'price_discount_policy_violation');
    expect('${body['violations']}', contains('returnQtyOverRemaining'));
    expect(await returnedTotal(), lessThanOrEqualTo(10));
  });

  test('five simultaneous partial returns never exceed what was sold',
      () async {
    final rs = await Future.wait([for (var i = 0; i < 5; i++) postReturn(4)]);
    final ok = rs.where((r) => r.statusCode == 200).length;
    expect(ok, 2); // 2 × 4 = 8 ≤ 10, a third would make 12
    expect(rs.where((r) => r.statusCode == 403).length, 3);
    expect(await returnedTotal(), 8);
  });

  test('return racing an exchange on the same line: sum ≤ sold', () async {
    final rs = await Future.wait([postReturn(10), postExchange(10)]);
    final codes = rs.map((r) => r.statusCode).toList()..sort();
    expect(codes, [200, 403]);
    expect(await returnedTotal(), lessThanOrEqualTo(10));
  });

  test('sequential legitimate returns keep their results', () async {
    expect((await postReturn(6)).statusCode, 200);
    expect((await postReturn(4)).statusCode, 200);
    expect((await postReturn(1)).statusCode, 403); // plain over-remaining (unchanged)
    expect(await returnedTotal(), 10);
  });
}
