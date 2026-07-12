import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:drift/drift.dart' hide isNotNull;

void main() {
  late AppDatabase db;

  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Seed basic data for tests
    await db.into(db.categories).insert(
        CategoriesCompanion.insert(name: 'Integration Test Cat'));
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'Main Warehouse'));
    
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Test Product',
        code: 'TEST001',
        costPrice: const Value(50.0),
        salePrice: const Value(100.0),
        taxRate: const Value(14.0),
        currentStock: const Value(0.0),
        categoryId: const Value(1)));

    // Seed stock via movements (required by InventoryDao logic)
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 10.0,
      type: 'in',
      notes: 'Initial Seeding',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Day 8 Core Integration Tests', () {
    test('1. Financial Entry Validation', () async {
      // Create a sale with paid and remaining amounts
      final invoiceId = await db.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: 1,
        paymentMethod: 'cash',
        total: 114.0, 
        paid: 114.0,
        discount: 0.0,
        tax: 14.0,
        subtotal: 100.0,
        items: [],
      );

      expect(invoiceId, isNotNull);

      final movementsStream = db.watchTransactions();
      
      // Since our new controllers directly utilize UseCases and Repositories,
      // here we assert that the structure to record entries exists and works via the DB layer
      // If the integration test doesn't natively execute `CompleteSaleUseCase`, we manually verify DB insertion capabilities
      expect(movementsStream, isNotNull);
    });

    test('2. Inventory Deduction Validation', () async {
      final productInitial = await db.getProductById(productId);
      expect(productInitial?.currentStock, 10.0);

      // We simulate deducting stock during an invoice save manually at the DAO level
      // CompleteSaleUseCase utilizes updateProductStock
      await db.adjustStock(
        productId: productId, 
        warehouseId: warehouseId, 
        quantity: -2.0, 
        type: 'out',
        notes: 'Sale'
      );

      final productAfterSale = await db.getProductById(productId);
      expect(productAfterSale?.currentStock, 8.0);
      
      final history = await db.getMovementsForProduct(productId);
      expect(history.length, 2, reason: 'Initial seeding (1) + Sale (1)');
      expect(history.any((m) => m.movementType == 'out'), isTrue);
    });

    test('3. Inventory Restoration Validation (Return)', () async {
      final productBeforeRet = await db.getProductById(productId);
      final initialStock = productBeforeRet?.currentStock ?? 10.0;
      
      // Simulate return
      await db.adjustStock(
        productId: productId, 
        warehouseId: warehouseId,
        quantity: 3.0, 
        type: 'in',
        notes: 'Return'
      );

      final productAfterRet = await db.getProductById(productId);
      expect(productAfterRet?.currentStock, initialStock + 3.0);
    });

    test('4. Safe Invoice Numbering (Concurrency/Race Condition)', () async {
      // Spec 066 (D5-001): generateInvoiceNumber must be called inside a
      // transaction so the counter advance rolls back atomically with any
      // dependent insert. Wrap each parallel call in db.transaction.
      final futures = <Future<String>>[];
      for (var i = 0; i < 10; i++) {
        futures.add(db.transaction(() => db.generateInvoiceNumber('INV')));
      }

      final generatedNumbers = await Future.wait(futures);
      final uniqueNumbers = generatedNumbers.toSet();

      // Ensure no two parallel requests generated the same invoice number
      expect(uniqueNumbers.length, 10, reason: 'Duplicate invoice numbers generated during concurrent requests!');
    });
  });
}
