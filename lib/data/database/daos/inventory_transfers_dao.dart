// =======================================================================
// INVENTORY TRANSFERS DAO
// Extracted from inventory_dao.dart — PIR Phase 4 God File Splitting
// Inventory bonds, stock transfers, stock requisitions
// =======================================================================

part of '../database.dart';

/// Extension for inventory bonds, stock transfers, and stock requisitions
extension InventoryTransfersDao on AppDatabase {

  // ═══════════════════════════════════════════════════════════════════════
  // INVENTORY BONDS OPERATIONS (Phase 2)
  // ═══════════════════════════════════════════════════════════════════════

  /// Create a new inventory bond header
  Future<int> createInventoryBond(InventoryBondsCompanion bond) {
    return into(inventoryBonds).insert(bond);
  }

  /// Add items to an inventory bond
  Future<void> addInventoryBondItems(
    List<InventoryBondItemsCompanion> items,
  ) async {
    await batch((batch) {
      batch.insertAll(inventoryBondItems, items);
    });
  }

  /// Get inventory bonds by type (in/out/opening)
  Future<List<InventoryBond>> getInventoryBondsByType(String type) {
    return (select(inventoryBonds)
          ..where((b) => b.type.equals(type))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .get();
  }

  /// Get details of a specific bond with its items
  Future<List<InventoryBondItem>> getInventoryBondItems(int bondId) {
    return (select(
      inventoryBondItems,
    )..where((i) => i.bondId.equals(bondId))).get();
  }

  /// Perform a stock transfer between warehouses
  ///
  /// [globalId] — Spec 129 F4: caller-supplied UUIDv7 stamped on the
  /// inventory_bonds row so mirror local + server share identity.
  ///
  /// Returns the created transfer bond id (Spec 148 — the stock-requisition
  /// approval flow stores it as `fulfilledByTransferId`). Existing callers
  /// that ignore the value are unaffected.
  Future<int> transferStock({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
    int? userId,
    String? globalId,
  }) async {
    return transaction(() async {
      final bondNumber = 'TRF-${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create Bond Header
      final bondId = await into(inventoryBonds).insert(
        InventoryBondsCompanion.insert(
          bondNumber: bondNumber,
          type: const Value('transfer'),
          warehouseId: fromWarehouseId,
          toWarehouseId: Value(toWarehouseId),
          notes: Value(notes),
          createdBy: Value(userId),
          bondDate: Value(DateTime.now()),
          globalId: Value(globalId),
        ),
      );

      double totalTransferValue = 0;

      final productIds = items.map((i) => i['productId'] as int).toList();
      final productMap = await getProductsByIds(productIds);
      for (final item in items) {
        final int productId = item['productId'];
        final double qty = (item['quantity'] as num).toDouble();
        final product = productMap[productId];
        if (product == null) continue;

        // B-03 + B-04: read the SOURCE warehouse balance ONCE — it feeds both
        // the negative-stock guard (available qty) and the per-warehouse cost
        // that must travel with the goods (average_cost).
        final warehouseBalance = await (select(inventoryBalances)
              ..where((b) => b.productId.equals(productId))
              ..where((b) => b.warehouseId.equals(fromWarehouseId)))
            .getSingleOrNull();
        final availableQty = warehouseBalance?.quantity ?? 0;

        // B-04 (Invariant #3 — no silent negative): a TRANSFER must NEVER drive
        // the source negative, REGARDLESS of `enable_negative_sales` or the
        // per-product `allowNegativeSale`. That sales flag governs SALES only;
        // letting it open negative transfers ships phantom goods (a −qty source
        // balance + a GL entry for stock that isn't there). Transfers block
        // unconditionally, fail-loud, in Arabic. (Sales still honour the flag —
        // this path is transfer-specific.)
        if (availableQty < qty) {
          throw Exception(
            'الكمية المتوفرة من "${product.name}" في المستودع المصدر ($availableQty) أقل من المطلوب ($qty)',
          );
        }

        // B-03 (Invariant #2d/#5 — value moves with the goods): blend the
        // destination against the SOURCE warehouse's per-warehouse WAC
        // (average_cost), NOT the global product.costPrice — the global cost may
        // already have been re-blended from a DIFFERENT mix of warehouses'
        // history and no longer represents what THIS source warehouse holds.
        // Fall back to costPrice only when the source has no positive
        // per-warehouse cost yet.
        final sourceUnitCost =
            (warehouseBalance != null && warehouseBalance.averageCost > 0)
                ? warehouseBalance.averageCost
                : product.costPrice;

        // 2. Create Bond Item
        await into(inventoryBondItems).insert(
          InventoryBondItemsCompanion.insert(
            bondId: bondId,
            productId: productId,
            quantity: qty,
            unitCost: Value(sourceUnitCost),
          ),
        );

        // 3. Stock Out from Source
        await adjustStock(
          productId: productId,
          warehouseId: fromWarehouseId,
          quantity: -qty,
          type: 'transfer_out',
          referenceType: 'inventory_bond',
          referenceId: bondId,
          notes:
              'Transfer Out to Warehouse #$toWarehouseId (Bond #$bondNumber)',
          // B-03: stamp the same source WAC on the out-leg movement so both
          // legs of the bond agree. A deduction (qty<0) does not re-blend the
          // source average_cost, so this only fixes the movement-log record.
          unitCost: sourceUnitCost,
        );

        // 4. Stock In to Destination — thread the SOURCE cost as unitCost so the
        // destination per-warehouse average_cost blends against the value that
        // actually moved (B-03), instead of the global product.costPrice.
        await adjustStock(
          productId: productId,
          warehouseId: toWarehouseId,
          quantity: qty,
          type: 'transfer_in',
          referenceType: 'inventory_bond',
          referenceId: bondId,
          notes:
              'Transfer In from Warehouse #$fromWarehouseId (Bond #$bondNumber)',
          unitCost: sourceUnitCost,
        );

        totalTransferValue += qty * sourceUnitCost;
      }

      // 5. F-12: Generate dual accounting JE for the transfer
      if (totalTransferValue > 0) {
        final inventoryAccount = await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
        );
        final gitAccount = await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('goods_in_transit', AccountingDao.accountPurposes['goods_in_transit']!),
        );

        final sourceBranchId = await getWarehouseById(fromWarehouseId).then((w) => w?.branchId);
        final destBranchId = await getWarehouseById(toWarehouseId).then((w) => w?.branchId);

        if (inventoryAccount == null || gitAccount == null) {
          throw Exception('حسابات المخزون أو بضاعة بالطريق غير مربوطة في الإعدادات، يرجى ربطها لتنفيذ التحويل.');
        }

        // قيد الفرع المُرسل (نقص مخزون، زيادة بضاعة بالطريق أو جاري فروع)
        await accountingDao.createJournalEntry(
          description: 'تحويل صادرات مخزون إلى المستودع #$toWarehouseId ($bondNumber)',
          date: DateTime.now(),
          lines: [
            JournalLine(
              accountId: gitAccount.id,
              debit: totalTransferValue,
              description: 'بضاعة بالطريق — قيد صادر من المستودع #$fromWarehouseId',
            ),
            JournalLine(
              accountId: inventoryAccount.id,
              credit: totalTransferValue,
              description: 'تحويل مخزون — خروج',
            ),
          ],
          referenceType: 'inventory_transfer_out',
          referenceId: bondId,
          isAutoPosted: true,
          branchId: sourceBranchId,
        );

        // قيد الفرع المستلم (زيادة مخزون، تصفية بضاعة بالطريق أو جاري فروع)
        await accountingDao.createJournalEntry(
          description: 'تحويل واردات مخزون من المستودع #$fromWarehouseId ($bondNumber)',
          date: DateTime.now(),
          lines: [
            JournalLine(
              accountId: inventoryAccount.id,
              debit: totalTransferValue,
              description: 'تحويل مخزون — دخول',
            ),
            JournalLine(
              accountId: gitAccount.id,
              credit: totalTransferValue,
              description: 'تصفية بضاعة بالطريق — قيد وارد للمستودع #$toWarehouseId',
            ),
          ],
          referenceType: 'inventory_transfer_in',
          referenceId: bondId,
          isAutoPosted: true,
          branchId: destBranchId,
        );
      }

      return bondId;
    });
  }
  // ═══════════════════════════════════════════════════════════════════════
  // STOCK REQUISITIONS OPERATIONS (Phase 2 Cross-Branch)
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all stock requisitions ordered by date descending
  Stream<List<StockRequisition>> watchAllStockRequisitions() {
    return (select(stockRequisitions)
          ..orderBy([(r) => OrderingTerm.desc(r.requisitionDate)]))
        .watch();
  }

  /// Get stock requisition by ID
  Future<StockRequisition?> getStockRequisitionById(int id) {
    return (select(stockRequisitions)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get items for a specific stock requisition
  Future<List<StockRequisitionItem>> getStockRequisitionItems(int requisitionId) {
    return (select(stockRequisitionItems)
          ..where((i) => i.requisitionId.equals(requisitionId)))
        .get();
  }

  /// Create a new stock requisition with its items
  Future<int> createStockRequisition({
    required StockRequisitionsCompanion requisition,
    required List<StockRequisitionItemsCompanion> items,
  }) async {
    return transaction(() async {
      final reqId = await into(stockRequisitions).insert(requisition);
      
      final itemsWithReqId = items.map((item) {
        return item.copyWith(requisitionId: Value(reqId));
      }).toList();
      
      await batch((batch) {
        batch.insertAll(stockRequisitionItems, itemsWithReqId);
      });
      
      return reqId;
    });
  }

  /// Update the status of a stock requisition
  Future<void> updateStockRequisitionStatus(int id, String status) async {
    await (update(stockRequisitions)..where((r) => r.id.equals(id))).write(
      StockRequisitionsCompanion(
        status: Value(status),
      ),
    );
  }

  /// Delete a draft stock requisition
  Future<void> deleteStockRequisition(int id) async {
    await transaction(() async {
      final req = await getStockRequisitionById(id);
      if (req == null || req.status != 'pending') {
        throw Exception('لا يمكن حذف الطلب لأن حالته ليست "معلق".');
      }
      
      await (delete(stockRequisitionItems)
            ..where((i) => i.requisitionId.equals(id)))
          .go();
      
      await (delete(stockRequisitions)..where((r) => r.id.equals(id))).go();
    });
  }

}
