import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_purchase_handler.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/delta_pull_service.dart';
import 'package:ural_erp/services/invoice_integrity_service.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late String? secret;

  setUp(() async {
    db = AppDatabase.forTesting();
    secret = null;
    await InvoiceIntegrityService.initialize(
      readSetting: (_) async => secret,
      writeSetting: (_, value) async => secret = value,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    userId = (await (db.select(db.users)..limit(1)).getSingle()).id;
  });

  tearDown(() => db.close());

  Request request(String path, Map<String, dynamic> body) => Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: userId},
      );

  Future<SalesInvoiceData> rawSale(int id) =>
      (db.select(db.salesInvoices)..where((row) => row.id.equals(id)))
          .getSingle();

  Future<PurchaseInvoiceData> rawPurchase(int id) =>
      (db.select(db.purchaseInvoices)..where((row) => row.id.equals(id)))
          .getSingle();

  bool verifiesSale(SalesInvoiceData invoice) =>
      InvoiceIntegrityService.verifySalesInvoiceHash(
        storedHash: invoice.integrityHash!,
        invoiceNumber: invoice.invoiceNumber,
        invoiceDate: invoice.invoiceDate,
        total: invoice.total,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.tax,
        paid: invoice.paid,
        customerId: invoice.customerId,
        userId: invoice.userId,
        paymentMethod: invoice.paymentMethod,
      );

  bool verifiesPurchase(PurchaseInvoiceData invoice) =>
      InvoiceIntegrityService.verifyPurchaseInvoiceHash(
        storedHash: invoice.integrityHash!,
        invoiceNumber: invoice.invoiceNumber,
        invoiceDate: invoice.invoiceDate,
        total: invoice.total,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.tax,
        paid: invoice.paid,
        supplierId: invoice.supplierId,
        paymentMethod: invoice.paymentMethod,
      );

  test('API sale and purchase are signed after posting without violations',
      () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      final productId = await db.insertProduct(ProductsCompanion.insert(
        code: 'API-INT-${DateTime.now().microsecondsSinceEpoch}',
        name: 'API integrity product',
        salePrice: const Value(100),
        costPrice: const Value(10),
        trackInventory: const Value(false),
      ));
      final salesResponse = await ApiSalesHandler(db, {}).postSale(
        request('/api/sales', {
          'invoiceNumber': 'API-INTEGRITY-SALE',
          'globalId': 'api-integrity-sale-gid',
          'subtotal': 100.0,
          'discount': 0.0,
          'tax': 0.0,
          'total': 100.0,
          'paid': 100.0,
          'paymentMethod': 'cash',
          'cashAmount': 100.0,
          'cashSafeId': (await db.getDefaultSafeByType('cash'))?.id,
          'warehouseId': warehouseId,
          'userId': userId,
          'items': [
            {
              'productId': productId,
              'quantity': 1.0,
              'unitPrice': 100.0,
              'total': 100.0,
              'costPrice': 10.0,
            },
          ],
        }),
      );
      final salesBody = jsonDecode(await salesResponse.readAsString())
          as Map<String, dynamic>;
      final sale = await rawSale(salesBody['serverId'] as int);

      expect(salesResponse.statusCode, 200);
      expect(sale.isLocked, isTrue);
      expect(verifiesSale(sale), isTrue);
      expect(await db.getSalesInvoiceById(sale.id), isNotNull);
      expect(logs.where((line) => line.contains('VIOLATION')), isEmpty);

      final supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'API integrity supplier',
              isSupplier: const Value(true),
            ),
          );
      final purchaseResponse = await ApiPurchaseHandler(db, {}).postPurchase(
        request('/api/purchases', {
          'invoiceNumber': 'API-INTEGRITY-PURCHASE',
          'globalId': 'api-integrity-purchase-gid',
          'supplierId': supplierId,
          'warehouseId': warehouseId,
          'paid': 0.0,
          'paymentMethod': 'credit',
          'items': [
            {
              'productId': productId,
              'quantity': 1.0,
              'unitCost': 10.0,
              'total': 10.0,
              'taxRate': 0.0,
              'taxAmount': 0.0,
            },
          ],
        }),
      );
      final purchaseBody = jsonDecode(await purchaseResponse.readAsString())
          as Map<String, dynamic>;
      final purchase = await rawPurchase(purchaseBody['serverId'] as int);

      expect(purchaseResponse.statusCode, 200);
      expect(verifiesPurchase(purchase), isTrue);
      await db.customStatement(
        'UPDATE purchase_invoices SET is_locked = 1 WHERE id = ?',
        [purchase.id],
      );
      expect(await db.getPurchaseInvoiceById(purchase.id), isNotNull);
      expect(logs.where((line) => line.contains('VIOLATION')), isEmpty);
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  test('delta-applied sales are re-signed locally and direct total tamper fails',
      () async {
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'SYNC-INTEGRITY-SALE',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 20,
      discount: 0,
      tax: 0,
      total: 20,
      paid: 20,
      paymentMethod: 'cash',
      items: const [],
    );
    final source = await rawSale(invoiceId);
    await db.customStatement(
      'UPDATE sales_invoices SET integrity_hash = ?, row_version = 1 WHERE id = ?',
      ['remote-device-signature', invoiceId],
    );

    DeltaPullService.instance.initialize(db);
    await DeltaPullService.instance.upsertRowForTest('sales_invoices', {
      'id': source.id,
      'invoice_number': source.invoiceNumber,
      'customer_id': source.customerId,
      'warehouse_id': source.warehouseId,
      'branch_id': source.branchId,
      'user_id': source.userId,
      'invoice_date': source.invoiceDate.millisecondsSinceEpoch,
      'subtotal': source.subtotal,
      'discount': source.discount,
      'tax': source.tax,
      'total': source.total,
      'paid': source.paid,
      'payment_method': source.paymentMethod,
      'status': source.status,
      'is_locked': source.isLocked,
      'is_deleted': source.isDeleted,
      'global_id': source.globalId,
      'integrity_hash': 'remote-device-signature',
      'row_version': 2,
    });

    expect(verifiesSale(await rawSale(invoiceId)), isTrue);

    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      await db.customStatement(
        'UPDATE sales_invoices SET total = ?, is_locked = 1 WHERE id = ?',
        [21.0, invoiceId],
      );
      expect(verifiesSale(await rawSale(invoiceId)), isFalse);
      expect(await db.getSalesInvoiceById(invoiceId), isNotNull);
    } finally {
      debugPrint = previousDebugPrint;
    }
    expect(logs.where((line) => line.contains('VIOLATION')), isNotEmpty);
  });
}
