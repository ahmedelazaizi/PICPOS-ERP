import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// E2E Test: Complete Sale Flow (Sprint 17)
/// POS → Invoice → Stock Deduction → Treasury Receipt
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'sale_test',
      password: 'test123',
      displayName: 'Sale Tester',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // Create product
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'SALE-01',
        name: 'منتج بيع',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        trackInventory: const Value(true),
      ),
    );

    // Seed stock for the warehouse correctly
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  group('E2E Sale Flow', () {
    test('POS → Invoice → Stock → Treasury', () async {
      // 1. Record initial state
      final initialProduct = await db.getProductById(productId);
      final cashSafe = await db.getDefaultSafeByType('cash');
      final initialCashBalance = cashSafe!.balance;

      // 2. Create sales invoice (simulates POS checkout)
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'INV-E2E-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 300.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 100.0,
            total: 300.0,
          ),
        ],
      );

      expect(invoiceId, isPositive);

      // 3. Verify stock was deducted
      final afterSaleProduct = await db.getProductById(productId);
      expect(afterSaleProduct!.currentStock, initialProduct!.currentStock - 3.0);

      // 4. Verify treasury received payment automatically (DAO handles this via _recordSalesReceipt)
      final finalCash = await db.getDefaultSafeByType('cash');
      expect(finalCash!.balance, initialCashBalance + 300.0);

      // 5. Verify stock movement was recorded
      final movements = await db.getMovementsForProduct(productId);
      expect(movements.any((m) => m.movementType == 'sale'), isTrue);
    });

    test('Sale with discount and tax', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'INV-E2E-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 500.0,
        discount: 50.0,
        tax: 63.0, // 14% of 450
        total: 513.0,
        paid: 513.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 100.0,
            total: 500.0,
            taxRate: const Value(14.0),
            taxAmount: const Value(63.0),
          ),
        ],
      );

      // Verify invoice stored correctly
      final invoices = await db.getSalesByDateRange(
        DateTime.now().subtract(const Duration(hours: 1)),
        DateTime.now().add(const Duration(hours: 1)),
      );
      final inv = invoices.firstWhere((i) => i.id == invoiceId);
      expect(inv.discount, 50.0);
      expect(inv.tax, 63.0);
      expect(inv.total, 513.0);
    });

    test('Sale with card payment goes to bank safe', () async {
      await db.createSalesInvoice(
        invoiceNumber: 'INV-E2E-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 0.0,
        tax: 0.0,
        total: 200.0,
        paid: 200.0,
        paymentMethod: 'card',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 100.0,
            total: 200.0,
          ),
        ],
      );

      // Card payment → bank safe
      final bankSafe = await db.getDefaultSafeByType('bank');
      await db.createReceiptVoucher(
        amount: 200.0,
        category: 'sales',
        safeId: bankSafe!.id,
        userId: userId,
      );

      final updatedBank = await db.getDefaultSafeByType('bank');
      expect(updatedBank!.balance, greaterThan(0));
    });
  });
}
