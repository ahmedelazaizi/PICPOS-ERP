// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY DAO - Stock Movements and Warehouse Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all inventory-related database operations extracted from
// the main database.dart file for better organization and maintainability.
//
// Usage: Import in database.dart and access via AppDatabase instance.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Inventory-related database operations
extension InventoryDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // STOCK MOVEMENTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all stock movements
  Stream<List<StockMovement>> watchAllStockMovements() {
    return (select(
      stockMovements,
    )..orderBy([(m) => OrderingTerm.desc(m.createdAt)])).watch();
  }

  /// Alias for watchAllStockMovements
  Stream<List<StockMovement>> watchRecentStockMovements() =>
      watchAllStockMovements();

  /// Get stock movements for a product.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets.
  Future<List<StockMovement>> getMovementsForProduct(
    int productId, {
    int limit = 500,
    int offset = 0,
  }) {
    return (select(stockMovements)
          ..where((m) => m.productId.equals(productId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Watch stock movements for a product (Stream)
  Stream<List<StockMovement>> watchProductMovements(int productId) {
    return (select(stockMovements)
          ..where((m) => m.productId.equals(productId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
        .watch();
  }

  /// Create a stock movement record.
  ///
  /// UUID-First (Phase 1): if the caller did not supply a `globalId`, mint a
  /// fresh UUID v7 so every movement has a stable cross-install identity for
  /// sync replay / idempotency.
  Future<int> createStockMovement(StockMovementsCompanion movement) {
    final hasGid = movement.globalId.present &&
        (movement.globalId.value?.isNotEmpty ?? false);
    final withGid = hasGid
        ? movement
        : movement.copyWith(globalId: Value(UuidV7.generate()));
    return into(stockMovements).insert(withGid);
  }

  /// Get movements by date range.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets.
  Future<List<StockMovement>> getMovementsByDateRange(
    DateTime from,
    DateTime to, {
    int limit = 500,
    int offset = 0,
  }) {
    return (select(stockMovements)
          ..where((m) => m.createdAt.isBetween(Variable(from), Variable(to)))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get movements by type.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets.
  Future<List<StockMovement>> getMovementsByType(
    String movementType, {
    int limit = 500,
    int offset = 0,
  }) {
    return (select(stockMovements)
          ..where((m) => m.movementType.equals(movementType))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Issue 5 (Feature 021): used by the Excel opening-stock importer to
  /// detect a previous opening_stock movement for the same product +
  /// warehouse pair before creating another. Re-importing the same file
  /// without this check double-counted opening balances.
  Future<bool> hasOpeningStockMovement({
    required int productId,
    required int warehouseId,
  }) async {
    final row = await (select(stockMovements)
          ..where((m) =>
              m.productId.equals(productId) &
              m.warehouseId.equals(warehouseId) &
              m.movementType.equals('opening_stock'))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? referenceType,
    int? referenceId,
    String? notes,
    int? userId, // R-28: audit trail
    DateTime? movementDate, // H-07: Allow specifying the actual movement date
    int? branchId, // PIR Phase 5: Branch Isolation
    double? unitCost, // Cost per unit — falls back to product.costPrice
    // Spec 135 BUG-A: caller-minted UUIDv7 identifying THIS adjustment
    // EVENT. Threaded identically into the local stock_movements.globalId
    // AND the autoposted JE's deterministic globalId AND the server submit,
    // so client and server converge on the same JE id for the SAME event
    // (dedup on replay) while two genuinely-different adjustments of the
    // same (product, warehouse, type) get DIFFERENT ids (no false
    // collision). Falls back to a fresh UUIDv7 when null (in-process
    // callers that don't supply one) — still event-unique, just not
    // cross-instance-deduplicable, which matches pre-135 behaviour for
    // those callers.
    String? adjustmentEventGid,
    // Spec 147 (S-COUNT): when false, the internal per-event settlement JE
    // below is SKIPPED — the balance, global stock cache, movement (with its
    // globalId), FIFO batch, closed-period + negative-stock guards all still
    // run. The count subsystems pass false because they post ONE aggregate
    // settlement entry per session themselves (finalizeAudit /
    // finalizeCycleCountTask), so letting adjustStock also post here would
    // double-count the same variance in the GL. Default true ⇒ every existing
    // caller (manual adjustments, write-offs, losses) is unchanged.
    bool postAdjustmentJournal = true,
  }) async {
    // PIR-04: Entire adjustStock wrapped in transaction for atomicity.
    // Prevents partial writes (product stock updated but warehouse balance/movement missing).
    await transaction(() async {
      // PHASE-10: SQLite IMMEDIATE mode — prevents WAL-level race conditions
      // SQLite's default DEFERRED lock allows concurrent readers to become writers,
      // potentially causing SQLITE_BUSY. IMMEDIATE acquires a write lock upfront.
      if (!isPostgres) {
        try {
          await customStatement('PRAGMA busy_timeout = 5000');
        } catch (e) { debugPrint('[Inventory] PRAGMA busy_timeout: $e'); }
      }

      // PIR-06: Defensive Row-Level Locking (Pessimistic Concurrency Control)
      // This strictly prevents the "Lost Update" race condition when concurrent 
      // API requests (from multiple branches) attempt to modify stock simultaneously.
      // PostgreSQL's default Read-Committed isolation allows lost updates on 
      // read-modify-write cycles unless explicit row locks are acquired.
      if (isPostgres) {
        // Lock the product row
        await customSelect(
          'SELECT id FROM products WHERE id = ? FOR UPDATE',
          variables: [Variable<int>(productId)],
        ).get();
        
        // Lock the warehouse balance row (if it exists)
        await customSelect(
          'SELECT id FROM inventory_balances WHERE product_id = ? AND warehouse_id = ? FOR UPDATE',
          variables: [Variable<int>(productId), Variable<int>(warehouseId)],
        ).get();
      }

      // I-02: SECURITY — Block stock movements in closed accounting periods (all types)
      // H-07: Use movementDate (if provided) instead of always using DateTime.now()
      final effectiveDate = movementDate ?? DateTime.now();
      final closedPeriod = await (select(accountingPeriods)
            ..where((p) => p.month.equals(effectiveDate.month))
            ..where((p) => p.year.equals(effectiveDate.year))
            ..where((p) => p.isClosed.equals(true))
            ..limit(1))
          .getSingleOrNull();
      if (closedPeriod != null) {
        throw Exception(
          'لا يمكن تعديل المخزون في فترة محاسبية مغلقة (${closedPeriod.name})',
        );
      }

      final product = await getProductById(productId);
      if (product == null) return;

      // Resolve branchId from warehouse if not provided
      final resolvedBranchId = branchId ?? await getWarehouseById(warehouseId).then((w) => w?.branchId);

      // F-11: Atomic Negative stock prevention is now delegated completely to `_updateWarehouseBalance`.
      final movementType = type ?? 'adjustment';

      // Cluster 023 / Issue 6 — global override for the per-product
      // `allowNegativeSale` flag. Operators were having to flip the
      // per-product toggle for every product after enabling the global
      // setting; treat the global flag as an implicit `true` for every
      // product when it's on so the global toggle becomes single-source.
      final negativeSalesRaw = await getSettingValue('enable_negative_sales');
      final globalAllowNegative = negativeSalesRaw == 'true';
      final effectiveAllowNegative =
          globalAllowNegative || product.allowNegativeSale;

      // B10 (S-INV-COST / PUR-1 / INV-2): on an INFLOW with a known receipt
      // cost, blend the per-warehouse average_cost against that ACTUAL
      // receipt unitCost — not the global product.costPrice (which may have
      // already been re-blended by updateProductWAC from a DIFFERENT mix of
      // warehouses' history and so no longer represents THIS warehouse's
      // receipt). Sales/transfers/generic adjustments never pass unitCost,
      // so they keep the pre-existing product.costPrice fallback unchanged.
      final warehouseBlendCost =
          (quantity > 0 && unitCost != null) ? unitCost : product.costPrice;

      // Update warehouse-specific balance FIRST (throws if atomic check fails)
      await _updateWarehouseBalance(
        productId: productId,
        warehouseId: warehouseId,
        quantity: quantity,
        cost: warehouseBlendCost,
        allowNegativeSale: effectiveAllowNegative,
        productName: product.name,
      );

      // Update global product stock atomically
      await adjustProductStockGlobal(productId, quantity);

      // PIR-05: balanceAfter now stores warehouse-specific balance (not global stock)
      final warehouseBalanceAfter = await _getWarehouseBalanceAfter(productId, warehouseId);

      // Spec 135 BUG-A: capture the per-event gid ONCE for this call. Used
      // for the stock_movements.globalId stamp below AND the autoposted JE's
      // sourceGid further down, so both rows of one logical event share a
      // stable cross-instance identity.
      final eventGid = adjustmentEventGid ?? UuidV7.generate();

      await createStockMovement(
        StockMovementsCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          movementType: movementType,
          quantity: quantity,
          balanceAfter: warehouseBalanceAfter,
          unitCost: Value(unitCost ?? product.costPrice),
          referenceType: Value(referenceType),
          referenceId: Value(referenceId),
          userId: Value(userId),
          notes: Value(notes ?? 'Stock adjustment'),
          createdAt: Value(effectiveDate),
          globalId: Value(eventGid),
        ),
      );

      // ═══ Batch consumption / restoration (Sprint 15) ═══
      // Keep the batch ledger in step with the warehouse. Issue order is
      // decided per product by getBatchesForIssue (FEFO for expiry-tracked
      // goods, FIFO otherwise).
      //
      // Both lists gate on the SIGN of the movement, so a type that occurs in
      // both directions belongs in BOTH lists and the sign dispatches it.
      // That is exactly the case for `void_reversal`: voiding a SALE puts
      // goods back (sales_actions_dao, positive) while voiding a PURCHASE
      // takes them away (purchase_dao, negative).
      //
      // `purchase_return` and `void_reversal` used to be in neither list, so
      // warehouse stock moved while the batches sat still — and in opposite
      // directions, so the drift did not even average out. Everything reading
      // batches downstream (expiry alerts, FEFO ordering, recall
      // traceability) was working off quantities that no longer described
      // what was on the shelf.
      const outboundTypes = {
        'sale',
        'legacy_sale',
        'edit_adjustment',
        'purchase_return', // goods physically returned to the supplier
        'void_reversal', // voiding a purchase removes what it brought in
      };
      const inboundTypes = {
        'return',
        'edit_reversal',
        'void_reversal', // voiding a sale puts the goods back on the shelf
      };
      final isSaleDeduction =
          quantity < 0 && outboundTypes.contains(movementType);
      final isReturnAddition =
          quantity > 0 && inboundTypes.contains(movementType);

      if (isSaleDeduction) {
        // Consume from oldest batches (FIFO)
        await consumeBatchesForIssue(
          productId: productId,
          quantity: quantity.abs(),
          // Was available in this scope all along and simply not passed —
          // which is why a sale in one branch ate another branch's lot.
          warehouseId: warehouseId,
        );
      } else if (isReturnAddition) {
        // Restore stock to most recent batch
        await restoreBatchForReturn(
          productId: productId,
          warehouseId: warehouseId,
          quantity: quantity,
          notes: notes,
        );
      }

      // ═══ Accounting Entry for manual inventory adjustments ═══
      // Mirrors the pattern in finalizeStockAudit() — createJournalEntry()
      // uses savepoints (nested transaction) which is safe inside an outer transaction.
      // ⚠️ **`waste` و`damage` مضافتان — كانتا تحرّكان المخزونَ بلا قيدٍ واحد.**
      //
      // شاشتا المخزون تُصدران هذين النوعَين حرفيّاً
      // (`inventory_notifier.dart:105,108`) من نفس القائمة التي تُصدر
      // `adjustment` — فخيارُ «إزالة» كان يُرحَّل وخيارا «هدر/تالف» بجانبه لا
      // يُرحَّلان. الأثرُ: المخزونُ ينقص والأستاذُ لا يتحرّك ⇒ الأصلُ والربحُ
      // مبالَغٌ فيهما بقيمةِ كلِّ إعدامٍ يدويٍّ منذ أوّل يوم.
      //
      // ⚠️ **ولا تُضاف بلا `postAdjustmentJournal: false` في مسار المرتجع
      // التالف** (`returns_repository_impl.dart`): ذاك المسارُ يستدعي
      // `adjustStock(type: 'waste')` **ثمّ يرحّل قيدَه بنفسه**، فإضافةٌ عاريةٌ
      // هنا كانت ستُنتج **ترحيلاً مزدوجاً** لكلِّ مرتجعٍ تالف. الموضعان
      // يُعدَّلان معاً أو لا يُعدَّلان.
      //
      // والوجهةُ `inventory_shrinkage` لا `misc_expense`: نفسُ الحسابِ الذي
      // يقصده مسارُ المرتجع التالف، فالحدثُ الماديُّ الواحد (بضاعةٌ أُتلفت)
      // يقع على حسابٍ واحدٍ مهما كان بابُ الإدخال.
      const adjustmentAccountedTypes = {
        'cycle_count', 'adjustment', 'write_off', 'loss', 'waste', 'damage',
      };
      final effectiveCost = unitCost ?? product.costPrice;
      if (postAdjustmentJournal &&
          adjustmentAccountedTypes.contains(movementType) &&
          effectiveCost > 0) {
        final adjustmentValue = quantity.abs() * effectiveCost;
        try {
          final invCode = await accountingDao.getMappedAccountCode(
            'inventory', AccountingDao.accountPurposes['inventory']!,
          );
          final invAcc = await accountingDao.getAccountByCode(invCode);
          if (invAcc == null) {
            throw StateError('لا يمكن ترحيل حركة المخزون: حساب المخزون غير مربوط.');
          } else {
            final jeLines = <JournalLine>[];
            if (quantity > 0) {
              // Positive adjustment (surplus / cycle-count gain):
              // Dr Inventory (1136) / Cr Inventory Surplus (4317)
              final surplusCode = await accountingDao.getMappedAccountCode(
                'inventory_surplus', AccountingDao.accountPurposes['inventory_surplus']!,
              );
              final surplusAcc = await accountingDao.getAccountByCode(surplusCode);
              if (surplusAcc == null) {
                 throw StateError('لا يمكن ترحيل حركة المخزون: حساب فائض المخزون غير مربوط.');
               }
               {
                jeLines.add(JournalLine(accountId: invAcc.id,      debit: adjustmentValue, description: 'زيادة مخزون — $movementType'));
                jeLines.add(JournalLine(accountId: surplusAcc.id,  credit: adjustmentValue, description: 'فائض مخزون — $movementType'));
              }
            } else {
              // Negative adjustment (shortage / write-off / loss):
              // Dr Inventory Shrinkage/Expense / Cr Inventory (1136)
              final expensePurpose = (movementType == 'write_off' || movementType == 'loss')
                  ? 'misc_expense'         // intentional write-off → general expense
                  : 'inventory_shrinkage'; // unexplained shortage → shrinkage account
              final expenseCode = await accountingDao.getMappedAccountCode(
                expensePurpose, AccountingDao.accountPurposes[expensePurpose]!,
              );
              final expenseAcc = await accountingDao.getAccountByCode(expenseCode);
              if (expenseAcc == null) {
                 throw StateError('لا يمكن ترحيل حركة المخزون: حساب خسائر المخزون غير مربوط.');
               }
               {
                jeLines.add(JournalLine(accountId: expenseAcc.id, debit: adjustmentValue,  description: 'عجز مخزون — $movementType'));
                jeLines.add(JournalLine(accountId: invAcc.id,     credit: adjustmentValue, description: 'تخفيض مخزون — $movementType'));
              }
            }
            if (jeLines.isNotEmpty) {
              // Spec 135 BUG-A — event-unique deterministic JE globalId.
              //
              // The old synthetic sourceGid packed only
              // (productId, warehouseId, referenceId ?? 0, movementType).
              // A MANUAL adjustment carries no referenceId, so it collapsed
              // to `...ref0...` for EVERY manual/server adjustment of the
              // same product+warehouse+type → the 2nd genuinely-different
              // adjustment minted the SAME JE globalId → PG 23505 on the
              // UNIQUE constraint (server_errors.log: je-stockadj…ref0…post)
              // aborting the whole transaction, OR a swallowed JE + a stock
              // movement with no GL counterpart.
              //
              // Now the sourceGid is the per-EVENT gid (same value stamped
              // on stock_movements.globalId above, and threaded from the
              // caller into the server submit). Two different events → two
              // different gids (no false collision); the same event replayed
              // (outbox retry, client+server of one logical op) → same gid →
              // the UNIQUE constraint dedups cleanly (Spec 129 intent
              // preserved). `sm` prefix = "stock movement event".
              final adjSourceGid = 'sm$eventGid';
              final jeGid = JournalEntryGid.compute(
                sourceType: JournalEntryGid.sourceStockAdjustment,
                sourceGid: adjSourceGid,
                verb: 'post',
              );
              unawaited(DiagnosticLogger.log(
                DiagnosticLogger.gidAutopost,
                'sourceType=stockadj sourceGid=${adjSourceGid.length >= 16 ? adjSourceGid.substring(0, 16) : adjSourceGid} '
                'verb=post mt=$movementType pid=$productId',
              ));
              await accountingDao.createJournalEntry(
                description: 'تسوية مخزون — $movementType — منتج #$productId',
                date: effectiveDate,
                lines: jeLines,
                referenceType: 'stock_adjustment',
                referenceId: referenceId,
                isAutoPosted: true,
                branchId: resolvedBranchId,
                globalId: jeGid,
              );
            }
          }
        } catch (e) {
          // Spec 135 STEP-0 #5 — fail-loud on a genuine JE error. Swallow ONLY
          // the idempotent-replay case (the deterministic globalId already
          // exists → UNIQUE violation), which is the expected, benign outcome
          // when one logical adjustment event is replayed (outbox retry, or
          // the client + server arms of a single op). createJournalEntry posts
          // inside a savepoint, so a UNIQUE violation rolls back only the JE
          // and leaves the already-written stock movement intact — exactly the
          // dedup we want. Any OTHER error means the stock movement would
          // otherwise persist with no balanced GL counterpart, so rethrow to
          // roll back the whole adjustment instead of silently drifting the
          // books. (Missing-account cases are handled gracefully above — they
          // never build lines, so they don't reach here.)
          final msg = e.toString();
          final isDuplicateGid = msg.contains('UNIQUE constraint failed') ||
              msg.contains('duplicate key') ||
              msg.contains('23505');
          if (isDuplicateGid) {
            debugPrint('[AUTOPOST] adjustStock JE already posted (idempotent '
                'replay) for $movementType #$productId: $e');
          } else {
            unawaited(DiagnosticLogger.log(
                'STOCKADJ-FAIL',
                'فشل قيد تسوية المخزون وتم التراجع عن التسوية: '
                'النوع=$movementType صنف=$productId — $e'));
            rethrow;
          }
        }
      }

      // ═══ Opening Stock GL Entry (P0-06) ═══
      // When a product's opening balance is established via 'opening_stock',
      // post: Dr Inventory / Cr Opening Equity (حساب الأرصدة الافتتاحية).
      // referenceType='opening_balance' is exempt from fiscal-period gating so
      // these entries work even before the first accounting period is configured.
      if (movementType == 'opening_stock' && quantity > 0 && effectiveCost > 0) {
        final openingValue = quantity * effectiveCost;
        try {
          final invAcc = await accountingDao.getAccountByPurpose('inventory');
          final openingEquityAcc = await accountingDao.getAccountByPurpose('opening_equity');
          if (invAcc != null && openingEquityAcc != null) {
            await accountingDao.createJournalEntry(
              description: 'رصيد مخزون افتتاحي — منتج #$productId',
              date: effectiveDate,
              lines: [
                JournalLine(
                  accountId: invAcc.id,
                  debit: openingValue,
                  description: 'رصيد مخزون افتتاحي',
                ),
                JournalLine(
                  accountId: openingEquityAcc.id,
                  credit: openingValue,
                  description: 'رصيد افتتاحي مقابل',
                ),
              ],
              referenceType: 'opening_balance',
              referenceId: productId,
              isAutoPosted: true,
              branchId: resolvedBranchId,
            );
          } else {
            debugPrint('[P0-06] Opening stock JE skipped for #$productId — '
                'inventory=${invAcc?.id} openingEquity=${openingEquityAcc?.id} '
                '(add account mappings to enable)');
          }
        } catch (e) {
          // Non-fatal: stock movement committed, JE can be repaired via backfill
          debugPrint('[P0-06] Opening stock JE failed for #$productId: $e');
        }
      }
    }); // end transaction
  }

  /// PIR-05: Get warehouse-specific balance after update (for balanceAfter field)
  Future<double> _getWarehouseBalanceAfter(int productId, int warehouseId) async {
    final wb = await (select(inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId))
          ..limit(1))
        .getSingleOrNull();
    return wb?.quantity ?? 0.0;
  }

  /// Update warehouse-specific inventory balance with true per-warehouse WAC
  /// Formula (on addition): ((existing.qty * existing.avgCost) + (newQty * newCost)) / (existing.qty + newQty)
  /// On deduction (sale/transfer-out): WAC stays unchanged (standard accounting practice)
  Future<void> _updateWarehouseBalance({
    required int productId,
    required int warehouseId,
    required double quantity,
    required double cost,
    required bool allowNegativeSale,
    required String productName,
  }) async {
    final isDeduction = quantity < 0;

    final existing = await (select(inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId))
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) {
      if (isDeduction) {
        // PIR-07: Atomic Deduction Check bypassing dart memory completely.
        // $quantity is a Dart double — toString() always uses '.' separator (locale-safe).
        final updateStmt = update(inventoryBalances)..where((b) => b.id.equals(existing.id) &
            (!allowNegativeSale
                ? CustomExpression<bool>(
                    '(quantity - COALESCE(reserved_quantity, 0)) + $quantity >= 0',
                  )
                : const Constant(true)));

        final affectedRows = await updateStmt.write(
          InventoryBalancesCompanion.custom(
            quantity: CustomExpression<double>('quantity + $quantity'),
            lastUpdated: Variable(DateTime.now()),
            // WAC strictly remains unchanged during deductions, no need to update averageCost
          ),
        );

        if (affectedRows == 0) {
          throw Exception(
            'عفواً، الكمية المتوفرة حالياً في المستودع ($warehouseId) غير كافية لمنتج $productName'
          );
        }
      } else {
        // Addition: Process standard newQuantity and WAC
        final newQuantity = existing.quantity + quantity;
        double newAverageCost;
        if (newQuantity > 0) {
          final existingValue = existing.quantity * existing.averageCost;
          final addedValue = quantity * cost;
          newAverageCost = (existingValue + addedValue) / newQuantity;
        } else {
          newAverageCost = cost;
        }

        // INV-3 (B10): guard a negative RESULT the same way updateProductWAC
        // does — happens when existing.quantity was already negative
        // (oversold via allowNegativeSale) and this addition brings
        // newQuantity back above zero, so the denominator guard above never
        // fires but the numerator can still be negative. There is no
        // per-warehouse equivalent of recalculateProductWAC to fall back on,
        // so clamp to the incoming receipt/movement `cost` — the one
        // trustworthy price we have for this event — and only fall back to
        // 0 in the (should-never-happen) case that `cost` itself is
        // negative.
        if (newAverageCost < 0) {
          newAverageCost = cost >= 0 ? cost : 0;
        }

        await (update(inventoryBalances)..where((b) => b.id.equals(existing.id))).write(
          InventoryBalancesCompanion(
            quantity: Value(newQuantity),
            averageCost: Value(newAverageCost),
            lastUpdated: Value(DateTime.now()),
          ),
        );
      }
    } else {
      if (isDeduction && !allowNegativeSale) {
        // Spec 136 (field 2026-06-08) — actionable message: tell the operator
        // WHICH warehouse this product belongs to, instead of the bare "not
        // available". Common on the mirror when a product was added to
        // warehouse X but the cashier sells from a different warehouse Y.
        final stocked = await (select(inventoryBalances)
              ..where((b) =>
                  b.productId.equals(productId) &
                  b.quantity.isBiggerThanValue(0)))
            .get();
        if (stocked.isNotEmpty) {
          final whIds = stocked.map((b) => b.warehouseId).toSet().toList();
          final whRows =
              await (select(warehouses)..where((w) => w.id.isIn(whIds))).get();
          final whNames = whRows.map((w) => w.name).join('، ');
          throw Exception(
            'الصنف "$productName" خاص بمستودع آخر ولا يمكن بيعه من المستودع '
            'الحالي ($warehouseId) — متوفر في: '
            '${whNames.isNotEmpty ? whNames : whIds.join('، ')}. '
            'اختر المستودع الصحيح للبيع منه.',
          );
        }
        throw Exception(
            'عفواً، الصنف "$productName" غير متوفر في أي مستودع. '
            'سجّل رصيداً افتتاحياً أو فاتورة شراء أولاً.');
      }
      
      // INV-3 (B10): symmetric negative guard with the UPDATE branch above —
      // a fresh balance must never persist a negative average_cost either.
      await into(inventoryBalances).insert(
        InventoryBalancesCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          quantity: Value(quantity),
          averageCost: Value(cost >= 0 ? cost : 0),
        ),
      );
    }
  }

  /// Update Product Weighted Average Cost (WAC)
  /// Formula: ((Current Qty * Current WAC) + (New Qty * New Unit Cost)) / (Current Qty + New Qty)
  Future<void> updateProductWAC({
    required int productId,
    required double newQuantity,
    required double newUnitCost,
  }) async {
    // PIR-06: Defensive Row-Level Locking to prevent WAC Lost Update
    if (isPostgres) {
      await customSelect(
        'SELECT id FROM products WHERE id = ? FOR UPDATE',
        variables: [Variable<int>(productId)],
      ).get();
    }

    final product = await getProductById(productId);
    if (product == null) return;

    final double currentQty = product.currentStock;
    final double currentWAC = product.costPrice;

    double updatedWAC;
    if (currentQty + newQuantity <= 0) {
      updatedWAC = newUnitCost; // Reset to new cost if stock was 0 or negative
    } else {
      updatedWAC =
          ((currentQty * currentWAC) + (newQuantity * newUnitCost)) /
          (currentQty + newQuantity);
    }

    // INV-3 (B10): guard against a negative RESULT even though the
    // denominator (currentQty + newQuantity) is positive. Happens when
    // currentQty is already negative (oversold via allowNegativeSale) and
    // this receipt brings the total back above zero — the numerator can
    // still be deeply negative, which would write a negative costPrice
    // (breaks COGS everywhere it's read). Mirrors reverseProductWAC's
    // existing `updatedWAC < 0` fallback below.
    if (updatedWAC < 0) {
      await recalculateProductWAC(productId);
      return;
    }

    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        costPrice: Value(updatedWAC),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // PERF: Invalidate cached product since costPrice changed
    invalidateProductCache(productId);
  }

  /// Apply landed cost (freight/customs/…) to Product WAC as an ADDED VALUE.
  /// S-COST (Spec 144): landed cost adds money to inventory already on hand —
  /// it does NOT add quantity (the purchase already ingested the qty into WAC).
  /// So we spread [addedValue] over the current on-hand stock, weighted:
  ///   newWAC = (currentQty * currentWAC + addedValue) / currentQty
  /// If currentQty <= 0 we cannot spread it → keep the existing WAC (caller's
  /// per-warehouse blend adopts the allocation's newUnitCost instead).
  Future<void> applyLandedCostToProductWAC({
    required int productId,
    required double addedValue,
  }) async {
    if (addedValue == 0) return;

    // PIR-06: Defensive Row-Level Locking to prevent WAC Lost Update
    if (isPostgres) {
      await customSelect(
        'SELECT id FROM products WHERE id = ? FOR UPDATE',
        variables: [Variable<int>(productId)],
      ).get();
    }

    final product = await getProductById(productId);
    if (product == null) return;

    final double currentQty = product.currentStock;
    if (currentQty <= 0) return; // cannot spread over 0/negative stock

    final double updatedWAC =
        ((currentQty * product.costPrice) + addedValue) / currentQty;

    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        costPrice: Value(updatedWAC),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // PERF: Invalidate cached product since costPrice changed
    invalidateProductCache(productId);
  }

  /// Reverse Product Weighted Average Cost (WAC)
  /// Formula: ((Current Qty * Current WAC) - (Reversed Qty * Reversed Unit Cost)) / (Current Qty - Reversed Qty)
  /// Used during Purchase Returns and Purchase Invoice Edits.
  Future<void> reverseProductWAC({
    required int productId,
    required double reversedQuantity,
    required double reversedUnitCost,
  }) async {
    // PIR-06: Defensive Row-Level Locking to prevent WAC Lost Update
    if (isPostgres) {
      await customSelect(
        'SELECT id FROM products WHERE id = ? FOR UPDATE',
        variables: [Variable<int>(productId)],
      ).get();
    }

    final product = await getProductById(productId);
    if (product == null) return;

    final double currentQty = product.currentStock;
    final double currentWAC = product.costPrice;
    
    // If the remaining stock is 0 or negative, we can't mathematically reverse WAC.
    // In this edge case, we fallback to a full recalculation from historic purchases.
    if ((currentQty - reversedQuantity) <= 0) {
      await recalculateProductWAC(productId);
      return;
    }

    final double remainingQty = currentQty - reversedQuantity;
    final double updatedWAC = ((currentQty * currentWAC) - (reversedQuantity * reversedUnitCost)) / remainingQty;

    // Guard against negative WAC anomalies (can happen if manual stock adjustments skewed the WAC)
    if (updatedWAC < 0) {
      await recalculateProductWAC(productId);
      return;
    }

    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        costPrice: Value(updatedWAC),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // PERF: Invalidate cached product since costPrice changed
    invalidateProductCache(productId);
  }

  /// Recalculate Product Weighted Average Cost (WAC) from historic purchases
  /// Use this to "Reset" WAC if edits or deletes caused drifting.
  /// Formula: SUM(item.quantity * item.unitCost) / SUM(item.quantity)
  Future<void> recalculateProductWAC(int productId) async {
    // PIR-06: Defensive Row-Level Locking to prevent WAC Lost Update
    if (isPostgres) {
      await customSelect(
        'SELECT id FROM products WHERE id = ? FOR UPDATE',
        variables: [Variable<int>(productId)],
      ).get();
    }

    // B8 (S-LANDED-LIFECYCLE / PR-1): JOIN through to the parent purchase
    // invoice and exclude voided/soft-deleted invoices. A void only flips
    // the header (`status='voided'`, `isDeleted=true`) — it never deletes
    // the purchase_invoice_items rows — so without this join a voided
    // purchase kept contributing its cost to every later WAC recalc
    // forever. (The old comment here claimed "a voided/edited line drops
    // its own allocation automatically" — that was never true; nothing
    // upstream filtered on invoice status.)
    final purchaseLinesQuery = select(purchaseInvoiceItems).join([
      innerJoin(
        purchaseInvoices,
        purchaseInvoices.id.equalsExp(purchaseInvoiceItems.invoiceId),
      ),
    ])
      ..where(
        purchaseInvoiceItems.productId.equals(productId) &
            purchaseInvoices.status.equals('voided').not() &
            purchaseInvoices.isDeleted.equals(false),
      );
    final purchaseRows = await purchaseLinesQuery.get();

    // صنفٌ بلا تاريخِ شراءٍ صالحٍ لا يُعاد تسعيرُه — كما كان.
    if (purchaseRows.isEmpty) return;

    // S-COST (Spec 144): fold APPLIED landed cost into the WAC so a later
    // purchase edit/void/return that triggers a recalc does not silently wipe
    // it. B8 (S-LANDED-LIFECYCLE / PR-1): also exclude allocations whose
    // parent purchase invoice is voided/soft-deleted — same gap as above,
    // a voided invoice's landed allocation must drop out of the blend too.
    final landedRow = await customSelect(
      '''SELECT COALESCE(SUM(lca.allocated_amount), 0) AS landed
         FROM landed_cost_allocations lca
         JOIN landed_cost_sheets lcs ON lcs.id = lca.sheet_id
         JOIN purchase_invoice_items pii ON pii.id = lca.purchase_item_id
         JOIN purchase_invoices pi ON pi.id = pii.invoice_id
         WHERE pii.product_id = ? AND lcs.status = 'applied'
           AND pi.status != 'voided' AND pi.is_deleted = ${sqlBool(false)}''',
      variables: [Variable<int>(productId)],
      readsFrom: {
        landedCostAllocations,
        landedCostSheets,
        purchaseInvoiceItems,
        purchaseInvoices,
      },
    ).getSingle();
    // ⚠️ تُضاف إلى **قيمة الدفتر** لا إلى مجموع الشراء: الكلفةُ المُنزَلةُ
    // ترفع قيمةَ المخزون في الأستاذ بلا حركةِ كمّيّة، فلا يلتقطها مجموعُ
    // `كمّيّة × تكلفة` على دفتر الحركات.
    final landedTotal = (landedRow.data['landed'] as num?)?.toDouble() ?? 0.0;

    // ── القيمةُ المتبقّيةُ ÷ الموجود — لا متوسّطُ الشراء مدى الحياة ────────
    //
    // 🔴 كان `wac = totalCost / totalQty` حيث `totalQty` مجموعُ كمّيّاتِ
    // **كلِّ** سطرِ شراءٍ في التاريخ. أي «متوسّطُ ما اشتريتَه يوماً» — وهو
    // يساوي المتوسّطَ المتحرّك **فقط** ما لم يقع بيعٌ بينهما. وأوّلُ بيعةٍ
    // تكسره:
    //
    //   شراء ١٠@١٠ ← بيع ٥ ← شراء ١٠@٢٠
    //     الأستاذ ٢٥٠ · الموجود ١٥ · الصحيح ١٦٫٦٦٧
    //     والقديم: (١٠٠+٢٠٠) ÷ ٢٠ = **١٥٫٠** ⇒ تقييمٌ ٢٢٥ مقابل أستاذٍ ٢٥٠،
    //     **انحرافٌ ٢٥** بلا قيدٍ ولا خطأ (‏مقيسٌ بـ`getInventoryGlReconciliation`).
    //
    // ⚠️ **والعلاجُ ليس قيداً موازناً.** حسابُ المخزون في هذا المستودع
    // **مدفوعٌ بالحركات**: كلُّ شراءٍ وبيعٍ وتعديلٍ وإبطالٍ يُرحَّل بتكلفته
    // لحظتَها، ولا تقييمَ دوريَّ في أيِّ مكان. فإضافةُ قيدِ إعادةِ تقييمٍ هنا
    // تُضاعف في **كلِّ** مواضع النداء الستّة — كلُّها ترحّل قيدَها أصلاً
    // (‏`createPurchaseInvoice` · `voidPurchaseInvoice` · مسارا المرتجع ·
    // تعديلُ الفاتورة). ونفسُ الحكم مكتوبٌ سلفاً في
    // `costing_method_service` حين حُذفت طريقةُ «آخر سعر شراء»: العلاجُ
    // إزالةُ الكتابة غير المحافِظة على القيمة، لا قيدٌ يصحّحها.
    //
    // فالقيمةُ تُشتقّ من دفتر الحركات — وهو المرآةُ الصنفيّةُ للأستاذ:
    //   قيمةُ الدفتر = Σ(‏كمّيّة × تكلفة الوحدة) على كلِّ حركة (‏الكمّيّةُ
    //   مُوقَّعة: + داخل، − خارج) **زائداً** الكلفةَ المُنزَلةَ المطبَّقة،
    //   لأنّها ترفع قيمةَ المخزون في الأستاذ **بلا حركةِ كمّيّة**.
    final bookRow = await customSelect(
      'SELECT COALESCE(SUM(quantity * unit_cost), 0) AS book '
      'FROM stock_movements '
      'WHERE product_id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(productId)],
      readsFrom: {stockMovements},
    ).getSingle();
    final ledgerValue =
        ((bookRow.data['book'] as num?)?.toDouble() ?? 0.0) + landedTotal;

    final product = await getProductById(productId);
    final onHand = product?.currentStock ?? 0.0;

    // ⚠️ **ولا كتابةَ حين لا يكون للجواب معنًى.** موجودٌ صفريٌّ أو سالبٌ
    // (‏بيعٌ على المكشوف) أو قيمةُ دفترٍ سالبةٌ لا تُنتج تكلفةَ وحدةٍ
    // صالحة. والقديمُ كان يكتب حينها متوسّطَ الشراء — رقماً موجباً يبدو
    // معقولاً ويُخفي أنّ الحالةَ شاذّة، ثمّ يتسرّب إلى تكلفة كلِّ بيعةٍ
    // لاحقة. تركُ القيمة كما هي أصدق: الشذوذُ يبقى مرئيّاً في تقرير
    // المصالحة بدل أن يُطمَس.
    if (onHand > 0 && ledgerValue > 0) {
      final wac = ledgerValue / onHand;
      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          costPrice: Value(wac),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // PERF: Invalidate cached product since costPrice changed
      invalidateProductCache(productId);
    } else {
      debugPrint('[WAC] recalc skipped for product $productId — '
          'onHand=$onHand ledgerValue=$ledgerValue '
          '(لا تكلفةَ وحدةٍ صالحة؛ التكلفةُ السابقة باقية)');
    }
  }

  /// Get the total returned quantity for a specific product from a specific invoice.
  /// Used to prevent double returns.
  ///
  /// PREFER [getReturnedQuantitiesForInvoice] when processing multiple items of
  /// the same invoice — it returns all items' totals in a single query.
  Future<double> getReturnedQuantityForInvoiceItem({
    required int invoiceId,
    required int productId,
  }) async {
    final query = select(stockMovements)
      ..where(
        (m) =>
            m.movementType.equals('return') &
            m.referenceType.equalsNullable('sales_invoice') &
            m.referenceId.equalsNullable(invoiceId) &
            m.productId.equals(productId),
      );

    final movements = await query.get();
    double totalReturned = 0;
    for (final m in movements) {
      totalReturned += m.quantity;
    }
    return totalReturned;
  }

  /// Batch version: returns `{productId: totalReturnedQuantity}` for ALL
  /// return movements referencing the given invoice, in ONE query + GROUP BY.
  ///
  /// Solves the N+1 freeze on the sales-returns invoice picker, where the
  /// previous per-item loop was performing a full-table scan × N items.
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(int invoiceId) async {
    final query = selectOnly(stockMovements, distinct: false)
      ..addColumns([stockMovements.productId, stockMovements.quantity.sum()])
      ..where(
        stockMovements.movementType.equals('return') &
            stockMovements.referenceType.equalsNullable('sales_invoice') &
            stockMovements.referenceId.equalsNullable(invoiceId),
      )
      ..groupBy([stockMovements.productId]);

    final rows = await query.get();
    final result = <int, double>{};
    for (final row in rows) {
      final pid = row.read(stockMovements.productId);
      final qty = row.read(stockMovements.quantity.sum());
      if (pid != null) {
        result[pid] = qty ?? 0.0;
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WAREHOUSES
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all warehouses
  Stream<List<Warehouse>> watchAllWarehouses() {
    return select(warehouses).watch();
  }

  /// Get warehouse by ID
  Future<Warehouse?> getWarehouseById(int id) {
    return (select(
      warehouses,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
  }

  /// Insert a warehouse
  Future<int> insertWarehouse(WarehousesCompanion warehouse) {
    return into(warehouses).insert(warehouse);
  }

  /// Update a warehouse
  Future<bool> updateWarehouse(Warehouse warehouse) {
    return update(warehouses).replace(warehouse);
  }

  /// Delete a warehouse (with protection check)
  /// Throws exception if warehouse is linked to products, stock movements, or invoices
  Future<int> deleteWarehouse(int id) async {
    // Check if any stock movements reference this warehouse
    final movementsCount =
        await (select(stockMovements)
              ..where((m) => m.warehouseId.equals(id))
              ..limit(1))
            .get();
    if (movementsCount.isNotEmpty) {
      throw Exception('لا يمكن حذف هذا المستودع: مرتبط بحركات مخزون');
    }

    // Check if any sales invoices reference this warehouse
    final salesCount =
        await (select(salesInvoices)
              ..where((i) => i.warehouseId.equals(id))
              ..limit(1))
            .get();
    if (salesCount.isNotEmpty) {
      throw Exception('لا يمكن حذف هذا المستودع: مرتبط بفواتير مبيعات');
    }

    // Check if any purchase invoices reference this warehouse
    final purchasesCount =
        await (select(purchaseInvoices)
              ..where((i) => i.warehouseId.equals(id))
              ..limit(1))
            .get();
    if (purchasesCount.isNotEmpty) {
      throw Exception('لا يمكن حذف هذا المستودع: مرتبط بفواتير مشتريات');
    }

    return (delete(warehouses)..where((w) => w.id.equals(id))).go();
  }

  /// Get default warehouse
  Future<Warehouse?> getDefaultWarehouse() {
    return (select(
      warehouses,
    )..where((w) => w.isDefault.equals(true))
     ..limit(1)).getSingleOrNull();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STOCK AUDIT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch the current open audit
  Stream<StockAudit?> watchOpenAudit() {
    return (select(stockAudits)
          ..where((a) => a.status.equals('open'))
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Create a new stock audit session
  Future<int> createStockAudit({String? notes, int? userId}) {
    return into(stockAudits).insert(
      StockAuditsCompanion.insert(
        auditDate: Value(DateTime.now()),
        status: const Value('open'),
        notes: Value(notes),
        createdBy: Value(userId),
      ),
    );
  }

  /// Add or update an item in the current audit
  Future<void> saveAuditItem({
    required int auditId,
    required int productId,
    required double actualQuantity,
    required double expectedQuantity,
  }) async {
    final existing =
        await (select(stockAuditItems)..where(
              (i) => i.auditId.equals(auditId) & i.productId.equals(productId),
            ))
            .getSingleOrNull();

    if (existing != null) {
      await (update(
        stockAuditItems,
      )..where((i) => i.id.equals(existing.id))).write(
        StockAuditItemsCompanion(
          actualQuantity: Value(actualQuantity),
          difference: Value(actualQuantity - expectedQuantity),
          scannedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await into(stockAuditItems).insert(
        StockAuditItemsCompanion.insert(
          auditId: auditId,
          productId: productId,
          expectedQuantity: expectedQuantity,
          actualQuantity: actualQuantity,
          difference: actualQuantity - expectedQuantity,
        ),
      );
    }
  }

  /// Manual "add item" flow (search then Add button) — insert the row ONCE with
  /// actual = expected (a neutral starting point the user then edits). Re-adding
  /// an item already in the audit is a no-op. Returns true if a row was added.
  ///
  /// This is distinct from a per-unit barcode SCAN (see the controller's
  /// scanBarcode → saveAuditItem(actual = existing + 1), which accumulates).
  /// Conflating the two made the Add button increment by 1 and start from 0.
  Future<bool> addAuditItemOnce({
    required int auditId,
    required int productId,
    required double expectedQuantity,
  }) async {
    final existing = await (select(stockAuditItems)
          ..where((i) => i.auditId.equals(auditId) & i.productId.equals(productId)))
        .getSingleOrNull();
    if (existing != null) return false;
    await saveAuditItem(
      auditId: auditId,
      productId: productId,
      expectedQuantity: expectedQuantity,
      actualQuantity: expectedQuantity,
    );
    return true;
  }

  /// Get all items for an audit
  Future<List<StockAuditItem>> getAuditItems(int auditId) {
    return (select(
      stockAuditItems,
    )..where((i) => i.auditId.equals(auditId))).get();
  }

  /// Finalize a stock audit and apply adjustments
  Future<void> finalizeAudit(int auditId) async {
    await transaction(() async {
      final audit = await (select(
        stockAudits,
      )..where((a) => a.id.equals(auditId))).getSingleOrNull();
      if (audit == null || audit.status != 'open') return;

      final items = await getAuditItems(auditId);
      // M-06: Use the audit's own warehouseId instead of always defaulting
      int auditWarehouseId;
      if (audit.warehouseId != null) {
        auditWarehouseId = audit.warehouseId!;
      } else {
        final warehouse = await getDefaultWarehouse();
        if (warehouse == null) throw Exception('No default warehouse found');
        auditWarehouseId = warehouse.id;
      }

      double totalShrinkage = 0;
      double totalSurplus = 0;

      final productMap = await getProductsByIds(items.map((i) => i.productId).toList());
      for (final rawItem in items) {
        // ── الفرق بيتحسب من قراءة **طازجة** وقت الترحيل ────────────────────
        //
        // `item.difference` لقطة اتحفظت وقت **العدّ**. أي بيعة بين العدّ
        // والترحيل بتخلّي الفرق ده قديم، والتطبيق بيوصل لرصيد **غير**
        // الكمية المعدودة:
        //   رصيد دفتري 100 · العدّ الفعلي 95 (difference = -5)
        //   بيعة 10 بين العدّ والترحيل → الرصيد 90
        //   بعد الترحيل: 85 — والعدّ قال 95.
        //
        // الجرد الدوري (`cycle_count_dao.dart:400-407`) بيقرا طازج ويحسب
        // `delta = counted − current`. ده نفس النمط.
        final curBal = await (select(inventoryBalances)
              ..where((b) =>
                  b.productId.equals(rawItem.productId) &
                  b.warehouseId.equals(auditWarehouseId))
              ..limit(1))
            .getSingleOrNull();
        final freshDelta = curBal == null
            ? rawItem.difference // مفيش رصيد للمخزن — سيبها زي ما هي
            : rawItem.actualQuantity - curBal.quantity;
        final item = rawItem.copyWith(difference: freshDelta);

        if (item.difference != 0) {
          final product = productMap[item.productId];
          final costPrice = product?.costPrice ?? 0;

          if (item.difference < 0) {
            totalShrinkage += item.difference.abs() * costPrice;
          } else {
            totalSurplus += item.difference * costPrice;
          }

          await adjustStock(
            productId: item.productId,
            warehouseId: auditWarehouseId,
            quantity: item.difference,
            type: 'adjustment',
            referenceType: 'inventory_audit',
            referenceId: auditId,
            notes: 'Audit adjustment (Audit #$auditId)',
            // Spec 147 (S-COUNT): suppress adjustStock's per-item internal
            // settlement JE — this audit posts ONE aggregate entry below.
            // Without this the same variance hit the GL twice (per-item
            // Dr shrinkage/Cr inventory AND the aggregate).
            postAdjustmentJournal: false,
          );
        }
      }

      // F-13: Generate accounting JE for audit adjustments
      // PHASE-2 FIX: Real DB errors propagate to the parent transaction() → full rollback.
      // Missing CoA mappings produce a warning only (configuration gap, not DB error).
      final inventoryAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
      );
      if (inventoryAccount == null) {
        throw StateError('لا يمكن ترحيل الجرد: حساب المخزون غير مربوط.');
      } else {
        final lines = <JournalLine>[];

        if (totalShrinkage > 0) {
          final shrinkageAccount = await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('inventory_shrinkage', AccountingDao.accountPurposes['inventory_shrinkage']!),
          );
          if (shrinkageAccount == null) {
             throw StateError('لا يمكن ترحيل الجرد: حساب عجز المخزون غير مربوط.');
           }
           {
            lines.add(JournalLine(
              accountId: shrinkageAccount.id,
              debit: totalShrinkage,
              description: 'عجز مخزون — جرد #$auditId',
            ));
            lines.add(JournalLine(
              accountId: inventoryAccount.id,
              credit: totalShrinkage,
              description: 'تخفيض مخزون — عجز جرد',
            ));
          }
        }

        if (totalSurplus > 0) {
          final surplusAccount = await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('inventory_surplus', AccountingDao.accountPurposes['inventory_surplus']!),
          );
          if (surplusAccount == null) {
             throw StateError('لا يمكن ترحيل الجرد: حساب فائض المخزون غير مربوط.');
           }
           {
            lines.add(JournalLine(
              accountId: inventoryAccount.id,
              debit: totalSurplus,
              description: 'زيادة مخزون — فائض جرد',
            ));
            lines.add(JournalLine(
              accountId: surplusAccount.id,
              credit: totalSurplus,
              description: 'فائض مخزون — جرد #$auditId',
            ));
          }
        }

        if (lines.isNotEmpty) {
          // Resolve branchId from audit warehouse
          final warehouse = await getWarehouseById(auditWarehouseId);
          final branchId = warehouse?.branchId;

          // Spec 147 (S-COUNT): deterministic gid (R9) so a replayed audit
          // settlement dedups on journal_entries.globalId instead of
          // duplicating. ponytail: keyed on the local auditId (audits have no
          // globalId column) → multi-device false-collision edge, same class
          // as 146's `order<id>`; real fix = the deferred count-table-sync spec.
          final auditJeGid = JournalEntryGid.compute(
            sourceType: JournalEntryGid.sourceInventoryCount,
            sourceGid: 'audit$auditId',
            verb: 'settle',
          );
          // Throws on DB failure → propagates to parent transaction() → rollback
          await accountingDao.createJournalEntry(
            description: 'قيد تسوية جرد #$auditId',
            date: DateTime.now(),
            lines: lines,
            referenceType: 'inventory_audit',
            referenceId: auditId,
            isAutoPosted: true,
            branchId: branchId,
            globalId: auditJeGid,
          );
        }
      }

      // Mark audit as completed
      await (update(stockAudits)..where((a) => a.id.equals(auditId))).write(
        const StockAuditsCompanion(status: Value('completed')),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BATCH & FEFO/FIFO → See inventory_batch_dao.dart
  // ═══════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════
  // INVENTORY ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get summary analytics for inventory reports
  /// When [warehouseIds] is provided, calculates values from per-warehouse
  /// balances instead of global product stock (server-side scoping).
  Future<InventoryAnalytics> getInventoryReportAnalytics({
    List<int>? warehouseIds,
  }) async {
    // م-1 (Spec 153): value the SAME set the report table renders — EVERY
    // product (incl inactive-with-residual-stock), UNCAPPED. The table rows come
    // from productRepo.getAllProducts() == select(products).get(); the KPI card
    // must aggregate that identical set, not the active-only, LIMIT-500
    // getAllProducts() DAO helper (which silently undercounted large catalogs and
    // dropped inactive stock-on-hand, so card ≠ Σ rows).
    final allProducts = await select(products).get();

    // FIL-3 (spec 149 B12): null → global stock (all); a NON-null list scopes
    // to those warehouses — and an EMPTY list now correctly means "nothing"
    // (isIn([]) → false → zero balances → zero analytics), NOT "all". This
    // matters when a region resolves to no linked warehouses
    // (inventory_report_screen builds an empty list there): the report shows
    // zero, not the whole company's stock.
    if (warehouseIds != null) {
      // Scoped: sum from inventory_balances for the selected warehouses
      double totalValueSale = 0;
      double totalValueCost = 0;
      double totalItems = 0; // BUG-M05: fractional-safe stock unit total
      int outOfStock = 0;
      int outOfStockTracked = 0;
      int uniqueWithStock = 0;

      // Fetch all balances for the selected warehouses in one query, then group in Dart.
      final allWarehouseBalances = await (select(inventoryBalances)
            ..where((b) => b.warehouseId.isIn(warehouseIds)))
          .get();
      final balancesByProduct = <int, List<InventoryBalance>>{};
      for (final b in allWarehouseBalances) {
        balancesByProduct.putIfAbsent(b.productId, () => []).add(b);
      }

      for (final p in allProducts) {
        final balances = balancesByProduct[p.id] ?? [];

        final warehouseQty = balances.fold<double>(0, (s, b) => s + b.quantity);

        if (warehouseQty > 0) uniqueWithStock++;
        totalValueSale += (p.salePrice * warehouseQty);
        // م-1 (Spec 153, owner decision 2026-07-12): value at the global WAC
        // products.costPrice in BOTH modes — matches the table rows
        // (inventory_report_screen: costPrice × stock), matches how COGS credits
        // GL 1136 on sale, and matches the documented WAC SoT. Per-warehouse
        // average_cost is intentionally NOT used here (it diverged from the rows).
        totalValueCost += (p.costPrice * warehouseQty);
        totalItems += warehouseQty; // BUG-M05: keep fractional units
        // م-1 (Spec 153): the VALUE set widened to ALL products, but low-stock /
        // out-of-stock ALERTS stay active-only (W2 hardening 2026-05-12) — a
        // discontinued SKU with residual stock is still valued above, yet must
        // not raise a reorder alert.
        if (p.isActive && p.minStock > 0 && warehouseQty <= p.minStock) outOfStock++;
        if (p.isActive && p.trackInventory && warehouseQty <= 0) outOfStockTracked++;
      }

      return InventoryAnalytics(
        totalCostValue: totalValueCost,
        totalSaleValue: totalValueSale,
        potentialProfit: totalValueSale - totalValueCost,
        uniqueProducts: allProducts.length,
        lowStockCount: outOfStock,
        outOfStockCount: outOfStockTracked,
        itemsCount: totalItems,
      );
    }

    // Global (no filter): use product-level stock
    double totalValueSale = 0;
    double totalValueCost = 0;
    double totalItems = 0; // BUG-M05: fractional-safe stock unit total
    int outOfStock = 0;

    for (final p in allProducts) {
      totalValueSale += (p.salePrice * p.currentStock);
      totalValueCost += (p.costPrice * p.currentStock);
      totalItems += p.currentStock; // BUG-M05: keep fractional units
      // م-1 (Spec 153): alerts active-only (W2), though inactive stock is valued.
      if (p.isActive && p.minStock > 0 && p.currentStock <= p.minStock) outOfStock++;
    }

    return InventoryAnalytics(
      totalCostValue: totalValueCost,
      totalSaleValue: totalValueSale,
      potentialProfit: totalValueSale - totalValueCost,
      uniqueProducts: allProducts.length,
      lowStockCount: outOfStock,
      outOfStockCount: allProducts.where((p) => p.isActive && p.trackInventory && p.currentStock <= 0).length,
      itemsCount: totalItems,
    );
  }

  /// Get products with low stock (current <= min).
  ///
  /// W2 hardening (2026-05-12): added `isActive=true` filter so the low-
  /// stock alert doesn't fire for soft-deleted products. Without this,
  /// a manager who deactivates a discontinued item still sees it in the
  /// low-stock dashboard until the next physical-count adjustment.
  Future<List<Product>> getLowStockProducts() {
    return (select(products)..where(
          (p) =>
              p.minStock.isBiggerThanValue(0) &
              p.currentStock.isSmallerOrEqual(p.minStock) &
              p.trackInventory.equals(true) &
              p.isActive.equals(true),
        ))
        .get();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STOCK RESERVATIONS (Sprint 16 — PIR P1-03 Activated)
  // ═══════════════════════════════════════════════════════════════════════

  /// Reserve stock for a product in a specific warehouse (e.g., confirmed SO).
  /// Adds [quantity] to `reserved_quantity` in inventory_balances.
  /// Throws if available quantity (quantity - reserved) would go negative.
  Future<void> reserveStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    required int salesOrderId,
  }) async {
    await transaction(() async {
      final balance = await (select(inventoryBalances)
            ..where(
              (b) =>
                  b.productId.equals(productId) &
                  b.warehouseId.equals(warehouseId),
            ))
          .getSingleOrNull();

      if (balance == null) return; // No balance record — nothing to reserve

      final available = balance.quantity - balance.reservedQuantity;
      if (available < quantity) {
        throw Exception(
          'الكمية المتاحة ($available) أقل من الكمية المطلوبة ($quantity) للمنتج #$productId',
        );
      }

      await (update(inventoryBalances)
            ..where(
              (b) =>
                  b.productId.equals(productId) &
                  b.warehouseId.equals(warehouseId),
            ))
          .write(
        InventoryBalancesCompanion(
          reservedQuantity: Value(balance.reservedQuantity + quantity),
        ),
      );
    });
  }

  /// Release reserved stock for a product (e.g., SO cancelled or converted to invoice).
  /// Reduces [quantity] from `reserved_quantity`. Clamps to 0 to prevent negatives.
  Future<void> releaseStock({
    required int productId,
    required int warehouseId,
    required double quantity,
  }) async {
    await transaction(() async {
      final balance = await (select(inventoryBalances)
            ..where(
              (b) =>
                  b.productId.equals(productId) &
                  b.warehouseId.equals(warehouseId),
            ))
          .getSingleOrNull();

      if (balance == null) return;

      final newReserved =
          (balance.reservedQuantity - quantity).clamp(0.0, double.infinity);

      await (update(inventoryBalances)
            ..where(
              (b) =>
                  b.productId.equals(productId) &
                  b.warehouseId.equals(warehouseId),
            ))
          .write(
        InventoryBalancesCompanion(
          reservedQuantity: Value(newReserved),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INVENTORY BONDS + TRANSFERS + REQUISITIONS → See inventory_transfers_dao.dart
  // ═══════════════════════════════════════════════════════════════════════

  /// One-shot backfill for products whose `current_stock` was written directly
  /// (e.g. by older Excel-import builds or by a legacy `postProduct` that set
  /// the column without creating an inventory_balances row). Any such product
  /// would fail at sale time with "غير متوفر نهائياً فى المستودع" because
  /// `_updateWarehouseBalance` can't find a balance row to deduct from.
  ///
  /// Idempotent: it only INSERTs rows that don't already exist.
  /// Returns the number of rows created (for logging).
  Future<int> backfillMissingInventoryBalances() async {
    final orphans = await customSelect(
      '''
      SELECT p.id AS product_id,
             p.warehouse_id AS warehouse_id,
             p.current_stock AS current_stock,
             p.cost_price AS cost_price,
             p.name AS product_name
      FROM products p
      WHERE p.current_stock > 0
        AND p.warehouse_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM inventory_balances ib
          WHERE ib.product_id = p.id AND ib.warehouse_id = p.warehouse_id
        )
      ''',
      readsFrom: {products, inventoryBalances},
    ).get();

    if (orphans.isEmpty) return 0;

    int created = 0;
    for (final row in orphans) {
      final productId = row.read<int>('product_id');
      final warehouseId = row.read<int>('warehouse_id');
      final quantity = row.read<double>('current_stock');
      final cost = row.read<double>('cost_price');
      final productName = row.read<String>('product_name');

      try {
        await into(inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            quantity: Value(quantity),
            averageCost: Value(cost),
          ),
        );
        await createStockMovement(
          StockMovementsCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            movementType: 'opening_stock',
            quantity: quantity,
            balanceAfter: quantity,
            unitCost: Value(cost),
            notes: const Value('Backfill: materialise missing inventory_balances'),
          ),
        );
        // P1-03: Post opening-balance GL entry for this inventory line.
        // Entry: Dr: Inventory (1136) / Cr: Retained Earnings (313).
        // Same convention used by party_dao for opening AR/AP balances.
        // Wrapped in try/catch — startup COA may not yet be initialised.
        try {
          final openingValue = quantity * cost;
          if (openingValue > 0) {
            final invAcc = await accountingDao.getAccountByPurpose('inventory');
            final equityAcc = await accountingDao.getAccountByPurpose('retained_earnings');
            if (invAcc != null && equityAcc != null) {
              await createJournalEntry(
                description: 'رصيد مخزون افتتاحي — $productName',
                date: DateTime.now(),
                lines: [
                  JournalLine(
                    accountId: invAcc.id,
                    debit: openingValue,
                    description: 'مخزون افتتاحي — $productName',
                  ),
                  JournalLine(
                    accountId: equityAcc.id,
                    credit: openingValue,
                    description: 'رصيد افتتاحي محوّل للمخزون — $productName',
                  ),
                ],
                referenceType: 'opening_inventory',
                referenceId: productId,
                isAutoPosted: true,
              );
            } else {
              debugPrint(
                '[P1-03] Opening inventory JE skipped for "$productName" '
                '— account mapping missing '
                '(inventory=${invAcc?.id}, retained_earnings=${equityAcc?.id})',
              );
            }
          }
        } catch (e, st) {
          // Non-fatal: backfill must never be blocked by an accounting failure.
          debugPrint('[P1-03] Opening inventory JE failed for "$productName": $e\n$st');
        }
        created++;
        debugPrint('[Backfill] materialised inventory_balances for "$productName" '
            '(product=$productId, warehouse=$warehouseId, qty=$quantity)');
      } catch (e) {
        debugPrint('[Backfill] failed for product=$productId warehouse=$warehouseId: $e');
      }
    }
    debugPrint('[Backfill] inventory_balances: $created row(s) created');
    return created;
  }

  // ── Maintenance: Stock Drift Check ───────────────────────────────────────

  /// Compares each product's cached `current_stock` against the sum of its
  /// per-warehouse `inventory_balances.quantity` rows.
  ///
  /// Returns a list of drift records — empty list means the stock cache is
  /// consistent.  Each map contains: productId, productName,
  /// cachedStock, actualStock, drift.
  Future<List<Map<String, dynamic>>> checkProductStockDrift() async {
    const sql = '''
      SELECT
        p.id             AS product_id,
        p.name           AS product_name,
        p.current_stock  AS cached_stock,
        COALESCE(SUM(ib.quantity), 0.0) AS actual_stock,
        ABS(p.current_stock - COALESCE(SUM(ib.quantity), 0.0)) AS drift
      FROM products p
      LEFT JOIN inventory_balances ib ON ib.product_id = p.id
      WHERE p.track_inventory = 1
        AND (p.deleted_at IS NULL OR p.deleted_at = 0)
      GROUP BY p.id
      HAVING drift > 0.01
      ORDER BY drift DESC
    ''';
    try {
      final results = await customSelect(sql).get();
      return results.map((row) {
        return {
          'productId': row.read<int>('product_id'),
          'productName': row.read<String>('product_name'),
          'cachedStock': row.read<double>('cached_stock'),
          'actualStock': row.read<double>('actual_stock'),
          'drift': row.read<double>('drift'),
        };
      }).toList();
    } catch (e) {
      debugPrint('[INVENTORY] checkProductStockDrift error: $e');
      return [];
    }
  }

  /// Re-syncs every product's `current_stock` from the sum of its
  /// `inventory_balances` rows.  Run after `checkProductStockDrift()` reports
  /// drifted rows to restore consistency.
  Future<void> fixProductStockDrift() async {
    const sql = '''
      UPDATE products
      SET current_stock = (
        SELECT COALESCE(SUM(ib.quantity), 0.0)
        FROM inventory_balances ib
        WHERE ib.product_id = products.id
      )
      WHERE track_inventory = 1
        AND (deleted_at IS NULL OR deleted_at = 0)
    ''';
    try {
      await customStatement(sql);
      debugPrint('[INVENTORY] fixProductStockDrift: product stock cache refreshed');
    } catch (e) {
      debugPrint('[INVENTORY] fixProductStockDrift error: $e');
    }
  }

  /// قيمةُ المخزون بالتكلفة **بتاريخٍ ماضٍ**.
  ///
  /// كان معدّلُ الدوران يقسم على قيمة المخزون **الآن** لأنّه لا استعلامَ
  /// لقيمتها في الماضي — فكان تقريباً معلَناً. وهذا يجعله محسوباً على
  /// **متوسّط** المدى كما تقتضي الصيغة: `COGS ÷ متوسّطِ المخزون`.
  ///
  /// الطريقة: الرصيدُ اليومَ ناقصَ صافي الحركات **بعد** [at]. و
  /// `stock_movements.quantity` موجبةٌ للوارد وسالبةٌ للصادر، فطرحُ مجموعِها
  /// يعيد الرصيدَ إلى الوراء.
  ///
  /// ⚠️ **والتقييمُ بـ`products.cost_price` عمداً** — لا بـ`unit_cost` في
  /// الحركة ولا بـ`inventory_balances.average_cost`. وهو قرارُ المالك
  /// 2026-07-12 المكتوبُ في [getInventoryReportAnalytics]: المتوسّطُ المرجّحُ
  /// العامُّ هو مصدرُ الحقيقة، وعليه تُقيَّم صفوفُ تقرير المخزون وتُقيَّد
  /// تكلفةُ المبيعات في الأستاذ. فتقييمٌ بأساسٍ آخرَ هنا كان سينتج بسطاً
  /// ومقاماً على مسطرتين، وهو أسوأُ من تقريبٍ معلَن.
  ///
  /// فالمتغيّرُ تاريخيّاً هو **الكمّيّة**، والتكلفةُ لقطةُ اليوم — وهذا
  /// مكتوبٌ حيث يُقرأ الرقم.
  ///
  /// [warehouseIds] `null` ⇒ الرصيدُ العامُّ من `products.current_stock`؛
  /// وقائمةٌ ⇒ مجموعُ `inventory_balances` لتلك المخازن. وقائمةٌ **فارغةٌ**
  /// تعني «لا شيء» لا «الكلّ» — نفسُ عقد FIL-3.
  Future<double> getInventoryCostValueAt(
    DateTime at, {
    List<int>? warehouseIds,
  }) async {
    if (warehouseIds != null && warehouseIds.isEmpty) return 0;

    final vars = <Variable>[dateVar(at)];
    var movementScope = '';
    var balanceSource = 'p.current_stock';
    var balanceJoin = '';

    if (warehouseIds != null) {
      final ph = warehouseIds.map((_) => '?').join(', ');
      movementScope = 'AND sm.warehouse_id IN ($ph)';
      vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      balanceSource = 'COALESCE(b.qty, 0)';
      balanceJoin = '''
      LEFT JOIN (
        SELECT product_id, SUM(quantity) AS qty
        FROM inventory_balances
        WHERE warehouse_id IN ($ph)
        GROUP BY product_id
      ) b ON b.product_id = p.id''';
      vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
    }

    final rows = await customSelect(
      '''
      SELECT COALESCE(SUM(($balanceSource - COALESCE(m.delta, 0)) * p.cost_price), 0) AS value
      FROM products p
      LEFT JOIN (
        SELECT sm.product_id, SUM(sm.quantity) AS delta
        FROM stock_movements sm
        WHERE sm.created_at > ? AND sm.deleted_at IS NULL $movementScope
        GROUP BY sm.product_id
      ) m ON m.product_id = p.id$balanceJoin
      ''',
      variables: vars,
      readsFrom: {products, stockMovements, inventoryBalances},
    ).get();

    return (rows.first.data['value'] as num?)?.toDouble() ?? 0.0;
  }
}
