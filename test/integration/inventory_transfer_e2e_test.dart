// ═══════════════════════════════════════════════════════════════════════════
// Inventory Transfer — E2E Integration Tests (Gap B)
//
// Verifies the transferStock() flow end-to-end:
//   - Source stock decreases, destination stock increases
//   - Transfer with insufficient stock fails before any mutation
//   - Bond header is created and items are recorded
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseA;
  late int warehouseB;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'مخزني', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'storekeeper',
      password: 'pw',
      displayName: 'Storekeeper',
      roleId: roleId,
    );

    warehouseA = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'مستودع أ',
        isDefault: const Value(true),
      ),
    );
    warehouseB = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(name: 'مستودع ب'),
    );
  });

  tearDown(() => db.close());

  Future<int> seedProduct(String code, {double stock = 0.0}) async {
    final id = await db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج $code',
        salePrice: const Value(50.0),
        costPrice: const Value(30.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(false),
      ),
    );
    if (stock > 0) {
      await db.adjustStock(
        productId: id,
        warehouseId: warehouseA,
        quantity: stock,
        type: 'initial',
      );
    }
    return id;
  }

  Future<double> getStock(int productId, int wh) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(wh)))
        .getSingleOrNull();
    return balance?.quantity ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  group('Stock Transfer: source decreases, destination increases', () {
    // ─────────────────────────────────────────────────────────────────────
    test('basic transfer moves stock from A to B', () async {
      final productId = await seedProduct('TRF-001', stock: 40.0);

      await db.transferStock(
        fromWarehouseId: warehouseA,
        toWarehouseId: warehouseB,
        items: [
          {'productId': productId, 'quantity': 10.0},
        ],
        userId: userId,
        notes: 'Test transfer',
      );

      expect(await getStock(productId, warehouseA), equals(30.0));
      expect(await getStock(productId, warehouseB), equals(10.0));
    });

    test('transfer of multiple products updates all balances', () async {
      final p1 = await seedProduct('TRF-002A', stock: 20.0);
      final p2 = await seedProduct('TRF-002B', stock: 30.0);

      await db.transferStock(
        fromWarehouseId: warehouseA,
        toWarehouseId: warehouseB,
        items: [
          {'productId': p1, 'quantity': 5.0},
          {'productId': p2, 'quantity': 15.0},
        ],
        userId: userId,
      );

      expect(await getStock(p1, warehouseA), equals(15.0));
      expect(await getStock(p2, warehouseA), equals(15.0));
      expect(await getStock(p1, warehouseB), equals(5.0));
      expect(await getStock(p2, warehouseB), equals(15.0));
    });

    test('bond header is created for every transfer', () async {
      final productId = await seedProduct('TRF-003', stock: 10.0);

      final bondsBefore = (await db.getInventoryBondsByType('transfer')).length;

      await db.transferStock(
        fromWarehouseId: warehouseA,
        toWarehouseId: warehouseB,
        items: [
          {'productId': productId, 'quantity': 5.0},
        ],
      );

      final bondsAfter = (await db.getInventoryBondsByType('transfer')).length;
      expect(bondsAfter, equals(bondsBefore + 1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Transfer with insufficient stock', () {
    // ─────────────────────────────────────────────────────────────────────
    test('transfer fails when source has insufficient stock', () async {
      final productId = await seedProduct('TRF-INS-001', stock: 5.0);

      expect(
        () => db.transferStock(
          fromWarehouseId: warehouseA,
          toWarehouseId: warehouseB,
          items: [
            {'productId': productId, 'quantity': 20.0},
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('stock is not mutated when transfer fails', () async {
      final productId = await seedProduct('TRF-INS-002', stock: 5.0);

      try {
        await db.transferStock(
          fromWarehouseId: warehouseA,
          toWarehouseId: warehouseB,
          items: [
            {'productId': productId, 'quantity': 99.0},
          ],
        );
      } catch (_) {}

      expect(await getStock(productId, warehouseA), equals(5.0));
      expect(await getStock(productId, warehouseB), equals(0.0));
    });
  });
}
