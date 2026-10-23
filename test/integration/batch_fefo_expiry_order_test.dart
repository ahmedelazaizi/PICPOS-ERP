// ═══════════════════════════════════════════════════════════════════════════
// A product that tracks expiry must sell nearest-expiry-first (FEFO).
// ═══════════════════════════════════════════════════════════════════════════
//
// `inventory_batch_dao` ships BOTH orderings. The file header says
// "Batch tracking, FEFO/FIFO operations, expiry management" and the section
// header says "BATCH & EXPIRY OPERATIONS (FEFO - First Expiry First Out)".
// But `getProductBatchesFEFO` / `deductFromBatchesFEFO` have ZERO production
// callers — the only reference is FEFO calling itself. The live path is
// `consumeBatchFIFO`, which orders by `created_at`.
//
// So the product sells the batch bought EARLIEST, not the one expiring
// SOONEST. On a shipment bought later but dated shorter — a short-dated
// promotional lot, a near-expiry supplier deal, anything cold-chain — the
// short-dated stock sits untouched until it expires and is written off, while
// long-dated stock leaves first.
//
// The system clearly means to care: batches are only created for
// `trackExpiry` products (purchase_dao ~699), and `sales_mutations_dao` ~105
// already BLOCKS a sale when every batch is expired. The ordering is the one
// piece that was never wired.
//
// Non-expiry products keep FIFO — for them "expiry" is either absent or
// fabricated, so ordering by it would be meaningless.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;
  });

  tearDown(() => db.close());

  Future<int> makeProduct({required bool trackExpiry, required String code}) {
    return db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج $code',
        trackInventory: const Value(true),
        trackExpiry: Value(trackExpiry),
      ),
    );
  }

  /// [ageDays] = how long ago the batch was purchased (drives FIFO order).
  /// [expiresInDays] = how soon it goes off (drives FEFO order).
  /// The two are deliberately independent so the orderings disagree.
  Future<int> seedBatch({
    required int productId,
    required String number,
    required int ageDays,
    required int expiresInDays,
    double quantity = 100,
  }) {
    return db.into(db.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            batchNumber: number,
            quantity: Value(quantity),
            unitCost: const Value(10),
            expiryDate: DateTime.now().add(Duration(days: expiresInDays)),
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

  test('an expiry-tracked product consumes the nearest-expiry batch first',
      () async {
    final productId =
        await makeProduct(trackExpiry: true, code: 'FEFO-MILK');
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 200,
      type: 'purchase',
      unitCost: 10,
      notes: 'seed',
    );

    // Bought FIRST, but long-dated — FIFO would take this one.
    final longDated = await seedBatch(
      productId: productId,
      number: 'LOT-OLD-LONG',
      ageDays: 30,
      expiresInDays: 90,
    );
    // Bought LATER, but goes off in a week — FEFO must take this one.
    final shortDated = await seedBatch(
      productId: productId,
      number: 'LOT-NEW-SHORT',
      ageDays: 1,
      expiresInDays: 7,
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -30,
      type: 'sale',
      notes: 'بيعة',
    );

    expect(await qtyOf(shortDated), 70.0,
        reason: 'the lot expiring in 7 days is the one that must move — '
            'leaving it on the shelf means writing it off next week while '
            'the 90-day lot was sold in its place');
    expect(await qtyOf(longDated), 100.0,
        reason: 'the long-dated lot has 90 days of shelf life and no reason '
            'to be picked first');
  });

  test('FEFO falls back to purchase order when two lots share an expiry date',
      () async {
    final productId =
        await makeProduct(trackExpiry: true, code: 'FEFO-TIE');
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 200,
      type: 'purchase',
      unitCost: 10,
      notes: 'seed',
    );

    final older = await seedBatch(
      productId: productId,
      number: 'LOT-TIE-OLD',
      ageDays: 30,
      expiresInDays: 30,
    );
    final newer = await seedBatch(
      productId: productId,
      number: 'LOT-TIE-NEW',
      ageDays: 1,
      expiresInDays: 30,
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -30,
      type: 'sale',
      notes: 'بيعة',
    );

    expect(await qtyOf(older), 70.0,
        reason: 'equal expiry → oldest stock first, so the tie-break stays '
            'deterministic instead of falling to row order');
    expect(await qtyOf(newer), 100.0);
  });

  test('a product WITHOUT expiry tracking keeps plain FIFO', () async {
    // Behaviour-preservation guard: ordering by a date that means nothing
    // for these products would be a silent change with no upside.
    final productId =
        await makeProduct(trackExpiry: false, code: 'FIFO-BOLT');
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 200,
      type: 'purchase',
      unitCost: 10,
      notes: 'seed',
    );

    final oldest = await seedBatch(
      productId: productId,
      number: 'LOT-A',
      ageDays: 30,
      expiresInDays: 90,
    );
    final newest = await seedBatch(
      productId: productId,
      number: 'LOT-B',
      ageDays: 1,
      expiresInDays: 7, // nearer expiry, but irrelevant here
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -30,
      type: 'sale',
      notes: 'بيعة',
    );

    expect(await qtyOf(oldest), 70.0,
        reason: 'no expiry tracking → oldest purchase first, exactly as '
            'before');
    expect(await qtyOf(newest), 100.0);
  });
}
