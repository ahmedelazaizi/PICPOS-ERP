// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — W1-B findings B-03 + B-04 (inventory transfers)
//
// B-03 [MAJOR]: transfer_in must blend the destination per-warehouse WAC
//   against the SOURCE warehouse's average_cost — NOT the global
//   product.costPrice (which may have been re-blended from other warehouses).
//
// B-04 [MAJOR]: `enable_negative_sales` must NOT open silent negative stock on
//   TRANSFERS. A transfer exceeding source stock is blocked regardless of the
//   sales flag, while a SALE with the flag on keeps allowing negative
//   (unchanged behaviour).
//
// Both tests FAIL against the pre-fix code and PASS after the fix in
// inventory_transfers_dao.dart::transferStock.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseA;
  late int warehouseB;

  setUp(() async {
    db = AppDatabase.forTesting();
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

  Future<int> seedProduct(String code, {required double costPrice}) {
    return db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج $code',
        salePrice: const Value(50.0),
        costPrice: Value(costPrice),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(false),
      ),
    );
  }

  Future<InventoryBalance?> balance(int productId, int wh) {
    return (db.select(db.inventoryBalances)
          ..where(
              (b) => b.productId.equals(productId) & b.warehouseId.equals(wh)))
        .getSingleOrNull();
  }

  // ── B-03 ───────────────────────────────────────────────────────────────
  test(
      'B-03: transfer_in blends destination against the SOURCE warehouse WAC, '
      'not the global costPrice', () async {
    // Global costPrice = 30, but the SOURCE warehouse holds stock @ WAC 100.
    final productId = await seedProduct('B03', costPrice: 30.0);
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseA,
      quantity: 10.0,
      type: 'initial',
      unitCost: 100.0, // establishes source-warehouse average_cost = 100
    );

    // sanity: source WAC == 100, but global costPrice is still 30 (they differ)
    expect((await balance(productId, warehouseA))!.averageCost,
        closeTo(100.0, 1e-9));
    expect((await db.getProductById(productId))!.costPrice, closeTo(30.0, 1e-9));

    await db.transferStock(
      fromWarehouseId: warehouseA,
      toWarehouseId: warehouseB, // empty destination
      items: [
        {'productId': productId, 'quantity': 5.0},
      ],
    );

    // Destination per-warehouse WAC must equal the SOURCE WAC (100), not 30.
    final destBal = await balance(productId, warehouseB);
    expect(destBal, isNotNull);
    expect(
      destBal!.averageCost,
      closeTo(100.0, 1e-9),
      reason:
          'value must move with the goods (source WAC 100), not global costPrice 30',
    );

    // ...and the transfer_in movement carries the source unit cost.
    final inMove = await (db.select(db.stockMovements)
          ..where((m) =>
              m.productId.equals(productId) &
              m.warehouseId.equals(warehouseB) &
              m.movementType.equals('transfer_in')))
        .getSingleOrNull();
    expect(inMove, isNotNull);
    expect(inMove!.unitCost, closeTo(100.0, 1e-9));
  });

  // ── B-04 ───────────────────────────────────────────────────────────────
  test(
      'B-04: enable_negative_sales does NOT open negative TRANSFERS; '
      'a SALE with the flag still allows negative (unchanged)', () async {
    await db.setSetting('enable_negative_sales', 'true');

    final productId = await seedProduct('B04', costPrice: 20.0);
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseA,
      quantity: 10.0,
      type: 'initial',
    );

    // A TRANSFER exceeding source stock must be BLOCKED even with the flag on.
    await expectLater(
      db.transferStock(
        fromWarehouseId: warehouseA,
        toWarehouseId: warehouseB,
        items: [
          {'productId': productId, 'quantity': 100.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    // No silent −90 on the source; destination was never created.
    expect((await balance(productId, warehouseA))!.quantity, equals(10.0));
    expect(await balance(productId, warehouseB), isNull);

    // CONTROL: a SALE with the flag on still honours enable_negative_sales.
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseA,
      quantity: -100.0,
      type: 'sale',
    );
    expect(
      (await balance(productId, warehouseA))!.quantity,
      equals(-90.0),
      reason:
          'sales path must keep honouring enable_negative_sales (behaviour unchanged)',
    );
  });
}
