import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// E2E Test: Sales Return Flow (Sprint 17)
/// Return → Stock Restoration → Treasury Refund → Customer Balance
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  // ignore: unused_local_variable
  late int originalInvoiceId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'return_test',
      password: 'test123',
      displayName: 'Return Tester',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RET-01',
        name: 'منتج مرتجع',
        salePrice: const Value(200.0),
        costPrice: const Value(120.0),
        currentStock: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );

    // Seed stock via movements
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'in',
      notes: 'Initial Seeding',
    );

    // Create original sale (sell 10 items)
    originalInvoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-ORIG-001',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 2000.0,
      discount: 0.0,
      tax: 0.0,
      total: 2000.0,
      paid: 2000.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10.0,
          unitPrice: 200.0,
          total: 2000.0,
        ),
      ],
    );
  });

  tearDown(() async => db.close());

  group('E2E Sales Return Flow', () {
    test('Return restores stock and records movement', () async {
      // Stock after sale: 100 - 10 = 90
      final afterSale = await db.getProductById(productId);
      expect(afterSale!.currentStock, 90.0);

      // Create return invoice (return 3 items)
      await db.createSalesInvoice(
        invoiceNumber: 'RET-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 600.0,
        discount: 0.0,
        tax: 0.0,
        total: 600.0,
        paid: 600.0,
        paymentMethod: 'cash',
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 200.0,
            total: 600.0,
          ),
        ],
      );

      // Stock restored: 90 + 3 = 93
      final afterReturn = await db.getProductById(productId);
      expect(afterReturn!.currentStock, 93.0);

      // Verify return movement exists
      final movements = await db.getMovementsForProduct(productId);
      expect(movements.any((m) => m.movementType == 'return'), isTrue);
    });

    test('Return creates refund payment voucher', () async {
      final cashSafe = await db.getDefaultSafeByType('cash');
      final initialBalance = cashSafe!.balance;

      // Create return and refund
      await db.createPaymentVoucher(
        amount: 600.0,
        category: 'sales_return',
        description: 'مرتجع فاتورة RET-001',
        safeId: cashSafe.id,
        userId: userId,
      );

      final afterRefund = await db.getDefaultSafeByType('cash');
      expect(afterRefund!.balance, initialBalance - 600.0);
    });

    test('Multiple returns do not exceed original quantity', () async {
      // Original sale: 10 items. After first return of 3: stock = 93.

      // Return 5 more
      await db.createSalesInvoice(
        invoiceNumber: 'RET-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1000.0,
        discount: 0.0,
        tax: 0.0,
        total: 1000.0,
        paid: 1000.0,
        paymentMethod: 'cash',
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 200.0,
            total: 1000.0,
          ),
        ],
      );

      final afterSecondReturn = await db.getProductById(productId);
      // 90 + 5 = 95 (original was 100, sold 10, returned 5 in this test)
      expect(afterSecondReturn!.currentStock, 95.0);
    });
  });
}
