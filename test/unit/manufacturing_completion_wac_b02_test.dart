// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — B-02 (MAJOR): completeProduction must stamp the finished good's
// per-warehouse average_cost AND stock_movements.unit_cost with the ACTUAL
// production cost, not the stale products.costPrice.
//
// Root cause: manufacturing_dao.completeProduction called adjustStock(...) for
// the produced output WITHOUT threading `unitCost:`. Inside adjustStock, when
// unitCost is null the warehouse blend + movement fall back to the OLD
// product.costPrice (inventory_dao.dart:221-222, 253). The correct per-unit
// production cost (totalCost / produced) is already available at :484.
//
// This test sets the finished good's stale costPrice to a sentinel that
// differs from the real production cost, so it FAILS pre-fix (stamps 999) and
// PASSES post-fix (stamps the production cost). It reads the authoritative
// production cost from the order's own totalCost/producedQty, which is set
// independently of the adjustStock/WAC path — so it stays correct even after
// B-01's separate ordering fix.
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

  // Sentinel stale cost on the finished good — must differ from the real
  // production cost so the assertion is meaningful (fails pre-fix).
  const double staleFinishedCostPrice = 999.0;

  setUp(() async {
    db = AppDatabase.forTesting();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    finishedProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'FIN-B02',
        name: 'منتج نهائي B02',
        salePrice: const Value(2000.0),
        costPrice: const Value(staleFinishedCostPrice), // stale / wrong
        trackInventory: const Value(true),
      ),
    );

    rawMaterial1Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-B02-1',
        name: 'مادة خام 1',
        salePrice: const Value(30.0),
        costPrice: const Value(20.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterial2Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-B02-2',
        name: 'مادة خام 2',
        salePrice: const Value(50.0),
        costPrice: const Value(30.0),
        trackInventory: const Value(true),
      ),
    );

    // BOM: 1 finished unit needs 2 of raw1 (@20) + 3 of raw2 (@30) = 130/unit
    bomId = await db.createBOM(
      finishedProductId: finishedProductId,
      bomCode: 'BOM-B02',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': rawMaterial1Id, 'quantity': 2.0},
        {'rawMaterialId': rawMaterial2Id, 'quantity': 3.0},
      ],
    );
  });

  tearDown(() => db.close());

  test(
    'completeProduction stamps finished-good average_cost & movement.unit_cost '
    'with the real production cost, not the stale products.costPrice',
    () async {
      // Stock raw materials (initial — no unitCost, keeps raw costPrice as-is)
      await db.adjustStock(
          productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');
      await db.adjustStock(
          productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 10.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 1.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await db.startProduction(orderId);
      await db.completeProduction(orderId, actualProducedQty: 1.0);

      // Authoritative production cost from the order itself (set at
      // manufacturing_dao.dart:515, independent of the adjustStock/WAC path).
      final order = await (db.select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
  // ignore: dead_code
      final produced = order.producedQty ?? 1.0;
      expect(produced, greaterThan(0.0));
      final expectedUnitCost = order.totalCost / produced;

      // Sanity: the real production cost MUST differ from the stale costPrice,
      // otherwise this test could not distinguish pre-fix from post-fix.
      expect(
        expectedUnitCost,
        isNot(closeTo(staleFinishedCostPrice, 0.001)),
        reason: 'production cost ($expectedUnitCost) must differ from stale '
            'costPrice ($staleFinishedCostPrice) for a meaningful assertion',
      );
      // (materials: 2*20 + 3*30 = 130)
      expect(expectedUnitCost, closeTo(130.0, 1e-6));

      // (a) stock_movements.unit_cost for the manufacturing_in movement
      final inMovement = await (db.select(db.stockMovements)
            ..where((m) =>
                m.productId.equals(finishedProductId) &
                m.movementType.equals('manufacturing_in')))
          .getSingle();
      expect(
        inMovement.unitCost,
        closeTo(expectedUnitCost, 1e-6),
        reason: 'manufacturing_in movement must record the real production '
            'unit cost, not the stale products.costPrice',
      );

      // (b) per-warehouse inventory_balances.average_cost for the finished good
      final balance = await (db.select(db.inventoryBalances)
            ..where((b) =>
                b.productId.equals(finishedProductId) &
                b.warehouseId.equals(warehouseId)))
          .getSingle();
      expect(
        balance.averageCost,
        closeTo(expectedUnitCost, 1e-6),
        reason: 'per-warehouse average_cost must reflect the real production '
            'cost, not the stale products.costPrice',
      );
    },
  );
}
