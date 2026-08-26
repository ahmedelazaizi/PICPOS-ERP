part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LANDED COST DAO — محرك التكاليف المحملة (Phase C2)
// ═══════════════════════════════════════════════════════════════════════════

extension LandedCostDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // SHEET MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a landed cost sheet for a purchase invoice
  Future<int> createLandedCostSheet({
    required int purchaseInvoiceId,
    required String sheetNumber,
    String allocationMethod = 'by_value',
    String? notes,
    int? createdBy,
  }) {
    return into(landedCostSheets).insert(
      LandedCostSheetsCompanion.insert(
        purchaseInvoiceId: purchaseInvoiceId,
        sheetNumber: sheetNumber,
        allocationMethod: Value(allocationMethod),
        notes: Value(notes),
        createdBy: Value(createdBy),
      ),
    );
  }

  /// Get sheets for a purchase invoice
  Future<List<LandedCostSheetData>> getLandedCostSheets({
    int? purchaseInvoiceId,
  }) {
    final query = select(landedCostSheets)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    if (purchaseInvoiceId != null) {
      query.where((s) => s.purchaseInvoiceId.equals(purchaseInvoiceId));
    }
    return query.get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COST ITEMS
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a cost item to a sheet
  Future<int> addLandedCostItem({
    required int sheetId,
    required String costType,
    required String description,
    required double amount,
    int? supplierPartyId,
  }) async {
    final id = await into(landedCostItems).insert(
      LandedCostItemsCompanion.insert(
        sheetId: sheetId,
        costType: Value(costType),
        description: description,
        amount: amount,
        supplierPartyId: Value(supplierPartyId),
      ),
    );

    // Update total
    await _recalculateSheetTotal(sheetId);
    return id;
  }

  /// Get cost items for a sheet
  Future<List<LandedCostItemData>> getLandedCostItems(int sheetId) {
    return (select(landedCostItems)
          ..where((i) => i.sheetId.equals(sheetId)))
        .get();
  }

  /// Delete a cost item
  Future<void> deleteLandedCostItem(int itemId) {
    return transaction(() async {
      final item = await (select(landedCostItems)
            ..where((i) => i.id.equals(itemId)))
          .getSingle();
      await (delete(landedCostItems)..where((i) => i.id.equals(itemId))).go();
      await _recalculateSheetTotal(item.sheetId);
    });
  }

  Future<void> _recalculateSheetTotal(int sheetId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) as total FROM landed_cost_items WHERE sheet_id = ?',
      variables: [Variable(sheetId)],
    ).getSingle();
    final total = (result.data['total'] as num?)?.toDouble() ?? 0.0;
    await (update(landedCostSheets)..where((s) => s.id.equals(sheetId)))
        .write(LandedCostSheetsCompanion(totalAdditionalCost: Value(total)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ALLOCATION
  // ─────────────────────────────────────────────────────────────────────────

  /// تغييرُ طريقة التوزيع لورقةٍ **مسوّدة**، ثمّ إعادةُ حساب توزيعها.
  ///
  /// ⚠️ **المسوّدةُ وحدَها.** الورقةُ المطبَّقةُ لها قيدٌ منشورٌ وتكلفةُ وحدةٍ
  /// اندمجت فعلاً في المتوسّط المرجَّح (`applyLandedCost`)، فتغييرُ طريقتها
  /// يجعل الجدولَ المعروضَ يخالف ما قُيِّد — أرقامٌ تكذب.
  ///
  /// ⚠️ **و`by_weight` مرفوضةٌ هنا لا في العرض وحدَه.** `calculateAllocations`
  /// لا تعرفها فتسقط على `by_value` في فرع `default` **صامتةً** — فتُكتَب في
  /// العمود طريقةٌ والمحسوبُ طريقةٌ أخرى. فالمنعُ عند الكتابة لا عند الزرّ.
  Future<void> updateAllocationMethod(int sheetId, String method) async {
    const allowed = {'by_value', 'by_quantity', 'equal'};
    if (!allowed.contains(method)) {
      throw ArgumentError.value(
          method, 'method', 'طريقةُ توزيعٍ غيرُ مدعومة');
    }
    final sheet = await (select(landedCostSheets)
          ..where((s) => s.id.equals(sheetId)))
        .getSingle();
    if (sheet.status != 'draft') {
      throw StateError(
          'لا تُغيَّر طريقةُ التوزيع إلّا على مسوّدة — حالةُ الورقة ${sheet.status}');
    }
    await (update(landedCostSheets)..where((s) => s.id.equals(sheetId)))
        .write(LandedCostSheetsCompanion(allocationMethod: Value(method)));
    await calculateAllocations(sheetId);
  }

  /// Calculate allocations based on the chosen method
  Future<List<LandedCostAllocationData>> calculateAllocations(int sheetId) async {
    final sheet = await (select(landedCostSheets)
          ..where((s) => s.id.equals(sheetId)))
        .getSingle();

    // Get purchase invoice items
    final items = await customSelect(
      '''SELECT pii.id as item_id, pii.product_id, pii.quantity,
            pii.unit_cost as unit_price,
            (pii.quantity * pii.unit_cost) as line_total
         FROM purchase_invoice_items pii
         WHERE pii.invoice_id = ?''',
      variables: [Variable(sheet.purchaseInvoiceId)],
    ).get();

    if (items.isEmpty) return [];

    final totalCost = sheet.totalAdditionalCost;
    final allocations = <LandedCostAllocationData>[];

    // Calculate allocation base
    double totalBase = 0;
    for (final item in items) {
      switch (sheet.allocationMethod) {
        case 'by_value':
          totalBase += (item.data['line_total'] as num).toDouble();
          break;
        case 'by_quantity':
          totalBase += (item.data['quantity'] as num).toDouble();
          break;
        case 'equal':
          totalBase = items.length.toDouble();
          break;
        default:
          totalBase += (item.data['line_total'] as num).toDouble();
      }
    }

    if (totalBase == 0) return [];

    // Clear old allocations
    await (delete(landedCostAllocations)
          ..where((a) => a.sheetId.equals(sheetId)))
        .go();

    // ── التقريبُ وفرقُه ────────────────────────────────────────────────
    //
    // ⚠️ **مجموعُ ما وُزِّع يجب أن يساوي إجماليَّ الورقة بالضبط.** القسمةُ
    // النسبيّةُ تعطي كسوراً بلا نهاية (‏تكلفةٌ ÷ ثلاثةِ بنودٍ مثلاً)، فتقريبُ
    // كلِّ سطرٍ على حدةٍ يترك فرقاً بين مجموعِ الأسطر وإجماليِّ الورقة.
    // وذلك الفرقُ ليس تجميليّاً: `applyLandedCost` يقيّد **إجماليَّ الورقة**
    // مديناً على المخزون بينما يُبلبل الأسطرَ على متوسّطات التكلفة — فيبقى
    // فرقٌ في حساب المخزون لا يقابله تحريكُ تكلفةٍ في أيّ صنف.
    //
    // فالفرقُ يُحمَّل على **أكبر بند**: أقلُّ الأسطر تأثّراً نسبيّاً بقرشٍ
    // زائدٍ أو ناقص. وهو ما يصفه التصميمُ نصّاً في رأس جدول التوزيع.
    final bases = <double>[];
    for (final item in items) {
      switch (sheet.allocationMethod) {
        case 'by_quantity':
          bases.add((item.data['quantity'] as num).toDouble());
          break;
        case 'equal':
          bases.add(1.0);
          break;
        case 'by_value':
        default:
          bases.add((item.data['line_total'] as num).toDouble());
      }
    }

    // تقريبٌ إلى قرشَين، ثمّ يُلقى الباقي على أكبر سطر.
    final amounts = bases
        .map((b) => (totalCost * (b / totalBase) * 100).roundToDouble() / 100)
        .toList();
    var biggest = 0;
    for (var i = 1; i < amounts.length; i++) {
      if (amounts[i] > amounts[biggest]) biggest = i;
    }
    final sum = amounts.fold<double>(0, (s, v) => s + v);
    final drift = ((totalCost - sum) * 100).roundToDouble() / 100;
    amounts[biggest] =
        ((amounts[biggest] + drift) * 100).roundToDouble() / 100;

    // Calculate and insert allocations
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final allocation = amounts[i];
      final qty = (item.data['quantity'] as num).toDouble();
      final unitPrice = (item.data['unit_price'] as num).toDouble();
      final newUnitCost = unitPrice + (qty > 0 ? allocation / qty : 0);

      final allocId = await into(landedCostAllocations).insert(
        LandedCostAllocationsCompanion.insert(
          sheetId: sheetId,
          productId: item.data['product_id'] as int,
          purchaseItemId: item.data['item_id'] as int,
          originalCost: unitPrice,
          allocatedAmount: allocation,
          newUnitCost: newUnitCost,
          quantity: qty,
        ),
      );

      // Build the allocation data for return
      allocations.add(LandedCostAllocationData(
        id: allocId,
        sheetId: sheetId,
        productId: item.data['product_id'] as int,
        purchaseItemId: item.data['item_id'] as int,
        originalCost: unitPrice,
        allocatedAmount: allocation,
        newUnitCost: newUnitCost,
        quantity: qty,
      ));
    }

    return allocations;
  }

  /// Apply a landed-cost sheet — ATOMICALLY (S-COST / Spec 144):
  ///  1. blend the allocated cost into `products.costPrice` (WAC → reaches COGS)
  ///  2. blend it into `inventory_balances.average_cost` for the invoice's
  ///     warehouse (value-add, NOT a `SET =` overwrite)
  ///  3. post ONE balanced journal entry: Dr inventory / Cr supplier-AP (آجل,
  ///     per `supplierPartyId`) or cash
  ///  4. mark the sheet `applied`
  /// All four run inside a single [transaction] so a failure leaves no
  /// half-applied state (R3). Re-applying an already-`applied` sheet is a no-op.
  Future<void> applyLandedCost(int sheetId) async {
    final sheet = await (select(landedCostSheets)
          ..where((s) => s.id.equals(sheetId)))
        .getSingle();

    // Idempotency (FR-008): only a 'draft' sheet may be applied. 'applied'
    // (already done) and 'voided' (reversed on purchase void — S-COST-2) are
    // both terminal; treating only 'applied' as terminal would let a voided
    // sheet be re-applied and double-blend the WAC (the JE would dedup, the
    // blend would not).
    if (sheet.status != 'draft') return;

    // B8 (S-LANDED-LIFECYCLE / PUR-2b): a DRAFT sheet's parent invoice can
    // still be voided out from under it (voidPurchaseInvoice only reverses
    // sheets that were already 'applied' — a draft one is untouched, left
    // pointing at a now-dead invoice). Applying it here would blend cost
    // into products.costPrice and post a live JE against an invoice that no
    // longer exists financially. Fail loud instead of silently capitalizing
    // freight against a voided purchase.
    final parentInvoice = await (select(purchaseInvoices)
          ..where((i) => i.id.equals(sheet.purchaseInvoiceId)))
        .getSingleOrNull();
    if (parentInvoice == null ||
        parentInvoice.status == 'voided' ||
        parentInvoice.isDeleted) {
      throw StateError(
        'لا يمكن تطبيق ورقة تكاليف محملة على فاتورة مشتريات ملغاة أو محذوفة — '
        'الفاتورة الأصلية لهذه الورقة (${sheet.sheetNumber}) لم تعد سارية.',
      );
    }

    final allocations = await (select(landedCostAllocations)
          ..where((a) => a.sheetId.equals(sheetId)))
        .get();
    final items = await (select(landedCostItems)
          ..where((i) => i.sheetId.equals(sheet.id)))
        .get();

    // Resolve the invoice's warehouse (cost blend target) + GL context.
    final invoice = await getPurchaseInvoiceById(sheet.purchaseInvoiceId);
    final int? warehouseId = invoice?.warehouseId;
    final warehouse =
        warehouseId != null ? await getWarehouseById(warehouseId) : null;
    final int? branchId = warehouse?.branchId;
    final int? ccId = invoice?.costCenterId ?? warehouse?.costCenterId;

    await transaction(() async {
      // TOCTOU (FR-008): the pre-check above races a concurrent apply. Re-read
      // status INSIDE the transaction (locked on PG) — if another apply
      // committed first, bail. createJournalEntry dedups the JE on
      // (referenceType, referenceId), but nothing else stops a SECOND WAC blend
      // from double-adding the landed amount, so this guard is what protects it.
      if (isPostgres) {
        await customSelect(
          'SELECT id FROM landed_cost_sheets WHERE id = ? FOR UPDATE',
          variables: [Variable<int>(sheetId)],
        ).get();
      }
      final fresh = await (select(landedCostSheets)
            ..where((s) => s.id.equals(sheetId)))
          .getSingle();
      if (fresh.status != 'draft') return;

      // ── 1 + 2. Cost side: blend WAC (product + warehouse), no overwrite ──
      for (final alloc in allocations) {
        // products.costPrice — added-value blend over current on-hand stock.
        await applyLandedCostToProductWAC(
          productId: alloc.productId,
          addedValue: alloc.allocatedAmount,
        );

        // inventory_balances.average_cost — same added-value blend per warehouse.
        if (warehouseId != null) {
          final bal = await (select(inventoryBalances)
                ..where((b) =>
                    b.productId.equals(alloc.productId) &
                    b.warehouseId.equals(warehouseId))
                ..limit(1))
              .getSingleOrNull();
          if (bal != null) {
            final double newAvg = bal.quantity > 0
                ? bal.averageCost + (alloc.allocatedAmount / bal.quantity)
                : alloc.newUnitCost;
            await (update(inventoryBalances)
                  ..where((b) => b.id.equals(bal.id)))
                .write(InventoryBalancesCompanion(
              averageCost: Value(newAvg),
              lastUpdated: Value(DateTime.now()),
            ));
          }
        }
      }

      // ── 3. GL side: one balanced JE (Dr inventory / Cr supplier-AP or cash) ──
      final desc = 'تكاليف محملة ${sheet.sheetNumber}';
      final invCode = await accountingDao.getMappedAccountCode(
        'inventory', AccountingDao.accountPurposes['inventory']!,
      );
      final invAcc = await accountingDao.getAccountByCode(invCode);

      if (invAcc == null) {
        // No CoA mapping → skip GL rather than crash (parity with purchases).
        // Cost blend above still stands; sheet is marked applied below.
        debugPrint(
            '[FINANCIAL_WARNING] Landed cost ${sheet.sheetNumber}: inventory account not mapped — GL entry skipped.');
      } else {
        // Group credits by resolved account: supplier AP (آجل) if the item has
        // a supplier, else cash. Sum amounts per account.
        final apCode = await accountingDao.getMappedAccountCode(
          'payables', AccountingDao.accountPurposes['payables']!,
        );
        final apControlAcc = await accountingDao.getAccountByCode(apCode);
        final cashCode = await accountingDao.getMappedAccountCode(
          'cash', AccountingDao.accountPurposes['cash']!,
        );
        final cashAcc = await accountingDao.getAccountByCode(cashCode);

        final Map<int, double> creditByAccount = {};
        bool creditsResolvable = true;
        for (final item in items) {
          if (item.amount == 0) continue;
          Account? acc;
          if (item.supplierPartyId != null) {
            acc = await _resolvePartySubAccount(
                item.supplierPartyId, apControlAcc);
          } else {
            acc = cashAcc;
          }
          if (acc == null) {
            creditsResolvable = false;
            break;
          }
          creditByAccount[acc.id] =
              (creditByAccount[acc.id] ?? 0) + item.amount;
        }

        if (creditsResolvable && creditByAccount.isNotEmpty) {
          // total == Σ item.amount == totalAdditionalCost == Σ allocatedAmount
          // (calculateAllocations distributes the sheet total), so the JE
          // inventory debit ties to the WAC value-add in the normal case.
          // Edge: if a product's whole stock was already sold before apply
          // (currentQty<=0), its WAC blend is skipped while its share still
          // debits inventory here — that residual sits in the inventory GL
          // until the next recalculateProductWAC folds it in. Rare; documented.
          final total =
              creditByAccount.values.fold<double>(0, (a, b) => a + b);
          final lines = <JournalLine>[
            JournalLine(
              accountId: invAcc.id,
              debit: total,
              description: 'إعادة تقييم مخزون - $desc',
            ),
            for (final e in creditByAccount.entries)
              JournalLine(
                accountId: e.key,
                credit: e.value,
                description: 'سداد $desc',
              ),
          ];
          // Deterministic globalId keyed on the sheet: a retry after a
          // rolled-back apply reuses the same id and converges with an
          // already-submitted server row (createJournalEntry also dedups on
          // (referenceType, referenceId)).
          final jeGid = JournalEntryGid.compute(
            sourceType: JournalEntryGid.sourceLandedCost,
            sourceGid: 'sheet${sheet.id}',
            verb: 'apply',
          );
          await accountingDao.createJournalEntry(
            description: 'قيد تكاليف محملة تلقائي - $desc',
            date: DateTime.now(),
            lines: lines,
            referenceType: 'landed_cost',
            referenceId: sheet.id,
            isAutoPosted: true,
            costCenterId: ccId,
            branchId: branchId,
            globalId: jeGid,
          );
        } else {
          debugPrint(
              '[FINANCIAL_WARNING] Landed cost ${sheet.sheetNumber}: credit account(s) unresolved — GL entry skipped.');
        }
      }

      // ── 4. Mark sheet as applied ──
      await (update(landedCostSheets)..where((s) => s.id.equals(sheetId)))
          .write(const LandedCostSheetsCompanion(status: Value('applied')));
    });
  }

  /// Get allocations with product names
  Future<List<Map<String, dynamic>>> getAllocationsWithDetails(int sheetId) async {
    final results = await customSelect(
      '''SELECT lca.*, p.name as product_name, p.code as product_code
         FROM landed_cost_allocations lca
         JOIN products p ON p.id = lca.product_id
         WHERE lca.sheet_id = ?
         ORDER BY p.name''',
      variables: [Variable(sheetId)],
    ).get();
    return results.map((r) => r.data).toList();
  }
}
