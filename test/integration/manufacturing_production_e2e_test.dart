// ═══════════════════════════════════════════════════════════════════════════
// Manufacturing Production — E2E Integration Tests (Gap C)
//
// Covers the BOM → Work Order → Execute production lifecycle:
//   - Raw materials deducted on startProduction
//   - Finished goods added on completeProduction
//   - Insufficient raw materials block production start
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int finishedProductId;
  late int rawMaterial1Id;
  late int rawMaterial2Id;
  late int bomId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    finishedProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'FIN-001',
        name: 'منتج نهائي',
        salePrice: const Value(200.0),
        costPrice: const Value(100.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterial1Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-001',
        name: 'مادة خام 1',
        salePrice: const Value(30.0),
        costPrice: const Value(20.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterial2Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-002',
        name: 'مادة خام 2',
        salePrice: const Value(50.0),
        costPrice: const Value(30.0),
        trackInventory: const Value(true),
      ),
    );

    // BOM: 1 finished product requires 2 of raw1 + 3 of raw2
    bomId = await db.createBOM(
      finishedProductId: finishedProductId,
      bomCode: 'BOM-001',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': rawMaterial1Id, 'quantity': 2.0},
        {'rawMaterialId': rawMaterial2Id, 'quantity': 3.0},
      ],
    );
  });

  tearDown(() => db.close());

  Future<double> getStock(int productId) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return balance?.quantity ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  group('BOM + Work Order → Production', () {
    // ─────────────────────────────────────────────────────────────────────
    test('startProduction deducts all raw materials per BOM', () async {
      await db.adjustStock(productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');
      await db.adjustStock(productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 2.0, // produce 2 units → needs 4 of raw1 + 6 of raw2
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await db.startProduction(orderId);

      expect(await getStock(rawMaterial1Id), equals(6.0), reason: '10 - (2*2) = 6');
      expect(await getStock(rawMaterial2Id), equals(4.0), reason: '10 - (2*3) = 4');
    });

    test('completeProduction adds finished goods to inventory', () async {
      await db.adjustStock(productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');
      await db.adjustStock(productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 1.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await db.startProduction(orderId);
      await db.completeProduction(orderId);

      expect(await getStock(finishedProductId), greaterThan(0.0), reason: 'Finished goods must increase');
    });

    test('full lifecycle: start + complete produces correct quantities', () async {
      await db.adjustStock(productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 20.0, type: 'initial');
      await db.adjustStock(productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 20.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 3.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await db.startProduction(orderId);
      await db.completeProduction(orderId, actualProducedQty: 3.0);

      expect(await getStock(rawMaterial1Id), equals(14.0), reason: '20 - 6 = 14');
      expect(await getStock(rawMaterial2Id), equals(11.0), reason: '20 - 9 = 11');
      expect(await getStock(finishedProductId), greaterThanOrEqualTo(3.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Insufficient raw materials', () {
    // ─────────────────────────────────────────────────────────────────────
    test('startProduction throws when raw material stock is insufficient', () async {
      // Only 1 of each — but BOM needs 2 of raw1 for qty 1
      await db.adjustStock(productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 1.0, type: 'initial');
      await db.adjustStock(productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 1.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await expectLater(
        () => db.startProduction(orderId),
        throwsA(isA<Exception>()),
      );
    });

    test('raw material stock is unchanged when production start fails', () async {
      await db.adjustStock(productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 1.0, type: 'initial');
      await db.adjustStock(productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 1.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      try {
        await db.startProduction(orderId);
      } catch (_) {}

      expect(await getStock(rawMaterial1Id), equals(1.0), reason: 'No deduction should have occurred');
    });
  });
}
