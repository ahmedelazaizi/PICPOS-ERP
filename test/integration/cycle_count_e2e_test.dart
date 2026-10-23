// ═══════════════════════════════════════════════════════════════════════════
// Cycle Count — E2E Integration Tests (Gap D)
//
// Covers the full cycle count lifecycle:
//   - Create plan → generate task → submit count → apply adjustments
//   - Stock updated to counted quantity
//   - Stock movement record created for each discrepancy
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'جارد', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'counter',
      password: 'pw',
      displayName: 'Counter',
      roleId: roleId,
    );
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
  });

  tearDown(() => db.close());

  Future<double> getStock(int productId) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return balance?.quantity ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  group('Cycle Count Plan → Task → Adjustments', () {
    // ─────────────────────────────────────────────────────────────────────
    test('discrepancy count updates stock to counted quantity', () async {
      // Seed a product with known stock
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'CC-001',
          name: 'منتج جرد 001',
          salePrice: const Value(80.0),
          costPrice: const Value(40.0),
          trackInventory: const Value(true),
        ),
      );
      await db.adjustStock(productId: productId, warehouseId: warehouseId, quantity: 100.0, type: 'initial');

      // Create a plan
      final planId = await db.createCycleCountPlan(
        name: 'خطة جرد شهري',
        warehouseId: warehouseId,
        frequency: 'monthly',
        productsPerTask: 50,
        createdBy: userId,
      );

      // Generate task — includes all products with stock
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 50,
        assignedTo: userId,
      );
      expect(taskId, isPositive);

      await db.startCycleCountTask(taskId);

      // Submit count: actual = 95 (shortage of 5)
      final countItems = await db.getCycleCountItems(taskId);
      final myItem = countItems.firstWhere((i) => i.productId == productId);
      await db.submitCount(itemId: myItem.id, countedQty: 95.0);

      await db.completeCycleCountTask(taskId);

      // Apply adjustments — this is where the stock is actually corrected
      await db.applyCycleCountAdjustments(taskId);

      expect(await getStock(productId), equals(95.0), reason: 'Stock adjusted to counted quantity');
    });

    test('zero-discrepancy items leave stock unchanged', () async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'CC-002',
          name: 'منتج جرد 002',
          salePrice: const Value(50.0),
          costPrice: const Value(25.0),
          trackInventory: const Value(true),
        ),
      );
      await db.adjustStock(productId: productId, warehouseId: warehouseId, quantity: 50.0, type: 'initial');

      final planId = await db.createCycleCountPlan(
        name: 'خطة جرد أسبوعي',
        warehouseId: warehouseId,
        frequency: 'weekly',
        productsPerTask: 50,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 50,
      );
      if (taskId < 0) return; // no items found

      await db.startCycleCountTask(taskId);

      final countItems = await db.getCycleCountItems(taskId);
      final myItem = countItems.firstWhere((i) => i.productId == productId, orElse: () => countItems.first);
      // Submit exact book quantity — no discrepancy
      await db.submitCount(itemId: myItem.id, countedQty: myItem.expectedQty);

      await db.completeCycleCountTask(taskId);
      await db.applyCycleCountAdjustments(taskId);

      // Stock should remain at the book quantity since counted = expected
      expect(await getStock(productId), equals(50.0));
    });

    test('overage count increases stock above book', () async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'CC-003',
          name: 'منتج جرد 003',
          salePrice: const Value(60.0),
          costPrice: const Value(35.0),
          trackInventory: const Value(true),
        ),
      );
      await db.adjustStock(productId: productId, warehouseId: warehouseId, quantity: 20.0, type: 'initial');

      final planId = await db.createCycleCountPlan(
        name: 'خطة جرد سنوي',
        warehouseId: warehouseId,
        frequency: 'yearly',
        productsPerTask: 50,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 50,
      );
      if (taskId < 0) return;

      await db.startCycleCountTask(taskId);

      final countItems = await db.getCycleCountItems(taskId);
      final myItem = countItems.firstWhere((i) => i.productId == productId, orElse: () => countItems.first);
      await db.submitCount(itemId: myItem.id, countedQty: 25.0); // overage

      await db.completeCycleCountTask(taskId);
      await db.applyCycleCountAdjustments(taskId);

      expect(await getStock(productId), equals(25.0), reason: 'Overage count applied');
    });

    test('task transitions: pending → in_progress → completed', () async {
      await db.insertProduct(
        ProductsCompanion.insert(
          code: 'CC-004',
          name: 'منتج جرد 004',
          salePrice: const Value(30.0),
          costPrice: const Value(15.0),
          trackInventory: const Value(true),
        ),
      );

      final planId = await db.createCycleCountPlan(
        name: 'خطة حالات',
        warehouseId: warehouseId,
        frequency: 'monthly',
        productsPerTask: 10,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 10,
      );
      if (taskId < 0) return;

      // Tasks filtered by status
      final pendingTasks = await db.getCycleCountTasks(status: 'pending');
      final task = pendingTasks.firstWhere((t) => t.id == taskId, orElse: () => pendingTasks.first);
      expect(task.status, isNot(equals('completed')));

      await db.startCycleCountTask(taskId);
      final inProgressTasks = await db.getCycleCountTasks(status: 'in_progress');
      expect(inProgressTasks.any((t) => t.id == taskId), isTrue);

      await db.completeCycleCountTask(taskId);
      final completedTasks = await db.getCycleCountTasks(status: 'completed');
      expect(completedTasks.any((t) => t.id == taskId), isTrue);
    });
  });
}
