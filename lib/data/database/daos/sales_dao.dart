// ═══════════════════════════════════════════════════════════════════════════
// SALES DAO - Sales Invoice and Related Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all sales-related database operations extracted from
// the main database.dart file for better organization and maintainability.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Sales-related database operations
extension SalesDao on AppDatabase {
  /// Watch all sales invoices ordered by creation date.
  /// PIR P1-05: Default LIMIT=500 to avoid loading thousands of rows into memory.
  /// [warehouseIds] filters by branch; [limit]/[offset] for pagination.
  ///
  /// Day-19: optional [from] / [to] constrain the stream to a date window
  /// (inclusive, matched against `invoice_date`). Pass either, both, or
  /// neither — unset bounds are treated as open-ended.
  Stream<List<SalesInvoiceData>> watchSalesInvoices({
    List<int>? warehouseIds,
    int limit = 500,
    int offset = 0,
    DateTime? from,
    DateTime? to,
  }) {
    // Same "saleType NULL is not a return" semantics as getSalesInvoicesPaged —
    // see the detailed rationale in that method's doc comment.
    final query = select(salesInvoices)
      ..where((i) => i.isDeleted.equals(false) &
          (i.saleType.equals('return').not() | i.saleType.isNull()))
      ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)])
      ..limit(limit, offset: offset);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    if (from != null) {
      query.where((i) => i.invoiceDate.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      // Include the full end day by using the start of the next day as the
      // exclusive upper bound, rather than requiring callers to add time math.
      final exclusiveTo = DateTime(to.year, to.month, to.day + 1);
      query.where((i) => i.invoiceDate.isSmallerThanValue(exclusiveTo));
    }
    return query.watch();
  }

  /// Paginated fetch of sales invoices (non-streaming version).
  ///
  /// ─────────────────────────────────────────────────────────────────────
  /// FILTER SEMANTICS (must match the returns-picker query):
  ///
  /// Include:  every row where `isDeleted = false` AND `saleType != 'return'`.
  /// Include:  rows where `saleType IS NULL` (treat as "not a return").
  ///
  /// ─────────────────────────────────────────────────────────────────────
  /// Why NULL handling matters:
  ///
  /// Previously the clause was `saleType != 'return'` which, under SQL's
  /// three-valued logic, evaluates to `NULL` (⇒ FALSE in WHERE) for rows
  /// whose `sale_type` column is NULL. The sales-returns picker in Dart
  /// uses `invoice.saleType == 'return'` which returns `false` for NULL,
  /// i.e. those rows ARE visible in the returns picker.
  ///
  /// The asymmetry caused the bug where invoices appeared in the
  /// "returns picker" but vanished from the main sales list on the server —
  /// the same data, interpreted differently by two queries.
  ///
  /// Fix: explicitly include NULL rows via `saleType IS NULL`.
  Future<List<SalesInvoiceData>> getSalesInvoicesPaged({
    List<int>? warehouseIds,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    final query = select(salesInvoices)
      ..where((i) => i.isDeleted.equals(false) &
          (i.saleType.equals('return').not() | i.saleType.isNull()))
      ..orderBy([(i) => OrderingTerm.desc(i.createdAt)])
      ..limit(limit, offset: offset);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    final rows = await query.get();

    // Diagnostic: if still empty, sample the raw table so operators see why.
    if (rows.isEmpty) {
      final sample = await (select(salesInvoices)..limit(20)).get();
      if (sample.isNotEmpty) {
        final saleTypeCounts = <String, int>{};
        int deleted = 0;
        for (final s in sample) {
          saleTypeCounts[s.saleType] = (saleTypeCounts[s.saleType] ?? 0) + 1;
          if (s.isDeleted) deleted++;
        }
        // Day-18: Gate diagnostic dump behind kDebugMode — release builds
        // must never leak internal filter state to the console/crash-log.
        if (kDebugMode) {
          debugPrint('[SalesDao] getSalesInvoicesPaged returned 0 rows. '
              'sample(${sample.length}) saleType distribution=$saleTypeCounts '
              'isDeleted=$deleted — first: num=${sample.first.invoiceNumber} '
              'saleType=${sample.first.saleType} status=${sample.first.status} '
              'isDeleted=${sample.first.isDeleted} '
              'warehouseId=${sample.first.warehouseId}');
        }
      }
    }
    return rows;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES INVOICE CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch today's sales
  /// When [warehouseIds] is provided and non-empty, only invoices belonging
  /// to those warehouses are returned (branch-level data isolation).
  Stream<List<SalesInvoiceData>> watchTodaySales({List<int>? warehouseIds}) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (i) => i.invoiceDate.isBetween(
          Variable(startOfDay),
          Variable(endOfDay),
        ) & i.isDeleted.equals(false) &
            (i.saleType.equals('return').not() | i.saleType.isNull()),
      )
      ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    return query.watch();
  }

  /// Get today's sales (non-streaming)
  /// When [warehouseIds] is provided and non-empty, only invoices belonging
  /// to those warehouses are returned (branch-level data isolation).
  Future<List<SalesInvoiceData>> getTodaySales({List<int>? warehouseIds}) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (i) => i.invoiceDate.isBetween(
          Variable(startOfDay),
          Variable(endOfDay),
        ) & i.isDeleted.equals(false) &
            (i.saleType.equals('return').not() | i.saleType.isNull()),
      )
      ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    return query.get();
  }

  /// Watch today's sales for a specific user (shift-scoped)
  Stream<List<SalesInvoiceData>> watchTodaySalesForUser(int userId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(salesInvoices)
          ..where(
            (i) =>
                i.invoiceDate.isBetween(
                  Variable(startOfDay),
                  Variable(endOfDay),
                ) &
                i.userId.equals(userId) &
                i.isDeleted.equals(false),
          )
          ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]))
        .watch();
  }

  /// Watch sales since [from] (open upper bound = "now").
  ///
  /// Spec 136 ISS-25 — shift-window scoping. Callers pass the active shift's
  /// `startTime` so a shift that crosses midnight keeps showing its
  /// pre-midnight sales — the calendar-day `watchTodaySales` dropped them at
  /// the 00:00 boundary. Mirrors `watchTodaySales`' predicate (non-deleted,
  /// excludes returns) with optional [userId] / [warehouseIds] scoping.
  Stream<List<SalesInvoiceData>> watchSalesSince(
    DateTime from, {
    int? userId,
    List<int>? warehouseIds,
  }) {
    final query = select(salesInvoices)
      ..where(
        (i) =>
            i.invoiceDate.isBiggerOrEqualValue(from) &
            i.isDeleted.equals(false) &
            (i.saleType.equals('return').not() | i.saleType.isNull()),
      )
      ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]);
    if (userId != null) {
      query.where((i) => i.userId.equals(userId));
    }
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    return query.watch();
  }

  /// Get today's sales for a specific user (shift-scoped, non-streaming)
  Future<List<SalesInvoiceData>> getTodaySalesForUser(int userId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(salesInvoices)
          ..where(
            (i) =>
                i.invoiceDate.isBetween(
                  Variable(startOfDay),
                  Variable(endOfDay),
                ) &
                i.userId.equals(userId) &
                i.isDeleted.equals(false),
          )
          ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]))
        .get();
  }

  /// Get sales for a date range.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets. Callers that need all rows (e.g. Excel export) can
  /// pass a very large limit explicitly.
  Future<List<SalesInvoiceData>> getSalesForDateRange(
    DateTime from,
    DateTime to, {
    int limit = 500,
    int offset = 0,
  }) {
    return (select(salesInvoices)
          ..where((i) => i.invoiceDate.isBetween(Variable(from), Variable(to)) & i.isDeleted.equals(false))
          ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get a single sales invoice by ID.
  /// PIR P0-02: Verifies integrityHash on locked invoices and logs any mismatch.
  Future<SalesInvoiceData?> getSalesInvoiceById(int id) async {
    final invoice = await (select(salesInvoices)
          ..where((i) => i.id.equals(id) & i.isDeleted.equals(false)))
        .getSingleOrNull();

    // P0-02: Integrity verification — only on locked (posted) invoices
    if (invoice != null && invoice.isLocked && invoice.integrityHash != null) {
      try {
        final isValid = InvoiceIntegrityService.verifySalesInvoiceHash(
          storedHash: invoice.integrityHash!,
          invoiceNumber: invoice.invoiceNumber,
          invoiceDate: invoice.invoiceDate,
          total: invoice.total,
          subtotal: invoice.subtotal,
          discount: invoice.discount,
          tax: invoice.tax,
          paid: invoice.paid,
          customerId: invoice.customerId,
          userId: invoice.userId,
          paymentMethod: invoice.paymentMethod,
        );

        if (!isValid) {
          debugPrint(
            '[INTEGRITY] ⚠️ VIOLATION: Sales invoice #${invoice.invoiceNumber} '
            '(id=$id) hash mismatch — possible tampering!',
          );
          // Log to field_audit_logs for auditor visibility
          await logFieldChange(
            entityType: 'sales_invoice',
            entityId: id,
            fieldName: 'INTEGRITY_VIOLATION',
            fieldKey: 'integrity_hash',
            oldValue: invoice.integrityHash,
            newValue: 'MISMATCH_DETECTED',
            changedBy: 0,
            changedByName: 'SYSTEM',
            changeReason: 'Integrity hash mismatch detected on read — possible data tampering',
            transactionId: 'integrity-check-${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      } catch (e) {
        debugPrint('[INTEGRITY] Verification error for invoice $id: $e');
      }
    }

    return invoice;
  }

  /// Update sales invoice status
  Future<void> updateSalesInvoiceStatus(int invoiceId, String status) async {
    await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
      SalesInvoicesCompanion(status: Value(status)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELD ORDERS — See sales_held_orders_dao.dart
  // ═══════════════════════════════════════════════════════════════════════


  /// Get sales by date range with optional user filter (Phase 9.2)
  Future<List<SalesInvoiceData>> getSalesByDateRange(
    DateTime startDate,
    DateTime endDate, {
    int? userId,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (s) => s.invoiceDate.isBetween(Variable(start), Variable(end)) &
               s.isDeleted.equals(false),
      );

    if (userId != null) {
      query.where((s) => s.userId.equals(userId));
    }

    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((s) => s.warehouseId.isIn(warehouseIds));
    }

    // Spec 149 B12-4 (FIL-2): auth-level branch scope, mirrors B12-1's
    // _buildAuthScopeFilter contract (null = full access, {} = fail-closed,
    // {ids} = branch OR NULL-branch rows stay visible).
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where((s) => s.branchId.isIn(const <int>[]));
      } else {
        query.where((s) => s.branchId.isIn(allowedBranchIds) | s.branchId.isNull());
      }
    }

    if (costCenterId != null) {
      final ccIds = await _resolveCostCenterIds(costCenterId);
      if (ccIds.isNotEmpty) {
        query.where((s) => s.costCenterId.isIn(ccIds));
      } else {
        query.where((s) => s.costCenterId.equals(costCenterId));
      }
    }

    query.orderBy([(s) => OrderingTerm.desc(s.createdAt)]);

    return query.get();
  }

  /// Get sales return invoices by date range.
  ///
  /// Spec 002 (Round 2): only returns *return invoices* — rows created by
  /// the return flow (`saleType='return'`) or with negative totals (legacy
  /// quick-return shape). The previous query also pulled in *original*
  /// invoices that had been returned (status='returned' / 'partial_return'),
  /// which produced a confusing "Sales Returns History" listing the
  /// originals alongside the returns. Originals are still discoverable from
  /// the main invoices list where the status badge is the relevant signal.
  ///
  /// Note: this also makes client and server behave identically. Before
  /// B2-T1 the server kept originals at status='completed' so the bug was
  /// invisible there; after B2-T1 the server flips status too, which would
  /// have surfaced the same client-side confusion server-side.
  Future<List<SalesInvoiceData>> getSalesReturns(
    DateTime startDate,
    DateTime endDate, {
    int limit = 500,
    int offset = 0,
    Set<int>? allowedBranchIds,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (s) => s.invoiceDate.isBetween(Variable(start), Variable(end)) &
               s.isDeleted.equals(false) &
               (s.saleType.equals('return') |
                s.total.isSmallerThanValue(0)),
      );

    // Spec 151 Track-3: authoritative branch-scope cap for the sales-returns
    // HISTORY LIST (the returns report screen filtered by warehouse on the UI
    // only, so a branch-restricted user with no warehouse chosen saw every
    // branch's returns). Same contract as getSalesByDateRange: null = full
    // access (no cap), {} = fail-closed, {ids} = those branches OR NULL-branch
    // (shared/head-office) rows stay visible.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where((s) => s.branchId.isIn(const <int>[]));
      } else {
        query.where((s) => s.branchId.isIn(allowedBranchIds) | s.branchId.isNull());
      }
    }

    query
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  /// Helper to resolve cost center and its children (copied/shared from SalesAnalyticsDao pattern)
  /// Note: Ideally this would be a shared mixin or base class method.
  Future<List<int>> _resolveCostCenterIds(int? costCenterId) async {
    if (costCenterId == null) return [];
    final ids = <int>[costCenterId];
    Future<void> addChildren(int parentId) async {
      final children = await (select(costCenters)
            ..where((c) => c.parentId.equals(parentId))
            ..where((c) => c.isActive.equals(true)))
          .get();
      for (final child in children) {
        ids.add(child.id);
        await addChildren(child.id);
      }
    }
    await addChildren(costCenterId);
    return ids;
  }

  /// Get sales invoice items
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) {
    return (select(
      salesInvoiceItems,
    )..where((i) => i.invoiceId.equals(invoiceId))).get();
  }

  /// Get next daily order number
  /// Order counter resets after daily closing or when reaching the configured limit
  Future<int> getNextDailyOrderNumber() async {
    // 1. Find the last shift opening to determine starting point
    // This implements Phase 5: Resetting order numbers per shift opening
    final lastShift =
        await (select(shifts)
              ..where((s) => s.status.equals('open'))
              ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
              ..limit(1))
            .getSingleOrNull();

    // If no open shift, fallback to the MOST RECENT shift regardless of status
    final latestShiftRecord =
        lastShift ??
        await (select(shifts)
              ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
              ..limit(1))
            .getSingleOrNull();

    DateTime startTime;
    if (latestShiftRecord != null) {
      startTime = latestShiftRecord.startTime;
    } else {
      // Emergency fallback to start of today if absolutely no shifts exist
      final today = DateTime.now();
      startTime = DateTime(today.year, today.month, today.day);
    }

    // 2. Count invoices since this shift started (PostgreSQL-compatible)
    final maxOrder = salesInvoices.orderNumber.max();
    final result = await (selectOnly(salesInvoices)
          ..addColumns([maxOrder])
          ..where(salesInvoices.createdAt.isBiggerOrEqualValue(startTime)))
        .map((row) => row.read(maxOrder))
        .getSingle();

    int currentOrderNumber = result ?? 0;

    // 3. Check limit (default 100, can be overridden via settings)
    const int defaultLimit = 100;
    int orderLimit = defaultLimit;
    try {
      final limitSetting = await (select(
        settings,
      )..where((s) => s.key.equals('order_counter_limit'))).getSingleOrNull();
      if (limitSetting != null) {
        orderLimit = int.tryParse(limitSetting.value ?? '') ?? defaultLimit;
      }
    } catch (_) {
      // settings table may not exist yet, use default
    }

    // 4. Reset if at or above limit
    final nextNumber = currentOrderNumber >= orderLimit
        ? 1
        : currentOrderNumber + 1;
    return nextNumber;
  }

  /// Reset order counter (called from daily closing)
  Future<void> resetOrderCounter() async {
    // The counter auto-resets by looking at invoices after last closing
    // This method is a no-op since the logic is already in getNextDailyOrderNumber
    // but can be used to explicitly mark the closing point
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES INVOICE MUTATIONS → See sales_mutations_dao.dart
  // createSalesInvoice, legacyCreateSalesInvoice, insertSalesInvoiceWithoutStock,
  // updateSalesInvoice, updateSalesInvoicePayment, updateSalesInvoicePaidAmount,
  // deleteSalesInvoice, getSalesInvoiceItemsWithProduct, getAlreadyReturnedQty
  // ═══════════════════════════════════════════════════════════════════════

  /// Returns the total returned amount per original sales-invoice id.
  ///
  /// Two sources are queried because the standalone and server flows
  /// store the return differently:
  ///
  ///  • **`safe_transactions`** (`reference_type='sales_return'`,
  ///    `reference_id=<originalInvoiceId>`) — the standalone return flow
  ///    writes one row per cash/bank refund and an AR memo when the
  ///    return offsets a credit balance.
  ///
  ///  • **`sales_invoices`** (`sale_type='return'`,
  ///    `notes='Return for invoice #<originalInvoiceId>'`) — the server's
  ///    API handler `postSalesReturn` records the return as its own
  ///    invoice row but skips the safe-transaction insert, so this is
  ///    the only place where client-pushed returns are visible to the
  ///    rest of the system after a DeltaPull.
  ///
  /// The two sources are mutually exclusive per invoice (one path per
  /// origin) so summing both is safe and handles every persisted return
  /// regardless of where it was processed.
  ///
  /// Used by the sales-invoices list to subtract the refund from the
  /// row's "المتبقي" and to drive the "إجمالي المرتجعات" summary card.
  Future<Map<int, double>> getReturnedAmountsForInvoices(
    List<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return const {};
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    final invoiceIdVars = [
      for (final id in invoiceIds) Variable.withInt(id),
    ];

    final stRows = await customSelect(
      'SELECT reference_id, COALESCE(SUM(amount), 0) AS total '
      'FROM safe_transactions '
      "WHERE reference_type = 'sales_return' "
      'AND reference_id IN ($placeholders) '
      'GROUP BY reference_id',
      variables: invoiceIdVars,
      readsFrom: {safeTransactions},
    ).get();

    // Server-API return invoices link back to the original via the
    // `notes` text "Return for invoice #<id>" because the row has no
    // dedicated FK. Extract the trailing number with a SUBSTR after
    // the '#' marker; CAST to INTEGER discards any trailing whitespace
    // and ignores rows whose notes don't follow the pattern. Soft-
    // deleted rows are excluded so cancelled returns don't count.
    final invRows = await customSelect(
      "SELECT CAST(SUBSTR(notes, INSTR(notes, '#') + 1) AS INTEGER) AS orig_id, "
      'COALESCE(SUM(total), 0) AS total '
      'FROM sales_invoices '
      "WHERE sale_type = 'return' "
      "  AND notes LIKE 'Return for invoice #%' "
      '  AND is_deleted = 0 '
      "  AND CAST(SUBSTR(notes, INSTR(notes, '#') + 1) AS INTEGER) IN ($placeholders) "
      'GROUP BY orig_id',
      variables: invoiceIdVars,
      readsFrom: {salesInvoices},
    ).get();

    final out = <int, double>{};
    for (final row in stRows) {
      final id = row.data['reference_id'] as int;
      out[id] = (out[id] ?? 0.0) +
          ((row.data['total'] as num?)?.toDouble() ?? 0.0);
    }
    for (final row in invRows) {
      final id = row.data['orig_id'] as int?;
      if (id == null) continue;
      out[id] = (out[id] ?? 0.0) +
          ((row.data['total'] as num?)?.toDouble() ?? 0.0);
    }
    return out;
  }
}
