part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MANUFACTURING DAO — التصنيع وأوامر الإنتاج
// ═══════════════════════════════════════════════════════════════════════════

extension ManufacturingDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // BOM — قوائم المكونات
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all BOMs
  Stream<List<BillOfMaterialData>> watchBOMs() {
    return (select(billOfMaterials)
          ..where((b) => b.isActive.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.bomCode)]))
        .watch();
  }

  /// Get BOM by ID
  Future<BillOfMaterialData?> getBOM(int id) {
    return (select(
      billOfMaterials,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
  }

  /// Get BOM components
  Future<List<BomComponentData>> getBOMComponents(int bomId) {
    return (select(bomComponents)..where((c) => c.bomId.equals(bomId))).get();
  }

  /// Get the last purchase price for a product from purchase invoice items
  Future<double?> getLastPurchasePrice(int productId) async {
    final result = await customSelect(
      '''SELECT pi.unit_cost
         FROM purchase_invoice_items pi
         JOIN purchase_invoices inv ON pi.invoice_id = inv.id
         WHERE pi.product_id = ?
         ORDER BY inv.invoice_date DESC, pi.id DESC
         LIMIT 1''',
      variables: [Variable(productId)],
      readsFrom: {purchaseInvoiceItems, purchaseInvoices},
    ).getSingleOrNull();

    if (result != null) {
      return (result.data['unit_cost'] as num?)?.toDouble();
    }
    return null;
  }

  /// Batch-fetch last purchase prices for multiple products in a single query.
  /// Returns a map of productId → last unit_cost (null if no purchase history).
  Future<Map<int, double?>> _getLastPurchasePricesByIds(List<int> ids) async {
    if (ids.isEmpty) return {};
    final unique = ids.toSet().toList();
    final placeholders = unique.map((_) => '?').join(',');
    final rows = await customSelect(
      '''SELECT pi.product_id, pi.unit_cost
         FROM purchase_invoice_items pi
         JOIN purchase_invoices inv ON pi.invoice_id = inv.id
         WHERE pi.product_id IN ($placeholders)
         ORDER BY pi.product_id, inv.invoice_date DESC, pi.id DESC''',
      variables: unique.map((id) => Variable<int>(id)).toList(),
      readsFrom: {purchaseInvoiceItems, purchaseInvoices},
    ).get();
    // Results are ordered most-recent-first per product; take first occurrence.
    final map = <int, double?>{};
    for (final row in rows) {
      final id = row.read<int>('product_id');
      if (!map.containsKey(id)) {
        map[id] = (row.data['unit_cost'] as num?)?.toDouble();
      }
    }
    return map;
  }

  /// Create a BOM with components
  Future<int> createBOM({
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    // Feature 009 — optional flags. Default `isActive = true` matches the
    // table-level default (Constitution I — pre-009 callers behave the same).
    // The FR-004 guard (`autoDepleteOnSale = true` requires `isActive = true`)
    // is enforced inside the transaction by T015.
    bool autoDepleteOnSale = false,
    String depletionPolicy = 'prefer_finished_stock',
    bool isActive = true,
    /// v166 — هويّةُ القائمة. تُسَكّ على العميل وتُمرَّر إلى الخادم، وإلّا
    /// سكّ كلُّ طرفٍ هويّةً فعادت القائمةُ بسحب الدلتا مكرَّرةً — وأمرا
    /// إنتاجٍ يشيران إلى قائمتَين لنفس الصنف.
    String? globalId,
  }) async {
    // FR-004 (defense-in-depth): an inactive BOM must never be allowed to
    // run an auto-deplete deduction at sale time. The UI guard in T022
    // disables the toggle when isActive is false, but admin tools and
    // server-side migrations can bypass that — so we enforce it at the DAO.
    if (autoDepleteOnSale && !isActive) {
      throw const InvalidPolicyException(
        'لا يمكن تفعيل خصم الخامات تلقائيًا على قائمة تصنيع غير مفعّلة (FR-004)',
      );
    }
    return transaction(() async {
      // Calculate estimated cost from components using last purchase price
      final materialIds = components.map((c) => c['rawMaterialId'] as int).toList();
      final lastPrices = await _getLastPurchasePricesByIds(materialIds);
      final productMap = await getProductsByIds(materialIds);

      double estimatedCost = 0;
      for (final c in components) {
        final materialId = c['rawMaterialId'] as int;
        final unitCost = lastPrices[materialId] ?? productMap[materialId]?.costPrice ?? 0;
        final qty = c['quantity'] as double;
        final wastage = (c['wastagePercent'] as double?) ?? 0;
        estimatedCost += unitCost * qty * (1 + wastage / 100);
      }

      final bomId = await into(billOfMaterials).insert(
        BillOfMaterialsCompanion.insert(
          finishedProductId: finishedProductId,
          bomCode: bomCode,
          expectedQuantity: Value(expectedQuantity),
          estimatedCost: Value(estimatedCost),
          notes: Value(notes),
          isActive: Value(isActive),
          autoDepleteOnSale: Value(autoDepleteOnSale),
          depletionPolicy: Value(depletionPolicy),
          globalId: Value(globalId ?? UuidV7.generate()), // v166
        ),
      );

      for (final c in components) {
        await into(bomComponents).insert(
          BomComponentsCompanion.insert(
            bomId: bomId,
            rawMaterialId: c['rawMaterialId'] as int,
            quantity: c['quantity'] as double,
            unit: Value((c['unit'] as String?) ?? 'قطعة'),
            quantityInBase: Value((c['quantityInBase'] as double?) ?? 1.0),
            wastagePercent: Value((c['wastagePercent'] as double?) ?? 0),
            // v166 — المكوّنُ يُزامَن استقلالاً عن قائمته.
            globalId: Value((c['globalId'] as String?) ?? UuidV7.generate()),
          ),
        );
      }

      return bomId;
    });
  }

  /// Update an existing BOM and its components (replace strategy)
  Future<void> updateBOM({
    required int bomId,
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    // Feature 009 — `null` means "leave unchanged" so existing callers
    // (BOM form widget pre-009) keep their behavior (Constitution I).
    bool? autoDepleteOnSale,
    String? depletionPolicy,
    bool? isActive,
  }) async {
    await transaction(() async {
      // FR-004 (defense-in-depth): compute the EFFECTIVE post-update state
      // because the caller may flip only one of (autoDepleteOnSale, isActive)
      // — e.g., setting isActive=false on a BOM that is already auto-deplete
      // must also fail. Read the current row and merge against the params.
      final current = await (select(billOfMaterials)
            ..where((b) => b.id.equals(bomId)))
          .getSingleOrNull();
      if (current == null) {
        throw Exception('قائمة التصنيع غير موجودة (#$bomId)');
      }
      final effectiveActive = isActive ?? current.isActive;
      final effectiveAuto = autoDepleteOnSale ?? current.autoDepleteOnSale;
      if (effectiveAuto && !effectiveActive) {
        throw const InvalidPolicyException(
          'لا يمكن تفعيل خصم الخامات تلقائيًا على قائمة تصنيع غير مفعّلة (FR-004)',
        );
      }

      // Calculate estimated cost from components using last purchase price
      final materialIds = components.map((c) => c['rawMaterialId'] as int).toList();
      final lastPrices = await _getLastPurchasePricesByIds(materialIds);
      final productMap = await getProductsByIds(materialIds);

      double estimatedCost = 0;
      for (final c in components) {
        final materialId = c['rawMaterialId'] as int;
        final unitCost = lastPrices[materialId] ?? productMap[materialId]?.costPrice ?? 0;
        final qty = c['quantity'] as double;
        final wastage = (c['wastagePercent'] as double?) ?? 0;
        estimatedCost += unitCost * qty * (1 + wastage / 100);
      }

      // Update BOM header
      await (update(billOfMaterials)..where((b) => b.id.equals(bomId))).write(
        BillOfMaterialsCompanion(
          finishedProductId: Value(finishedProductId),
          bomCode: Value(bomCode),
          expectedQuantity: Value(expectedQuantity),
          estimatedCost: Value(estimatedCost),
          notes: Value(notes),
          isActive: isActive == null ? const Value.absent() : Value(isActive),
          autoDepleteOnSale: autoDepleteOnSale == null
              ? const Value.absent()
              : Value(autoDepleteOnSale),
          depletionPolicy: depletionPolicy == null
              ? const Value.absent()
              : Value(depletionPolicy),
        ),
      );

      // Delete old components and insert new ones
      await (delete(bomComponents)..where((c) => c.bomId.equals(bomId))).go();

      for (final c in components) {
        await into(bomComponents).insert(
          BomComponentsCompanion.insert(
            bomId: bomId,
            rawMaterialId: c['rawMaterialId'] as int,
            quantity: c['quantity'] as double,
            unit: Value((c['unit'] as String?) ?? 'قطعة'),
            quantityInBase: Value((c['quantityInBase'] as double?) ?? 1.0),
            wastagePercent: Value((c['wastagePercent'] as double?) ?? 0),
            // v166 — المكوّنُ يُزامَن استقلالاً عن قائمته.
            globalId: Value((c['globalId'] as String?) ?? UuidV7.generate()),
          ),
        );
      }
    });
  }

  /// Update a draft manufacturing order
  Future<void> updateManufacturingOrder({
    required int orderId,
    int? bomId,
    double? orderedQty,
    int? warehouseId,
    String? notes,
  }) async {
    final order = await (select(manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (order == null) throw Exception('أمر الإنتاج غير موجود');
    if (order.status != 'draft') {
      throw Exception('لا يمكن تعديل أمر إنتاج ليس مسودة');
    }

    await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
      ManufacturingOrdersCompanion(
        bomId: bomId != null ? Value(bomId) : const Value.absent(),
        orderedQty: orderedQty != null ? Value(orderedQty) : const Value.absent(),
        warehouseId: warehouseId != null ? Value(warehouseId) : const Value.absent(),
        notes: notes != null ? Value(notes) : const Value.absent(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MANUFACTURING ORDERS — أوامر الإنتاج
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch manufacturing orders
  Stream<List<ManufacturingOrderData>> watchManufacturingOrders({
    String? status,
  }) {
    final q = select(manufacturingOrders)
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    if (status != null) q.where((o) => o.status.equals(status));
    return q.watch();
  }

  /// Create a manufacturing order
  Future<int> createManufacturingOrder({
    required int bomId,
    required double orderedQty,
    required int warehouseId,
    required DateTime startDate,
    String? notes,
    /// v166 — هويّةُ الأمر. كلُّ حدثٍ ماليٍّ بعدها يُشير إليها لا إلى رقمٍ
    /// محلّيّ: رقمُ الأمر على العميل يخالف رقمَه على الخادم، وحدثٌ يصل
    /// برقمٍ محلّيٍّ قد يُشغَّل على أمرٍ **آخر** فيستهلك خاماتِ غيره.
    String? globalId,
  }) async {
    // Generate order number
    final count =
        await (selectOnly(manufacturingOrders)
              ..addColumns([manufacturingOrders.id.count()]))
            .map((row) => row.read(manufacturingOrders.id.count()))
            .getSingle();
    final orderNumber = 'MFG-${((count ?? 0) + 1).toString().padLeft(5, '0')}';

    return into(manufacturingOrders).insert(
      ManufacturingOrdersCompanion.insert(
        orderNumber: orderNumber,
        bomId: bomId,
        orderedQty: orderedQty,
        warehouseId: warehouseId,
        startDate: startDate,
        notes: Value(notes),
        globalId: Value(globalId ?? UuidV7.generate()), // v166
      ),
    );
  }

  /// Start production: deduct raw materials from inventory + journal entry
  /// Uses adjustStock() from InventoryDao for proper balance tracking
  /// GAP-1 FIX: Generates Dr WIP / Cr Raw Materials journal entry
  ///
  /// v146 (Feature 009 / T010b): the per-component deduction loop is now
  /// delegated to [consumeBomComponentsAtomic]. Behavior is preserved by
  /// passing `StockShortagePolicy.block` (matches the legacy
  /// "throw on insufficient stock" path) and re-wrapping the helper's
  /// [InsufficientStockException] back into `Exception(e.message)` so any
  /// existing UI that surfaces `e.toString()` sees identical text
  /// (Constitution I — Behavior Preservation).
  /// v166 — يُرسل حدثاً ماليّاً على أمرِ إنتاجٍ قائمٍ إلى الخادم.
  ///
  /// ⚠️ **بالهويّة لا بالرقم.** رقمُ الأمر على العميل يخالف رقمَه على
  /// الخادم بالتصميم، وحدثٌ يصل برقمٍ محلّيٍّ قد يُشغَّل على أمرٍ **آخر**
  /// فيستهلك خاماتِ غيره. والاستهلاكُ الخطأ لا يُعكَس بقيد.
  ///
  /// ويعيد `true` حين تولّى الخادمُ الحدثَ، فيمتنع النداءُ المحلّيّ.
  Future<bool> _pushMfgAction(int orderId, String action,
      [Map<String, dynamic> extra = const {}]) async {
    if (!SyncInterceptor.isClientMode) return false;
    final order = await (select(manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (order == null || order.globalId == null) {
      // أمرٌ بلا هويّةٍ لا يُدعى على الخادم. الفشلُ صريحٌ لا صامت: تمريرُه
      // يعني تنفيذاً محلّيّاً يُنتج التفاوتَ الذي نسدّه.
      throw StateError('أمرُ الإنتاج بلا معرّفٍ عالميّ — لا يمكن إرسالُه.');
    }
    await SyncInterceptor.instance?.submitManufacturingAction(<String, dynamic>{
      'orderGlobalId': order.globalId,
      'action': action,
      ...extra,
    });
    return true;
  }

  Future<void> startProduction(int orderId) async {
    if (await _pushMfgAction(orderId, 'start')) return;

    await transaction(() async {
      final order = await (select(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) throw Exception('أمر الإنتاج غير موجود');
      if (order.status != 'draft') {
        throw Exception('لا يمكن بدء أمر إنتاج غير مسودة');
      }

      final bom = await getBOM(order.bomId);
      if (bom == null) throw Exception('قائمة المكونات غير موجودة');

      final multiplier = order.orderedQty / bom.expectedQuantity;

      // GAP-2 FIX: Resolve branchId from warehouse for branch isolation
      final warehouse = await getWarehouseById(order.warehouseId);
      final resolvedBranchId = warehouse?.branchId;

      // Deduct raw materials via the shared helper (T010a). For manual
      // production we use `block` policy — historic behavior. The helper
      // performs the same wastage formula, the same stock check, the
      // same `adjustStock` call, and accumulates costs we sum below.
      final List<ConsumedLine> consumed;
      try {
        consumed = await consumeBomComponentsAtomic(
          bomId: order.bomId,
          multiplier: multiplier,
          warehouseId: order.warehouseId,
          branchId: resolvedBranchId,
          context: BomConsumptionContext(
            movementType: 'manufacturing_out',
            referenceType: 'manufacturing_order',
            referenceId: orderId,
            notes: 'صرف للإنتاج — أمر ${order.orderNumber}',
          ),
          shortagePolicy: StockShortagePolicy.block,
        );
      } on InsufficientStockException catch (e) {
        // Preserve the pre-009 startProduction error contract: re-throw as
        // `Exception(message)` so any caller that does `e.toString()` sees
        // "Exception: مخزون غير كافٍ: ..." identical to the legacy output.
        throw Exception(e.message);
      }

      final totalConsumedCost =
          consumed.fold<double>(0, (sum, c) => sum + c.lineCost);

      // Update order status
      await (update(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).write(
        const ManufacturingOrdersCompanion(status: Value('in_progress')),
      );

      // GAP-1 FIX: Generate Dr WIP / Cr Raw Materials journal entry
      if (totalConsumedCost > 0) {
        final wipCode = await accountingDao.getMappedAccountCode(
          'wip',
          AccountingDao.accountPurposes['wip']!,
        );
        final rawMatCode = await accountingDao.getMappedAccountCode(
          'raw_materials',
          AccountingDao.accountPurposes['raw_materials'] ?? AccountingDao.accountPurposes['inventory']!,
        );
        final wipAccount = await accountingDao.getAccountByCode(wipCode);
        final rawMatAccount = await accountingDao.getAccountByCode(rawMatCode);

        if (wipAccount != null && rawMatAccount != null) {
          await accountingDao.createJournalEntry(
            date: DateTime.now(),
            description:
                'صرف مواد خام للإنتاج — أمر ${order.orderNumber} بتكلفة ${totalConsumedCost.toStringAsFixed(AppConstants.decimalPlaces)}',
            lines: [
              JournalLine(
                accountId: wipAccount.id,
                debit: totalConsumedCost,
                credit: 0,
                description: 'إنتاج تحت التشغيل',
              ),
              JournalLine(
                accountId: rawMatAccount.id,
                debit: 0,
                credit: totalConsumedCost,
                description: 'مواد خام مستهلكة',
              ),
            ],
            referenceType: 'manufacturing_order',
            referenceId: orderId,
            isAutoPosted: true,
            branchId: resolvedBranchId,
            // Spec 146 (S-MFG-GL / FR-006): deterministic gid so a retried start
            // converges to one row instead of duplicating on sync.
            globalId: JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceManufacturing,
              sourceGid: 'order$orderId',
              verb: 'start',
            ),
          );
        }
      }
    });
  }

  /// Complete production: add finished product to inventory + journal entry
  /// Uses adjustStock() for proper inventory tracking
  Future<void> completeProduction(
    int orderId, {
    double? actualProducedQty,
    int? costCenterId,
  }) async {
    if (await _pushMfgAction(orderId, 'complete', <String, dynamic>{
      'actualProducedQty': actualProducedQty,
      'costCenterId': costCenterId,
    })) {
      return;
    }

    await transaction(() async {
      final order = await (select(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) throw Exception('أمر الإنتاج غير موجود');
      if (order.status != 'in_progress') {
        throw Exception('أمر الإنتاج ليس قيد التنفيذ');
      }

      final bom = await getBOM(order.bomId);
      if (bom == null) throw Exception('قائمة المكونات غير موجودة');

      final produced = actualProducedQty ?? order.orderedQty;

      // FIX: Calculate actual consumed cost from stock movements recorded during startProduction
      double totalMaterialCost = 0;
      final consumptionMovements = await customSelect(
        '''SELECT SUM(ABS(sm.quantity) * sm.unit_cost) as total_cost
           FROM stock_movements sm
           WHERE sm.reference_type = 'manufacturing_order'
             AND sm.reference_id = ?
             AND sm.movement_type = 'manufacturing_out' ''',
        variables: [Variable(orderId)],
        readsFrom: {stockMovements},
      ).getSingleOrNull();

      if (consumptionMovements != null) {
        totalMaterialCost = (consumptionMovements.data['total_cost'] as num?)?.toDouble() ?? 0.0;
      }

      // Fallback: if no movements found, calculate from BOM components.
      // ponytail: pre-existing fallback. Spec 146 note — when startProduction
      // recorded NO consumption (raws had costPrice 0 at start → no WIP debit)
      // but the raw gains a cost before completion, this recomputes materials
      // from the current BOM×costPrice and the completion JE then credits WIP for
      // materials it was never debited → net WIP ≠ 0 on that degenerate path
      // (SC-001 hole). Atypical; a proper fix belongs with a costing/WAC pass
      // that separates finished-goods valuation from the WIP-credit amount.
      if (totalMaterialCost <= 0) {
        final components = await getBOMComponents(order.bomId);
        final multiplier = order.orderedQty / bom.expectedQuantity;
        final costProductMap = await getProductsByIds(components.map((c) => c.rawMaterialId).toList());
        for (final comp in components) {
          final product = costProductMap[comp.rawMaterialId];
          if (product != null) {
            totalMaterialCost += product.costPrice * comp.quantity * comp.quantityInBase * multiplier;
          }
        }
      }

      // GAP-4 FIX: Aggregate MfgOrderCosts (labor, overhead, depreciation) into additionalCosts
      double aggregatedAdditionalCosts = 0;
      final orderCosts = await getMfgOrderCosts(orderId);
      for (final cost in orderCosts) {
        aggregatedAdditionalCosts += cost.amount;
      }
      // Sync back to order.additionalCosts if itemized costs exist
      if (aggregatedAdditionalCosts > 0 && aggregatedAdditionalCosts != order.additionalCosts) {
        await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
          ManufacturingOrdersCompanion(additionalCosts: Value(aggregatedAdditionalCosts)),
        );
      }
      final effectiveAdditionalCosts = aggregatedAdditionalCosts > 0 ? aggregatedAdditionalCosts : order.additionalCosts;

      final totalCost = totalMaterialCost + effectiveAdditionalCosts;
      final unitCost = produced > 0 ? totalCost / produced : 0.0;

      // GAP-2 FIX: Resolve branchId from warehouse for branch isolation
      final warehouse = await getWarehouseById(order.warehouseId);
      final resolvedBranchId = warehouse?.branchId;

      // Spec 151 B-01: blend WAC BEFORE bumping stock — mirrors the purchase
      // path (purchase_dao.dart). updateProductWAC reads products.current_stock
      // as the "before" quantity; adjustStock writes current_stock. Calling
      // adjustStock first made the WAC read include the just-produced qty, so
      // (0*0 + 10*50)/(10+10) = 25 instead of (0*0 + 10*50)/(0+10) = 50 —
      // the finished good's cost came out HALVED on production onto empty stock,
      // understating COGS on every later sale of it. WAC-first fixes the count.
      await updateProductWAC(
        productId: bom.finishedProductId,
        newQuantity: produced,
        newUnitCost: unitCost,
      );

      await adjustStock(
        productId: bom.finishedProductId,
        warehouseId: order.warehouseId,
        quantity: produced,
        type: 'manufacturing_in',
        referenceType: 'manufacturing_order',
        referenceId: orderId,
        notes: 'إنتاج أمر ${order.orderNumber}',
        branchId: resolvedBranchId,
        // Spec 151 B-02: thread the ACTUAL per-unit production cost
        // (totalCost / produced, computed above) so the per-warehouse
        // inventory_balances.average_cost and stock_movements.unit_cost for
        // the finished good record the real cost instead of falling back to
        // the stale products.costPrice inside adjustStock. Computed from the
        // production cost (not a post-adjust WAC read), so it stays correct
        // regardless of ordering.
        unitCost: unitCost,
      );

      // Update order
      await (update(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          status: const Value('completed'),
          producedQty: Value(produced),
          totalCost: Value(totalCost),
          endDate: Value(DateTime.now()),
        ),
      );

      // Spec 146 (S-MFG-GL / FR-001..FR-005): give the capitalised indirect cost
      // a credit party. `effectiveAdditionalCosts` is the exact amount folded into
      // `totalCost` beyond raw materials, so crediting it here (Dr WIP / Cr 5138)
      // makes the order's net WIP movement zero once the completion JE below
      // credits WIP for the full `totalCost`. Posted INSIDE this transaction (R3)
      // and BEFORE the completion entry. Skipped when there is no indirect cost.
      if (effectiveAdditionalCosts > 0) {
        final appliedCode = await accountingDao.getMappedAccountCode(
          'applied_overhead',
          AccountingDao.accountPurposes['applied_overhead']!,
        );
        final wipCodeOh = await accountingDao.getMappedAccountCode(
          'wip',
          AccountingDao.accountPurposes['wip']!,
        );
        final appliedAccount = await accountingDao.getAccountByCode(appliedCode);
        final wipAccountOh = await accountingDao.getAccountByCode(wipCodeOh);
        // FR-005: fail loud rather than silently drop the overhead credit — the
        // whole completion rolls back (nothing half-applied).
        if (appliedAccount == null || wipAccountOh == null) {
          throw Exception(
            'حساب «تحميل صناعي مطبّق» (5138) غير مُعرَّف في دليل الحسابات. '
            'استكمل إعداد الحسابات قبل إتمام أمر عليه تكاليف غير مباشرة.',
          );
        }
        await accountingDao.createJournalEntry(
          date: DateTime.now(),
          description:
              'تحميل تكاليف غير مباشرة — أمر ${order.orderNumber} بمبلغ ${effectiveAdditionalCosts.toStringAsFixed(AppConstants.decimalPlaces)}',
          lines: [
            JournalLine(
              accountId: wipAccountOh.id,
              debit: effectiveAdditionalCosts,
              credit: 0,
              description: 'تحميل صناعي على الإنتاج تحت التشغيل',
            ),
            JournalLine(
              accountId: appliedAccount.id,
              debit: 0,
              credit: effectiveAdditionalCosts,
              description: 'تحميل صناعي مطبّق',
            ),
          ],
          referenceType: 'manufacturing_overhead',
          referenceId: orderId,
          isAutoPosted: true,
          costCenterId: costCenterId,
          branchId: resolvedBranchId,
          globalId: JournalEntryGid.compute(
            sourceType: JournalEntryGid.sourceManufacturing,
            sourceGid: 'order$orderId',
            verb: 'overhead',
          ),
        );
      }

      // Dr: Inventory (finished goods added)
      // Cr: WIP (raw materials consumed — إنتاج تحت التشغيل)
      final inventoryCode = await accountingDao.getMappedAccountCode(
        'inventory',
        AccountingDao.accountPurposes['inventory']!,
      );
      final wipCode = await accountingDao.getMappedAccountCode(
        'wip',
        AccountingDao.accountPurposes['wip']!,
      );
      final inventoryAccount = await accountingDao.getAccountByCode(inventoryCode);
      final wipAccount = await accountingDao.getAccountByCode(wipCode);

      // Spec 146 (S-MFG-GL / FR-003, SC-001): the completion entry MUST credit
      // WIP for the full totalCost, else the order's net WIP movement never
      // reaches zero. Fail loud (symmetric with the overhead block above and its
      // FR-005 guard) instead of the old silent skip + credit-inventory fallback,
      // which on a partial COA could add finished stock + mark the order
      // completed while leaving WIP unbalanced.
      if (inventoryAccount == null || wipAccount == null) {
        throw Exception(
          'حساب مخزون البضاعة التامة ($inventoryCode) أو الإنتاج تحت التشغيل '
          '($wipCode) غير مُعرَّف في دليل الحسابات — تعذّر ترحيل قيد إتمام الإنتاج.',
        );
      }
      {
        await accountingDao.createJournalEntry(
          date: DateTime.now(),
          description:
              'إنتاج أمر رقم ${order.orderNumber} — تكلفة: ${totalCost.toStringAsFixed(AppConstants.decimalPlaces)}',
          lines: [
            JournalLine(
              accountId: inventoryAccount.id,
              debit: totalCost,
              credit: 0,
              description: 'مخزون إنتاج تام',
            ),
            JournalLine(
              accountId: wipAccount.id,
              debit: 0,
              credit: totalCost,
              description: 'إنتاج تحت التشغيل مكتمل',
            ),
          ],
          // Spec 146 (S-MFG-GL): DISTINCT referenceType from the start entry.
          // Both previously used 'manufacturing_order' + the same referenceId,
          // so createJournalEntry's (referenceType, referenceId) auto-post dedup
          // silently SWALLOWED this completion entry (Dr Finished-Inv / Cr WIP)
          // whenever a start entry existed — WIP never got its completion credit.
          // Distinct types let the dedup allow one start + one complete while
          // still blocking a double-posted completion.
          referenceType: 'manufacturing_complete',
          referenceId: orderId,
          isAutoPosted: true,
          costCenterId: costCenterId,
          branchId: resolvedBranchId,
          // FR-006: deterministic gid, distinct verb from start + overhead.
          globalId: JournalEntryGid.compute(
            sourceType: JournalEntryGid.sourceManufacturing,
            sourceGid: 'order$orderId',
            verb: 'complete',
          ),
        );
      }
    });
  }

  /// Reverse a manufacturing order (Spec 146 / S-MFG-GL, US2). Atomic (R3).
  ///
  /// By status:
  ///   • `draft`       → set status='cancelled' only. Nothing was consumed, so
  ///                     there is no stock or GL to unwind (FR-007).
  ///   • `in_progress` → restore each consumed raw material at its FROZEN
  ///                     consumed unit cost + post the reversing WIP entry
  ///                     (Dr Raw / Cr WIP) + set status='cancelled' (FR-008).
  ///   • `completed` / `cancelled` → rejected (FR-009). Reversing a completed
  ///                     order (which would also remove finished goods, unwind
  ///                     WAC, and reverse the overhead + completion entries) is
  ///                     out of scope for S-MFG-GL.
  ///
  /// `adjustStock` is stock-only (it posts no JE of its own — the WIP reversal
  /// below is the single GL entry), so there is no double-post. The whole
  /// operation is one transaction: a failure anywhere rolls back everything.
  Future<void> reverseManufacturingOrder(int orderId) async {
    if (await _pushMfgAction(orderId, 'reverse')) return;

    await transaction(() async {
      // Re-read status INSIDE the tx so a lost race with complete/reverse fails
      // on the guard rather than double-posting (TOCTOU hardening, cf. S-COST).
      final order = await (select(manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) throw Exception('أمر الإنتاج غير موجود');

      if (order.status == 'draft') {
        await (update(manufacturingOrders)..where((o) => o.id.equals(orderId)))
            .write(const ManufacturingOrdersCompanion(
                status: Value('cancelled')));
        return; // FR-007 — no stock, no GL
      }
      if (order.status != 'in_progress') {
        final statusAr = order.status == 'completed'
            ? 'مكتمل'
            : (order.status == 'cancelled' ? 'ملغى' : order.status);
        throw Exception('لا يمكن عكس أمر إنتاج حالته الحالية ($statusAr).');
      }

      // Resolve branch isolation the same way start/complete do.
      final warehouse = await getWarehouseById(order.warehouseId);
      final resolvedBranchId = warehouse?.branchId;

      // Restore each consumed raw material at its frozen consumed unit cost so
      // the reversal exactly offsets the start entry (FR-008). Reading the
      // movements also scopes the restore to what was actually consumed.
      final movements = await customSelect(
        '''SELECT product_id, warehouse_id, quantity, unit_cost
           FROM stock_movements
           WHERE reference_type = 'manufacturing_order'
             AND reference_id = ?
             AND movement_type = 'manufacturing_out' ''',
        variables: [Variable(orderId)],
        readsFrom: {stockMovements},
      ).get();

      double totalConsumedCost = 0;
      for (final m in movements) {
        final productId = m.read<int>('product_id');
        final whId = m.read<int>('warehouse_id');
        final movedQty = (m.data['quantity'] as num).toDouble();
        final unitCost = (m.data['unit_cost'] as num?)?.toDouble() ?? 0;
        final restoreQty = movedQty.abs();
        if (restoreQty <= 0) continue;
        await adjustStock(
          productId: productId,
          warehouseId: whId,
          quantity: restoreQty,
          type: 'manufacturing_reverse',
          referenceType: 'manufacturing_order',
          referenceId: orderId,
          unitCost: unitCost,
          notes: 'عكس أمر إنتاج — ${order.orderNumber}',
          branchId: resolvedBranchId,
        );
        totalConsumedCost += restoreQty * unitCost;
      }

      // Reverse the start WIP entry: Dr Raw / Cr WIP (mirror of startProduction).
      if (totalConsumedCost > 0) {
        final wipCode = await accountingDao.getMappedAccountCode(
          'wip',
          AccountingDao.accountPurposes['wip']!,
        );
        final rawMatCode = await accountingDao.getMappedAccountCode(
          'raw_materials',
          AccountingDao.accountPurposes['raw_materials'] ??
              AccountingDao.accountPurposes['inventory']!,
        );
        final wipAccount = await accountingDao.getAccountByCode(wipCode);
        final rawMatAccount = await accountingDao.getAccountByCode(rawMatCode);
        if (wipAccount != null && rawMatAccount != null) {
          await accountingDao.createJournalEntry(
            date: DateTime.now(),
            description:
                'عكس صرف مواد خام — أمر ${order.orderNumber} بتكلفة ${totalConsumedCost.toStringAsFixed(AppConstants.decimalPlaces)}',
            lines: [
              JournalLine(
                accountId: rawMatAccount.id,
                debit: totalConsumedCost,
                credit: 0,
                description: 'استرجاع مواد خام (عكس إنتاج)',
              ),
              JournalLine(
                accountId: wipAccount.id,
                debit: 0,
                credit: totalConsumedCost,
                description: 'عكس إنتاج تحت التشغيل',
              ),
            ],
            referenceType: 'manufacturing_reverse',
            referenceId: orderId,
            isAutoPosted: true,
            branchId: resolvedBranchId,
            globalId: JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceManufacturing,
              sourceGid: 'order$orderId',
              verb: 'revstart',
            ),
          );
        }
      }

      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId)))
          .write(const ManufacturingOrdersCompanion(status: Value('cancelled')));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MANUFACTURING ORDER COSTS — تفصيل تكاليف أمر التصنيع
  // ─────────────────────────────────────────────────────────────────────────

  /// Add cost to manufacturing order
  Future<int> addMfgOrderCost({
    required int orderId,
    required String costType,
    required String description,
    required double amount,
    int? expenseCategoryId,
    int? expenseId,
    String? globalId, // v166
  }) async {
    // v166 — التكلفةُ الإضافيّةُ تُرحَّل قيداً على الخادم (‏`manufacturing_
    // overhead`)، فالعميلُ يُرسلها ولا يكتبها: صفٌّ محلّيٌّ بلا قيدِه يجعل
    // تكلفةَ الأمر تخالف الأستاذ.
    final gid = globalId ?? UuidV7.generate();
    if (await _pushMfgAction(orderId, 'add_cost', <String, dynamic>{
      'globalId': gid,
      'costType': costType,
      'description': description,
      'amount': amount,
    })) {
      return 0;
    }

    return into(mfgOrderCosts).insert(MfgOrderCostsCompanion.insert(
        orderId: orderId,
        costType: costType,
        description: description,
        amount: amount,
        expenseCategoryId: Value(expenseCategoryId),
        expenseId: Value(expenseId),
      globalId: Value(gid), // v166
    ));
  }

  /// Get all costs for a manufacturing order
  Future<List<MfgOrderCostData>> getMfgOrderCosts(int orderId) =>
      (select(mfgOrderCosts)..where((c) => c.orderId.equals(orderId))).get();

  /// Watch costs for a manufacturing order
  Stream<List<MfgOrderCostData>> watchMfgOrderCosts(int orderId) =>
      (select(mfgOrderCosts)..where((c) => c.orderId.equals(orderId))).watch();

  /// Watch **every** order's cost rows in one stream.
  ///
  /// ⚠️ **لجدولٍ يعرض أوامرَ كثيرةً معاً** — تبويبُ «تحميل أوامر التصنيع» في
  /// شاشة المصروفات يعرض خامات/أجور/تحميل لكلّ أمر. و[watchMfgOrderCosts]
  /// تأخذ أمراً واحداً، فبناءُ الجدول منها يعني استعلاماً لكلّ صفّ (N+1) —
  /// وستّةُ أوامرَ تصير ستّةَ مجاري تُعاد كلَّما تغيّر أيٌّ منها.
  Stream<List<MfgOrderCostData>> watchAllMfgOrderCosts() =>
      select(mfgOrderCosts).watch();

  /// Get total cost breakdown for a manufacturing order by type
  Future<Map<String, double>> getMfgOrderCostBreakdown(int orderId) async {
    final results = await customSelect(
      '''
      SELECT cost_type, SUM(amount) as total
      FROM mfg_order_costs
      WHERE order_id = ?
      GROUP BY cost_type
      ''',
      variables: [Variable(orderId)],
      readsFrom: {mfgOrderCosts},
    ).get();

    final map = <String, double>{};
    for (final row in results) {
      map[row.data['cost_type'] as String] =
          (row.data['total'] as num?)?.toDouble() ?? 0.0;
    }
    return map;
  }

  /// Delete a cost entry from manufacturing order
  Future<int> deleteMfgOrderCost(int costId) =>
      (delete(mfgOrderCosts)..where((c) => c.id.equals(costId))).go();

  /// Delete an operational expense
  Future<int> deleteExpense(int expenseId) =>
      (delete(opExpenses)..where((e) => e.id.equals(expenseId))).go();

  /// Auto-allocate monthly fixed expenses to manufacturing orders
  /// Distributes fixed_monthly expenses equally across all active orders in the period
  Future<void> allocateMonthlyExpenses({
    required DateTime month,
  }) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    // Get active manufacturing orders in this month
    final activeOrders = await (select(manufacturingOrders)
          ..where((o) =>
              o.status.isIn(['draft', 'in_progress']) &
              o.startDate.isSmallerOrEqualValue(endOfMonth)))
        .get();

    if (activeOrders.isEmpty) return;

    // Get fixed_monthly production expenses for this month
    final fixedExpenses = await customSelect(
      '''
      SELECT e.id, e.category_id, e.amount, c.name
      FROM op_expenses e
      JOIN op_expense_categories c ON e.category_id = c.id
      WHERE c.allocation_method = 'fixed_monthly'
        AND c.is_production_related = 1
        AND e.expense_date BETWEEN ? AND ?
      ''',
      variables: [Variable(startOfMonth), Variable(endOfMonth)],
      readsFrom: {opExpenses, opExpenseCategories},
    ).get();

    // Distribute equally
    final perOrder = <int, double>{};
    for (final exp in fixedExpenses) {
      final amount = (exp.data['amount'] as num?)?.toDouble() ?? 0.0;
      final share = amount / activeOrders.length;
      for (final order in activeOrders) {
        perOrder[order.id] = (perOrder[order.id] ?? 0) + share;
      }
    }

    // Record allocation
    for (final entry in perOrder.entries) {
      await addMfgOrderCost(
        orderId: entry.key,
        costType: 'overhead',
        description: 'حصة مصروفات ثابتة شهرية (${activeOrders.length} أوامر)',
        amount: entry.value,
      );
    }
  }

  /// Helper: get account by code (manufacturing-scoped)
  Future<Account?> _mfgGetAccountByCode(String code) async {
    return (select(accounts)..where((a) => a.code.equals(code))..limit(1))
        .getSingleOrNull();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // v146 / Feature 009 (Auto-Deplete BOM on Sale) — shared consumption helper
  //
  // Extracted from the original startProduction loop (lines 276-305 pre-009)
  // so the same deduction + cost-accumulation path is reused by:
  //   • startProduction (rewired in T010b — passes shortagePolicy = block to
  //     preserve the legacy "throw on insufficient stock" behavior)
  //   • applyAutoDepleteForSale (T015 — passes the policy resolved by
  //     StockShortagePolicyService for the active terminal/branch/global tier)
  //
  // The helper itself is policy-aware and recursion-aware (recursion arrives
  // in T015). T010a adds the helper without rewiring callers — Constitution V
  // (Small Reversible Steps): if anything is wrong with the helper, T010a is
  // a no-op revert because the helper has no callers yet.
  // ─────────────────────────────────────────────────────────────────────────

  /// Consume BOM components atomically inside the caller's open Drift
  /// transaction. Per the contract in
  /// `specs/009-auto-deplete-bom/contracts/auto-deplete-flow.md` §2.
  ///
  /// Pre-conditions:
  ///   • A `transaction(...)` is currently open on this database.
  ///   • [bomId] refers to an existing, active BOM.
  ///   • [multiplier] = (sold or produced qty) / `bom.expectedQuantity`.
  ///   • [shortagePolicy] is resolved by the caller (block for manual
  ///     production; resolved via StockShortagePolicyService for sales).
  ///
  /// Throws:
  ///   • [InsufficientStockException] when [shortagePolicy] is `block` and
  ///     a raw material's currentStock is below the required qty.
  ///   • [BomCycleException] if [bomId] re-enters [visitedBomIds] or the
  ///     recursion [depth] exceeds 5 levels (FR-014).
  ///
  /// Returns the per-leaf consumed lines so the caller can build the COGS
  /// or WIP journal entry.
  Future<List<ConsumedLine>> consumeBomComponentsAtomic({
    required int bomId,
    required double multiplier,
    required int warehouseId,
    required int? branchId,
    required BomConsumptionContext context,
    required StockShortagePolicy shortagePolicy,
    Set<int>? visitedBomIds,
    int depth = 0,
  }) async {
    final visited = visitedBomIds ?? <int>{};
    if (depth > 5) {
      throw BomCycleException(
        visited.toList()..add(bomId),
        'BOM recursion depth exceeded (max 5)',
      );
    }
    if (visited.contains(bomId)) {
      throw BomCycleException(visited.toList()..add(bomId));
    }
    visited.add(bomId);

    final components = await getBOMComponents(bomId);
    if (components.isEmpty) {
      return const <ConsumedLine>[];
    }

    final componentProductMap = await getProductsByIds(
      components.map((c) => c.rawMaterialId).toList(),
    );
    final consumed = <ConsumedLine>[];

    for (final comp in components) {
      final product = componentProductMap[comp.rawMaterialId];
      if (product == null) {
        // Same wording the legacy startProduction loop used so any error UI
        // that string-matches keeps working (Constitution I).
        throw Exception('المنتج الخام غير موجود');
      }

      // UOM: quantity is in the BOM's selected unit; quantityInBase converts
      // to the product's base unit. Wastage adds a percent on top.
      var requiredQty = comp.quantity *
          comp.quantityInBase *
          multiplier *
          (1 + comp.wastagePercent / 100);

      if (product.currentStock < requiredQty) {
        switch (shortagePolicy) {
          case StockShortagePolicy.block:
            throw InsufficientStockException(
              'مخزون غير كافٍ: ${product.name} (متوفر: ${product.currentStock}, مطلوب: ${requiredQty.toStringAsFixed(2)})',
              shortages: {
                comp.rawMaterialId: (
                  required: requiredQty,
                  available: product.currentStock,
                  name: product.name,
                ),
              },
            );
          case StockShortagePolicy.allowNegative:
            // Proceed with full requiredQty; stock will go negative.
            break;
          case StockShortagePolicy.clampToZero:
            // Deduct only what's available; the unmet remainder is dropped
            // (asymmetric — the COGS leg under-represents real consumption,
            // an accepted trade-off documented in research.md R-4).
            requiredQty =
                product.currentStock > 0 ? product.currentStock : 0;
            if (requiredQty == 0) {
              continue; // skip entirely; nothing to deduct or record
            }
            break;
        }
      }

      await adjustStock(
        productId: comp.rawMaterialId,
        warehouseId: warehouseId,
        quantity: -requiredQty,
        type: context.movementType,
        referenceType: context.referenceType,
        referenceId: context.referenceId,
        notes: context.notes,
        branchId: branchId,
      );

      consumed.add(ConsumedLine(
        rawMaterialId: comp.rawMaterialId,
        qty: requiredQty,
        unitCost: product.costPrice,
        productName: product.name,
      ));
    }

    return consumed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // T015 — applyAutoDepleteForSale (Feature 009 / US1 MVP)
  //
  // Per contracts/auto-deplete-flow.md §1. MUST be called inside the
  // caller's open Drift transaction (the orchestrator's `_db.transaction`).
  //
  // Resolved decisions (recorded 2026-05-05):
  //   • Inventory account: SINGLETON resolution via
  //     `getMappedAccountCode('inventory') → '1136'`. Every CogsLine in
  //     the breakdown points to the same account today; T017 aggregates by
  //     accountId before emitting JE legs, so the JE shape is identical to
  //     the legacy single-account COGS path (Constitution I). The per-line
  //     structure is forward-compatible with future per-product accounts.
  //   • Idempotency: `sale_bom_consumptions.global_id` is derived
  //     deterministically from (saleGlobalId, rawMaterialId, seq) using
  //     UUIDv5 — see UuidV7.deriveConsumptionGlobalId. Retries hit the
  //     unique index and roll back the transaction (no insertOrIgnore).
  //   • Hybrid mode: `prefer_finished_stock` is rejected with
  //     InvalidPolicyException in this MVP — US4 (T036) layers the split.
  //     T022 defaults the BOM form dropdown to `always_auto_deplete` so
  //     this exception never fires in the normal flow.
  // ─────────────────────────────────────────────────────────────────────────
  Future<SaleAutoDepleteResult> applyAutoDepleteForSale({
    required int saleInvoiceId,
    required List<SaleLineRef> items,
    required int? branchId,
    required String shortagePolicy,
    required String saleGlobalId,
    // T021 — included in the diagnostic log line so per-terminal
    // forensics work in production. Caller is the right layer to
    // resolve it (orchestrator reads from PosTerminalRegistrationService
    // on the client side; server-side calls leave it null since the
    // server isn't a POS terminal itself).
    int? posTerminalId,
  }) async {
    // Map the string form (carried over the wire from settings) onto the
    // typed enum used by the shared consume helper. Unknown strings are a
    // configuration error worth surfacing loud.
    final StockShortagePolicy resolvedPolicy;
    switch (shortagePolicy) {
      case 'block':
        resolvedPolicy = StockShortagePolicy.block;
        break;
      case 'allow_negative':
        resolvedPolicy = StockShortagePolicy.allowNegative;
        break;
      case 'clamp_to_zero':
        resolvedPolicy = StockShortagePolicy.clampToZero;
        break;
      default:
        throw InvalidPolicyException(
          'سياسة نقص المخزون غير معروفة: $shortagePolicy',
        );
    }

    // Singleton inventory account resolution (see header comment).
    final inventoryCode = await accountingDao.getMappedAccountCode(
      'inventory',
      AccountingDao.accountPurposes['inventory']!,
    );
    final inventoryAccount =
        await accountingDao.getAccountByCode(inventoryCode);
    if (inventoryAccount == null) {
      throw const InvalidPolicyException(
        'حساب المخزون (1136) غير مُعرَّف فى دليل الحسابات. '
        'برجاء استكمال إعداد الحسابات قبل تفعيل خصم الخامات تلقائيًا.',
      );
    }

    final cogsBreakdown = <CogsLine>[];
    final coveredSaleItemIds = <int>{};

    for (final item in items) {
      // 1. Look up the active auto-deplete BOM for this finished product.
      //    Inactive BOMs are skipped silently (FR-004 guard already
      //    prevents the (active=false + auto=true) state from existing).
      final bom = await (select(billOfMaterials)
            ..where((b) =>
                b.finishedProductId.equals(item.productId) &
                b.autoDepleteOnSale.equals(true) &
                b.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();
      if (bom == null) {
        // Legacy single-account COGS path covers this line at the orchestrator
        // level — nothing to do here.
        continue;
      }

      // 2. Resolve the depletion split per BOM policy.
      //    - `always_auto_deplete` (legacy MVP): all qty deducts raw materials.
      //    - `prefer_finished_stock` (US4 / T036, RD-1 default): deduct from
      //      finished-product on-hand first, only the residual reaches the
      //      auto-deplete path. The orchestrator's earlier `adjustStock`
      //      already deducted the FULL `item.qty` from the finished
      //      product → we refund the over-deduction (`from_auto_deplete`)
      //      so the net change to finished stock equals `from_finished`.
      //    - Any other string is a configuration error.
      double fromAutoDeplete;
      switch (bom.depletionPolicy) {
        case 'always_auto_deplete':
          fromAutoDeplete = item.qty;
          break;
        case 'prefer_finished_stock':
          final product = await (select(products)
                ..where((p) => p.id.equals(item.productId))
                ..limit(1))
              .getSingleOrNull();
          if (product == null) {
            // Defensive — sales_invoice_items had a productId that no
            // longer exists. Fall through as if `always_auto_deplete`
            // so we don't silently leave raw materials un-deducted.
            fromAutoDeplete = item.qty;
            break;
          }
          // Legacy `adjustStock` already ran for `item.qty`. The CURRENT
          // value reflects the post-deduction state. Reverse the math
          // to find what was on-hand BEFORE the sale started.
          final preDeduction = product.currentStock + item.qty;
          final fromFinished = preDeduction <= 0
              ? 0.0
              : (item.qty < preDeduction ? item.qty : preDeduction);
          fromAutoDeplete = item.qty - fromFinished;
          // Refund the legacy over-deduction so net finished change
          // equals `from_finished`. Skip when fully covered by raws.
          if (fromAutoDeplete > 0 && fromFinished < item.qty) {
            await adjustStock(
              productId: item.productId,
              warehouseId: item.warehouseId,
              quantity: fromAutoDeplete,
              type: 'sale_finished_refund',
              referenceType: 'sale_invoice',
              referenceId: saleInvoiceId,
              branchId: branchId,
              notes:
                  'تعديل: المنتج التام كان كافٍ لـ${fromFinished.toStringAsFixed(3)} '
                  'فقط — الباقى يُخصم من الخامات (auto-deplete hybrid).',
            );
          }
          break;
        default:
          throw InvalidPolicyException(
            'سياسة "${bom.depletionPolicy}" غير معروفة. '
            'القيم المتاحة: always_auto_deplete | prefer_finished_stock.',
          );
      }

      // 3. Compute the multiplier and run the shared consume helper. The
      //    helper enforces depth + visited-cycle guards (FR-014) and applies
      //    the resolved shortage policy.
      if (fromAutoDeplete <= 0) continue;
      final multiplier = fromAutoDeplete / bom.expectedQuantity;

      // The helper adds `bom.id` to its own visited set on entry — pass an
      // empty set here so it doesn't immediately trip the cycle guard.
      final consumed = await consumeBomComponentsAtomic(
        bomId: bom.id,
        multiplier: multiplier,
        warehouseId: item.warehouseId,
        branchId: branchId,
        context: BomConsumptionContext(
          movementType: stockMovementSaleAutoDeplete,
          referenceType: 'sale_invoice',
          referenceId: saleInvoiceId,
          notes: 'خصم خامات تلقائي — فاتورة #$saleInvoiceId',
        ),
        shortagePolicy: resolvedPolicy,
        visitedBomIds: <int>{},
      );

      // 4. Persist one sale_bom_consumptions row per consumed leaf line.
      //    The deterministic globalId is critical for idempotency under
      //    fire-and-forget mirror-mode pushes (Feature 007 contract).
      var seq = 0;
      for (final line in consumed) {
        final consumptionGlobalId = UuidV7.deriveConsumptionGlobalId(
          saleGlobalId: saleGlobalId,
          rawMaterialId: line.rawMaterialId,
          sequenceIndex: seq,
        );
        await into(saleBomConsumptions).insert(
          SaleBomConsumptionsCompanion.insert(
            saleInvoiceId: saleInvoiceId,
            saleInvoiceItemId: item.saleItemId,
            bomId: bom.id,
            rawMaterialId: line.rawMaterialId,
            consumedQty: line.qty,
            unitCostAtSale: line.unitCost,
            warehouseId: item.warehouseId,
            branchId: Value(branchId),
            globalId: consumptionGlobalId,
          ),
        );
        cogsBreakdown.add(CogsLine(
          rawMaterialId: line.rawMaterialId,
          inventoryAccountId: inventoryAccount.id,
          totalCost: line.lineCost,
        ));
        // This invoice line's cost is now carried by the raw materials above,
        // so the JE factory must not also charge its own costPrice.
        coveredSaleItemIds.add(item.saleItemId);
        seq++;
      }
    }

    // T021 — single visible health signal in production. Only emit when
    // we actually deducted something so the log isn't spammed by every
    // sale of non-BOM products. Tag matches contracts/auto-deplete-flow.md §5.
    if (cogsBreakdown.isNotEmpty) {
      final totalCost = cogsBreakdown.fold<double>(
        0.0,
        (s, l) => s + l.totalCost,
      );
      final rawMaterialCount = cogsBreakdown
          .map((l) => l.rawMaterialId)
          .toSet()
          .length;
      // Use unawaited semantics — the log is best-effort and must never
      // hold up the enclosing transaction.
      DiagnosticLogger.log(
        'SALE-AUTODEPLETE',
        'inv=$saleInvoiceId items=${items.length} '
        'rawMaterials=$rawMaterialCount cost=${totalCost.toStringAsFixed(4)} '
        'branch=$branchId terminal=$posTerminalId',
      );
    }

    return SaleAutoDepleteResult(
      cogsBreakdown: cogsBreakdown,
      coveredSaleItemIds: coveredSaleItemIds,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // T030 — reverseSaleConsumption (Feature 009 / US3)
  //
  // Restores raw materials at the FROZEN unit_cost_at_sale (NOT current WAC)
  // when a sale is returned. Idempotent on `reversed_by_return_id IS NULL`
  // so a retried return is a no-op. Per-item return fractions handle the
  // common case where a partial return covers some items but not others.
  //
  // [itemReturnFractions] maps `sale_invoice_items.id` → fraction in [0, 1]
  // (returnedQty / originalQty). Items not in the map are NOT reversed.
  // Pass an empty map to get a no-op result.
  //
  // Contract: specs/009-auto-deplete-bom/contracts/auto-deplete-flow.md §3.
  // Cluster: Feature 021 / Issue 6.
  // ───────────────────────────────────────────────────────────────────────
  Future<SaleAutoDepleteResult> reverseSaleConsumption({
    required int saleInvoiceId,
    required int salesReturnId,
    required Map<int, double> itemReturnFractions,
  }) async {
    if (itemReturnFractions.isEmpty) {
      return const SaleAutoDepleteResult(cogsBreakdown: []);
    }

    // Step 1 — read the consumption rows that haven't been reversed yet.
    // Rows with `reversedByReturnId != null` are skipped (idempotent retry).
    // Filter to the sale-items the caller actually returned so unaffected
    // items keep their consumption rows untouched.
    final returnedItemIds = itemReturnFractions.keys.toList();
    final rows = await (select(saleBomConsumptions)
          ..where((c) =>
              c.saleInvoiceId.equals(saleInvoiceId) &
              c.saleInvoiceItemId.isIn(returnedItemIds) &
              c.reversedByReturnId.isNull()))
        .get();

    if (rows.isEmpty) {
      // Either a non-auto-deplete sale, a pre-009 sale, or a fully-reversed
      // sale on a retry. All three paths are no-ops by design — see spec.
      return const SaleAutoDepleteResult(cogsBreakdown: []);
    }

    // Step 2 — resolve the inventory account once per call (mirrors the
    // `applyAutoDepleteForSale` pattern). Every reverse-cogs leg points to
    // the same singleton inventory account today; the per-line structure
    // stays forward-compatible with future per-product accounts.
    final inventoryCode = await accountingDao.getMappedAccountCode(
      'inventory',
      AccountingDao.accountPurposes['inventory']!,
    );
    final inventoryAccount =
        await accountingDao.getAccountByCode(inventoryCode);
    if (inventoryAccount == null) {
      throw StateError(
          'Inventory account ($inventoryCode) not found — cannot '
          'reverse BOM consumption for sale=$saleInvoiceId.');
    }

    final cogsBreakdown = <CogsLine>[];

    for (final row in rows) {
      final fraction = itemReturnFractions[row.saleInvoiceItemId] ?? 0.0;
      if (fraction <= 0) continue;

      final restoreQty = row.consumedQty * fraction;
      if (restoreQty <= 0) continue;

      // Step 3 — restore stock with a positive adjustment. Type marker is
      // 'sale_auto_deplete_return' so reports can isolate reversal flow.
      // referenceId points to the return invoice; referenceType to
      // 'sales_return' for parity with the rest of the returns flow.
      await adjustStock(
        productId: row.rawMaterialId,
        warehouseId: row.warehouseId,
        quantity: restoreQty,
        type: stockMovementSaleAutoDepleteReturn,
        referenceType: 'sales_return',
        referenceId: salesReturnId,
        unitCost: row.unitCostAtSale,
        notes: 'إرجاع تلقائي: مرتجع رقم $salesReturnId',
      );

      cogsBreakdown.add(CogsLine(
        rawMaterialId: row.rawMaterialId,
        inventoryAccountId: inventoryAccount.id,
        totalCost: restoreQty * row.unitCostAtSale,
      ));

      // Step 4 — only mark rows as fully reversed when the whole quantity
      // for this item came back. Partial item returns leave the marker
      // NULL so a later return of the rest can still scale against the
      // full original qty. Tolerates float rounding around 1.0.
      final isItemFullyReturned = fraction >= 0.999;
      if (isItemFullyReturned) {
        await (update(saleBomConsumptions)
              ..where((c) => c.id.equals(row.id)))
            .write(SaleBomConsumptionsCompanion(
          reversedByReturnId: Value(salesReturnId),
        ));
      }
    }

    if (cogsBreakdown.isNotEmpty) {
      final totalCost = cogsBreakdown.fold<double>(
        0.0,
        (s, l) => s + l.totalCost,
      );
      DiagnosticLogger.log(
        'SALE-AUTODEPLETE-RETURN',
        'sale=$saleInvoiceId return=$salesReturnId '
        'items=${itemReturnFractions.length} '
        'rawMaterials=${cogsBreakdown.length} '
        'cost=${totalCost.toStringAsFixed(4)}',
      );
    }

    return SaleAutoDepleteResult(cogsBreakdown: cogsBreakdown);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // T039 — Consumption report (Feature 009 / US5)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Aggregates `sale_bom_consumptions` joined with `products` (raw material
  // name) and optionally with `shifts` (so per-terminal filtering works
  // without storing posTerminalId on every consumption row). Returned rows
  // are pre-aggregated so the screen can display them as-is.
  //
  // Branch + terminal filters are nullable; null = no filter on that
  // dimension. Date range is always applied (the screen forces a default
  // of "today" so reports don't accidentally scan years of data).
  Future<List<ConsumptionReportRow>> getConsumptionReport({
    required DateTime fromDate,
    required DateTime toDate,
    int? branchId,
    int? terminalId,
    Set<int>? allowedBranchIds,
  }) async {
    // Build dynamic where clauses to avoid joining `shifts` unless we
    // have to (terminal filter) — keeps the common case cheap.
    final where = <String>[
      "c.created_at >= ?",
      "c.created_at < ?",
    ];
    final args = <Variable>[
      Variable<DateTime>(fromDate),
      Variable<DateTime>(toDate),
    ];
    if (branchId != null) {
      where.add("c.branch_id = ?");
      args.add(Variable<int>(branchId));
    }
    // Spec 151 Track-3: authoritative branch-scope cap. `branchId` above is the
    // USER-CHOSEN dropdown value (null = "all branches"); this cap is the AUTH
    // ceiling the user cannot widen. null = full access, {} = fail-closed,
    // {ids} = those branches OR NULL-branch (legacy/shared) rows stay visible.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        where.add("1 = 0");
      } else {
        final placeholders = allowedBranchIds.map((_) => '?').join(', ');
        where.add("(c.branch_id IN ($placeholders) OR c.branch_id IS NULL)");
        args.addAll(allowedBranchIds.map((id) => Variable<int>(id)));
      }
    }
    String terminalJoin = '';
    if (terminalId != null) {
      // sale_invoices has user_id, shifts have user_id + posTerminalId.
      // Join via the open shift at the time of sale (best-effort: take
      // the most recent shift for the user that owns the invoice).
      terminalJoin = '''
        INNER JOIN sales_invoices si ON si.id = c.sale_invoice_id
        INNER JOIN shifts sh ON sh.user_id = si.user_id
          AND sh.pos_terminal_id = ?
      ''';
      args.add(Variable<int>(terminalId));
    }
    final sql = '''
      SELECT
        c.raw_material_id AS raw_material_id,
        p.name           AS name,
        SUM(c.consumed_qty)                      AS total_qty,
        SUM(c.consumed_qty * c.unit_cost_at_sale) AS total_cost,
        COUNT(DISTINCT c.sale_invoice_id)        AS invoice_count
      FROM sale_bom_consumptions c
      INNER JOIN products p ON p.id = c.raw_material_id
      $terminalJoin
      WHERE c.reversed_by_return_id IS NULL
        AND ${where.join(' AND ')}
      GROUP BY c.raw_material_id, p.name
      ORDER BY total_cost DESC
    ''';
    final rows = await customSelect(
      sql,
      variables: args,
      readsFrom: {saleBomConsumptions, products},
    ).get();
    return rows.map((r) => ConsumptionReportRow(
          rawMaterialId: r.read<int>('raw_material_id'),
          name: r.read<String>('name'),
          totalQty: r.read<double>('total_qty'),
          totalCost: r.read<double>('total_cost'),
          invoiceCount: r.read<int>('invoice_count'),
        )).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // T040 — Product profitability report (Feature 009 / US5)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // For each finished product whose sales involved auto-deplete BOMs in
  // the range, compute (revenue − raw-material-cost). Rows where the
  // product has zero auto-deplete sales are omitted (they're already
  // covered by the legacy sales-cost report).
  Future<List<ProfitabilityReportRow>> getProductProfitabilityReport({
    required DateTime fromDate,
    required DateTime toDate,
    int? productId,
    Set<int>? allowedBranchIds,
  }) async {
    final where = <String>[
      "si.invoice_date >= ?",
      "si.invoice_date < ?",
      "si.is_deleted = 0",
    ];
    final args = <Variable>[
      Variable<DateTime>(fromDate),
      Variable<DateTime>(toDate),
    ];
    if (productId != null) {
      where.add("sii.product_id = ?");
      args.add(Variable<int>(productId));
    }
    // Spec 151 Track-3: authoritative branch-scope cap on the sales invoice
    // (this "product profitability" tab previously had NO branch dimension at
    // all, so it leaked every branch unconditionally). null = full access,
    // {} = fail-closed, {ids} = those branches OR NULL-branch rows stay visible.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        where.add("1 = 0");
      } else {
        final placeholders = allowedBranchIds.map((_) => '?').join(', ');
        where.add("(si.branch_id IN ($placeholders) OR si.branch_id IS NULL)");
        args.addAll(allowedBranchIds.map((id) => Variable<int>(id)));
      }
    }
    final sql = '''
      SELECT
        sii.product_id                                     AS product_id,
        p.name                                             AS name,
        SUM(sii.quantity)                                  AS qty_sold,
        SUM(sii.quantity * sii.unit_price)                 AS revenue,
        COALESCE(SUM(c.consumed_qty * c.unit_cost_at_sale), 0) AS raw_cost,
        COUNT(DISTINCT sii.invoice_id)                     AS invoice_count
      FROM sales_invoice_items sii
      INNER JOIN sales_invoices si ON si.id = sii.invoice_id
      INNER JOIN products p ON p.id = sii.product_id
      LEFT JOIN sale_bom_consumptions c
        ON c.sale_invoice_item_id = sii.id
        AND c.reversed_by_return_id IS NULL
      WHERE ${where.join(' AND ')}
      GROUP BY sii.product_id, p.name
      HAVING SUM(c.consumed_qty) IS NOT NULL
      ORDER BY (SUM(sii.quantity * sii.unit_price)
              - COALESCE(SUM(c.consumed_qty * c.unit_cost_at_sale), 0)) DESC
    ''';
    final rows = await customSelect(
      sql,
      variables: args,
      readsFrom: {salesInvoiceItems, salesInvoices, products, saleBomConsumptions},
    ).get();
    return rows.map((r) {
      final revenue = r.read<double>('revenue');
      final rawCost = r.read<double>('raw_cost');
      return ProfitabilityReportRow(
        productId: r.read<int>('product_id'),
        name: r.read<String>('name'),
        qtySold: r.read<double>('qty_sold'),
        revenue: revenue,
        rawCost: rawCost,
        margin: revenue - rawCost,
        invoiceCount: r.read<int>('invoice_count'),
      );
    }).toList();
  }
}

/// Aggregated row returned by `getConsumptionReport`. Each instance
/// represents one raw material totalled over the report range.
class ConsumptionReportRow {
  final int rawMaterialId;
  final String name;
  final double totalQty;
  final double totalCost;
  final int invoiceCount;

  const ConsumptionReportRow({
    required this.rawMaterialId,
    required this.name,
    required this.totalQty,
    required this.totalCost,
    required this.invoiceCount,
  });
}

/// Aggregated row returned by `getProductProfitabilityReport`.
class ProfitabilityReportRow {
  final int productId;
  final String name;
  final double qtySold;
  final double revenue;
  final double rawCost;
  final double margin;
  final int invoiceCount;

  const ProfitabilityReportRow({
    required this.productId,
    required this.name,
    required this.qtySold,
    required this.revenue,
    required this.rawCost,
    required this.margin,
    required this.invoiceCount,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// v146 / Feature 009 — internal value types for the consume helper
// ─────────────────────────────────────────────────────────────────────────

/// Internal context bundle for one BOM consumption operation.
/// Captures the stock-movement metadata so the helper can write
/// rows that the caller will later trace to its source (a manufacturing
/// order or a sales invoice).
class BomConsumptionContext {
  /// Movement type written to `stock_movements.movement_type`. Use the
  /// constants in [stockMovementSaleAutoDeplete] /
  /// [stockMovementSaleAutoDepleteReturn] / `'manufacturing_out'`.
  final String movementType;

  /// Reference type written to `stock_movements.reference_type` —
  /// `'manufacturing_order'` or `'sale_invoice'`.
  final String referenceType;

  /// Reference id (the manufacturing order id or the sales invoice id).
  final int referenceId;

  /// Free-text notes saved on each generated stock_movement row.
  final String? notes;

  const BomConsumptionContext({
    required this.movementType,
    required this.referenceType,
    required this.referenceId,
    this.notes,
  });
}

/// One leaf-level raw-material line consumed by `consumeBomComponentsAtomic`.
/// Returned to the caller so it can build a journal-entry breakdown
/// (per-raw-material COGS legs in the sale path; aggregated WIP/Raw-Materials
/// JE in the manufacturing path).
class ConsumedLine {
  final int rawMaterialId;
  final double qty;
  final double unitCost;
  final String productName;

  const ConsumedLine({
    required this.rawMaterialId,
    required this.qty,
    required this.unitCost,
    required this.productName,
  });

  /// Convenience — the line's contribution to total cost.
  double get lineCost => qty * unitCost;
}

// ─────────────────────────────────────────────────────────────────────────
// Feature 009 — public data carriers for `applyAutoDepleteForSale`
//
// Per contracts/auto-deplete-flow.md §1 + tasks.md T016. The classes are
// declared here (rather than waiting for T016) so the T013 test file can
// reference them without compile errors; T016 is then a verification step
// rather than a creation step.
// ─────────────────────────────────────────────────────────────────────────

/// Reference to one persisted `sales_invoice_items` row that the orchestrator
/// is asking the auto-deplete pass to evaluate. The orchestrator builds the
/// list **after** invoice insertion so `saleItemId` is the real DB id.
class SaleLineRef {
  final int saleItemId;
  final int productId;
  final double qty;
  final int warehouseId;

  const SaleLineRef({
    required this.saleItemId,
    required this.productId,
    required this.qty,
    required this.warehouseId,
  });
}

/// One per-raw-material COGS leg the caller passes to
/// `AccountingService.generateSalesAccountingEntry` (T017). The accounting
/// service splits the COGS journal-entry leg by inventory account when this
/// list is non-null; when it is null, the legacy single-account path runs
/// unchanged (Constitution I).
class CogsLine {
  final int rawMaterialId;
  final int inventoryAccountId;
  final double totalCost;

  const CogsLine({
    required this.rawMaterialId,
    required this.inventoryAccountId,
    required this.totalCost,
  });
}

/// Return value of `applyAutoDepleteForSale`. The caller uses
/// [cogsBreakdown] to build the per-raw-material COGS leg of the sale JE.
/// Empty list means no item on the invoice triggered an auto-deplete BOM
/// (legacy single-account COGS path).
class SaleAutoDepleteResult {
  final List<CogsLine> cogsBreakdown;

  /// `sales_invoice_items.id` whose cost is now represented by
  /// [cogsBreakdown] because raw materials were consumed on their behalf.
  ///
  /// The JE factory must skip these lines when summing `item.costPrice`,
  /// otherwise a finished item that DOES carry a book cost gets charged
  /// twice — once as the finished good and again as its raw materials.
  /// Empty for a sale with no auto-deplete BOM, which keeps the legacy
  /// single-account path byte-identical (Constitution I).
  final Set<int> coveredSaleItemIds;

  const SaleAutoDepleteResult({
    required this.cogsBreakdown,
    this.coveredSaleItemIds = const <int>{},
  });

  /// Convenience — total COGS across all raw-material lines.
  /// SAL-5 (spec 149 B15): retained — not dead (asserted by
  /// test/unit/auto_deplete_for_sale_test.dart). cogsBreakdown itself is
  /// load-bearing (per-material COGS legs); the audit's "dead cogsBreakdown"
  /// premise did not reproduce.
  double get totalCost =>
      cogsBreakdown.fold(0.0, (sum, line) => sum + line.totalCost);
}
