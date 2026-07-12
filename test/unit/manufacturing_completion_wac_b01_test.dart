// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — B-01 (BLOCKER): completeProduction must blend the finished good's
// GLOBAL WAC (products.costPrice) BEFORE bumping current_stock, so the produced
// quantity is not counted on both sides of the average.
//
// Root cause: manufacturing_dao.completeProduction called adjustStock(+produced)
// — which writes products.current_stock — BEFORE updateProductWAC, which reads
// products.current_stock as its "before" quantity. Producing N units at cost C
// onto empty stock then computed:
//     (N*0 + N*C) / (N + N) = C/2      ← produced qty double-counted → HALVED
// instead of the correct:
//     (0*0 + N*C) / (0 + N) = C
// So every manufactured good's cost came out at half, understating COGS on all
// later sales of it. The purchase path already blends WAC-before-stock; the fix
// reorders manufacturing to match.
//
// This test produces onto EMPTY finished stock with costPrice 0 and asserts the
// resulting products.costPrice equals the real per-unit production cost (read
// from the order's own totalCost/producedQty — an independent code path). It
// FAILS pre-fix (costPrice = C/2) and PASSES post-fix (costPrice = C).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

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

    // Finished good is fresh: costPrice 0 and current_stock 0 (never produced).
    // This is the natural state that exposes the clean halving.
    finishedProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'FIN-B01',
        name: 'منتج نهائي B01',
        salePrice: const Value(2000.0),
        costPrice: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterial1Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-B01-1',
        name: 'مادة خام 1',
        salePrice: const Value(30.0),
        costPrice: const Value(20.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterial2Id = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RAW-B01-2',
        name: 'مادة خام 2',
        salePrice: const Value(50.0),
        costPrice: const Value(30.0),
        trackInventory: const Value(true),
      ),
    );

    // BOM: 1 finished unit needs 2 of raw1 (@20) + 3 of raw2 (@30) = 130/unit
    bomId = await db.createBOM(
      finishedProductId: finishedProductId,
      bomCode: 'BOM-B01',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': rawMaterial1Id, 'quantity': 2.0},
        {'rawMaterialId': rawMaterial2Id, 'quantity': 3.0},
      ],
    );
  });

  tearDown(() => db.close());

  test(
    'completeProduction onto empty stock sets products.costPrice to the FULL '
    'production cost, not half (WAC blended before stock bump)',
    () async {
      // Stock raw materials only (finished good stays at qty 0 / cost 0).
      // 4 units × (2 raw1 + 3 raw2) = 8 raw1 + 12 raw2 consumed — stock plenty.
      await db.adjustStock(
          productId: rawMaterial1Id, warehouseId: warehouseId, quantity: 100.0, type: 'initial');
      await db.adjustStock(
          productId: rawMaterial2Id, warehouseId: warehouseId, quantity: 100.0, type: 'initial');

      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 4.0,
        warehouseId: warehouseId,
        startDate: DateTime.now(),
      );

      await db.startProduction(orderId);
      await db.completeProduction(orderId, actualProducedQty: 4.0);

      // Authoritative production cost from the order itself (set directly at
      // completeProduction, independent of the adjustStock/WAC path).
      final order = await (db.select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      final produced = order.producedQty ?? 4.0;
      expect(produced, greaterThan(0.0));
      final expectedUnitCost = order.totalCost / produced;
      // materials per unit: 2*20 + 3*30 = 130
      expect(expectedUnitCost, closeTo(130.0, 1e-6));

      // The finished good's global WAC (COGS source-of-truth) must be the FULL
      // unit cost. Pre-fix (stock bumped before WAC read) yields 130/2 = 65.
      final product = await db.getProductById(finishedProductId);
      expect(
        product!.costPrice,
        closeTo(expectedUnitCost, 1e-6),
        reason: 'products.costPrice must equal the full production cost '
            '($expectedUnitCost); a halved value (${expectedUnitCost / 2}) '
            'means adjustStock ran before updateProductWAC and the produced '
            'qty was double-counted in the average.',
      );
    },
  );
}
