// ═══════════════════════════════════════════════════════════════════════════
// FIFO batch consumption must stay inside the warehouse that sold the goods.
// ═══════════════════════════════════════════════════════════════════════════
//
// `getProductBatchesFIFO(productId)` filters by product and status only, and
// `consumeBatchFIFO` never receives the warehouseId even though `adjustStock`
// — its only caller — has it as a required parameter. So a sale in branch B
// walks the global batch list and eats branch A's oldest batch.
//
// SCOPE — this is a TRACEABILITY and EXPIRY defect, not a valuation one.
// `product_batches.unit_cost` feeds no COGS or valuation path: COGS comes from
// `sales_invoice_items.cost_price` (products.costPrice / WAC) and the asset
// figure from `products.cost_price`. Nothing here moves the ledger. What it
// does break:
//   • expiry tracking — branch B consumes a batch that is physically in A,
//     so A's real expiring stock stays "unsold" in the books;
//   • recall traceability — the wrong lot is recorded as dispatched;
//   • per-warehouse batch quantities stop matching per-warehouse stock.
//
// `product_batches.warehouse_id` already exists and is NOT NULL, so no schema
// migration is needed — the column is simply never used in the queries.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId;
  late int warehouseA;
  late int warehouseB;

  setUp(() async {
    db = AppDatabase.forTesting();

    warehouseA = (await db.getDefaultWarehouse())!.id;
    warehouseB = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'فرع ب',
            globalId: const Value('gid-wh-b-batch'),
          ),
        );

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'BATCH-ISO-1',
        name: 'منتج بصلاحية',
        trackInventory: const Value(true),
        trackExpiry: const Value(true),
      ),
    );

    // 100 units physically present in EACH warehouse.
    for (final wh in [warehouseA, warehouseB]) {
      await db.adjustStock(
        productId: productId,
        warehouseId: wh,
        quantity: 100,
        type: 'purchase',
        unitCost: 10,
        notes: 'seed',
      );
    }
  });

  tearDown(() => db.close());

  /// A batch belonging to [warehouseId]. [ageDays] controls FIFO order —
  /// larger means older, so it is picked first by `ORDER BY created_at ASC`.
  Future<int> seedBatch({
    required int warehouseId,
    required String number,
    required int ageDays,
    double quantity = 100,
  }) async {
    return db.into(db.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            batchNumber: number,
            quantity: Value(quantity),
            unitCost: const Value(10),
            expiryDate: DateTime.now().add(Duration(days: 90 - ageDays)),
            createdAt: Value(DateTime.now().subtract(Duration(days: ageDays))),
            status: const Value('active'),
          ),
        );
  }

  Future<double> qtyOf(int batchId) async {
    final row = await (db.select(db.productBatches)
          ..where((b) => b.id.equals(batchId)))
        .getSingle();
    return row.quantity;
  }

  test('a sale from warehouse B does not consume warehouse A batches',
      () async {
    // A's batch is deliberately the OLDEST, so a warehouse-blind FIFO walk
    // reaches for it first — that is exactly the bug.
    final batchA = await seedBatch(
        warehouseId: warehouseA, number: 'LOT-A-OLD', ageDays: 30);
    final batchB = await seedBatch(
        warehouseId: warehouseB, number: 'LOT-B-NEW', ageDays: 1);

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseB,
      quantity: -30,
      type: 'sale',
      notes: 'بيعة من فرع ب',
    );

    expect(await qtyOf(batchA), 100.0,
        reason: 'warehouse A never sold anything — its lot must be untouched. '
            'Consuming it here means A shows expiring stock it already '
            '"sold", and the wrong lot is on record for a recall');
    expect(await qtyOf(batchB), 70.0,
        reason: 'the 30 units left from warehouse B, so B\'s own lot is what '
            'must go down');
  });

  test('a return to warehouse B does not inflate a warehouse A batch',
      () async {
    // restoreBatchForReturn picks "the most recent batch for this product"
    // with no warehouse filter at all — so a return in B can top up A.
    final batchA = await seedBatch(
        warehouseId: warehouseA, number: 'LOT-A-RECENT', ageDays: 1);
    final batchB = await seedBatch(
        warehouseId: warehouseB, number: 'LOT-B-OLD', ageDays: 30);

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseB,
      quantity: 10,
      type: 'return',
      notes: 'مرتجع لفرع ب',
    );

    expect(await qtyOf(batchA), 100.0,
        reason: 'goods returned to B cannot appear in A\'s lot — that invents '
            'physical stock in a warehouse nobody delivered to');
    expect(await qtyOf(batchB), 110.0,
        reason: 'the returned units belong to a lot in the receiving '
            'warehouse');
  });
}
