import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// Integration Test: Stock Movements Flow (Sprint 16)
///
/// Verifies the complete Purchase → Sale → Return cycle:
/// - Purchase adds stock + creates batch
/// - Sale deducts stock via FIFO batch consumption
/// - Return restores stock via batch restoration
/// - SUM(movements) always equals expected final stock
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Seed a role and user
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(false)),
    );
    await db.createUser(
      username: 'stock_test',
      password: 'test123',
      displayName: 'Stock Tester',
      roleId: roleId,
    );

    // Get default warehouse
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // Create a test product with inventory tracking
    productId = await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'منتج اختبار المخزون',
        code: 'TST-001',
        barcode: const Value('9999999999990'),
        salePrice: const Value(50.0),
        costPrice: const Value(30.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
        isActive: const Value(true),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Stock Movements Flow — Purchase → Sale → Return', () {
    test('Purchase adds stock and creates batch', () async {
      // Simulate purchase: add 100 units
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
        notes: 'شراء 100 وحدة',
      );

      // Create a batch for the purchase
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: 'BATCH-001',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        quantity: const Value(100),
        initialQuantity: const Value(100),
        unitCost: const Value(30.0),
      ));

      // Verify stock
      final product = await db.getProductById(productId);
      expect(product!.currentStock, 100.0);

      // Verify batch
      final batches = await db.getProductBatchesFIFO(productId);
      expect(batches.length, 1);
      expect(batches.first.quantity, 100.0);
    });

    test('Sale deducts stock via FIFO', () async {
      // Setup: purchase 100 units + batch
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
      );
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: 'BATCH-001',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        quantity: const Value(100),
        initialQuantity: const Value(100),
        unitCost: const Value(30.0),
      ));

      // Sale: deduct 25 units
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -25,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 1,
        notes: 'مبيعات فاتورة #1',
      );

      // Verify global stock
      final product = await db.getProductById(productId);
      expect(product!.currentStock, 75.0);

      // Verify batch was consumed via FIFO
      final batches = await db.getProductBatchesFIFO(productId);
      expect(batches.length, 1);
      expect(batches.first.quantity, 75.0);
    });

    test('Return restores stock and batch', () async {
      // Setup: purchase 100 → sell 25
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
      );
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: 'BATCH-001',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        quantity: const Value(100),
        initialQuantity: const Value(100),
        unitCost: const Value(30.0),
      ));
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -25,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 1,
      );

      // Return: restore 10 units
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 10,
        type: 'return',
        referenceType: 'sales_invoice',
        referenceId: 2,
        notes: 'مرتجع 10 وحدات',
      );

      // Verify final stock: 100 - 25 + 10 = 85
      final product = await db.getProductById(productId);
      expect(product!.currentStock, 85.0);

      // Verify batch was restored
      final batches = await db.getProductBatchesFIFO(productId);
      expect(batches.first.quantity, 85.0);
    });

    test('FIFO order: oldest batch consumed first', () async {
      // Setup: purchase 50 (batch 1), then 30 (batch 2)
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 80,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
      );

      // Batch 1: older (createdAt = now)
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: 'BATCH-OLD',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        quantity: const Value(50),
        initialQuantity: const Value(50),
        unitCost: const Value(25.0),
      ));

      // Small delay to ensure different createdAt
      await Future.delayed(const Duration(milliseconds: 50));

      // Batch 2: newer
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: 'BATCH-NEW',
        expiryDate: DateTime.now().add(const Duration(days: 730)),
        quantity: const Value(30),
        initialQuantity: const Value(30),
        unitCost: const Value(35.0),
      ));

      // Sell 60 units — should consume all of batch 1 (50) + 10 from batch 2
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -60,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 1,
      );

      // Verify: batch 1 depleted, batch 2 has 20 remaining
      final allBatches = await (db.select(db.productBatches)
            ..where((b) => b.productId.equals(productId))
            ..orderBy([(b) => OrderingTerm.asc(b.createdAt)]))
          .get();

      expect(allBatches.length, 2);

      // Batch 1 (oldest): depleted
      expect(allBatches[0].batchNumber, 'BATCH-OLD');
      expect(allBatches[0].quantity, 0.0);
      expect(allBatches[0].status, 'depleted');

      // Batch 2 (newer): 30 - 10 = 20
      expect(allBatches[1].batchNumber, 'BATCH-NEW');
      expect(allBatches[1].quantity, 20.0);
      expect(allBatches[1].status, 'active');
    });

    test('Stock movements sum matches final balance', () async {
      // Full cycle: purchase 100, sell 30, return 5, sell 15
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
      );
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -30,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 1,
      );
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 5,
        type: 'return',
        referenceType: 'sales_invoice',
        referenceId: 2,
      );
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -15,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 3,
      );

      // Expected: 100 - 30 + 5 - 15 = 60
      final product = await db.getProductById(productId);
      expect(product!.currentStock, 60.0);

      // Verify SUM of movements equals final balance
      final movements = await db.getMovementsForProduct(productId);
      final movementSum = movements.fold<double>(
        0,
        (sum, m) => sum + m.quantity,
      );
      expect(movementSum, 60.0);
      expect(movementSum, product.currentStock);
    });
  });
}
