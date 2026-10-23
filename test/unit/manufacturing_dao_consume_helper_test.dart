// ═══════════════════════════════════════════════════════════════════════════
// Feature 009 / T011 — consumeBomComponentsAtomic policy tests
//
// Exercises the three stock-shortage policies (block / allowNegative /
// clampToZero) on the shared helper that backs both startProduction
// (manual) and applyAutoDepleteForSale (sale-time, T015). The block path
// also covers the existing startProduction behavior (Constitution I).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int finishedProductId;
  late int rawMaterialId;
  late int bomId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    finishedProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'F009-FIN',
        name: 'منتج للاختبار',
        salePrice: const Value(100.0),
        costPrice: const Value(50.0),
        trackInventory: const Value(true),
      ),
    );

    rawMaterialId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'F009-RAW',
        name: 'مادة خام',
        salePrice: const Value(20.0),
        costPrice: const Value(10.0),
        trackInventory: const Value(true),
        // Required so allowNegative policy can deduct past zero — the
        // underlying _updateWarehouseBalance enforces this product flag
        // independently of our shortage policy. (T015 will document the
        // production-side coupling for callers.)
        allowNegativeSale: const Value(true),
      ),
    );

    // 1 finished -> 2 raw (no wastage to keep math clean)
    bomId = await db.createBOM(
      finishedProductId: finishedProductId,
      bomCode: 'F009-BOM',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': rawMaterialId, 'quantity': 2.0, 'wastagePercent': 0.0},
      ],
    );
  });

  tearDown(() => db.close());

  Future<double> stockOf(int productId) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return balance?.quantity ?? 0.0;
  }

  // Helper to call consumeBomComponentsAtomic inside a Drift tx.
  Future<List<ConsumedLine>> runConsume({
    required double multiplier,
    required StockShortagePolicy policy,
  }) async {
    late List<ConsumedLine> consumed;
    await db.transaction(() async {
      consumed = await db.consumeBomComponentsAtomic(
        bomId: bomId,
        multiplier: multiplier,
        warehouseId: warehouseId,
        branchId: null,
        context: const BomConsumptionContext(
          movementType: 'sale_auto_deplete',
          referenceType: 'sale_invoice',
          referenceId: 1,
          notes: 'test',
        ),
        shortagePolicy: policy,
      );
    });
    return consumed;
  }

  group('consumeBomComponentsAtomic — happy path', () {
    test('deducts the exact required quantity when stock is sufficient',
        () async {
      await db.adjustStock(
          productId: rawMaterialId,
          warehouseId: warehouseId,
          quantity: 100.0,
          type: 'initial');

      final consumed =
          await runConsume(multiplier: 3.0, policy: StockShortagePolicy.block);

      expect(consumed, hasLength(1));
      expect(consumed.first.rawMaterialId, rawMaterialId);
      expect(consumed.first.qty, 6.0, reason: '2 components/unit × 3 units');
      expect(consumed.first.unitCost, 10.0);
      expect(consumed.first.lineCost, 60.0);
      expect(await stockOf(rawMaterialId), 94.0, reason: '100 − 6');
    });
  });

  group('consumeBomComponentsAtomic — shortage policies (FR-016)', () {
    test('block: throws InsufficientStockException, transaction rolled back',
        () async {
      // Need 10, have 5 → short by 5. Block policy must throw.
      await db.adjustStock(
          productId: rawMaterialId,
          warehouseId: warehouseId,
          quantity: 5.0,
          type: 'initial');

      Object? caught;
      try {
        await runConsume(multiplier: 5.0, policy: StockShortagePolicy.block);
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<InsufficientStockException>(),
          reason: 'block policy must raise InsufficientStockException');
      final iss = caught as InsufficientStockException;
      expect(iss.shortages, isNotNull);
      expect(iss.shortages!.length, 1);
      expect(iss.shortages![rawMaterialId]?.required, 10.0);
      expect(iss.shortages![rawMaterialId]?.available, 5.0);
      expect(iss.message, contains('مخزون غير كافٍ'),
          reason: 'message must preserve legacy Arabic wording');

      // Transaction rolled back → stock untouched.
      expect(await stockOf(rawMaterialId), 5.0,
          reason: 'rollback restores original stock');
    });

    test('allowNegative: proceeds with full required qty, stock goes negative',
        () async {
      await db.adjustStock(
          productId: rawMaterialId,
          warehouseId: warehouseId,
          quantity: 5.0,
          type: 'initial');

      final consumed = await runConsume(
          multiplier: 5.0, policy: StockShortagePolicy.allowNegative);

      expect(consumed, hasLength(1));
      expect(consumed.first.qty, 10.0, reason: 'full required deduction');
      expect(await stockOf(rawMaterialId), -5.0,
          reason: '5 − 10 = −5 (negative allowed)');
    });

    test('clampToZero: deducts only available, residual not charged',
        () async {
      await db.adjustStock(
          productId: rawMaterialId,
          warehouseId: warehouseId,
          quantity: 5.0,
          type: 'initial');

      final consumed = await runConsume(
          multiplier: 5.0, policy: StockShortagePolicy.clampToZero);

      expect(consumed, hasLength(1));
      expect(consumed.first.qty, 5.0,
          reason: 'clamped to currentStock (the available 5)');
      expect(await stockOf(rawMaterialId), 0.0,
          reason: 'stock floored to zero');
    });

    test('clampToZero: skips component entirely when stock <= 0', () async {
      // No initial stock at all.
      final consumed = await runConsume(
          multiplier: 5.0, policy: StockShortagePolicy.clampToZero);

      expect(consumed, isEmpty,
          reason: 'no rows when nothing was deductible');
      expect(await stockOf(rawMaterialId), 0.0);
    });
  });
}
