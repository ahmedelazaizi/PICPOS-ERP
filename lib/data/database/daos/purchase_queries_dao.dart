// Purchase invoice reads: posted-ids, watchers, paged/date-range/supplier lookups, invoice + items by id.
part of '../database.dart';

extension PurchaseQueriesDao on AppDatabase {
  /// من بين [invoiceIds]، ما له **قيدٌ مشترياتٍ مُرحَّلٌ فعلاً** في الأستاذ.
  ///
  /// ⚠️ **ولماذا لا `isLocked`:** الرايةُ تكذب في ثلاث حالات.
  /// `createPurchaseInvoice` يرحّل قيدَه مُدمَجاً و**لا يرفعها قطّ** (راجع
  /// `_voidPurchaseInvoice` حيث وُثّق ذلك)، و`autoPostPurchase` يرفعها،
  /// **والإلغاءُ يرفعها أيضاً**. فعمودٌ مبنيٌّ عليها يكتب «مسودة» على
  /// فاتورةٍ قيدُها في الأستاذ، و«معتمد» على ملغاة. وتعليقان في هذا
  /// الملفّ نفسِه يتناقضان في وصفها.
  ///
  /// فالمقروءُ هنا الأستاذُ نفسُه بـ[kPurchaseJeReferenceTypes] — عينُ ما
  /// يقرؤه مسارا العكس عند التعديل والإلغاء.
  ///
  /// ⚙️ ويُزاد `isPosted` على مُرشِّحَي العكس: أولئك يسألان «هل ثمّة
  /// ما يُحذف؟» وهذا يسأل «هل هو في الأستاذ الآن؟» — وقيدٌ مُنزَلُ
  /// الترحيل موجودٌ وغيرُ مُرحَّل. والعمودُ الافتراضيُّ `true`،
  /// فلا يُسقِط هذا شيئاً في المسار المعتاد.
  ///
  /// و[invoiceIds] فارغةٌ ⇒ مجموعةٌ فارغةٌ بلا استعلام.
  Future<Set<int>> postedPurchaseInvoiceIds(List<int> invoiceIds) async {
    if (invoiceIds.isEmpty) return <int>{};
    final rows = await (selectOnly(journalEntries, distinct: true)
          ..addColumns([journalEntries.referenceId])
          ..where(journalEntries.referenceType
                  .isIn(kPurchaseJeReferenceTypes.toList()) &
              journalEntries.referenceId.isIn(invoiceIds) &
              journalEntries.isAutoPosted.equals(true) &
              journalEntries.isPosted.equals(true)))
        .get();
    return {for (final r in rows) ?r.read(journalEntries.referenceId)};
  }
  // ═══════════════════════════════════════════════════════════════════════
  // PURCHASE INVOICE CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all purchase invoices.
  /// PIR P1-05: Default LIMIT=500 to prevent loading thousands of rows.
  Stream<List<PurchaseInvoiceData>> watchAllPurchases({
    List<int>? warehouseIds,
    int limit = 500,
    int offset = 0,
  }) {
    final query = select(purchaseInvoices)
      ..where((p) => p.isDeleted.equals(false))
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
      ..limit(limit, offset: offset);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((p) => p.warehouseId.isIn(warehouseIds));
    }
    return query.watch();
  }

  /// Paginated fetch of purchase invoices (non-streaming version).
  Future<List<PurchaseInvoiceData>> getPurchaseInvoicesPaged({
    List<int>? warehouseIds,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) {
    final query = select(purchaseInvoices)
      ..where((p) => p.isDeleted.equals(false))
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
      ..limit(limit, offset: offset);
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((p) => p.warehouseId.isIn(warehouseIds));
    }
    return query.get();
  }

  /// Alias for watchAllPurchases for legacy compatibility
  Stream<List<PurchaseInvoiceData>> watchPurchaseInvoices({List<int>? warehouseIds}) =>
      watchAllPurchases(warehouseIds: warehouseIds);

  /// Watch purchase invoices with supplier name (for display in lists)
  /// When [warehouseIds] is provided and non-empty, only invoices belonging
  /// to those warehouses are returned (branch-level data isolation).
  Stream<List<PurchaseInvoiceWithSupplier>> watchPurchasesWithSupplier({List<int>? warehouseIds}) {
    final query = select(purchaseInvoices).join([
      leftOuterJoin(parties, parties.id.equalsExp(purchaseInvoices.supplierId)),
    ]);
    query.where(purchaseInvoices.isDeleted.equals(false));
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where(purchaseInvoices.warehouseId.isIn(warehouseIds));
    }
    query.orderBy([OrderingTerm.desc(purchaseInvoices.createdAt)]);

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseInvoiceWithSupplier(
          invoice: row.readTable(purchaseInvoices),
          supplierName: row.readTableOrNull(parties)?.name,
        );
      }).toList(),
    );
  }

  /// Alias for watchAllPurchases
  Stream<List<PurchaseInvoiceData>> watchAllAllPurchases({List<int>? warehouseIds}) =>
      watchAllPurchases(warehouseIds: warehouseIds);

  /// Get purchases for a date range.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets. Callers that need all rows can pass a large limit.
  /// البند 7 (متطلبات العميل 2026-07-25) — [supplierId] و[productId]
  /// و[invoiceNumberLike] تُنفَّذ في SQL عمداً.
  ///
  /// The purchase-returns screen used to filter the invoice number with an
  /// in-memory `contains()` over whatever this method had already truncated to
  /// `limit` rows. That made "search for invoice X" fail SILENTLY whenever X
  /// fell outside the newest 500 invoices of the range: the operator saw "no
  /// results" for an invoice that exists. Pushing the predicate down here is
  /// the fix — adding more in-memory filters on top of a truncated page would
  /// not have been.
  ///
  /// [invoiceNumberLike] matches BOTH `invoice_number` and
  /// `supplier_invoice_number`: the operator thinks of «رقم الفاتورة» as the
  /// number the supplier printed, not our internal one.
  ///
  /// [productId] matches invoices CONTAINING that item, via an EXISTS over
  /// `purchase_invoice_items` (index `idx_purchase_items_invoice` covers it).
  Future<List<PurchaseInvoiceData>> getPurchasesForDateRange(
    DateTime from,
    DateTime to, {
    int limit = 500,
    int offset = 0,
    Set<int>? allowedBranchIds,
    int? supplierId,
    int? productId,
    String? invoiceNumberLike,
  }) {
    // Normalize to full-day boundaries (same as getSalesByDateRange)
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    final query = select(purchaseInvoices)
      ..where((i) => i.invoiceDate.isBetween(Variable(start), Variable(end)) & i.isDeleted.equals(false));

    if (supplierId != null) {
      query.where((i) => i.supplierId.equals(supplierId));
    }

    final needle = invoiceNumberLike?.trim();
    if (needle != null && needle.isNotEmpty) {
      final pattern = '%${needle.toLowerCase()}%';
      query.where((i) =>
          i.invoiceNumber.lower().like(pattern) |
          i.supplierInvoiceNumber.lower().like(pattern));
    }

    if (productId != null) {
      query.where((i) => existsQuery(
            selectOnly(purchaseInvoiceItems)
              ..addColumns([purchaseInvoiceItems.id])
              ..where(purchaseInvoiceItems.invoiceId.equalsExp(i.id) &
                  purchaseInvoiceItems.productId.equals(productId)),
          ));
    }

    // Spec 151 Track-3: authoritative branch-scope cap (drives the purchase-
    // returns history report). Same contract as getSalesByDateRange: null =
    // full access, {} = fail-closed, {ids} = those branches OR NULL-branch rows.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where((i) => i.branchId.isIn(const <int>[]));
      } else {
        query.where((i) => i.branchId.isIn(allowedBranchIds) | i.branchId.isNull());
      }
    }

    return (query
          ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get a single purchase invoice by ID.
  /// PIR P0-02: Verifies integrityHash on locked invoices and logs any mismatch.
  Future<PurchaseInvoiceData?> getPurchaseInvoiceById(int id) async {
    final invoice = await (select(purchaseInvoices)
          ..where((i) => i.id.equals(id) & i.isDeleted.equals(false)))
        .getSingleOrNull();

    // P0-02: Integrity verification — only on locked (posted) invoices
    if (invoice != null && invoice.isLocked && invoice.integrityHash != null) {
      try {
        final isValid = InvoiceIntegrityService.verifyPurchaseInvoiceHash(
          storedHash: invoice.integrityHash!,
          invoiceNumber: invoice.invoiceNumber,
          invoiceDate: invoice.invoiceDate,
          total: invoice.total,
          subtotal: invoice.subtotal,
          discount: invoice.discount,
          tax: invoice.tax,
          paid: invoice.paid,
          supplierId: invoice.supplierId,
          paymentMethod: invoice.paymentMethod,
        );

        if (!isValid) {
          debugPrint(
            '[INTEGRITY] ⚠️ VIOLATION: Purchase invoice #${invoice.invoiceNumber} '
            '(id=$id) hash mismatch — possible tampering!',
          );
          await logFieldChange(
            entityType: 'purchase_invoice',
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
        debugPrint('[INTEGRITY] Verification error for purchase invoice $id: $e');
      }
    }

    return invoice;
  }

  /// Get purchases for a specific supplier by ID.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets.
  Future<List<PurchaseInvoiceData>> getPurchasesBySupplierId(
    int supplierId, {
    int limit = 500,
    int offset = 0,
  }) {
    return (select(purchaseInvoices)
          ..where((i) => i.supplierId.equals(supplierId) & i.isDeleted.equals(false))
          ..orderBy([(i) => OrderingTerm.desc(i.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Watch purchases for a date range
  Stream<List<PurchaseInvoiceData>> watchPurchaseInvoicesByDateRange(
    DateTime from,
    DateTime to,
  ) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    return (select(purchaseInvoices)
          ..where((i) => i.invoiceDate.isBetween(Variable(start), Variable(end)) & i.isDeleted.equals(false))
          ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate)]))
        .watch();
  }

  /// Alias for getPurchasesForDateRange
  Future<List<PurchaseInvoiceData>> getPurchasesReport(
    DateTime from,
    DateTime to,
  ) => getPurchasesForDateRange(from, to);

  /// Get purchase invoice items
  Future<List<PurchaseInvoiceItem>> getPurchaseInvoiceItems(int invoiceId) {
    return (select(
      purchaseInvoiceItems,
    )..where((tbl) => tbl.invoiceId.equals(invoiceId))).get();
  }
}
