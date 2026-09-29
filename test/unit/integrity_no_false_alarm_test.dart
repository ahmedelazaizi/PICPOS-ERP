import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/invoice_integrity_service.dart';
import 'package:shelf/shelf.dart';
import 'dart:convert';

Future<List<String>> captureIntegrityOutput(Future<void> Function() action) async {
  final output = <String>[];
  final previousDebugPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) => output.add(message ?? '');
  try {
    await action();
  } finally {
    debugPrint = previousDebugPrint;
  }
  return output;
}

void expectNoIntegrityViolations(Iterable<String> output) {
  expect(output.where((line) => line.contains('VIOLATION')), isEmpty);
}

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
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
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'NO-FALSE-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Integrity regression product',
      salePrice: const Value(100),
      costPrice: const Value(10),
      trackInventory: const Value(false),
    ));
  });

  tearDown(() => db.close());

  Future<({int id, int warehouseId, int productId})> createPostedSale({
    String paymentMethod = 'cash',
    int? customerId,
    double paid = 200,
  }) async {
    final id = await db.createSalesInvoice(
      invoiceNumber: 'NO-FALSE-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: userId,
      customerId: customerId,
      subtotal: 200,
      discount: 0,
      tax: 0,
      total: 200,
      paid: paid,
      paymentMethod: paymentMethod,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 2,
          unitPrice: 100,
          total: 200,
        ),
      ],
    );
    final invoice = await db.getSalesInvoiceById(id);
    if (paymentMethod == 'credit') {
      await db.autoPostCreditSale(invoice!);
    } else {
      await db.autoPostCashSale(invoice!);
    }
    return (id: id, warehouseId: warehouseId, productId: productId);
  }

  Future<int> createSupplier() => db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Integrity regression supplier',
          isSupplier: const Value(true),
        ),
      );

  Future<int> createLockedSaleEditor() async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'Integrity locked sale editor',
            isSystemRole: const Value(false),
          ),
        );
    final editorId = await db.createUser(
      username: 'integrity-editor-${DateTime.now().microsecondsSinceEpoch}',
      password: 'pw',
      displayName: 'Integrity editor',
      roleId: roleId,
    );
    final permission = await (db.select(db.permissions)
          ..where((row) => row.code.equals(PermissionCodes.modifyLockedInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, permission.id);
    return editorId;
  }

  test('payment-method change re-signs before journal repost verification',
      () async {
    final sale = await createPostedSale();
    final output = await captureIntegrityOutput(
      () => db.updateSalesInvoicePayment(sale.id, 'credit', null),
    );
    expectNoIntegrityViolations(output);
  });

  test('locked sale edit re-signs before journal repost verification', () async {
    final editorId = await createLockedSaleEditor();
    final sale = await createPostedSale();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final repository = container.read(salesRepositoryProvider);

    final output = await captureIntegrityOutput(
      () => repository.updateFullSalesInvoice(
        invoiceId: sale.id,
        userId: editorId,
        warehouseId: sale.warehouseId,
        paid: 300,
        paymentMethod: 'cash',
        items: [
          CartItemEntity(
            productId: sale.productId,
            productName: 'Integrity regression product',
            productCode: 'NO-FALSE',
            quantity: 3,
            unitPrice: 100,
          ),
        ],
      ),
    );
    expectNoIntegrityViolations(output);
  });

  test('purchase edit re-signs before purchase repost verification', () async {
    final supplierId = await createSupplier();
    final purchaseId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1,
          unitCost: 10,
          total: 10,
        ),
      ],
      userId: userId,
    );

    final output = await captureIntegrityOutput(
      () => db.updatePurchaseInvoice(
        invoiceId: purchaseId,
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        userId: userId,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: purchaseId,
            productId: productId,
            quantity: 2,
            unitCost: 10,
            total: 20,
          ),
        ],
      ),
    );
    expectNoIntegrityViolations(output);
  });

  test('API sale does not emit an integrity violation', () async {
    final handler = ApiSalesHandler(db, {});
    final request = Request(
      'POST',
      Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': 'NO-FALSE-API',
        'globalId': 'no-false-api-sale',
        'subtotal': 100.0,
        'discount': 0.0,
        'tax': 0.0,
        'total': 100.0,
        'paid': 100.0,
        'paymentMethod': 'cash',
        'cashAmount': 100.0,
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
      headers: {'Content-Type': 'application/json'},
      context: {ApiUserCtx.userIdKey: userId},
    );

    final output = await captureIntegrityOutput(
      () async => await handler.postSale(request),
    );
    expectNoIntegrityViolations(output);
  });

  test('partial collection re-signs before receipt verification', () async {
    final customerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Integrity regression customer',
            isCustomer: const Value(true),
          ),
        );
    final sale = await createPostedSale(
      paymentMethod: 'credit',
      customerId: customerId,
      paid: 0,
    );
    final output = await captureIntegrityOutput(
      () => db.addSalesPayment(
        invoiceId: sale.id,
        amount: 50,
        userId: userId,
      ),
    );
    expectNoIntegrityViolations(output);
  });
}
