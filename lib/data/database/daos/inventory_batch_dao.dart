// =======================================================================
// INVENTORY BATCH DAO
// Extracted from inventory_dao.dart — PIR Phase 4 God File Splitting
// Batch tracking, FEFO/FIFO operations, expiry management
// =======================================================================

part of '../database.dart';

/// Extension for batch tracking and expiry/FEFO/FIFO operations
extension InventoryBatchDao on AppDatabase {


  // ═══════════════════════════════════════════════════════════════════════
  // BATCH & EXPIRY OPERATIONS (FEFO - First Expiry First Out)
  // ═══════════════════════════════════════════════════════════════════════

  /// Insert a new product batch
  Future<int> insertBatch(ProductBatchesCompanion batch) =>
      into(productBatches).insert(batch);

  /// Get all active batches for a product, ordered by expiry date (FEFO)
  Future<List<ProductBatch>> getProductBatchesFEFO(int productId) async {
    return (select(productBatches)
          ..where(
            (b) =>
                b.productId.equals(productId) &
                b.status.equals('active') &
                b.quantity.isBiggerThan(const Variable(0)),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.expiryDate)]))
        .get();
  }

  /// Deduct quantity from batches using FEFO method
  Future<List<Map<String, dynamic>>> deductFromBatchesFEFO({
    required int productId,
    required double quantity,
  }) async {
    final batches = await getProductBatchesFEFO(productId);
    double remaining = quantity;
    final deductions = <Map<String, dynamic>>[];

    for (final batch in batches) {
      if (remaining <= 0) break;

      final deduct = remaining > batch.quantity ? batch.quantity : remaining;
      final newQty = batch.quantity - deduct;

      await (update(productBatches)..where((b) => b.id.equals(batch.id))).write(
        ProductBatchesCompanion(
          quantity: Value(newQty),
          status: Value(newQty <= 0 ? 'depleted' : 'active'),
        ),
      );

      deductions.add({
        'batchId': batch.id,
        'batchNumber': batch.batchNumber,
        'quantity': deduct,
        'unitCost': batch.unitCost,
        'expiryDate': batch.expiryDate,
      });

      remaining -= deduct;
    }

    return deductions;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FIFO BATCH CONSUMPTION (First In First Out — by purchase/creation date)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all active batches for a product, ordered by creation date (FIFO)
  /// Oldest purchased batches are consumed first.
  ///
  /// [warehouseId] scopes the walk to the stock that is physically in the
  /// warehouse doing the selling. Without it a sale in one branch consumed
  /// another branch's oldest lot — the ledger stayed right (batch unit_cost
  /// feeds no COGS path) but expiry tracking and recall traceability did not:
  /// the untouched branch kept showing stock it had already "sold", and the
  /// wrong lot went on record as dispatched.
  ///
  /// Nullable so existing/global callers keep today's behaviour verbatim;
  /// `product_batches.warehouse_id` is NOT NULL, so no migration is involved.
  Future<List<ProductBatch>> getProductBatchesFIFO(
    int productId, {
    int? warehouseId,
  }) async {
    return (select(productBatches)
          ..where(
            (b) {
              final base = b.productId.equals(productId) &
                  b.status.equals('active') &
                  b.quantity.isBiggerThan(const Variable(0));
              return warehouseId == null
                  ? base
                  : base & b.warehouseId.equals(warehouseId);
            },
          )
          ..orderBy([(b) => OrderingTerm.asc(b.createdAt)]))
        .get();
  }

  /// Consume quantity from batches using FIFO method (oldest first by createdAt).
  ///
  /// Returns a list of deduction records for audit/traceability:
  /// `[{batchId, batchNumber, quantity, unitCost, expiryDate}]`
  ///
  /// If no active batches exist, returns an empty list (stock is still
  /// deducted globally via adjustStock — batches are optional).
  Future<List<Map<String, dynamic>>> consumeBatchFIFO({
    required int productId,
    required double quantity,
    // Required, not optional: the sole caller (adjustStock) already takes
    // warehouseId as a required parameter, so there is no call site that
    // legitimately does not know it. Leaving it optional is what let the
    // value sit unused in the caller's scope for this long.
    required int warehouseId,
  }) async {
    final batches =
        await getProductBatchesFIFO(productId, warehouseId: warehouseId);
    if (batches.isEmpty) return [];

    double remaining = quantity;
    final deductions = <Map<String, dynamic>>[];

    for (final batch in batches) {
      if (remaining <= 0) break;

      final deduct = remaining > batch.quantity ? batch.quantity : remaining;
      final newQty = batch.quantity - deduct;

      await (update(productBatches)..where((b) => b.id.equals(batch.id))).write(
        ProductBatchesCompanion(
          quantity: Value(newQty),
          status: Value(newQty <= 0 ? 'depleted' : 'active'),
        ),
      );

      deductions.add({
        'batchId': batch.id,
        'batchNumber': batch.batchNumber,
        'quantity': deduct,
        'unitCost': batch.unitCost,
        'expiryDate': batch.expiryDate,
      });

      remaining -= deduct;
    }

    return deductions;
  }

  /// Restore batch quantity on sales return.
  ///
  /// Strategy: add stock back to the most recently depleted/active batch
  /// for this product. If no batch exists, creates a 'return' batch.
  Future<void> restoreBatchForReturn({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? notes,
  }) async {
    // Find the most recent batch IN THE RECEIVING WAREHOUSE. The parameter was
    // already being passed in and then ignored by this query, so a return
    // booked to one branch could top up a lot sitting in another — inventing
    // physical stock in a warehouse nobody delivered to.
    final recentBatch = await (select(productBatches)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
          ..limit(1))
        .getSingleOrNull();

    if (recentBatch != null) {
      // Restore to existing batch
      final newQty = recentBatch.quantity + quantity;
      await (update(productBatches)..where((b) => b.id.equals(recentBatch.id)))
          .write(
        ProductBatchesCompanion(
          quantity: Value(newQty),
          status: const Value('active'),
        ),
      );
    } else {
      // No batch history — create a return batch
      await insertBatch(
        ProductBatchesCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          batchNumber: 'RTN-${DateTime.now().millisecondsSinceEpoch}',
          expiryDate: DateTime.now().add(const Duration(days: 365)),
          quantity: Value(quantity),
          initialQuantity: Value(quantity),
          status: const Value('active'),
        ),
      );
    }
  }

  /// Get products with expired batches
  Future<List<ProductBatch>> getExpiredBatches() async {
    return (select(productBatches)
          ..where(
            (b) =>
                b.expiryDate.isSmallerOrEqual(Variable(DateTime.now())) &
                b.quantity.isBiggerThan(const Variable(0)),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.expiryDate)]))
        .get();
  }

  /// Get products expiring within specified days
  Future<List<ProductBatch>> getExpiringBatches(int days) async {
    final futureDate = DateTime.now().add(Duration(days: days));
    return (select(productBatches)
          ..where(
            (b) =>
                b.expiryDate.isSmallerOrEqual(Variable(futureDate)) &
                b.expiryDate.isBiggerThan(Variable(DateTime.now())) &
                b.quantity.isBiggerThan(const Variable(0)),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.expiryDate)]))
        .get();
  }

  /// Get batch history for a product
  Future<List<ProductBatch>> getProductBatches(int productId) async {
    return (select(productBatches)
          ..where((b) => b.productId.equals(productId))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .get();
  }

  /// Get earliest expiry date for each product with active batches
  Future<Map<int, DateTime>> getProductExpiryMap() async {
    final batches =
        await (select(productBatches)
              ..where((b) => b.quantity.isBiggerThan(const Variable(0)))
              ..orderBy([(b) => OrderingTerm.asc(b.expiryDate)]))
            .get();

    final Map<int, DateTime> result = {};
    for (final batch in batches) {
      if (!result.containsKey(batch.productId)) {
        result[batch.productId] = batch.expiryDate;
      }
    }
    return result;
  }

  /// Watch products requiring expiry tracking
  Stream<List<Product>> watchExpiryTrackingProducts() {
    return (select(products)
          ..where((p) => p.trackExpiry.equals(true) & p.isActive.equals(true)))
        .watch();
  }

  /// Mark expired batches
  Future<void> markExpiredBatches() async {
    await (update(productBatches)..where(
          (b) =>
              b.expiryDate.isSmallerThan(Variable(DateTime.now())) &
              b.status.equals('active'),
        ))
        .write(const ProductBatchesCompanion(status: Value('expired')));
  }

}
