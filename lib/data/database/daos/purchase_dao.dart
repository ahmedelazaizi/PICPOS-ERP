// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE DAO - Purchase Invoice and Related Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all purchase-related database operations.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// إجمالياتُ فواتير المشتريات المطابِقةِ للمرشِّحات — **من SQL لا من الصفحة**.
///
/// ‏`watchAllPurchases` يسقّف بـ٥٠٠ صفّ (‏PIR P1-05)، فطيُّ الصفحة في Dart
/// يعطي رقماً أقلَّ من الحقيقة بلا ما يشي بذلك. وهذا هو نفسُ عطبِ «ح-2» الذي
/// عولج في جانب المبيعات بـ[SalesInvoiceSummary].
class PurchaseInvoiceSummary {
  /// عدد فواتير الشراء **المطابِقة** (لا المحمَّلة على الشاشة).
  final int invoiceCount;

  /// إجمالي المشتريات — شامل الضريبة، بعد الخصم، قبل المرتجعات.
  final double totalAmount;

  /// المدفوعُ للموردين من الفواتير نفسِها.
  ///
  /// ولا سنداتِ صرفٍ مضمومةً إليه — بخلاف «المحصّل» في المبيعات الذي يضمّ
  /// سنداتِ القبض: `PurchaseInvoicesScreenState` لا تحمل سنداتِ صرفٍ أصلاً،
  /// وضمُّها هنا وحدَها كان سيجعل البطاقةَ تخالف الصفوفَ تحتها.
  final double totalPaid;

  /// إجمالي مرتجعات المشتريات لفواتيرِ **هذه** النافذة والنطاق.
  final double totalReturns;

  /// عددُ الفواتير المسدَّدةِ بالكامل.
  ///
  /// ⚠️ والعدُّ على عمود `status` لا على `paid >= total` — بخلاف المبيعات.
  /// السببُ مقيسٌ لا مذوَّق: `_applyFilters` في
  /// `purchase_invoices_controller.dart` يرشِّح بـ`inv.status`، و`inv.status`
  /// يأتي من `InvoiceEntity._mapStatus` على العمود. فلو عُدَّ هنا بالمبلغ
  /// لأعطت الشريحةُ عدداً لا يطابق ما تُظهره حين تُنقَر — عدّادٌ يكذب على
  /// مرشِّحه.
  final int paidCount;

  /// عددُ الفواتير المسدَّدةِ جزئيّاً — `status = 'partial'`.
  final int partialCount;

  /// عددُ الفواتير غيرِ المسدَّدة.
  ///
  /// وهي **حالةُ الافتراض** في `_mapStatus` لا قيمةٌ مسمّاة: أيُّ `status`
  /// خارجَ المعروفِ يقع هنا (بما فيه `NULL` والفارغُ والمجهول). فالعدُّ
  /// بالنفي لا بالإثبات، وإلّا سقط صفٌّ من العدّادات الثلاثة وهو معروضٌ في
  /// القائمة.
  final int unpaidCount;

  const PurchaseInvoiceSummary({
    required this.invoiceCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalReturns,
    this.paidCount = 0,
    this.partialCount = 0,
    this.unpaidCount = 0,
  });

  /// المتبقي = الإجمالي − المدفوع − المرتجعات. نفسُ معادلةِ `_applyFilters`
  /// حرفاً بحرف كي لا تخالف البطاقةُ مجموعَ الصفوف.
  double get totalRemaining => totalAmount - totalPaid - totalReturns;
}

/// Extension for Purchase-related database operations
extension PurchaseDao on AppDatabase {

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

  /// Total monetary value of all purchase returns recorded against [invoiceId].
  ///
  /// Spec 002 Round 7: the returns-history dialog used to display
  /// `invoice.total` (the ORIGINAL purchase invoice amount, e.g. 5000 د.أ)
  /// alongside each row, which misled the user into thinking the entire
  /// invoice was returned even when only a small portion was. Use this
  /// method to display the actual returned amount instead.
  ///
  /// Aggregates across all partial returns: if a user processed two
  /// partial returns of 4 + 3 units, this returns the sum of both.
  /// Returns 0.0 when the local cache has no stock_movements yet (e.g.
  /// the return was processed by the server but DeltaPull hasn't run).
  Future<double> getPurchaseReturnTotal(int invoiceId) async {
    final rows = await customSelect(
      '''
      SELECT COALESCE(SUM(ABS(quantity) * unit_cost), 0.0) AS total
      FROM stock_movements
      WHERE reference_type = 'purchase_return'
        AND reference_id   = ?
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {stockMovements},
    ).getSingleOrNull();
    final raw = rows?.data['total'];
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  /// Batch version of [getPurchaseReturnTotal] — returns the total
  /// returned value per original purchase-invoice id in a single query.
  /// Used by the purchase-invoices list to subtract refunds from
  /// "المتبقي" and to aggregate the "إجمالي مرتجعات المشتريات" card
  /// without an N+1 lookup per row. Returns an empty map for an empty
  /// id list.
  Future<Map<int, double>> getPurchaseReturnedAmountsForInvoices(
    List<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return const {};
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    final rows = await customSelect(
      '''
      SELECT reference_id,
             COALESCE(SUM(ABS(quantity) * unit_cost), 0.0) AS total
      FROM stock_movements
      WHERE reference_type = 'purchase_return'
        AND reference_id IN ($placeholders)
      GROUP BY reference_id
      ''',
      variables: [for (final id in invoiceIds) Variable.withInt(id)],
      readsFrom: {stockMovements},
    ).get();
    return {
      for (final row in rows)
        row.data['reference_id'] as int:
            (row.data['total'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// المُرتجَعُ سابقاً من كلّ صنفٍ في [invoiceId] — معرّفُ الصنف ↦ الكمّيّة.
  ///
  /// ⚠️ **والوحدةُ أساسيّةٌ في الطرفَين.** `stock_movements.quantity` يُكتب من
  /// `item.returnQuantity` وهو آتٍ من `purchase_invoice_items.quantity` المخزّنة
  /// بالوحدة الأساسيّة بعد التحويل في `createPurchaseInvoice` (موثّقٌ عند
  /// `stockReturnQty` في `purchases_repository_impl.dart`). فمقارنةُ هذا
  /// المخرَج بـ`item.quantity` مشروعةٌ بلا ضربٍ في معامل الوحدة —
  /// والضربُ هنا كان سيعطي عشرةَ أضعافٍ كما وقع فعلاً 2026-04-28.
  ///
  /// والمصدرُ `stock_movements` لا `purchase_returns`: الجدولُ الأخيرُ
  /// يحمل إجماليَ المرتجع لا سطورَه، فلا يجيب عن «كم رُدّ من هذا
  /// الصنف؟». وهذا عينُ ما تقرؤه [getPurchaseReturnItemDetails] أدناه.
  Future<Map<int, double>> getPurchaseReturnedQtyByProduct(
    int invoiceId,
  ) async {
    final rows = await customSelect(
      '''
      SELECT product_id,
             COALESCE(SUM(ABS(quantity)), 0.0) AS qty
      FROM stock_movements
      WHERE reference_type = 'purchase_return'
        AND reference_id = ?
      GROUP BY product_id
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {stockMovements},
    ).get();
    return {
      for (final row in rows)
        row.data['product_id'] as int:
            (row.data['qty'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Get the ACTUAL returned items for a purchase return from stock_movements.
  /// Returns [{productId, productName, returnedQty, unitCost, unitName, total}]
  Future<List<Map<String, dynamic>>> getPurchaseReturnItemDetails(int invoiceId) async {
    final smRows = await customSelect(
      '''
      SELECT
        sm.product_id,
        p.name            AS product_name,
        ABS(sm.quantity)  AS returned_qty,
        COALESCE(pii.unit_cost, sm.unit_cost, 0)   AS unit_cost,
        COALESCE(pii.unit_name, '')                 AS unit_name,
        p.code                                      AS product_code,
        COALESCE(p.barcode, '')                     AS product_barcode,
        -- ⚠️ **الخصمُ والضريبةُ مقسَّطان بنسبة المرتجَع**: القيمتان المخزَّنتان
        --    تخصّان السطرَ كاملاً، ونقلُهما حرفيّاً في مرتجعٍ جزئيٍّ يطبع
        --    خصماً أكبرَ من قيمة المرتجَع نفسِه — رقمٌ خاطئٌ على مستندٍ ماليّ.
        --    والقسمةُ محروسةٌ من الصفر: سطرٌ بكمّيّةٍ صفريّةٍ يعطي صفراً لا NULL.
        CASE WHEN COALESCE(pii.quantity, 0) > 0
             THEN COALESCE(pii.discount, 0) * ABS(sm.quantity) / pii.quantity
             ELSE 0 END                             AS line_discount,
        CASE WHEN COALESCE(pii.quantity, 0) > 0
             THEN COALESCE(pii.tax_amount, 0) * ABS(sm.quantity) / pii.quantity
             ELSE 0 END                             AS line_tax,
        ABS(sm.quantity) * COALESCE(pii.unit_cost, sm.unit_cost, 0) AS total_amount
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id
      LEFT JOIN purchase_invoice_items pii
             ON pii.invoice_id = sm.reference_id
            AND pii.product_id = sm.product_id
      WHERE sm.reference_type = 'purchase_return'
        AND sm.reference_id   = ?
      ORDER BY sm.id
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {stockMovements, products, purchaseInvoiceItems},
    ).get();
    if (smRows.isNotEmpty) {
      return smRows.map((r) => r.data).toList();
    }

    // Spec 002 (Round 2): the primary query missed — no local stock_movements
    // with reference_type='purchase_return' for this invoice. We can fall
    // back ONLY for full returns (status='returned'): every original line is
    // returned at full quantity, so showing them is honest. For partial
    // returns (status='partial_return') we cannot reconstruct WHICH lines
    // and HOW MUCH were returned without the stock_movements rows — showing
    // the full original invoice (the previous behavior) was actively
    // misleading: a partial return for 4-of-100 units displayed as 100
    // units. Return empty in that case so the UI can render "تفاصيل المرتجع
    // غير متاحة محلياً — سيتم تحديثها عند المزامنة التالية" instead of
    // wrong data.
    final inv = await (select(purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId))
          ..limit(1))
        .getSingleOrNull();
    if (inv == null || inv.status != 'returned') {
      // Either the invoice is missing, or its status is 'partial_return' /
      // 'completed' — in both cases fabricating "full original items" would
      // misrepresent the truth. Return empty.
      return const [];
    }

    final rows = await customSelect(
      '''
      SELECT
        pii.product_id,
        p.name AS product_name,
        pii.quantity AS returned_qty,
        pii.unit_cost AS unit_cost,
        COALESCE(pii.unit_name, '') AS unit_name,
        p.code AS product_code,
        COALESCE(p.barcode, '') AS product_barcode,
        -- مرتجعٌ **كامل** (‏`status = 'returned'` شرطٌ أعلاه) ⇒ بلا تقسيط.
        COALESCE(pii.discount, 0) AS line_discount,
        COALESCE(pii.tax_amount, 0) AS line_tax,
        pii.total AS total_amount
      FROM purchase_invoice_items pii
      JOIN products p ON p.id = pii.product_id
      WHERE pii.invoice_id = ?
      ORDER BY pii.id
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {purchaseInvoiceItems, products},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Get the ACTUAL returned items for a sales return from stock_movements.
  /// Returns [{productId, productName, returnedQty, unitCost, unitName, total}]
  ///
  /// P5 (Issue #1): Falls back to looking up the items of the corresponding
  /// "return invoice" (saleType='return' rows linked to this original invoice
  /// via the notes field) when no stock_movements exist. This is necessary
  /// for the SERVER side, where postSalesReturn creates the return invoice
  /// row but does NOT insert stock_movements (those side-effects only
  /// happen on the standalone path). Without the fallback, the eye-icon
  /// preview on the server / a viewer client would always show "no return
  /// data" even though the return is fully recorded.
  Future<List<Map<String, dynamic>>> getSalesReturnItemDetails(int invoiceId) async {
    final smRows = await customSelect(
      '''
      SELECT
        sm.product_id,
        p.name            AS product_name,
        ABS(sm.quantity)  AS returned_qty,
        COALESCE(sii.unit_price, sm.unit_cost, 0)  AS unit_cost,
        ''                                          AS unit_name,
        ABS(sm.quantity) * COALESCE(sii.unit_price, sm.unit_cost, 0) AS total_amount
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id
      LEFT JOIN sales_invoice_items sii
             ON sii.invoice_id = sm.reference_id
            AND sii.product_id = sm.product_id
      WHERE sm.reference_type IN ('sales_return', 'return')
        AND sm.reference_id   = ?
      ORDER BY sm.id
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {stockMovements, products, salesInvoiceItems},
    ).get();
    if (smRows.isNotEmpty) {
      return smRows.map((r) => r.data).toList();
    }

    // FIX 2026-04-28: Fallback when stock_movements are not yet populated
    // (typical for client mode where the server is authoritative for stock
    // movements but they haven't been delta-pulled yet). Show the items of
    // the ORIGINAL invoice so the user sees what was returned. This mirrors
    // the purchase return fallback (which also reads from purchase_invoice_items).
    // The previous query searched for a separate "return invoice" row by
    // saleType='return' + notes-LIKE — that row is never created in the
    // current data model, so it always returned empty → "لا توجد بيانات مرتجع".
    final rows = await customSelect(
      '''
      SELECT
        sii.product_id,
        p.name AS product_name,
        sii.quantity AS returned_qty,
        sii.unit_price AS unit_cost,
        COALESCE(sii.unit_name, '') AS unit_name,
        sii.total AS total_amount
      FROM sales_invoice_items sii
      JOIN products p ON p.id = sii.product_id
      WHERE sii.invoice_id = ?
      ORDER BY sii.id
      ''',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {salesInvoiceItems, products},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Create a complete purchase invoice with items
  Future<int> createPurchaseInvoice({
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? supplierInvoiceNumber,
    String? notes,
    DateTime? invoiceDate,
    int? costCenterId,
    int? safeId,
    // UUID-First (Phase 1)
    String? globalId,
    // 062 (D1-004): caller's userId for the overrideCreditLimit gate.
    int? userId,
    // Client issue ح-1 (2026-07-25): invoice-level discount. Was accepted by
    // the form, dropped on the way down, and never reached the DAO — so the
    // header stored the GROSS total while the operator paid the NET, leaving
    // a permanent phantom payable on the supplier for the discount amount.
    double discount = 0,
  }) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      //
      // بتاريخ **الفاتورة** مش النهاردة. الفحص على `DateTime.now()` كان
      // بيخلّي قفل الفترة متجاوَز على مستوى المستند: فاتورة مؤرَّخة مارس
      // بتتقبل حتى لو مارس مقفول، لأن الفحص بيتم على أغسطس.
      final effectiveInvoiceDate = invoiceDate ?? DateTime.now();
      await accountingDao.validateFinancialPeriod(effectiveInvoiceDate,
          operation: 'فاتورة مشتريات');

      double taxTotal = 0;
      double total = 0;
      double rawMaterialSubtotal = 0;
      double subtotalSum = 0;
      // مواضعُ سطور الخامات — يُجمَع نصيبُها من **الصافي** بعد الخصم
      // أدناه، لا بضربِ إجماليّها في معاملٍ واحد.
      final rawMaterialLineIndexes = <int>{};

      for (var lineAt = 0; lineAt < items.length; lineAt++) {
        final item = items[lineAt];
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Per-line tax toggle: one invoice can mix taxable and exempt
        // items, so the form passes `taxAmount=0` for exempt lines while
        // still carrying the product's rate. Honour the passed amount
        // when present; only recompute from rate for callers that did
        // not supply it (legacy / outbox replays).
        //
        // Spec 151 E-03: round to the financial precision here too, using the
        // SAME expression the per-line INSERT below now uses, so
        // SUM(line.tax) == header.tax exactly (no float-noise drift).
        final tax = FinancialUtils.round(item.taxAmount.present
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100));

        subtotalSum += subtotal;
        // نصيب الخامات من الإجمالي. الشراء كان بيدخّل **كل** الأصناف على
        // ١١٣٦ بينما استهلاك التصنيع بيسحب من ١١٣١، فالخامة بتدخل حساب
        // وتخرج من حساب تاني و١١٣١ بيبقى رصيد أصل سالب مع كل أمر إنتاج.
        if (item.productId.present) {
          final p = await getProductById(item.productId.value);
          if (inventoryAccountPurposeForProduct(p?.productType) ==
              'raw_materials') {
            rawMaterialSubtotal += subtotal;
            rawMaterialLineIndexes.add(lineAt);
          }
        }
        total += subtotal + tax;
        taxTotal += tax;
      }

      // ح-1 — TRADE discount (owner decision 2026-07-25). IAS 2.11 requires a
      // trade discount to be DEDUCTED FROM THE COST of inventory, not booked
      // as income. So the discount is apportioned pro-rata into the line unit
      // costs, `subtotal` is stored NET, and no purchase-discount (4316) leg is
      // posted at all.
      //
      // Consequences that fall out of this, all of them correct:
      //   • WAC reflects the true landed cost (10 @ 100 less 100 → 90).
      //   • The inventory GL debit equals Σ(qty × cost), so the GL ↔ stock
      //     valuation reconciliation stays tied.
      //   • A later purchase RETURN refunds the net cost, so a discounted
      //     invoice can no longer refund more cash than was ever paid.
      final effectiveDiscount =
          discount > 0 ? FinancialUtils.round(discount) : 0.0;
      if (effectiveDiscount > total) {
        throw StateError(
          'الخصم (${effectiveDiscount.toStringAsFixed(2)}) أكبر من إجمالي '
          'الفاتورة (${total.toStringAsFixed(2)}).',
        );
      }
      // Factor applied to every line's unit cost. Guard against a zero-value
      // invoice so we never divide by zero.
      // خصمٌ **لكلّ صنف** — قرارُ المالك 2026-09-18. القاعدةُ واحدةٌ:
      // خصمُ السطر الصريحُ يُطرَح أوّلاً، وما بقي من خصم المستند يُوزَّع
      // نسبةً إلى ما بقي من قيمة السطور. راجع [resolvePurchaseLineNets].
      //
      // ⚠️ **وبلا خصومِ سطورٍ تُنتج القاعدةُ عينَ التوزيع النسبيّ القديم**
      // حرفاً — وهو شرطُ ألّا يتغيّر رقمٌ في فاتورةٍ قديمةٍ أو في إعادةِ
      // صندوقٍ صادرٍ أو مزامنة.
      final lineNets = resolvePurchaseLineNets(
        grossPerLine: [
          for (final it in items)
            (it.quantity.present ? it.quantity.value : 1.0) *
                (it.unitCost.present ? it.unitCost.value : 0.0),
        ],
        explicitDiscountPerLine: [
          for (final it in items) it.discount.present ? it.discount.value : 0.0,
        ],
        documentDiscount: effectiveDiscount,
      );
      total = FinancialUtils.round(total - effectiveDiscount);
      subtotalSum = FinancialUtils.round(subtotalSum - effectiveDiscount);

      final remaining = total - paid;
      final status = remaining <= 0
          ? 'paid'
          : (paid > 0 ? 'partial' : 'pending');

      // Enforce supplier credit limit — mirror of the customer check in
      // sales_mutations_dao so a purchase can't silently push us past the
      // limit we agreed with the supplier. `balance > 0` means we owe
      // them, so a partial/unpaid purchase projects forward by the
      // remaining amount. Zero creditLimit means "not configured" → no
      // enforcement (matches sales semantics).
      if (remaining > 0.01) {
        final supplier = await (select(
          parties,
        )..where((p) => p.id.equals(supplierId))).getSingleOrNull();
        if (supplier != null && supplier.creditLimit > 0) {
          final projectedBalance = supplier.balance + remaining;
          if (projectedBalance > supplier.creditLimit) {
            // 062 (D1-004): overrideCreditLimit allows the purchase to
            // proceed; emit CREDIT-OVERRIDE log.
            final hasOverride = await permissionEnforcer.hasCriticalOp(
              userId, PermissionCodes.overrideCreditLimit);
            if (!hasOverride) {
              throw Exception(
                'تجاوز المورد الحد الائتماني المسموح به (${supplier.creditLimit})',
              );
            }
            unawaited(DiagnosticLogger.log('CREDIT-OVERRIDE',
                'purchase user=$userId supplier=${supplier.id} '
                'projected=$projectedBalance limit=${supplier.creditLimit}'));
          }
        }
      }

      // البند 5: reject a supplier-invoice-number already used by this supplier
      // BEFORE anything is written. Inside the transaction() → a violation
      // rolls back stock/GL/treasury with the invoice.
      await _assertSupplierInvoiceNumberFree(supplierId, supplierInvoiceNumber);

      // Use supplier invoice number if provided, else generate internal PUR- number
      // This implements Phase 5: Purchase invoices using the number provided by the supplier.
      final invoiceNumber =
          (supplierInvoiceNumber != null && supplierInvoiceNumber.isNotEmpty)
          ? supplierInvoiceNumber
          : await generateInvoiceNumber('PUR');

      // L3 (2026-04-28): Resolve branchId from warehouse so each invoice
      // carries its branch directly — eliminates 2-hop JOIN for reports.
      int? resolvedBranchId;
      try {
        final wh = await (select(warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
        resolvedBranchId = wh?.branchId;
      } catch (_) {/* non-fatal — branch stays null */}

      // Insert invoice
      // v164 — الاستحقاقُ لقطةٌ من مهلةِ المورد وقتَ الإصدار.
      final dueAt = await resolveInvoiceDueDate(
        partyId: supplierId,
        invoiceDate: invoiceDate ?? DateTime.now(),
      );
      final invoiceId = await into(purchaseInvoices).insert(
        PurchaseInvoicesCompanion.insert(
          invoiceNumber: invoiceNumber,
          supplierId: supplierId,
          warehouseId: warehouseId,
          branchId: Value(resolvedBranchId),
          invoiceDate: invoiceDate ?? DateTime.now(),
          dueDate: Value(dueAt),
          subtotal: Value(subtotalSum),
          discount: Value(effectiveDiscount),
          tax: Value(taxTotal),
          total: Value(total),
          paid: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
          costCenterId: Value(costCenterId),
          // UUID-First (Phase 1): carry the caller's globalId through, or
          // mint one so every purchase invoice has stable cross-install id.
          globalId: Value(
            (globalId != null && globalId.isNotEmpty)
                ? globalId
                : UuidV7.generate(),
          ),
        ),
      );

      for (var lineAt = 0; lineAt < items.length; lineAt++) {
        final item = items[lineAt];
        final productId = item.productId.present ? item.productId.value : 0;
        final quantity = item.quantity.present ? item.quantity.value : 1.0;
        // ح-1 (trade discount): الخصمُ يصل تكلفةَ السطر **قبل** أن يصل
        // السطرَ المخزَّنَ وحركةَ المخزون و`updateProductWAC` — وهذا ما
        // يجعل متوسّطَ التكلفة تكلفةً حقيقيّةً ويمنع مرتجعاً من ردّ أكثرَ
        // ممّا دُفع.
        //
        // 🔴 **ومرّةً واحدةً بالضبط**: الصافي مطروحٌ منه الخصمُ الصريحُ
        // وحصّتُه من الباقي معاً في [resolvePurchaseLineNets]، فلا ضربَ
        // في معاملٍ هنا يُطبّقه ثانيةً.
        final unitCost = quantity > 0
            ? FinancialUtils.round(lineNets[lineAt] / quantity)
            : 0.0;
        final taxRate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        // Spec 151 E-03: honour the passed per-line taxAmount (exactly as the
        // header loop above does) instead of always recomputing from the rate.
        // A mixed invoice sends taxAmount=0 for an exempt line while still
        // carrying the product's rate; recomputing here stored PHANTOM input
        // VAT that a purchase RETURN later reversed — and made SUM(line.tax)
        // diverge from header.tax. Only recompute as a fallback when the caller
        // supplied no amount (legacy / outbox / api_purchase_handler replays).
        // Round to the financial precision so the stored line reconciles with
        // the header exactly.
        final taxAmount = FinancialUtils.round(item.taxAmount.present
            ? (item.taxAmount.value ?? 0.0)
            : (quantity * unitCost) * (taxRate / 100));

        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            // ح-1 (trade discount): persist the APPORTIONED cost. copyWith
            // keeps the caller's gross value otherwise, so the stored line
            // would disagree with stock/WAC/GL and a later return would
            // refund more than was ever paid.
            unitCost: Value(unitCost),
            total: Value(quantity * unitCost + taxAmount),
            taxAmount: Value(taxAmount),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );

        // Update product stock and WAC cost (#PIR Phase 0)
        final product = await getProductById(productId);
        if (product != null && product.trackInventory) {
          // 1. Update WAC Cost BEFORE updating stock quantity if we want standard average logic,
          // or pass "newQuantity" to the helper which handles current balance.
          await updateProductWAC(
            productId: productId,
            newQuantity: quantity,
            newUnitCost: unitCost,
          );

          // 2. Update Stock Quantity
          // B10 (S-INV-COST / PUR-1): thread the receipt's real unitCost
          // through so the per-warehouse average_cost blend (inside
          // adjustStock → _updateWarehouseBalance) uses the ACTUAL receipt
          // cost instead of the just-updated GLOBAL WAC. Without this, a
          // price change or a multi-warehouse setup left
          // inventory_balances.average_cost silently diverged from the true
          // receipt cost. products.costPrice (COGS source-of-truth) is
          // still set exclusively by updateProductWAC above — untouched.
          await adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: quantity,
            type: 'purchase',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            notes: 'مشتريات فاتورة #$invoiceNumber',
            unitCost: unitCost,
          );
        }

        // Create batch if expiry tracking
        if (product != null &&
            product.trackExpiry &&
            item.expiryDate.value != null) {
          await into(productBatches).insert(
            ProductBatchesCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              batchNumber: item.batchNumber.value ?? invoiceNumber,
              quantity: Value(quantity),
              initialQuantity: Value(quantity),
              productionDate: item.productionDate,
              expiryDate: item.expiryDate.value!,
              unitCost: Value(unitCost),
              purchaseInvoiceId: Value(invoiceId),
            ),
          );
        }
      }

      // Update supplier balance if on credit
      if (remaining > 0) {
        await adjustPartyBalance(supplierId, remaining);
      }

      // Record treasury transaction if paid. Client issue البند 6: keep the
      // returned row — the cash leg is no longer posted inline; it is posted
      // from this voucher by autoPostPayment further down, so the credited
      // account is the PAYING safe's own linked account (fixes ح-4) and the
      // amount is what actually left the safe (fixes ح-3).
      SafeTransactionData? paymentTxn;
      if (paid > 0) {
        paymentTxn = await _recordPurchasePayment(invoiceId, paid, paymentMethod, costCenterId, safeId: safeId, supplierId: supplierId);
        if (paymentTxn == null) {
          // Symmetry with addPurchasePayment: a payment we cannot attribute to
          // a safe must not silently reduce the GL with no treasury movement.
          throw StateError(
            'تعذّر تسجيل دفعة فاتورة المشتريات #$invoiceNumber: لا يوجد صندوق '
            'مطابق لطريقة الدفع. أنشئ صندوقاً افتراضياً أو اختر صندوقاً '
            'قبل الحفظ.',
          );
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // AUTOMATIC ACCOUNTING ENTRY (#PIR Phase 0)
      // PHASE-2 FIX: GL errors propagate to parent transaction() → full rollback.
      // B7 (S-FAILLOUD / PUR-3): the inventory account used to be an optional
      // leg — a missing mapping just debugPrinted a warning and SKIPPED the
      // whole GL entry while stock/WAC/party-balance/treasury above had
      // already committed inside this same transaction. That is exactly the
      // "financial side-effect with no balanced JE" invariant this batch
      // exists to close. A missing inventory account means the chart of
      // accounts is genuinely broken (syncDefaultAccounts always seeds it) —
      // fail loud and let the whole invoice roll back instead of silently
      // posting stock movements with no accounting trail.
      // ═══════════════════════════════════════════════════════════════════════
      final List<JournalLine> journalLines = [];

      // 1. Debit side (Assets - Inventory increase) — dynamic account resolution
      final invCode = await accountingDao.getMappedAccountCode(
        'inventory', AccountingDao.accountPurposes['inventory']!,
      );
      final invAcc = await accountingDao.getAccountByCode(invCode);
      if (invAcc == null) {
        throw StateError(
          'تعذّر تسجيل فاتورة المشتريات #$invoiceNumber: حساب المخزون '
          '($invCode) غير موجود في الدليل المحاسبي. '
          'راجع إعدادات الحسابات ← ربط الحسابات قبل حفظ الفاتورة.',
        );
      }
      // ── توجيه المدين حسب نوع الصنف (قرار المالك، 2026-08-02) ────────────
      //
      // الخامات على حساب الخامات (١١٣١) والباقي على المخزون (١١٣٦). قبل كده
      // كل الأصناف كانت بتدخل ١١٣٦ بينما `manufacturing_dao` بيسحب الاستهلاك
      // من ١١٣١ — فكل أمر إنتاج بيضخّم ١١٣٦ بقيمة الخامات المستهلكة ويخلّي
      // ١١٣١ رصيد أصل سالب.
      //
      // نسبة الخصم اتطبقت على `subtotalSum` فوق، فنصيب الخامات بيتعدّل بنفس
      // النسبة عشان مجموع السطرين يساوي الإجمالي بعد الخصم بالظبط.
      // نصيبُ الخامات من الصافي — مجموعُ صافي سطورها بعد الخصم، فمجموعُ
      // السطرَين المحاسبيَّين يساوي الإجماليَّ بعد الخصم بالضبط.
      final rawShare = rawMaterialSubtotal > 0
          ? FinancialUtils.round([
              for (final at in rawMaterialLineIndexes) lineNets[at],
            ].fold<double>(0, (a, v) => a + v))
          : 0.0;
      final rawAcc = rawShare > 0
          ? await accountingDao.getAccountByCode(
              await accountingDao.getMappedAccountCode('raw_materials',
                  AccountingDao.accountPurposes['raw_materials']!))
          : null;
      // حساب الخامات مش موجود (دليل معدَّل) ⇒ الكل على المخزون زي الأول بدل
      // ما القيد يفشل ويوقف الفاتورة.
      final rawLeg = rawAcc == null ? 0.0 : rawShare;

      if (rawLeg > 0) {
        journalLines.add(
          JournalLine(
            accountId: rawAcc!.id,
            debit: rawLeg,
            description: 'مشتريات خامات فاتورة #$invoiceNumber',
          ),
        );
      }
      if (subtotalSum - rawLeg > 0) {
        journalLines.add(
          JournalLine(
            accountId: invAcc.id,
            debit: FinancialUtils.round(subtotalSum - rawLeg),
            description: 'مشتريات مخزنية فاتورة #$invoiceNumber',
          ),
        );
      }

      if (taxTotal > 0) {
        final inputTaxCode = await accountingDao.getMappedAccountCode(
          'input_vat', AccountingDao.accountPurposes['input_vat']!,
        );
        final inputTaxAcc = await accountingDao.getAccountByCode(inputTaxCode);
        if (inputTaxAcc != null) {
          journalLines.add(
            JournalLine(
              accountId: inputTaxAcc.id,
              debit: taxTotal,
              description: 'ضريبة مدخلات مشتريات #$invoiceNumber',
            ),
          );
        }
      }

      // ح-1 (trade discount): NO purchase-discount (4316) credit leg. A trade
      // discount reduces the cost of the goods (IAS 2.11) — it is not income.
      // `subtotalSum` above is already NET and the line costs were apportioned,
      // so the inventory debit equals Σ(qty × cost) and the JE balances against
      // the payable without any extra leg.
      //
      // (A SETTLEMENT discount would be different — that IS financing income
      // and would belong on 4316. This field is a trade discount by owner
      // decision; if that ever changes, the two treatments must not be mixed.)

      // 2. Credit side — البند 6 (approved 2026-07-25): the supplier's payable
      // is ALWAYS the counter-party, cash or credit alike. The settlement leg
      // (Dr payable / Cr cash) is posted separately from the payment voucher
      // by autoPostPayment below.
      //
      // Why: previously a cash purchase credited the cash account directly and
      // the supplier's account never moved, so their GL card showed nothing —
      // the accountant could not read "purchased / paid" per supplier from the
      // ledger. Trial-balance effect is identical either way.
      //
      // This also removes the paymentMethod-keyed branch that credited Cash for
      // the FULL total on a partially-paid cash invoice (ح-3), and stops the
      // cash leg landing on the global cash account instead of the paying
      // safe's own account (ح-4) — autoPostPayment resolves that from the safe.
      if (total > 0) {
        final apCode = await accountingDao.getMappedAccountCode(
          'payables', AccountingDao.accountPurposes['payables']!,
        );
        final apControlAcc = await accountingDao.getAccountByCode(apCode);
        // Route to the supplier sub-account (2111-XXXXX) so COA/GL show
        // per-supplier balances instead of a lumped 2111 control total.
        final apAcc = await _resolvePartySubAccount(supplierId, apControlAcc);
        if (apAcc != null) {
          journalLines.add(
            JournalLine(
              accountId: apAcc.id,
              credit: total,
              description: 'مشتريات فاتورة #$invoiceNumber',
            ),
          );
        }
      }

      // journalLines always has at least the inventory debit line at this
      // point (invAcc==null already threw above). If the cash/payables credit
      // leg above was skipped (unmapped account), createJournalEntry's own
      // balance check (Spec 139) throws on the resulting imbalance — same
      // "propagates to parent transaction() → rollback" guarantee.
      // H-09 FIX: Get branchId from warehouse to ensure financial isolation
      final warehouse = await getWarehouseById(warehouseId);
      final branchId = warehouse?.branchId;

      // Resolve costCenterId from invoice (if tracked) or warehouse
      final invoiceData = await getPurchaseInvoiceById(invoiceId);
      final ccId = invoiceData?.costCenterId ?? warehouse?.costCenterId;

      // Throws on DB failure → propagates to parent transaction() → rollback
      await accountingDao.createJournalEntry(
        description: 'قيد مشتريات تلقائي للفاتورة #$invoiceNumber',
        // تاريخ **الفاتورة** مش النهاردة. الهيدر بيتخزن بتاريخ الفاتورة
        // والقيد كان بتاريخ اليوم، فتقرير المشتريات (بيفلتر بـinvoiceDate)
        // وتقرير الضريبة (بيفلتر بـentry_date) بيقولوا شهرين مختلفين لنفس
        // المستند — وضريبة المدخلات بتتحسب في إقرار الشهر الغلط.
        // `autoPostPurchase:968` نفسه بيستعمل `purchase.invoiceDate`.
        date: effectiveInvoiceDate,
        lines: journalLines,
        referenceType: 'purchase_invoice',
        referenceId: invoiceId,
        isAutoPosted: true,
        costCenterId: ccId,
        branchId: branchId,
      );

      // البند 6 — settlement leg: Dr supplier payable / Cr the PAYING safe's
      // linked account. autoPostPayment already implements exactly this for
      // `category == 'purchase'`, so there is no new posting code: it resolves
      // the supplier sub-account for the debit and the safe's own account for
      // the credit. Runs inside the same transaction() → a failure rolls the
      // whole invoice back rather than leaving a payable that was never settled.
      if (paymentTxn != null) {
        // autoPostPayment returns null (does NOT throw) when the safe has no
        // linked account and the global cash/bank mapping is missing, or the
        // payables control account is gone. Swallowing that would leave the
        // payable credited in full with the safe already debited and NO
        // settlement JE — the exact silent divergence this batch closes.
        // addPurchasePayment already fails loud here; match it.
        final settlementJeId =
            await accountingDao.autoPostPayment(paymentTxn, costCenterId: ccId);
        if (settlementJeId == null) {
          throw StateError(
            'تعذّر ترحيل قيد سداد فاتورة المشتريات #$invoiceNumber: '
            'حساب الصندوق أو حساب الذمم غير مربوط في الدليل المحاسبي. '
            'راجع إعدادات الحسابات ← ربط الحسابات.',
          );
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SYNC ENGINE: Add to outbox (#Phase7)
      //
      // NO try/catch here. An outbox failure MUST fail the whole transaction
      // so stock/WAC/GL/invoice roll back together. The previous swallow-and-
      // continue masked real errors as Postgres 25P02 ("transaction aborted")
      // because the swallowed exception already poisoned the tx at the DB
      // layer, then later COMMIT would fail with 25P02 and the original cause
      // was lost.
      // ═══════════════════════════════════════════════════════════════════════
      await addToSyncOutbox(
        tableName: 'purchase_invoices',
        recordId: invoiceId.toString(),
        operation: 'insert',
        payload: {
          'invoice_number': invoiceNumber,
          'supplier_id': supplierId,
          'warehouse_id': warehouseId,
          'invoice_date': DateTime.now().toIso8601String(),
          'subtotal': subtotalSum,
          'tax': taxTotal,
          'total': total,
          'paid': paid,
          'payment_method': paymentMethod,
          'status': status,
          'notes': notes,
          'items': items
              .map(
                (e) => {
                  'product_id': e.productId.value,
                  'quantity': e.quantity.value,
                  'unit_cost': e.unitCost.value,
                  'tax_rate': e.taxRate.present ? e.taxRate.value : 0.0,
                  'batch_number': e.batchNumber.present ? e.batchNumber.value : null,
                  'expiry_date': e.expiryDate.value?.toIso8601String(),
                },
              )
              .toList(),
        },
      );

      return invoiceId;
    });
  }

  /// Insert purchase invoice WITHOUT stock/accounting/treasury side effects.
  /// Used by client dual-write: server handles stock/WAC/GL, client just caches for local visibility.
  Future<int> insertPurchaseInvoiceWithoutStock({
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? notes,
    String? supplierInvoiceNumber,
    DateTime? invoiceDate,
    int? costCenterId,
    // UUID-First (Phase 1): pass-through from the server's submission
    String? globalId,
    // ح-1: mirror the server's net total in the local cache row, otherwise the
    // mirror's invoice list shows a gross total the server never stored.
    double discount = 0,
  }) async {
    return transaction(() async {
      double taxTotal = 0;
      double total = 0;
      double subtotalSum = 0;

      for (final item in items) {
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Honour the per-line `taxAmount` passed from the form so exempt
        // lines (toggle off) stay at 0 even when the product carries a
        // non-zero default rate. See createPurchaseInvoice for the same
        // fix; this path is used by the client-mode local cache.
        final tax = item.taxAmount.present
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100);
        subtotalSum += subtotal;
        total += subtotal + tax;
        taxTotal += tax;
      }

      // ح-1 (trade discount): same net rule as createPurchaseInvoice so the
      // mirror's cached header matches what the server actually stored. This
      // path writes no stock/WAC (that is the server's job), so only the
      // header amounts need netting here.
      final effectiveDiscount =
          discount > 0 ? FinancialUtils.round(discount) : 0.0;
      total = FinancialUtils.round(total - effectiveDiscount);
      subtotalSum = FinancialUtils.round(subtotalSum - effectiveDiscount);

      final remaining = total - paid;
      final status = remaining <= 0.01 ? 'paid' : (paid > 0 ? 'partial' : 'pending');
      final invoiceNumber = await generateInvoiceNumber('PUR');

      // v164 — الاستحقاقُ لقطةٌ من مهلةِ المورد وقتَ الإصدار.
      final dueAt = await resolveInvoiceDueDate(
        partyId: supplierId,
        invoiceDate: invoiceDate ?? DateTime.now(),
      );
      final invoiceId = await into(purchaseInvoices).insert(
        PurchaseInvoicesCompanion.insert(
          invoiceNumber: invoiceNumber,
          supplierId: supplierId,
          warehouseId: warehouseId,
          invoiceDate: invoiceDate ?? DateTime.now(),
          dueDate: Value(dueAt),
          subtotal: Value(subtotalSum),
          discount: Value(effectiveDiscount),
          tax: Value(taxTotal),
          total: Value(total),
          paid: Value(paid),
          status: Value(status),
          paymentMethod: Value(paymentMethod),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
          costCenterId: Value(costCenterId),
          globalId: Value(
            (globalId != null && globalId.isNotEmpty)
                ? globalId
                : UuidV7.generate(),
          ),
        ),
      );

      for (final item in items) {
        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );
      }

      return invoiceId;
    });
  }

  /// Record purchase payment in treasury.
  ///
  /// البند 5 (متطلبات العميل 2026-07-25) — يرفض تكرار رقم فاتورة المورد
  /// **لنفس المورد**.
  ///
  /// Scope is per-supplier, NOT global: a supplier's invoice number is only
  /// unique within that supplier's own book, so two different suppliers may
  /// legitimately both issue `1001`. A global UNIQUE would reject real data.
  ///
  /// Blank/absent numbers are exempt — those invoices get an auto-generated
  /// `PUR-n`, which carries no business meaning to collide on.
  ///
  /// Soft-deleted (voided) invoices do not reserve their number.
  ///
  /// [excludeInvoiceId] must be passed on the edit path so re-saving an invoice
  /// under its own number isn't reported as a collision with itself.
  ///
  /// NOTE: this is an APPLICATION-level guard on purpose. A partial UNIQUE
  /// index is the stronger fix but must not be added until the customer's live
  /// database is confirmed free of pre-existing duplicates — otherwise the
  /// migration fails on their data.
  Future<void> _assertSupplierInvoiceNumberFree(
    int supplierId,
    String? number, {
    int? excludeInvoiceId,
  }) async {
    if (number == null || number.trim().isEmpty) return;
    final trimmed = number.trim();

    final query = select(purchaseInvoices)
      ..where((p) =>
          p.supplierId.equals(supplierId) &
          p.supplierInvoiceNumber.equals(trimmed) &
          p.isDeleted.equals(false))
      ..limit(2);

    final hits = await query.get();
    final clash = hits.where((h) => h.id != excludeInvoiceId).toList();
    if (clash.isEmpty) return;

    final supplier = await (select(parties)
          ..where((p) => p.id.equals(supplierId))
          ..limit(1))
        .getSingleOrNull();
    throw StateError(
      'رقم فاتورة المورد "$trimmed" مستخدم بالفعل '
      '${supplier != null ? 'للمورد «${supplier.name}» ' : ''}'
      '(فاتورة #${clash.first.invoiceNumber}). '
      'راجع الرقم أو افتح الفاتورة القائمة لتعديلها.',
    );
  }

  /// P2 (batch B7): returns the inserted safe-transaction row (or null when
  /// no target safe was resolved) so callers — [addPurchasePayment] — can
  /// feed it straight into [AccountingAutopostDao.autoPostPayment] without a
  /// second lookup, keeping the payment + its GL posting in one atomic pass.
  Future<SafeTransactionData?> _recordPurchasePayment(
    int invoiceId,
    double amount,
    String paymentMethod,
    int? costCenterId, {
    int? safeId,
    int? supplierId,
    int? userId,
    String? globalId,
  }) async {
    final safeType = (paymentMethod == 'transfer' || paymentMethod == 'card')
        ? 'bank'
        : 'cash';

    Safe? targetSafe;

    // If a specific safe was requested by the user, use it directly
    if (safeId != null) {
      targetSafe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    }

    if (targetSafe == null && costCenterId != null) {
      // Find default safe for this specific cost center. `.limit(1)` is
      // required to keep `getSingleOrNull` safe when a cost center has
      // more than one safe of the same type (e.g. main cash + secondary
      // cash till) — without it the whole purchase save crashes with
      // "Bad state: Too many elements".
      targetSafe = await (select(safes)
            ..where((s) =>
                s.safeType.equals(safeType) &
                s.costCenterId.equals(costCenterId) &
                s.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();
    }

    // Fallback to global default safe if none found
    targetSafe ??= await getDefaultSafeByType(safeType);

    if (targetSafe != null) {
      final newBalance = targetSafe.balance - amount;
      // allow-bare-generateInvoiceNumber: _recordPurchasePayment is a private
      // helper called only from createPurchaseInvoice, voidPurchaseInvoice
      // and addPurchasePayment — all already inside a transaction().
      final voucherNumber = await generateInvoiceNumber('PV');

      final txnId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: targetSafe.id,
          transactionType: 'payment',
          category: 'purchase',
          amount: amount,
          balanceAfter: newBalance,
          referenceType: const Value('purchase_invoice'),
          referenceId: Value(invoiceId),
          partyId: Value(supplierId),
          // Spec 151 C-03: stamp the caller's userId + deterministic globalId so
          // the payment voucher is attributable and dedup-keyed end-to-end
          // (offline replay / mirror re-submit match on this globalId).
          userId: Value(userId),
          globalId: Value(globalId),
        ),
      );

      // H15 — خصمُ سدادٍ ذرّيّ: سدادان متزامنان على نفس الخزنة كانا
      // يقرآن نفسَ الرصيد فيضيع أحدُهما. `newBalance` لقطةُ `balanceAfter`.
      await adjustSafeBalance(targetSafe.id, -amount);

      return (select(safeTransactions)..where((t) => t.id.equals(txnId)))
          .getSingle();
    }
    return null;
  }

  /// Update a purchase invoice with full edit capability
  /// Reverses old stock amounts, applies new amounts, updates supplier balance
  Future<void> updatePurchaseInvoice({
    required int invoiceId,
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    required String paymentMethod,
    String? notes,
    String? supplierInvoiceNumber,
    int? costCenterId,
    // Purchase-edit policy: the caller's userId is the ONLY gate. Required —
    // a null userId is denied (see the requireCriticalOp call below).
    int? userId,
    // ح-1: the edit path had no discount parameter, so re-saving a discounted
    // invoice — even with identical lines — recomputed `total` GROSS and left
    // the `discount` column stale. That silently restored the phantom payable
    // ح-1 exists to prevent, on EVERY edit. Null = keep whatever the header
    // already holds (so callers that don't collect a discount can't wipe one).
    double? discount,
  }) async {
    return transaction(() async {
      // Get original invoice
      final oldInvoice = await getPurchaseInvoiceById(invoiceId);
      if (oldInvoice == null) throw Exception('Invoice not found');

      // ── Purchase-edit policy (supersedes ISS-04 / 062 D1-004) ────────────
      // Owner decision 2026-07-22: editing a purchase invoice is governed by
      // ONE thing — does the caller hold `purchases_edit`?
      //   • holds it  → UNLIMITED edits, before or after posting. Re-posting
      //     the GL entry is already handled at the end of this method
      //     (_reverseOldPurchaseJournalEntry + autoPostPurchase), so a posted
      //     invoice stays consistent across any number of edits.
      //   • lacks it  → denied outright.
      // `isLocked` is therefore NO LONGER a gate; it stays as the posted-state
      // marker that drives integrityHash verification and the void reversal.
      //
      // Why this replaced the old gate: the previous code demanded the
      // `modify_locked_invoice` critical-op permission whenever isLocked was
      // true, but NO call site ever threaded `userId` down here — so
      // PermissionEnforcer.hasCriticalOp(null, ...) always returned false and
      // EVERY posted purchase invoice was permanently uneditable, even for a
      // system admin holding the permission. The userId is now threaded from
      // every call site (local repo, server putPurchase, client interceptor).
      await permissionEnforcer.requireCriticalOp(
        userId: userId,
        code: PermissionCodes.purchasesEdit,
        arabicReason: 'لا تملك صلاحية تعديل فواتير المشتريات. '
            'يلزم صلاحية "تعديل فاتورة مشتريات".',
      );

      // البند 5: reject a supplier-invoice-number that belongs to a DIFFERENT
      // live invoice of this supplier. Excluding this invoice's own id keeps
      // re-saving under its existing number legal.
      await _assertSupplierInvoiceNumberFree(
        supplierId,
        supplierInvoiceNumber,
        excludeInvoiceId: invoiceId,
      );

      // Audit breadcrumb — editing an already-posted (locked) invoice reverses
      // and re-posts the GL entry, so it is worth a persistent trail even
      // though it is now a permitted operation.
      if (oldInvoice.isLocked) {
        unawaited(DiagnosticLogger.log(
          'PURCHASE-EDIT',
          'posted invoice edited — id=$invoiceId '
          'number=${oldInvoice.invoiceNumber} by userId=$userId '
          'oldTotal=${oldInvoice.total}',
        ));
      }

      // S-COST-2 (Spec 145): the FK that crashes the item hard-delete below is
      // landed_cost_allocations.purchaseItemId (NOT NULL, NO ACTION). Those
      // allocation rows are persisted by calculateAllocations while the sheet
      // is still 'draft' — BEFORE apply — so gating on 'applied' alone would
      // miss the crash (compute-then-cancel leaves draft allocations). Block
      // whenever a non-voided sheet of this invoice has persisted allocations
      // (the real crash predicate). Operator must void the invoice or delete
      // the sheet or use returns instead.
      final pinned = await customSelect(
        '''SELECT lcs.sheet_number AS sn
           FROM landed_cost_allocations lca
           JOIN landed_cost_sheets lcs ON lcs.id = lca.sheet_id
           WHERE lcs.purchase_invoice_id = ? AND lcs.status != 'voided'
           LIMIT 1''',
        variables: [Variable<int>(invoiceId)],
        readsFrom: {landedCostAllocations, landedCostSheets},
      ).getSingleOrNull();
      if (pinned != null) {
        throw Exception(
            'لا يمكن تعديل فاتورة عليها تكاليف محمّلة (${pinned.data['sn']}) — '
            'ألغِ الفاتورة أو احذف ورقة التكاليف أو استخدم المرتجعات.');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(oldInvoice.invoiceDate, operation: 'تعديل فاتورة مشتريات');

      // Get original items
      final oldItems = await getPurchaseInvoiceItems(invoiceId);

      // Reverse old stock quantities and WAC
      final oldProductMap = await getProductsByIds(oldItems.map((i) => i.productId).toList());
      for (final item in oldItems) {
        final product = oldProductMap[item.productId];
        if (product != null && product.trackInventory) {
          // 1. First reverse the WAC impact of the old purchase line
          await reverseProductWAC(
            productId: item.productId,
            reversedQuantity: item.quantity,
            reversedUnitCost: item.unitCost,
          );

          // 2. Reverse the stock
          await adjustStock(
            productId: item.productId,
            warehouseId: oldInvoice.warehouseId,
            quantity: -item.quantity,
            type: 'adjustment',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            // F-02: the inventory GL leg is owned by the base purchase JE
            // (reversed by _reverseOldPurchaseJournalEntry + reposted by
            // autoPostPurchase below). This old-stock reversal must move
            // stock/WAC ONLY — never post a stock_adjustment shrinkage/surplus
            // JE, or it survives the base-JE reversal and corrupts inventory GL.
            postAdjustmentJournal: false,
            notes:
                'تعديل فاتورة مشتريات (حذف قديم) #${oldInvoice.invoiceNumber}',
          );
        }
      }

      // Reverse old supplier balance (if had remaining balance)
      final oldRemaining = oldInvoice.total - oldInvoice.paid;
      if (oldRemaining > 0) {
        await adjustPartyBalance(oldInvoice.supplierId, -oldRemaining);
      }

      // F-02 (Spec 151): reverse the OLD purchase GL journal entry AND the OLD
      // treasury payment here, so the re-post at the end of this method reflects
      // the NEW amounts. Before this fix the method moved stock/WAC/supplier-
      // balance to the new values but left the purchase JE frozen at the OLD
      // amounts (the trailing "simplified — just log" comment) and never touched
      // the safe — GL diverged from inventory/AP and the safe was never adjusted
      // for the payment delta on every edit. This mirrors updateFullSalesInvoice
      // (the sales sibling): delete the old JE + recompute balances, then re-post.
      await _reverseOldPurchaseJournalEntry(invoiceId);
      // F02-1/F02-2: reversing the old payment also reverses any separate GL
      // 'payment' JE (prevents the double-count on re-post) and yields the
      // original payment's safe so we re-record onto the SAME safe.
      final originalPaymentSafeId = await _reverseOldPurchasePayment(invoiceId);

      // Delete old items
      // Cluster 023 / Issue 2 — capture the deleted-row count and log a
      // SYNC-WARN whenever it diverges from oldItems.length. Field reports
      // showed sites whose edit-then-save flow ended up with 2N rows; a
      // mismatch here is the only place a stale duplicate (left by an
      // earlier sync race or a prior buggy version) could survive the
      // delete-then-insert dance and surface as the doubled-items
      // symptom on the next reopen.
      final deletedCount = await (delete(
        purchaseInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).go();
      if (deletedCount != oldItems.length) {
        DiagnosticLogger.log(
          'SYNC-WARN',
          'updatePurchaseInvoice deleted=$deletedCount but oldItems.length=${oldItems.length} '
          'for invoice=$invoiceId — pre-existing duplicate purchase items detected and cleaned up.',
        );
      }

      // Delete old batches linked to this invoice
      await (delete(
        productBatches,
      )..where((b) => b.purchaseInvoiceId.equals(invoiceId))).go();

      // Calculate new totals
      double newTotal = 0;
      double newTaxTotal = 0;
      for (final item in items) {
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Same rationale as createPurchaseInvoice: honour the form's
        // per-line taxAmount so editing a mixed invoice keeps exempt
        // rows at zero tax. Spec 151 E-03: round with the SAME expression as
        // the per-line INSERT below so SUM(line.tax) == header.tax exactly.
        final tax = FinancialUtils.round(item.taxAmount.present
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100));
        newTotal += subtotal + tax;
        newTaxTotal += tax;
      }

      // ح-1 (trade discount): the edit must produce the SAME shape as create —
      // header stored NET, line costs apportioned, and NO 4316 leg. Storing a
      // net `subtotal` also makes autoPostPurchase's _deriveBalancedLegs
      // compute discountLeg == 0 by construction, so the re-post debits
      // inventory net and credits only the payable.
      final effectiveDiscount = FinancialUtils.round(
          discount ?? oldInvoice.discount);
      final grossSubtotal = newTotal - newTaxTotal;
      if (effectiveDiscount > newTotal) {
        throw StateError(
          'الخصم (${effectiveDiscount.toStringAsFixed(2)}) أكبر من إجمالي '
          'الفاتورة (${newTotal.toStringAsFixed(2)}).',
        );
      }
      final editDiscountFactor = (effectiveDiscount > 0 && grossSubtotal > 0)
          ? (grossSubtotal - effectiveDiscount) / grossSubtotal
          : 1.0;
      newTotal = FinancialUtils.round(newTotal - effectiveDiscount);
      final netSubtotal = FinancialUtils.round(grossSubtotal - effectiveDiscount);

      final newRemaining = newTotal - paid;
      final newStatus = newRemaining <= 0
          ? 'paid'
          : (paid > 0 ? 'partial' : 'pending');

      // Update invoice header
      await (update(
        purchaseInvoices,
      )..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          warehouseId: Value(warehouseId),
          subtotal: Value(netSubtotal),
          discount: Value(effectiveDiscount),
          tax: Value(newTaxTotal),
          total: Value(newTotal),
          paid: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(newStatus),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
        ),
      );

      // Insert new items and update stock
      final newProductIds = items.map((i) => i.productId.present ? i.productId.value : 0)
          .where((id) => id > 0).toList();
      final newProductMap = await getProductsByIds(newProductIds);

      for (final item in items) {
        final productId = item.productId.present ? item.productId.value : 0;
        final quantity = item.quantity.present ? item.quantity.value : 1.0;
        // ح-1 (trade discount): apportion on the edit path too, so re-saving
        // never restores gross line costs into stock/WAC.
        final unitCost = FinancialUtils.round(
            (item.unitCost.present ? item.unitCost.value : 0.0) *
                editDiscountFactor);
        final taxRate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        // Spec 151 E-03: honour the passed per-line taxAmount (matching the
        // header loop above) instead of always recomputing from the rate, so an
        // exempt line (rate>0, amount=0) stores 0 tax — no phantom input VAT
        // for a later return to reverse — and SUM(line.tax) == header.tax.
        // Fallback-recompute only when no amount was supplied; round to the
        // financial precision.
        final taxAmount = FinancialUtils.round(item.taxAmount.present
            ? (item.taxAmount.value ?? 0.0)
            : (quantity * unitCost) * (taxRate / 100));

        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            unitCost: Value(unitCost),
            total: Value(quantity * unitCost + taxAmount),
            taxAmount: Value(taxAmount),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );

        // Update product stock (add new quantity)
        final product = newProductMap[productId];
        if (product != null && product.trackInventory) {
          // 1. Update WAC Cost with new values
          await updateProductWAC(
            productId: productId,
            newQuantity: quantity,
            newUnitCost: unitCost,
          );

          // 2. Adjust Stock
          // B10 (S-INV-COST / PUR-1): same gap as createPurchaseInvoice —
          // thread the edited line's real unitCost so the per-warehouse
          // average_cost blend uses the actual receipt cost, not whatever
          // updateProductWAC just wrote to the global costPrice.
          await adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: quantity,
            type: 'purchase',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            notes: 'تعديل فاتورة مشتريات #${oldInvoice.invoiceNumber}',
            unitCost: unitCost,
          );
        }

        // Create batch if expiry tracking
        if (product != null &&
            product.trackExpiry &&
            item.expiryDate.value != null) {
          await into(productBatches).insert(
            ProductBatchesCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              batchNumber: item.batchNumber.value ?? oldInvoice.invoiceNumber,
              quantity: Value(quantity),
              initialQuantity: Value(quantity),
              productionDate: item.productionDate,
              expiryDate: item.expiryDate.value!,
              unitCost: Value(unitCost),
              purchaseInvoiceId: Value(invoiceId),
            ),
          );
        }
      }

      // Update new supplier balance if on credit
      if (newRemaining > 0) {
        await adjustPartyBalance(supplierId, newRemaining);
      }

      // F-02 (Spec 151): re-record the treasury payment for the NEW `paid`
      // amount (the old payment safe_transaction(s) were reversed above). Uses
      // the SAME _recordPurchasePayment helper as createPurchaseInvoice:586-589
      // so the safe debit + safe_transaction row are identical in shape to a
      // fresh purchase — the safe now moves by exactly (newPaid − oldPaid).
      // F02-2: thread the original payment's safe so a payment made from a
      // non-default safe is re-recorded onto that SAME safe (not the global
      // default). Null when there was no prior payment → default resolution.
      SafeTransactionData? repostPaymentTxn;
      if (paid > 0) {
        repostPaymentTxn = await _recordPurchasePayment(
          invoiceId,
          paid,
          paymentMethod,
          costCenterId,
          safeId: originalPaymentSafeId,
          supplierId: supplierId,
        );
        // Same fail-loud contract as the create path: an edit that says "paid"
        // but moves no safe would leave the payable open with no trail.
        if (repostPaymentTxn == null) {
          throw StateError(
            'تعذّر تسجيل دفعة تعديل فاتورة المشتريات #$invoiceId: لا يوجد '
            'صندوق مطابق لطريقة الدفع.',
          );
        }
      }

      // F-02 (Spec 151): re-post the purchase GL entry with the NEW amounts.
      // autoPostPurchase reads the header we just updated, is dedup/TOCTOU-
      // guarded (the old JE was deleted above so this posts fresh), and builds a
      // balanced JE via the canonical path — exactly how updateFullSalesInvoice
      // re-posts through autoPostCashSale/autoPostCreditSale after deleting the
      // old sale JE. Balanced-by-construction; createJournalEntry hard-fails an
      // imbalance so a broken COA rolls the whole edit back (R3, fail-loud).
      final repostInvoice = await getPurchaseInvoiceById(invoiceId);
      if (repostInvoice != null && repostInvoice.total > 0) {
        await autoPostPurchase(
          repostInvoice,
          costCenterId: costCenterId ?? repostInvoice.costCenterId,
        );
      }

      // البند 6 — re-post the settlement leg for the NEW payment. The old
      // payment JE was reversed by _reverseOldPurchasePayment above, and
      // autoPostPurchase now credits the payable for the FULL total, so
      // without this the payable would stay open even though the safe moved.
      if (repostPaymentTxn != null) {
        final repostJeId = await accountingDao.autoPostPayment(
          repostPaymentTxn,
          costCenterId: costCenterId ?? repostInvoice?.costCenterId,
        );
        if (repostJeId == null) {
          throw StateError(
            'تعذّر ترحيل قيد سداد تعديل فاتورة المشتريات #$invoiceId: '
            'حساب الصندوق أو حساب الذمم غير مربوط في الدليل المحاسبي.',
          );
        }
      }
    });
  }

  /// F-02 (Spec 151): reverse the posted purchase JE for [invoiceId] by hard-
  /// deleting the entry + its lines and recomputing the affected accounts'
  /// balances from the POSTED lines that survive. Mirrors the GL-reversal step
  /// of updateFullSalesInvoice (the sales sibling). Called only from
  /// [updatePurchaseInvoice], already inside its transaction(); the subsequent
  /// autoPostPurchase re-posts the entry with the new amounts.
  ///
  /// Matches BOTH reference-type aliases a purchase JE can carry: the inline
  /// createPurchaseInvoice path stores 'purchase_invoice'; autoPostPurchase
  /// stores 'purchase'. Deleting both lets autoPostPurchase's dedup guard pass.
  Future<void> _reverseOldPurchaseJournalEntry(int invoiceId) async {
    final oldEntries = await (select(journalEntries)
          ..where((e) =>
              e.referenceType.isIn(kPurchaseJeReferenceTypes.toList()) &
              e.referenceId.equals(invoiceId) &
              e.isAutoPosted.equals(true)))
        .get();
    if (oldEntries.isEmpty) return;

    final affectedAccountIds = <int>{};
    for (final entry in oldEntries) {
      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();
      for (final l in lines) {
        affectedAccountIds.add(l.accountId);
      }
      await (delete(journalEntryLines)..where((l) => l.entryId.equals(entry.id)))
          .go();
      await (delete(journalEntries)..where((e) => e.id.equals(entry.id))).go();
    }

    // Recompute each affected account's balance from the POSTED lines that
    // survive the delete — the same self-healing Σdebit − Σcredit recompute
    // createJournalEntry and _updateAccountBalance use (is_posted = 1 filter).
    for (final accId in affectedAccountIds) {
      final result = await customSelect(
        'SELECT COALESCE(SUM(jel.debit),0) AS d, COALESCE(SUM(jel.credit),0) AS c '
        'FROM journal_entry_lines jel '
        'INNER JOIN journal_entries je ON je.id = jel.entry_id '
        'WHERE jel.account_id = ? AND je.is_posted = 1',
        variables: [Variable<int>(accId)],
        readsFrom: {journalEntryLines, journalEntries},
      ).getSingle();
      final d = (result.data['d'] as num).toDouble();
      final c = (result.data['c'] as num).toDouble();
      await (update(accounts)..where((a) => a.id.equals(accId)))
          .write(AccountsCompanion(balance: Value(d - c)));
    }
  }

  /// F-02 (Spec 151): reverse the ORIGINAL treasury payment(s) recorded for
  /// [invoiceId] by createPurchaseInvoice/_recordPurchasePayment/addPurchasePayment
  /// — restore each safe's balance, reverse the separate GL 'payment' JE (if
  /// any), and delete the payment safe_transaction row(s) — so
  /// [updatePurchaseInvoice] can re-record the payment for the new `paid` amount
  /// cleanly (delete-and-reapply: the same shape this edit already uses for the
  /// items and the base GL). Called only from updatePurchaseInvoice, inside its
  /// transaction(). No-op when the invoice had no payment.
  ///
  /// Returns the safeId of the FIRST original payment (or null when there was
  /// none) so the caller can re-record the new payment against the SAME safe
  /// (F02-2) instead of silently falling back to the global default safe — a
  /// payment made from a non-default safe would otherwise be reversed from the
  /// original safe but re-recorded to the default one (per-safe misallocation).
  ///
  /// Targets the purchase-payment rows (referenceType 'purchase_invoice',
  /// transactionType 'payment'); void reversals live under
  /// 'purchase_invoice_void' and are untouched.
  ///
  /// F02-1: a prior [addPurchasePayment] posts a SEPARATE, balanced GL 'payment'
  /// JE via autoPostPayment (referenceType 'payment', referenceId = this
  /// safe_txn.id, isAutoPosted=TRUE) — Dr payables(supplier) / Cr cash. The
  /// create-time down-payment does NOT (its cash leg lives inside the base
  /// purchase JE). If that 'payment' JE is left live while the re-post below
  /// credits cash again for the full invoice.paid, the payment is DOUBLE-COUNTED
  /// in the GL (cash credited twice, payables under-credited). So mirror-reverse
  /// it here (audit trail preserved), keyed on the UNIQUE safe_txn.id. Uses the
  /// shared reverser's default requireAutoPosted:true — autoPostPayment JEs are
  /// auto-posted, so the default is correct. All inside updatePurchaseInvoice's
  /// transaction() (R3), balanced by construction.
  Future<int?> _reverseOldPurchasePayment(int invoiceId) async {
    final oldPayments = await (select(safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    int? primarySafeId;
    for (final txn in oldPayments) {
      // F02-2: remember the FIRST original payment's safe so the re-record
      // lands back on the same safe.
      primarySafeId ??= txn.safeId;
      final safe = await (select(safes)..where((s) => s.id.equals(txn.safeId)))
          .getSingleOrNull();
      if (safe != null) {
        // The original payment DEBITED the safe (balance −= amount); restore it.
        // H15 — ردٌّ ذرّيّ: القراءةُ ثم الكتابة كانت تضيّع ردّاً موازياً.
        await adjustSafeBalance(safe.id, txn.amount);
      }
      // F02-1: reverse the separate GL 'payment' JE that addPurchasePayment
      // posted for THIS safe_txn (no-op for create-time down-payments, which
      // carry no such JE). Without this the base-JE re-post below double-counts
      // the cash/payables legs. safe_txn.globalId is null for these rows, so
      // qualify the deterministic reversal gid with the unique safe_txn id to
      // avoid a '<null>-rev' collision across multiple payments.
      final srcGid = txn.globalId ?? 'paytxn${txn.id}';
      await reverseAutoPostedJournalEntriesFor(
        referenceType: 'payment',
        referenceId: txn.id,
        voidReferenceType: 'payment_void',
        sourceGlobalId: srcGid,
        description: 'عكس قيد سداد (تعديل فاتورة مشتريات) #$invoiceId',
      );
      await (delete(safeTransactions)..where((t) => t.id.equals(txn.id))).go();
    }
    return primarySafeId;
  }

  /// Add payment to a purchase invoice.
  ///
  /// P2 (batch B7 / S-FAILLOUD): this used to move cash out of the safe
  /// (via [_recordPurchasePayment]) and mark the invoice more-paid WITHOUT
  /// ever posting a journal entry — the supplier payable in the GL never
  /// reduced, silently diverging from the treasury/party-balance side.
  /// Now posts a balanced payment JE (Dr payables sub-account / Cr cash-or-
  /// bank) via the existing [AccountingAutopostDao.autoPostPayment] — its
  /// 'purchase' category routing already does exactly this shape — inside
  /// the SAME transaction as the payment write, so a resolution failure
  /// rolls back the invoice.paid/status update and the safe transaction
  /// together instead of leaving a payment with no GL trace.
  Future<void> addPurchasePayment({
    required int invoiceId,
    required double amount,
    String paymentMethod = 'cash',
    int? safeId,
    int? userId,
    String? globalId,
  }) async {
    return transaction(() async {
      // Spec 151 C-03 idempotency: a payment is ADDITIVE, so an offline-outbox
      // replay or a mirror re-submit carrying the SAME globalId must NOT
      // double-apply (200 → 400 on retry, over-crediting the safe and
      // double-reducing payables). The payment's safe_transaction stamps this
      // globalId below, so if one already exists this event was applied →
      // return without touching paid/safe/JE. Dedup lives here (not only in the
      // HTTP handler) so BOTH the local path and the server handler are
      // idempotent. Inside the transaction so it can't race a concurrent apply.
      if (globalId != null && globalId.isNotEmpty) {
        final existing = await (select(safeTransactions)
              ..where((t) => t.globalId.equals(globalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) return;
      }

      final invoice = await getPurchaseInvoiceById(invoiceId);
      if (invoice == null) throw Exception('Invoice not found');

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'سداد دفعة مشتريات');

      final newPaid = invoice.paid + amount;
      final newRemaining = invoice.total - newPaid;
      final newStatus = newRemaining <= 0 ? 'paid' : 'partial';

      await (update(
        purchaseInvoices,
      )..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          paid: Value(newPaid),
          status: Value(newStatus),
        ),
      );

      final safeTxn = await _recordPurchasePayment(
        invoiceId, amount, paymentMethod, invoice.costCenterId,
        safeId: safeId,
        supplierId: invoice.supplierId,
        userId: userId,
        globalId: globalId,
      );

      // B7 (S-FAILLOUD): a payment must move cash AND post a balanced JE.
      // If no target safe resolved, nothing moved in treasury and no JE can
      // be posted — fail loud so the invoice.paid/status advance above rolls
      // back too, instead of leaving the invoice marked more-paid with no
      // cash movement and no GL trace (the same side-effect-without-JE class
      // this batch closes, previously left open for the no-safe config).
      if (safeTxn == null) {
        throw StateError(
          'تعذّر تسجيل دفعة المشتريات للفاتورة #${invoice.invoiceNumber}: '
          'لا يوجد صندوق/بنك محدد لصرف الدفعة منه. '
          'راجع إعدادات الصناديق قبل تسجيل الدفعة.',
        );
      }
      final jeId = await autoPostPayment(safeTxn, costCenterId: invoice.costCenterId);
      if (jeId == null) {
        throw StateError(
          'تعذّر ترحيل قيد سداد دفعة المشتريات للفاتورة #${invoice.invoiceNumber}: '
          'تحقق من ربط حساب الدائنون (الموردين) وحساب الصندوق/البنك '
          'في إعدادات الربط المحاسبي.',
        );
      }

      // Spec 151 (FIN-B-ACC-1) — decrement the supplier's cached parties.balance
      // so it stops OVERSTATING payables after a payment. Invoice create/edit/
      // void all maintain this denormalized balance; the payment path
      // historically did not (the asymmetry the Wave B committee caught vs the
      // sales-collection twin, which credits the customer's balance via
      // createReceiptVoucher). Inside the transaction → rolls back with the JE
      // on any failure; idempotent because the whole method dedups on globalId.
      await adjustPartyBalance(invoice.supplierId, -amount);
    });
  }

  /// Update payment amount for a purchase invoice (simple update)
  Future<void> updatePurchaseInvoicePayment(
    int invoiceId,
    double newPaid,
  ) async {
    final invoice = await getPurchaseInvoiceById(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    // 0. Soft/Hard Period Closing Gating
    await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'تعديل سداد مشتريات');

    final newRemaining = invoice.total - newPaid;
    final newStatus = newRemaining <= 0
        ? 'paid'
        : (newPaid > 0 ? 'partial' : 'pending');

    await (update(
      purchaseInvoices,
    )..where((i) => i.id.equals(invoiceId))).write(
      PurchaseInvoicesCompanion(paid: Value(newPaid), status: Value(newStatus)),
    );
  }

  /// Update purchase invoice status intentionally (e.g. for returns)
  Future<void> updatePurchaseInvoiceStatus(int invoiceId, String status) async {
    await (update(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).write(
      PurchaseInvoicesCompanion(status: Value(status)),
    );
  }

  /// Void a purchase invoice (ISS-05: void instead of hard delete)
  /// Preserves the invoice for audit trail, reverses stock and treasury
  /// [deletedBy]: userId of the operator performing the void (PIR P0-01 audit trail).
  /// [globalId]: PR-2 (pre-deploy batch B6) — the void operation's identity,
  /// minted once by the caller and threaded into both the server submit and
  /// this method's reversal JE (R9). When omitted, the reversal JE derives a
  /// deterministic id from the invoice's own globalId + verb 'void' (same
  /// `JournalEntryGid.compute` pattern the landed-cost reversal below uses),
  /// so client-mode retries and the standalone path both converge on the
  /// same JE identity without needing an explicit value.
  Future<void> voidPurchaseInvoice(int invoiceId, {String? reason, int? deletedBy, String? globalId}) async {
    await transaction(() async {
      final invoice = await getPurchaseInvoiceById(invoiceId);
      if (invoice == null) return;

      if (invoice.status == 'voided') {
        throw Exception('الفاتورة ملغية بالفعل');
      }

      // 062 (D1-004): voidPaidInvoice gate for purchase invoices.
      final isPaidInFull = invoice.paid >= invoice.total - 0.01;
      if (isPaidInFull) {
        await permissionEnforcer.requireCriticalOp(
          userId: deletedBy,
          code: PermissionCodes.voidPaidInvoice,
          arabicReason: 'لا يمكن إلغاء فاتورة مشتريات مدفوعة بالكامل — '
              'يلزم صلاحية "إلغاء فاتورة مدفوعة".',
        );
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'إلغاء فاتورة مشتريات');

      final items = await getPurchaseInvoiceItems(invoiceId);
      final productMap = await getProductsByIds(items.map((i) => i.productId).toList());
      for (final item in items) {
        final product = productMap[item.productId];
        if (product != null && product.trackInventory) {
          await adjustStock(
            productId: item.productId,
            warehouseId: invoice.warehouseId,
            quantity: -item.quantity,
            type: 'void_reversal',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            unitCost: item.unitCost,
            notes: 'إلغاء فاتورة مشتريات #${invoice.invoiceNumber}',
          );
          // B8 (S-LANDED-LIFECYCLE / PUR-2a): the WAC recalc used to run
          // right here, but at this point the invoice is still 'active'
          // (the status flip happens near the end of this method) and any
          // applied landed-cost sheet is still 'applied' (its reversal runs
          // further below too) — recalculateProductWAC's PR-1 fix filters
          // on BOTH, so recalculating this early would still count this
          // void's own purchase cost and landed allocation, a no-op in
          // disguise. The real recalc now runs once, after every status
          // flip below, so it actually excludes them.
        }
      }

      // Reverse treasury transactions
      final treasuryTxns = await (select(safeTransactions)..where(
            (t) =>
                t.referenceType.equals('purchase_invoice') &
                t.referenceId.equals(invoiceId),
          )).get();

      final txnSafeIds = treasuryTxns.map((t) => t.safeId).toSet().toList();
      final safeList = await (select(safes)..where((s) => s.id.isIn(txnSafeIds))).get();
      final safeMap = {for (final s in safeList) s.id: s};

      // البند 6 / regression guard: since the purchase JE stopped carrying the
      // cash leg (it now credits the payable in full and the settlement is a
      // SEPARATE `referenceType:'payment'` JE posted by autoPostPayment), the
      // void below — which only mirrors the purchase JE — no longer undoes the
      // cash movement. Left unreversed it produced a phantom AP DEBIT and left
      // GL cash permanently below `safes.balance` by the paid amount.
      //
      // Reverse the settlement JE per payment transaction. Same call
      // `_reverseOldPurchasePayment` uses on the edit path — but here we must
      // NOT touch `safes.balance`, because the treasury loop below already
      // restores it via its own reversal transactions.
      for (final txn in treasuryTxns) {
        if (txn.transactionType != 'payment') continue;
        await reverseAutoPostedJournalEntriesFor(
          referenceType: 'payment',
          referenceId: txn.id,
          voidReferenceType: 'payment_void',
          sourceGlobalId: txn.globalId ?? 'paytxn${txn.id}',
          description: 'عكس قيد سداد (إلغاء فاتورة مشتريات) #$invoiceId',
        );
      }

      for (final txn in treasuryTxns) {
        final safe = safeMap[txn.safeId];
        if (safe != null) {
          final reverseAmount = txn.transactionType == 'payment'
              ? txn.amount
              : -txn.amount;
          final newBalance = safe.balance + reverseAmount;
          final voucherNumber = await generateInvoiceNumber('VD');

          await into(safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucherNumber,
              safeId: safe.id,
              transactionType: txn.transactionType == 'payment' ? 'receipt' : 'payment',
              category: 'void',
              amount: txn.amount,
              balanceAfter: newBalance,
              referenceType: const Value('purchase_invoice_void'),
              referenceId: Value(invoiceId),
              description: Value('عكس حركة إلغاء فاتورة مشتريات #${invoice.invoiceNumber}'),
            ),
          );
          // H15 — عكسٌ ذرّيّ بمقدار `reverseAmount` (موجبٌ للسداد المعكوس،
          // سالبٌ لغيره). `newBalance` لقطةُ `balanceAfter` وحدَها.
          await adjustSafeBalance(safe.id, reverseAmount);
        }
      }

      // Reverse supplier balance
      final remaining = invoice.total - invoice.paid;
      if (remaining > 0) {
        await adjustPartyBalance(invoice.supplierId, -remaining);
      }

      // Create reversal journal entry if one was posted.
      //
      // The `invoice.isLocked` gate that used to wrap this was dead-wrong:
      // `createPurchaseInvoice` posts its JE inline and NEVER sets `isLocked`
      // (only autoPostPurchase / AutoPostingService do). So voiding any
      // invoice created from the purchases screen skipped the reversal
      // entirely — stock was returned and the safe restored while the
      // inventory GL account kept the full debit against zero stock, and the
      // supplier payable kept its credit. Pre-existing; surfaced by the void
      // regression test added with the البند 6 pass-through work.
      //
      // The lookup below already keys on referenceType + referenceId +
      // isAutoPosted, so "was anything posted?" is answered by whether it
      // finds a row — the flag added nothing but the bug.
      {
        try {
          final originalJE = await (select(journalEntries)
                ..where((e) =>
                    e.referenceType
                        .isIn(kPurchaseJeReferenceTypes.toList()) &
                    e.referenceId.equals(invoice.id) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();

          if (originalJE != null) {
            final originalLines = await (select(journalEntryLines)
                  ..where((l) => l.entryId.equals(originalJE.id)))
                .get();

            final reversalLines = originalLines.map((line) => JournalLine(
                  accountId: line.accountId,
                  debit: line.credit,
                  credit: line.debit,
                  description: 'عكس: ${line.description ?? ""}',
                )).toList();

            if (reversalLines.isNotEmpty) {
              // H-09 FIX: Get branchId from warehouse to ensure financial isolation
              final warehouse = await getWarehouseById(invoice.warehouseId);
              final branchId = warehouse?.branchId;

              // PR-2 (batch B6) / R9: deterministic globalId so this reversal
              // JE converges across client/mirror + server instead of each
              // side minting its own random id (which would survive DeltaPull
              // as two rows). Prefer the caller-supplied [globalId] (threaded
              // from the same value sent to the server submit); fall back to
              // deriving one from the invoice's own globalId — mirrors the
              // landed-cost reversal a few lines below.
              final voidJeGid = (globalId != null && globalId.isNotEmpty)
                  ? globalId
                  : JournalEntryGid.compute(
                      sourceType: JournalEntryGid.sourcePurchase,
                      sourceGid: invoice.globalId ?? 'invid$invoiceId',
                      verb: 'void',
                    );

              await accountingDao.createJournalEntry(
                description: 'قيد عكسي — إلغاء فاتورة مشتريات ${invoice.invoiceNumber}${reason != null ? " ($reason)" : ""}',
                date: DateTime.now(),
                lines: reversalLines,
                referenceType: 'purchase_invoice_void',
                referenceId: invoiceId,
                isAutoPosted: true,
                costCenterId: invoice.costCenterId,
                branchId: branchId,
                globalId: voidJeGid,
              );
            }
          }
        } catch (e, st) {
          // B7 (S-FAILLOUD / PUR-4): this used to be non-blocking — the
          // reversal JE's failure was logged and swallowed while the void
          // proceeded to reverse stock/treasury/supplier-balance and flip
          // the invoice to 'voided' anyway. That leaves the ORIGINAL
          // purchase JE live in the GL with none of its financial effects
          // reflected anywhere else (inventory reversed, GL untouched) — a
          // financial side-effect with no balanced counter-entry, and the
          // caller saw a false "void succeeded". Log to the audit trail for
          // visibility (best-effort — see inner catch), then RETHROW so the
          // whole transaction (stock reversal, treasury reversal, supplier-
          // balance reversal, invoice status flip) rolls back atomically.
          // Note: because this insert shares the SAME db.transaction() that
          // is about to roll back, it is rolled back too — the debugPrint
          // above is therefore the durable trace for this failure; the
          // logActivity call is kept for the (rare) case a future refactor
          // moves it off this connection, and as a hint in case a partial
          // commit is ever observed.
          debugPrint('[ISS-05] Purchase reversal JE failed — logging to audit trail: $e\n$st');
          try {
            await logActivity(
              userId: deletedBy ?? 0,
              userName: 'System',
              action: 'accounting_warning',
              entityType: 'purchase_invoice',
              entityId: invoiceId,
              description:
                  '[P1-02] فشل القيد العكسي عند إلغاء فاتورة المشتريات #${invoice.invoiceNumber}: $e',
            );
          } catch (_) {} // logActivity failure must NEVER mask the original error
          rethrow;
        }
      }

      // S-COST-2 (Spec 145): reverse any APPLIED landed-cost sheet's JE so the
      // capitalized freight/customs does not linger in the inventory GL after
      // the void, and un-apply the sheet. Independent of invoice.isLocked — a
      // landed JE exists whenever the sheet was applied.
      final landedSheets =
          await getLandedCostSheets(purchaseInvoiceId: invoiceId);
      for (final sheet in landedSheets.where((s) => s.status == 'applied')) {
        try {
          final landedJE = await (select(journalEntries)
                ..where((e) =>
                    e.referenceType.equals('landed_cost') &
                    e.referenceId.equals(sheet.id) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();
          if (landedJE != null) {
            final lines = await (select(journalEntryLines)
                  ..where((l) => l.entryId.equals(landedJE.id)))
                .get();
            final reversalLines = lines
                .map((l) => JournalLine(
                      accountId: l.accountId,
                      debit: l.credit,
                      credit: l.debit,
                      description: 'عكس: ${l.description ?? ""}',
                    ))
                .toList();
            if (reversalLines.isNotEmpty) {
              final warehouse = await getWarehouseById(invoice.warehouseId);
              await accountingDao.createJournalEntry(
                description:
                    'عكس تكاليف محملة ${sheet.sheetNumber} — إلغاء فاتورة #${invoice.invoiceNumber}',
                date: DateTime.now(),
                lines: reversalLines,
                referenceType: 'landed_cost_void',
                referenceId: sheet.id,
                isAutoPosted: true,
                costCenterId: invoice.costCenterId,
                branchId: warehouse?.branchId,
                globalId: JournalEntryGid.compute(
                  sourceType: JournalEntryGid.sourceLandedCost,
                  sourceGid: 'sheet${sheet.id}',
                  verb: 'void',
                ),
              );
            }
          }
          // B7 (S-FAILLOUD / PUR-4): only flip the sheet to 'voided' AFTER
          // its reversal JE has actually posted (or there was genuinely
          // nothing to reverse — landedJE == null / no lines). Previously
          // this write ran unconditionally after the try/catch, so a sheet
          // whose reversal JE failed still got marked voided — the
          // capitalized freight/customs stayed live in the inventory GL
          // while the sheet record claimed it had been reversed.
          await (update(landedCostSheets)..where((s) => s.id.equals(sheet.id)))
              .write(const LandedCostSheetsCompanion(status: Value('voided')));
        } catch (e) {
          // B7: was non-blocking (log + swallow, sheet still flipped below).
          // Now rethrows — see the purchase-reversal catch above for the
          // full rationale (no financial side-effect may survive with its
          // counter-entry missing). The sheet status update above is
          // skipped on this path since it sits inside the try, after the
          // post, so a failed reversal leaves the sheet 'applied' — honest
          // about the fact its JE was never reversed.
          debugPrint(
              '[S-COST-2] landed reversal failed for sheet ${sheet.id}: $e');
          try {
            await logActivity(
              userId: deletedBy ?? 0,
              userName: 'System',
              action: 'accounting_warning',
              entityType: 'purchase_invoice',
              entityId: invoiceId,
              description:
                  'فشل عكس قيد التكاليف المحمّلة ${sheet.sheetNumber} عند إلغاء الفاتورة #${invoice.invoiceNumber}: $e',
            );
          } catch (_) {}
          rethrow;
        }
      }

      // Mark invoice as voided and soft-deleted (Phase 4)
      // PIR P0-01: record deletedBy for audit trail
      await (update(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          status: const Value('voided'),
          notes: Value('${invoice.notes ?? ""}\n[ملغي] ${reason ?? "بدون سبب"} - ${DateTime.now().toIso8601String()}'),
          isLocked: const Value(true),
          isDeleted: const Value(true),
          deletedAt: Value(DateTime.now()),
          deletedBy: Value(deletedBy),
        ),
      );

      // B8 (S-LANDED-LIFECYCLE / PUR-2a): recalc WAC HERE — after BOTH the
      // invoice header is marked 'voided'/isDeleted (just above) AND the
      // landed-cost sheet(s), if any, were flipped away from 'applied'
      // (the loop above). recalculateProductWAC's PR-1 fix excludes both a
      // voided invoice's own purchase lines and its landed allocation, so
      // running it only now actually unwinds the void's cost impact — one
      // call per affected product (dedup: an invoice can repeat a product
      // across multiple lines).
      final affectedProductIds = items.map((i) => i.productId).toSet();
      for (final pid in affectedProductIds) {
        final product = productMap[pid];
        if (product != null && product.trackInventory) {
          await recalculateProductWAC(pid);
        }
      }
    });
  }

  /// Legacy delete — redirects to void for backward compatibility
  Future<void> deletePurchaseInvoice(int invoiceId, {int? deletedBy}) async {
    await voidPurchaseInvoice(invoiceId, reason: 'حذف (تم تحويله إلى إلغاء)', deletedBy: deletedBy);
  }

  /// إجمالياتُ فواتير المشتريات في نافذةٍ ونطاقٍ — من SQL على **كلّ** الصفوف
  /// المطابِقة لا على الصفحة المحمَّلة.
  ///
  /// نظيرُ [getSalesInvoiceSummary]، وثلاثةُ فروقٍ **مقيسةٌ لا منسوخة**:
  ///
  /// ١. **عدّاداتُ الحالة على عمود `status`** لا على `paid >= total`.
  ///    مرشِّحُ الشاشة (`_applyFilters`) يقارن `inv.status`، وهو مشتقٌّ من
  ///    العمود عبر `InvoiceEntity._mapStatus`. والعدُّ بالمبلغ كان سيعطي
  ///    شريحةً رقمُها لا يطابق ما تعرضه حين تُنقَر.
  ///
  /// ٢. **«غيرُ المسدَّد» يُعَدُّ بالنفي** — حالةُ الافتراض في `_mapStatus`.
  ///    فأيُّ `status` مجهولٍ أو `NULL` يقع فيها، ومجموعُ الثلاثةِ يبقى
  ///    ≤ [PurchaseInvoiceSummary.invoiceCount] بلا صفٍّ يسقط من العدّ
  ///    (‏`cancelled` و`returned` و`draft` و`partial_return` لا تُعَدُّ في
  ///    أيٍّ من الثلاثة — تماماً كما لا يُظهرها أيُّ مرشِّح).
  ///
  /// ٣. **المرتجعاتُ تُنسَب لنافذةِ الفاتورة الأصليّة** لا لتاريخِ المرتجع —
  ///    بخلاف المبيعات. لأن `_applyFilters` يجمعها هكذا بالضبط
  ///    (‏`filtered.fold(… returnedAmounts[inv.id])`)، فلو نُسبت لتاريخِ
  ///    حدوثها لخالفت البطاقةُ مجموعَ الصفوفِ تحتها — وهو العطبُ عينُه الذي
  ///    عولج في جانب المبيعات.
  Future<PurchaseInvoiceSummary> getPurchaseInvoiceSummary({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    int? branchId,
    int? costCenterId,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(to.year, to.month, to.day + 1);
    final boolFalse = sqlBool(false);

    // يُبنى مرّتين — مرّةً للفواتير بلا بادئةٍ ومرّةً للمرتجعات ببادئة `pi.`
    // — والمتغيّراتُ تُملأ بنفس الترتيب في كلٍّ منهما.
    (String, List<Variable>) scopeFor(String p) {
      final vars = <Variable>[dateVar(start), dateVar(endExclusive)];
      var sql = '${p}is_deleted = $boolFalse '
          'AND ${p}invoice_date >= ? AND ${p}invoice_date < ?';
      if (warehouseIds != null) {
        if (warehouseIds.isEmpty) {
          sql += ' AND 1 = 0';
        } else {
          sql += ' AND ${p}warehouse_id IN '
              '(${warehouseIds.map((_) => '?').join(', ')})';
          vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
        }
      }
      if (branchId != null) {
        // الشقُّ الثاني ليس زخرفاً: `_applyFilters` يقبل الصفَّ إذا طابق
        // `branch_id` **أو** كان مخزنُه تابعاً للفرع (صفوفٌ قديمةٌ سابقةٌ
        // لعمود L3 تحمل `NULL`). و`branch_id = ?` وحدَه كان سيُسقطها من
        // البطاقة وهي معروضةٌ في القائمة.
        sql += ' AND (${p}branch_id = ? OR (${p}branch_id IS NULL AND '
            '${p}warehouse_id IN '
            '(SELECT id FROM warehouses WHERE branch_id = ?)))';
        vars.add(Variable<int>(branchId));
        vars.add(Variable<int>(branchId));
      }
      if (costCenterId != null) {
        sql += ' AND ${p}cost_center_id = ?';
        vars.add(Variable<int>(costCenterId));
      }
      return (sql, vars);
    }

    final (invScope, invVars) = scopeFor('');

    // الحالاتُ المعروفةُ في `_mapStatus` — تُذكَر مرّةً هنا وتُنفى في
    // `n_unpaid` كي لا ينحرف الطرفان.
    const known =
        "('paid','completed','partial','cancelled','draft','returned',"
        "'partial_return')";

    final head = await customSelect(
      'SELECT COUNT(*) AS n, '
      'COALESCE(SUM(total), 0) AS total, '
      'COALESCE(SUM(paid), 0) AS paid, '
      "SUM(CASE WHEN LOWER(status) IN ('paid','completed') "
      'THEN 1 ELSE 0 END) AS n_paid, '
      "SUM(CASE WHEN LOWER(status) = 'partial' "
      'THEN 1 ELSE 0 END) AS n_partial, '
      'SUM(CASE WHEN status IS NULL OR LOWER(status) NOT IN $known '
      'THEN 1 ELSE 0 END) AS n_unpaid '
      'FROM purchase_invoices WHERE $invScope',
      variables: invVars,
      readsFrom: {purchaseInvoices},
    ).getSingle();

    // المرتجعاتُ بنفسِ صيغةِ [getPurchaseReturnedAmountsForInvoices] حرفاً
    // بحرف (‏`ABS(quantity) * unit_cost` بلا `COALESCE` على العامل) كي
    // يبقى مجموعُ البطاقة هو مجموعَ ما تطرحه الصفوفُ من «المتبقي».
    final (retScope, retVars) = scopeFor('pi.');
    final returns = await customSelect(
      'SELECT COALESCE(SUM(ABS(sm.quantity) * sm.unit_cost), 0) AS total '
      'FROM stock_movements sm '
      'JOIN purchase_invoices pi ON pi.id = sm.reference_id '
      "WHERE sm.reference_type = 'purchase_return' AND $retScope",
      variables: retVars,
      readsFrom: {stockMovements, purchaseInvoices},
    ).getSingle();

    double num_(String k, Map<String, dynamic> d) =>
        (d[k] as num?)?.toDouble() ?? 0.0;
    int int_(String k, Map<String, dynamic> d) => (d[k] as num?)?.toInt() ?? 0;

    return PurchaseInvoiceSummary(
      invoiceCount: int_('n', head.data),
      totalAmount: num_('total', head.data),
      totalPaid: num_('paid', head.data),
      totalReturns: num_('total', returns.data),
      paidCount: int_('n_paid', head.data),
      partialCount: int_('n_partial', head.data),
      unpaidCount: int_('n_unpaid', head.data),
    );
  }
}

