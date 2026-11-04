import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/activity_logger.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/audit_log.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  late AppDatabase db;
  late ApiSalesHandler api;
  late int userId;
  late int roleId;
  late int productId;
  late int warehouseId;
  var seq = 0;

  Future<void> grant(String code) async {
    final p = await (db.select(db.permissions)..where((x) => x.code.equals(code))).getSingle();
    await db.into(db.rolePermissions).insert(
        RolePermissionsCompanion.insert(roleId: roleId, permissionId: p.id));
  }

  setUp(() async {
    seq = 0;
    StockShortagePolicyService.resetCacheForTest();
    db = AppDatabase.forTesting();
    AuditLog.configure(ActivityLogger(db));
    await db.syncDefaultAccounts();
    roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'audit-api-cashier', isSystemRole: const Value(false)));
    userId = await db.createUser(username: 'audit-api', password: 'pw123456',
        displayName: 'API audit', roleId: roleId);
    await grant(PermissionCodes.salesCreate);
    await grant(PermissionCodes.salesEdit);
    await grant(PermissionCodes.salesReturnCreate);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'SP23-P', name: 'SP23 product',
      salePrice: const Value(10), costPrice: const Value(5),
      trackInventory: const Value(true), allowNegativeSale: const Value(false),
    ));
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 2, type: 'opening_stock', unitCost: 5);
    api = ApiSalesHandler(db, {});
  });

  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await db.close();
  });

  Future<Response> postSale({
    String? number,
    String? gid,
    String? idem,
    double qty = 1,
    double price = 10,
    double cost = 5,
    double discount = 0,
    int? customerId,
    double? paid,
    String paymentMethod = 'cash',
  }) {
    final n = ++seq;
    final invoiceNo = number ?? 'SP23-$n';
    final globalId = gid ?? 'sp23-gid-$n';
    final lineDiscount = qty * price * discount / 100;
    final total = qty * price - lineDiscount;
    return api.postSale(Request('POST', Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': invoiceNo, 'globalId': globalId,
        'subtotal': qty * price, 'discount': lineDiscount, 'tax': 0,
        'total': total, 'paid': paid ?? total, 'paymentMethod': paymentMethod,
        'customerId': customerId,
        'warehouseId': warehouseId, 'userId': userId,
        'items': [{'productId': productId, 'quantity': qty,
          'unitPrice': price, 'discount': discount, 'total': total,
          'costPrice': cost}],
      }),
      headers: {'content-type': 'application/json', 'X-Idempotency-Key': ?idem},
      context: {ApiUserCtx.userIdKey: userId},
    ));
  }

  Future<void> printMetrics(String scenario) async {
    final journals = await db.select(db.journalEntries).get();
    final safeTx = await db.select(db.safeTransactions).get();
    final movements = await db.select(db.stockMovements).get();
    final accounts = await db.select(db.accounts).get();
    final balances = accounts.where((a) => a.balance != 0)
        .map((a) => '${a.code}:${a.balance}').join(',');
    // ignore: avoid_print
    print('[AUDIT-SP23-$scenario] journalEntries=${journals.length} '
        'safe_transactions=${safeTx.length} stock_movements=${movements.length} '
        'accounts.balance=[$balances]');
  }

  test('SP23 API rejects oversell with block policy and returns a client error', () async {
    await db.setSetting('enable_negative_sales', 'false');
    await db.setSetting('stock_shortage_policy', 'block');
    StockShortagePolicyService.resetCacheForTest();
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: -2, type: 'adjustment');
    final response = await postSale(qty: 1);
    final invoices = await db.select(db.salesInvoices).get();
    final stock = (await db.getProductById(productId))!.currentStock;
    // ignore: avoid_print
    print('[AUDIT-SP23-NEG] status=${response.statusCode} invoices=${invoices.length} stock=$stock');
    await printMetrics('NEG');
    final responseBody = await response.readAsString();
    // 422 is deliberately not 409/Conflict: the outbox's duplicate branch
    // folds generic 409 responses into success; this business rejection must
    // retain its row as a visible terminal failure instead.
    expect(response.statusCode, 422, reason: responseBody);
    final rejection = jsonDecode(responseBody) as Map;
    expect(rejection['code'], 'INSUFFICIENT_STOCK');
    expect(rejection['error'], contains('الكمية المتوفرة حالياً'));
    expect(invoices, isEmpty);
    expect(stock, 0);
  });

  test('SP23 API permits oversell when server policy explicitly allows it', () async {
    await db.setSetting('stock_shortage_policy', 'allow_negative');
    StockShortagePolicyService.resetCacheForTest();
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: -2, type: 'adjustment');
    final response = await postSale(qty: 1);
    final balance = await (db.select(db.inventoryBalances)
          ..where((row) => row.productId.equals(productId) & row.warehouseId.equals(warehouseId)))
        .getSingle();
    final responseBody = await response.readAsString();
    await printMetrics('ALLOW-NEG');
    expect(response.statusCode, 200, reason: responseBody);
    expect(balance.quantity, -1);
  });

  test('SP23 server honors zero_cost_policy=block', () async {
    await db.setSetting('zero_cost_policy', 'block');
    final product = await db.getProductById(productId);
    expect(product, isNotNull);
    await db.updateProduct(product!.copyWith(costPrice: 0));
    final response = await postSale(cost: 0);
    final invoices = await db.select(db.salesInvoices).get();
    // ignore: avoid_print
    print('[AUDIT-SP23-ZERO] status=${response.statusCode} invoices=${invoices.length}');
    await printMetrics('ZERO');
    final responseBody = await response.readAsString();
    expect(response.statusCode, 422, reason: responseBody);
    expect((jsonDecode(responseBody) as Map)['code'], 'ZERO_COST_BLOCKED');
    expect(invoices, isEmpty);
  });

  test('SP23 API rejects overpayment before effects; valid partial/full collections post', () async {
    final customerId = await db.insertParty(PartiesCompanion.insert(
      name: 'SP23 customer', isCustomer: const Value(true),
    ));
    final saleResponse = await postSale(
      number: 'SP23-CREDIT', gid: 'sp23-credit', customerId: customerId,
      qty: 2, price: 100, paid: 0, paymentMethod: 'credit',
    );
    final saleBody = jsonDecode(await saleResponse.readAsString()) as Map;
    expect(saleResponse.statusCode, 200);
    final invoiceId = saleBody['serverId'] as int;
    final invoiceNumber = saleBody['invoiceNumber'] as String;
    Future<Response> postCollection(double amount, String gid) => api.postSalesPayment(
      Request('POST', Uri.parse('http://localhost/api/sales/payment'),
        body: jsonEncode({
          'salesId': invoiceId, 'salesGlobalId': 'sp23-credit',
          'invoiceNumber': invoiceNumber, 'amount': amount, 'globalId': gid,
        }),
        headers: {'content-type': 'application/json'},
        context: {ApiUserCtx.userIdKey: userId},
      ),
    );
    final journalsBefore = (await db.select(db.journalEntries).get()).length;
    final safeBefore = (await db.select(db.safeTransactions).get()).length;
    final negative = await postCollection(-50, 'sp23-negative');
    final negativeBody = jsonDecode(await negative.readAsString()) as Map;
    expect(negative.statusCode, 422);
    expect(negativeBody['code'], 'PAYMENT_NOT_POSITIVE');
    expect(negativeBody['error'], contains('أكبر من صفر'));
    final over = await postCollection(250, 'sp23-over');
    final overBody = jsonDecode(await over.readAsString()) as Map;
    expect(over.statusCode, 422);
    expect(overBody['code'], 'PAYMENT_EXCEEDS_REMAINING');
    expect(overBody['error'], contains('مبلغ التحصيل يتجاوز المتبقي'));
    expect((await db.getSalesInvoiceById(invoiceId))!.paid, 0);
    expect((await db.select(db.journalEntries).get()).length, journalsBefore);
    expect((await db.select(db.safeTransactions).get()).length, safeBefore);

    final partial = await postCollection(100, 'sp23-partial');
    expect(partial.statusCode, 200, reason: await partial.readAsString());
    expect((await db.getSalesInvoiceById(invoiceId))!.paid, 100);
    final finalPayment = await postCollection(100, 'sp23-full');
    expect(finalPayment.statusCode, 200, reason: await finalPayment.readAsString());
    expect((await db.getSalesInvoiceById(invoiceId))!.paid, 200);
  });

  test('SP23 server rejects cumulative return beyond sold quantity', skip: _skip, () async {
    final saleResponse = await postSale(number: 'SP23-ORIG', gid: 'sp23-orig', qty: 1);
    final saleResponseBody = await saleResponse.readAsString();
    expect(saleResponse.statusCode, 200, reason: saleResponseBody);
    final saleBody = jsonDecode(saleResponseBody) as Map;
    final originalId = saleBody['serverId'] as int;
    Future<Response> postReturn(String gid) => api.postSalesReturn(Request(
      'POST', Uri.parse('http://localhost/api/sales/return'),
      body: jsonEncode({
        'globalId': gid, 'invoiceNumber': 'SP23-R-$gid',
        'originalInvoiceId': originalId, 'subtotal': 10, 'total': 10,
        'paid': 0, 'paymentMethod': 'cash', 'warehouseId': warehouseId,
        'userId': userId,
        'items': [{'productId': productId, 'quantity': 1, 'unitPrice': 10,
          'discount': 0, 'total': 10, 'costPrice': 5}],
      }),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: userId},
    ));
    final first = await postReturn('sp23-ret-1');
    final second = await postReturn('sp23-ret-2');
    final returns = (await db.select(db.salesInvoices).get()).where((x) => x.saleType == 'return').length;
    // ignore: avoid_print
    print('[AUDIT-SP23-RET] status=${first.statusCode}/${second.statusCode} returns=$returns');
    expect(first.statusCode, 200, reason: await first.readAsString());
    expect(second.statusCode, 403, reason: await second.readAsString());
    expect(returns, 1);
    await printMetrics('RET');
  });

  test('SP23 server rejects below-cost price and excessive discount',
      skip: _skip, () async {
    final belowCost = await postSale(price: 3);
    final excessiveDiscount = await postSale(discount: 40);
    expect(belowCost.statusCode, 403, reason: await belowCost.readAsString());
    expect(excessiveDiscount.statusCode, 403, reason: await excessiveDiscount.readAsString());
    expect(await db.select(db.salesInvoices).get(), isEmpty);
    // ignore: avoid_print
    print('[AUDIT-SP23-PRICE] belowCost=${belowCost.statusCode} '
        'discount40pct=${excessiveDiscount.statusCode} invoices=0');
    await printMetrics('PRICE');
  });

  test('SP23 API idempotency key persists one sale on replay',
      skip: _skip, () async {
    final first = await postSale(number: 'SP23-IDEM', gid: 'sp23-idem-gid', idem: 'sp23-idem-key');
    final replay = await postSale(number: 'SP23-IDEM', gid: 'sp23-idem-gid', idem: 'sp23-idem-key');
    final invoices = await (db.select(db.salesInvoices)
          ..where((row) => row.globalId.equals('sp23-idem-gid')))
        .get();
    // ignore: avoid_print
    print('[AUDIT-SP23-IDEM] statuses=${first.statusCode}/${replay.statusCode} rows=${invoices.length}');
    expect(first.statusCode, 200, reason: await first.readAsString());
    expect(replay.statusCode, 200, reason: await replay.readAsString());
    expect(invoices, hasLength(1));
    await printMetrics('IDEM');
  });
}
