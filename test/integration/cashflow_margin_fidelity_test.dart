import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart' show TransactionData;
import 'package:ural_erp/domain/usecases/accounting/get_cashflow_statement_usecase.dart';

void main() {
  late AppDatabase db;
  late GetCashFlowStatementUseCase cashflowUseCase;

  setUp(() async {
    db = AppDatabase.forTesting();
    cashflowUseCase = GetCashFlowStatementUseCase();
  });

  tearDown(() async {
    await db.close();
  });

  group('Margin Fidelity (WAC Calculation & Reversal)', () {
    test('WAC updates correctly on purchase and reverses on return', () async {
      // 1. Setup Base Data
      final catId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(name: 'Test Category'),
      );
      
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'TEST-WAC-1',
          name: 'WAC Test Product',
          categoryId: Value(catId),
          trackInventory: const Value(true),
          costPrice: const Value(15.0), // Initial WAC = 15
          salePrice: const Value(25.0),
        ),
      );

      final warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
          name: 'Main WH',
          isDefault: const Value(true),
        ),
      );

      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Supplier A',
          isSupplier: const Value(true),
          isCustomer: const Value(false),
        ),
      );

      // 2. Perform a Purchase to alter WAC
      // Buy 5 units at 20 each. 
      // Current stock is 0. So WAC should become 20.
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paymentMethod: 'cash',
        paid: 0,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0, // Added dummy invoiceId
            productId: productId,
            quantity: 5,
            unitCost: 20.0, // New cost is 20
            total: 100.0, // 5 * 20.0
            taxRate: const Value(0),
          )
        ],
      );

      var product = await db.getProductById(productId);
      expect(product!.costPrice, 20.0, reason: 'WAC should update to latest cost when stock was 0');
      expect(product.currentStock, 5.0);

      // 3. Purchase again to mix WAC
      // Current: 5 units @ 20. Total Value = 100.
      // Buy 5 units at 30. Value = 150.
      // New WAC = (100 + 150) / 10 = 250 / 10 = 25.0
  // ignore: unused_local_variable
        final invoiceId = await db.createPurchaseInvoice(
          supplierId: supplierId,
          warehouseId: warehouseId,
          paid: 0.0,
          paymentMethod: 'cash',
          items: [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: productId,
              quantity: 5, // Changed from 10 to 5 to match the test logic
              unitCost: 30.0, // Changed from 15.0 to 30.0 to match the test logic
              total: 150.0, // 5 * 30.0
              taxRate: const Value(0),
            )
          ],
        );

      product = await db.getProductById(productId);
      expect(product!.costPrice, 25.0, reason: 'WAC should be a weighted average of 20 and 30');
      expect(product.currentStock, 10.0);

      // 4. Test WAC Reversal (Simulate returning 5 units @ 30)
      // WAC Reversal Formula: ((Current Qty * Current WAC) - (Reversed Qty * Reversed Unit Cost)) / (Remaining Qty)
      // ((10 * 25) - (5 * 30)) / 5
      // (250 - 150) / 5 = 100 / 5 = 20.0 (Back to original)
      
      await db.reverseProductWAC(
        productId: productId,
        reversedQuantity: 5,
        reversedUnitCost: 30.0,
      );

      product = await db.getProductById(productId);
      expect(product!.costPrice, 20.0, reason: 'WAC must accurately reverse to previous state');
    });

    test('WAC Reversal Edge Case (Reset to recalculate if reversed to <= 0 stock)', () async {
       // Setup
      final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Cat'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P-123', name: 'Product', categoryId: Value(catId), trackInventory: const Value(true), costPrice: const Value(10.0), salePrice: const Value(20.0)),
      );

      // Buy 10 @ 10
      final invoiceId = await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(supplierId: 1, warehouseId: 1, invoiceNumber: 'INV-123', invoiceDate: DateTime.now(), subtotal: const Value(100), tax: const Value(0), total: const Value(100), paid: const Value(0), status: const Value('paid')));
      await db.into(db.purchaseInvoiceItems).insert(PurchaseInvoiceItemsCompanion.insert(invoiceId: invoiceId, productId: productId, quantity: 10, unitCost: 10.0, total: 100.0, taxRate: const Value(0)));
      await db.updateProductWAC(productId: productId, newQuantity: 10, newUnitCost: 10);
      
      var p = await db.getProductById(productId);
      expect(p!.costPrice, 10.0);

      // Reverse ALL stock (Reversing 10 @ 10)
      await db.reverseProductWAC(productId: productId, reversedQuantity: 10, reversedUnitCost: 10);
      p = await db.getProductById(productId);
      
      // Should fallback to recalculate, which finds 1 invoice (10 @ 10), so it stays 10
      expect(p!.costPrice, 10.0);
    });
  });

  group('GetCashFlowStatementUseCase', () {
    test('Correctly categorizes and calculates cash flow', () {
      final transactions = [
        TransactionData(id: 1, voucherNumber: 'T1', safeId: 1, safeName: 'Cash', transactionType: 'receipt', category: 'sales', amount: 1000.0, discount: 0.0, balanceAfter: 1000.0, createdAt: DateTime.now()),
        TransactionData(id: 2, voucherNumber: 'T2', safeId: 1, safeName: 'Cash', transactionType: 'receipt', category: 'sales', amount: 500.0, discount: 0.0, balanceAfter: 1500.0, createdAt: DateTime.now()),
        TransactionData(id: 3, voucherNumber: 'T3', safeId: 2, safeName: 'Bank', transactionType: 'payment', category: 'purchases', amount: 200.0, discount: 0.0, balanceAfter: 1300.0, createdAt: DateTime.now()),
        TransactionData(id: 4, voucherNumber: 'T4', safeId: 1, safeName: 'Cash', transactionType: 'payment', category: 'expenses', amount: 50.0, discount: 0.0, balanceAfter: 1250.0, createdAt: DateTime.now()),
      ];

      final result = cashflowUseCase.executeFromTransactions(transactions);

      // Assertions
      expect(result.totalInflows, 1500.0);
      expect(result.totalOutflows, 250.0);
      expect(result.netFlow, 1250.0);

      expect(result.inflowsByCategory['sales'], 1500.0);
      expect(result.outflowsByCategory['purchases'], 200.0);
      expect(result.outflowsByCategory['expenses'], 50.0);
    });
    
    test('Handles empty transaction list correctly', () {
      final result = cashflowUseCase.executeFromTransactions([]);
      expect(result.totalInflows, 0.0);
      expect(result.totalOutflows, 0.0);
      expect(result.netFlow, 0.0);
      expect(result.inflowsByCategory.isEmpty, isTrue);
      expect(result.outflowsByCategory.isEmpty, isTrue);
    });
  });
}
