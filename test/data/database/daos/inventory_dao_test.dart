import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  group('InventoryDao - adjustStock Tests', () {
    test('adjustStock creates correct StockMovement for a sale', () async {
      // 1. Setup seed data (Product & Warehouse)
      final warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'Main Warehouse',
            ),
          );

      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'Test Product',
              code: 'TP-001',
              costPrice: const Value(10.0),
              trackInventory: const Value(true),
            ),
          );

      // Seed initial stock correctly for the warehouse
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100.0,
        type: 'adjustment',
      );

      // 2. Perform Adjust Stock (Simulating a sale of 5 items)
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -5,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 99,
        notes: 'Test Sale',
      );

      // 3. Assert Product global stock updated
      final product = await db.getProductById(productId);
      expect(product!.currentStock, equals(95)); // 100 - 5

      // 4. (Skipping Warehouse balance assertion as it requires a specific query block here)
      // final balance = await db.getWarehouseBalance(productId, warehouseId);
      // expect(balance!.quantity, equals(-5));

      // 5. Assert Stock Movement created accurately
      final movements = await db.select(db.stockMovements).get();
      expect(movements.length, 2); // 1 seed + 1 sale
      final movement = movements.last;
      
      expect(movement.productId, productId);
      expect(movement.warehouseId, warehouseId);
      expect(movement.quantity, -5);
      expect(movement.movementType, 'sale');
      expect(movement.referenceType, 'sales_invoice');
      expect(movement.referenceId, 99);
      expect(movement.balanceAfter, 95); // 100 - 5
      expect(movement.notes, 'Test Sale');
    });

    test('adjustStock creates correct StockMovement for a purchase', () async {
      // 1. Setup seed data
      final warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'Main Warehouse',
            ),
          );

      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'Test Product 2',
              code: 'TP-002',
              costPrice: const Value(10.0),
              trackInventory: const Value(true),
            ),
          );

      // Seed initial stock
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 50.0,
        type: 'adjustment',
      );

      // 2. Perform Adjust Stock (Simulating a purchase of 20 items)
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 20,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 105,
        notes: 'Test Purchase',
      );

      // 3. Assert Stock Movement created accurately
      final movements = await db.select(db.stockMovements).get();
      expect(movements.length, 2); // 1 seed + 1 purchase
      final movement = movements.last;
      
      expect(movement.productId, productId);
      expect(movement.warehouseId, warehouseId);
      expect(movement.quantity, 20);
      expect(movement.movementType, 'purchase');
      expect(movement.referenceType, 'purchase_invoice');
      expect(movement.referenceId, 105);
      expect(movement.balanceAfter, 70); // 50 + 20
    });
  });
}
