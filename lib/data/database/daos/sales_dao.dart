// ═══════════════════════════════════════════════════════════════════════════
// SALES DAO - Sales Invoice and Related Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all sales-related database operations extracted from
// the main database.dart file for better organization and maintainability.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// البند 3 — الصيغة الوحيدة التي تربط صف المرتجع بفاتورته الأصلية.
///
/// There is no FK column for this link: `getReturnedAmountsForInvoices` parses
/// the id out of the invoice `notes` text. Every writer of a return row MUST
/// use this helper so the reader and the writers cannot drift apart — the
/// server handler, the standalone path and the client's local cache row all
/// go through it.
///
/// The id passed must be the one meaningful IN THE STORE BEING WRITTEN: the
/// server writes its own resolved id, the client writes its local id.
///
/// FOLLOW-UP (not done): replace the whole scheme with a real
/// `sales_invoices.original_invoice_id` column. That needs a schema migration,
/// a code-gen pass and sync-strategy changes, so it is left as a separate
/// piece of work; this helper closes the correctness gap without touching the
/// schema.
/// [originalGlobalId], when supplied, is appended as `|gid:<uuid>` and becomes
/// the AUTHORITATIVE half of the link.
///
/// Why: the numeric id is only meaningful in the store that wrote it. The
/// server writes ITS id; DeltaPull then replaces the client's cached return row
/// wholesale (serverWins), so the client ends up holding a server id and reads
/// it against LOCAL ids — netting the refund off the wrong invoice, or none.
/// The UUID is stable across every store, so the reader resolves by gid first
/// and only falls back to the number for rows written before this format.
String localReturnLinkNote(int originalInvoiceId, {String? originalGlobalId}) {
  final base = 'Return for invoice #$originalInvoiceId';
  if (originalGlobalId == null || originalGlobalId.isEmpty) return base;
  return '$base|gid:$originalGlobalId';
}

/// صف واحد في «سجل مرتجع المبيعات».
///
/// A sales return is persisted in one of two mutually exclusive shapes (see
/// the doc on [SalesDao.getReturnedAmountsForInvoices]): either as a separate
/// `sale_type='return'` invoice row (server API / mirror cache / POS), or as a
/// status flip on the ORIGINAL invoice plus `safe_transactions` rows (the
/// standalone path that the sales-returns SCREEN itself runs). This entry
/// normalises both so the UI does not have to care which one it is looking at.
class SalesReturnHistoryEntry {
  /// The row to display — the return document (shape B) or the flipped
  /// original (shape A).
  final SalesInvoiceData invoice;

  /// The id to pass to `getSalesReturnItemDetails` / reprint helpers. Always
  /// the ORIGINAL invoice's local id, because that is what
  /// `stock_movements.reference_id` and `safe_transactions.reference_id` hold.
  final int originalInvoiceId;

  /// The ORIGINAL invoice row, when it is resolvable locally. This — not
  /// [invoice] — is what `cancelSalesReturn` must be handed: it reverses stock
  /// movements, safe transactions and JEs keyed on the ORIGINAL invoice's id
  /// and resets that invoice's status. Null only when the return document's
  /// link is unresolvable (a POS quick-return has no original at all).
  final SalesInvoiceData? originalInvoice;

  /// The original invoice's human number, for the list title.
  final String originalInvoiceNumber;

  /// The amount actually refunded — never the original invoice's total.
  final double returnAmount;

  /// The original invoice's total, shown alongside [returnAmount] the same way
  /// the purchase-returns history does.
  final double originalInvoiceTotal;

  /// `true` when the whole invoice was returned (`status='returned'`).
  final bool isFullReturn;

  /// `true` when [invoice] is a standalone return document (shape B).
  final bool isReturnDocument;

  const SalesReturnHistoryEntry({
    required this.invoice,
    required this.originalInvoiceId,
    required this.originalInvoice,
    required this.originalInvoiceNumber,
    required this.returnAmount,
    required this.originalInvoiceTotal,
    required this.isFullReturn,
    required this.isReturnDocument,
  });
}

/// ح-2 + البند 2 — نتيجة تجميع بطاقات شاشة فواتير المبيعات، محسوبة في SQL.
class SalesInvoiceSummary {
  /// عدد فواتير البيع **المطابقة** (لا المحمَّلة على الشاشة).
  final int invoiceCount;

  /// إجمالي المبيعات — شامل الضريبة والتوصيل، بعد خصم السطور، قبل المرتجعات.
  final double totalAmount;

  /// المحصّل من الفواتير نفسها (لا يشمل سندات القبض المستقلة).
  final double totalPaid;

  /// إجمالي المرتجعات في نفس المدى والنطاق.
  final double totalReturns;

  /// عددُ الفواتير المدفوعةِ بالكامل في نفس المدى والنطاق.
  ///
  /// الثلاثةُ تُحسَب في **نفس** استعلام الإجماليات، ومجموعُها
  /// [invoiceCount] بالضبط: الحدودُ متتابعةٌ لا متداخلة
  /// (‏`paid >= total` ثمّ `0 < paid < total` ثمّ `paid <= 0`).
  final int paidCount;

  /// عددُ الفواتير المدفوعةِ جزئيّاً.
  final int partialCount;

  /// عددُ الفواتير غيرِ المدفوعة.
  final int unpaidCount;

  const SalesInvoiceSummary({
    required this.invoiceCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalReturns,
    this.paidCount = 0,
    this.partialCount = 0,
    this.unpaidCount = 0,
  });

  /// البند 2 — «صافي المبيعات» الذي طلبه العميل صراحةً.
  double get netSales => totalAmount - totalReturns;

  /// المتبقي على العملاء = الإجمالي − المحصّل − المرتجعات.
  double get totalRemaining => totalAmount - totalPaid - totalReturns;
}

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
  ///
  /// ── Return-exclusion + warehouse scoping added ────────────────────────
  /// Its three siblings ([watchTodaySales], [getTodaySales], [watchSalesSince])
  /// all exclude returns and all accept [warehouseIds]; this one did neither.
  /// The asymmetry was invisible while the previous-invoices dialog only
  /// LISTED rows, but that dialog now sums them into a total, and a cashier
  /// with no open shift falls back to exactly this stream — so return
  /// invoices were about to be added into a "sales" figure, overstating it.
  Stream<List<SalesInvoiceData>> watchTodaySalesForUser(
    int userId, {
    List<int>? warehouseIds,
  }) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (i) =>
            i.invoiceDate.isBetween(
              Variable(startOfDay),
              Variable(endOfDay),
            ) &
            i.userId.equals(userId) &
            i.isDeleted.equals(false) &
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

  /// Watch the single most recent sale invoice belonging to [userId].
  ///
  /// Feeds the PicPos invoice header and its «الفاتورة السابقة» dialog. The
  /// product owner was explicit that a cashier recalling their last invoice
  /// must get THEIR OWN — not a copy another terminal or another user pushed
  /// to the server — hence the mandatory `userId` scope rather than a plain
  /// "newest invoice" query.
  ///
  /// Predicate copied from [watchSalesSince] deliberately: non-deleted, and
  /// returns excluded (a sales return is not "the last invoice I sold").
  ///
  /// The `id` tiebreaker on top of `invoiceDate` is not cosmetic — two sales
  /// inside the same second are routine on a busy till, and `invoiceDate`
  /// alone is not a total order, so without it the "last" invoice would flip
  /// between two rows at random.
  Stream<SalesInvoiceData?> watchLastInvoiceForUser(
    int userId, {
    DateTime? since,
    List<int>? warehouseIds,
  }) {
    final query = select(salesInvoices)
      ..where(
        (i) =>
            i.userId.equals(userId) &
            i.isDeleted.equals(false) &
            (i.saleType.equals('return').not() | i.saleType.isNull()),
      )
      ..orderBy([
        (i) => OrderingTerm.desc(i.invoiceDate),
        (i) => OrderingTerm.desc(i.id),
      ])
      ..limit(1);
    if (since != null) {
      query.where((i) => i.invoiceDate.isBiggerOrEqualValue(since));
    }
    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where((i) => i.warehouseId.isIn(warehouseIds));
    }
    return query.watchSingleOrNull();
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
    /// يستثني الصفوف اللي **مش إيراد**: مستندات المرتجع (saleType='return')
    /// والفواتير الملغية/المعدومة والأصول اللي اترجّعت.
    ///
    /// موجود كمعامل اختياري لأن الدالة دي مشتركة: returns_repository_impl
    /// بينديها عشان يلاقي فاتورة يرجّعها (ومحتاج يشوف المكتملة والمُرجَعة)،
    /// و tax_report_screen للقائمة التفصيلية. تغيير الدلالة عامةً كان هيكسر
    /// مسار المرتجعات.
    ///
    /// تقرير المبيعات بيطلبه عشان جمع عمود الجدول يطابق بطاقة «إجمالي
    /// المبيعات» — البطاقة بتنده getSalesAnalytics اللي بيستثني التلاتة دول
    /// أصلاً، فمن غير المعامل ده الكارت بيقول ١٠٠٬٠٠٠ وجمع Excel ١٠٨٬٠٠٠.
    bool revenueOnly = false,

    /// H8 · يستبعد **الملغى/المعدوم فقط** ويُبقي مستنداتِ المرتجع.
    ///
    /// تقريرُ الضريبة يحتاج هذا تحديداً ولا يصلح له [revenueOnly]: بطاقةُ
    /// التقرير تقرأ من **الأستاذ** (حسابا الضريبة) فتحمل عكسَ ضريبة المخرجات
    /// سالباً وتستبعد الملغى، بينما القائمةُ التفصيلية كانت تقرأ صفوفَ
    /// الفواتير خاماً ⇒ تجمع الملغى وتجمع المرتجعَ **موجباً** بدل أن تطرحه.
    ///
    /// و[revenueOnly] يُسقط المرتجعَ كذلك، فيختفي العكسُ من التفصيل بينما
    /// البطاقةُ تحتسبه — فجوةٌ جديدةٌ في الاتجاه المعاكس على إقرارٍ ضريبيّ.
    bool excludeVoided = false,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    // H7 (نفسُ العائلة) · نهايةُ المدى هي منتصفُ ليل اليوم التالي، فلا بدّ من
    // مدىً **نصفِ مفتوح**: `isBetween` شاملُ الطرفين ⇒ فاتورةُ الحدّ تُحتسب
    // في مدّتين متجاورتين.
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));

    final query = select(salesInvoices)
      ..where(
        (s) => s.invoiceDate.isBiggerOrEqualValue(start) &
               s.invoiceDate.isSmallerThanValue(end) &
               s.isDeleted.equals(false),
      );

    // نفس استثناءات getSalesAnalytics بالظبط (sales_analytics_dao) — أي انحراف
    // بينهم بيرجّع نفس العطل: كارت وجدول بيجاوبوا سؤالين تحت عنوان واحد.
    if (revenueOnly) {
      query.where((s) => s.saleType.isNull() | s.saleType.equals('return').not());
      query.where(
          (s) => s.status.isIn(const ['returned', 'cancelled', 'voided']).not());
    } else if (excludeVoided) {
      query.where((s) => s.status.isIn(const ['cancelled', 'voided']).not());
    }

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

  /// «سجل مرتجع المبيعات» — every sales return in the window, whichever of
  /// the two storage shapes it was written in.
  ///
  /// Why this exists on top of [getSalesReturns]: that query matches only
  /// `sale_type='return' OR total < 0`, i.e. shape B (a separate return
  /// DOCUMENT, written by the server API handler, the client mirror cache and
  /// the POS quick-return). The sales-returns SCREEN's own standalone path
  /// (`processSalesReturn`) writes shape A instead — it flips the ORIGINAL
  /// invoice to `returned` / `partial_return` and records the refund in
  /// `safe_transactions(reference_type='sales_return')` — and creates no
  /// return document at all. So on a standalone/server install the history
  /// dialog fed by [getSalesReturns] was always empty, while the purchases
  /// dialog (which keys off the ORIGINAL invoice's status) listed everything.
  /// This method matches both shapes, which is the parity the purchases side
  /// has had all along.
  ///
  /// Dedup: when a return document exists, its original has ALSO been flipped
  /// (both the server handler and the mirror path do that), so the original is
  /// dropped from the result — otherwise every client-mode return would be
  /// listed twice. The link is the `notes` text written by
  /// [localReturnLinkNote], resolved by `|gid:` first and by the raw id only
  /// for rows written before that format — same precedence as
  /// [getReturnedAmountsForInvoices].
  ///
  /// [allowedBranchIds] follows the Spec 151 Track-3 contract: null = no cap,
  /// {} = fail-closed, {ids} = those branches OR NULL-branch rows.
  /// معرّفاتُ الفواتير التي **سُجِّل لها استردادٌ** داخل النافذة.
  ///
  /// في المسار المستقلّ هذا هو الأثرُ الوحيد الذي يحمل **تاريخ المرتجع**:
  /// `safe_transactions(reference_type='sales_return')` و`reference_id`
  /// معرّفُ الفاتورة الأصلية.
  Future<List<int>> _invoiceIdsRefundedBetween(
      DateTime start, DateTime end) async {
    final rows = await customSelect(
      'SELECT DISTINCT reference_id AS id FROM safe_transactions '
      "WHERE reference_type = 'sales_return' "
      'AND deleted_at IS NULL '
      'AND reference_id IS NOT NULL '
      'AND created_at >= ? AND created_at < ?',
      variables: [dateVar(start), dateVar(end)],
      readsFrom: {safeTransactions},
    ).get();
    return [for (final r in rows) r.data['id'] as int];
  }

  Future<List<SalesReturnHistoryEntry>> getSalesReturnHistoryEntries(
    DateTime startDate,
    DateTime endDate, {
    int limit = 500,
    Set<int>? allowedBranchIds,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));

    void applyBranchCap(SimpleSelectStatement<$SalesInvoicesTable, SalesInvoiceData> q) {
      if (allowedBranchIds == null) return;
      if (allowedBranchIds.isEmpty) {
        q.where((s) => s.branchId.isIn(const <int>[]));
      } else {
        q.where((s) => s.branchId.isIn(allowedBranchIds) | s.branchId.isNull());
      }
    }

    // ── Shape B: standalone return documents ────────────────────────────────
    final docQuery = select(salesInvoices)
      ..where(
        (s) =>
            s.invoiceDate.isBetween(Variable(start), Variable(end)) &
            s.isDeleted.equals(false) &
            (s.saleType.equals('return') | s.total.isSmallerThanValue(0)),
      );
    applyBranchCap(docQuery);
    docQuery
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(limit);
    final docs = await docQuery.get();

    // ── Shape A: originals flipped by a return ──────────────────────────────
    //
    // ⚠️ `invoiceDate` هو تاريخُ **البيع** لا المرتجع، والشكلُ أ لا مستندَ له
    // يحمل تاريخَ المرتجع — يحمله صفُّ الخزينة وحدَه. فالفلترةُ به وحدَها
    // تُخفي بيعَ يوليو المرتجَعَ في أغسطس من تقرير أغسطس، والمدى الافتراضيُّ
    // للشاشة (أوّلُ الشهر → اليوم) يجعل **كلَّ** مرتجعٍ لفاتورةٍ أقدم غيرَ
    // مرئيّ. مقيسٌ: التقريرُ رجع فارغاً على تنصيبٍ مستقلّ.
    //
    // والتوسعةُ **إضافيةٌ بـ`OR`** لا استبدال: لا تُسقط صفّاً كان يظهر، ولا
    // تكسر اختباراً قائماً. والفاتورةُ المطابقةُ للشرطين تظهر مرةً واحدة —
    // الـ`OR` شرطٌ لا وصل.
    final refundedIds = await _invoiceIdsRefundedBetween(start, end);
    final originalQuery = select(salesInvoices)
      ..where((s) {
        final inWindow = s.invoiceDate.isBetween(Variable(start), Variable(end));
        // `isIn([])` يولّد `IN ()` — غيرُ صالحٍ في SQLite، فيُتخطّى الشقُّ.
        final dated =
            refundedIds.isEmpty ? inWindow : (inWindow | s.id.isIn(refundedIds));
        return dated &
            s.isDeleted.equals(false) &
            s.status.isIn(const ['returned', 'partial_return']) &
            (s.saleType.equals('return').not() | s.saleType.isNull());
      });
    applyBranchCap(originalQuery);
    originalQuery
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(limit);
    final originals = await originalQuery.get();

    // Resolve each return document's original. `|gid:` wins because the numeric
    // id is only meaningful in the store that wrote it (see localReturnLinkNote).
    final gids = <String>{};
    for (final d in docs) {
      final gid = _originalGidFromNote(d.notes);
      if (gid != null) gids.add(gid);
    }
    final gidToLocalId = <String, int>{};
    if (gids.isNotEmpty) {
      final rows = await (select(salesInvoices)
            ..where((s) => s.globalId.isIn(gids)))
          .get();
      for (final r in rows) {
        final g = r.globalId;
        if (g != null) gidToLocalId[g] = r.id;
      }
    }

    final byId = {for (final o in originals) o.id: o};
    final linkedOriginalIds = <int>{};
    final docOriginalId = <int, int?>{};
    for (final d in docs) {
      final gid = _originalGidFromNote(d.notes);
      final resolved = (gid != null ? gidToLocalId[gid] : null) ??
          _originalIdFromNote(d.notes);
      docOriginalId[d.id] = resolved;
      if (resolved != null) linkedOriginalIds.add(resolved);
    }

    // A linked original may sit OUTSIDE the window (a June sale returned in
    // July) or carry an un-flipped status, so it won't be in `originals`.
    // Fetch the stragglers — the cancel/reprint actions need that row.
    final missingOriginalIds =
        linkedOriginalIds.where((id) => !byId.containsKey(id)).toList();
    if (missingOriginalIds.isNotEmpty) {
      final extra = await (select(salesInvoices)
            ..where((s) => s.id.isIn(missingOriginalIds)))
          .get();
      for (final e in extra) {
        byId[e.id] = e;
      }
    }

    // Actual refund per ORIGINAL invoice, from both persisted sources.
    // Drop originals already represented by a return document, and any row
    // that landed in BOTH lists (a legacy negative-total row whose status was
    // also flipped) — either would otherwise be listed twice.
    final docIds = {for (final d in docs) d.id};
    final unlinkedOriginals = originals
        .where((o) => !linkedOriginalIds.contains(o.id) && !docIds.contains(o.id))
        .toList();
    final amounts = await getReturnedAmountsForInvoices(
      unlinkedOriginals.map((o) => o.id).toList(),
    );

    final entries = <SalesReturnHistoryEntry>[
      for (final d in docs)
        () {
          final origId = docOriginalId[d.id];
          final orig = origId != null ? byId[origId] : null;
          return SalesReturnHistoryEntry(
            invoice: d,
            originalInvoiceId: origId ?? d.id,
            originalInvoice: orig,
            originalInvoiceNumber: orig?.invoiceNumber ?? d.invoiceNumber,
            returnAmount: d.total.abs(),
            originalInvoiceTotal: orig?.total ?? d.total.abs(),
            isFullReturn: orig?.status == 'returned',
            isReturnDocument: true,
          );
        }(),
      for (final o in unlinkedOriginals)
        SalesReturnHistoryEntry(
          invoice: o,
          originalInvoiceId: o.id,
          originalInvoice: o,
          originalInvoiceNumber: o.invoiceNumber,
          returnAmount: amounts[o.id] ?? 0.0,
          originalInvoiceTotal: o.total,
          isFullReturn: o.status == 'returned',
          isReturnDocument: false,
        ),
    ];

    entries.sort((a, b) => b.invoice.createdAt.compareTo(a.invoice.createdAt));
    return entries.length > limit ? entries.sublist(0, limit) : entries;
  }

  /// `'Return for invoice #12|gid:<uuid>'` → `<uuid>`; null when absent.
  static String? _originalGidFromNote(String? notes) {
    if (notes == null) return null;
    final i = notes.indexOf('|gid:');
    if (i < 0) return null;
    final gid = notes.substring(i + 5).trim();
    return gid.isEmpty ? null : gid;
  }

  /// `'Return for invoice #12|gid:…'` → `12`; null when the note doesn't
  /// follow the [localReturnLinkNote] format (e.g. a POS quick-return, which
  /// has no original at all).
  static int? _originalIdFromNote(String? notes) {
    if (notes == null || !notes.startsWith('Return for invoice #')) return null;
    var tail = notes.substring('Return for invoice #'.length);
    final bar = tail.indexOf('|');
    if (bar >= 0) tail = tail.substring(0, bar);
    return int.tryParse(tail.trim());
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
  /// ح-2 + البند 2 (متطلبات العميل 2026-07-25) — إجماليات شاشة فواتير المبيعات
  /// محسوبة في **SQL** على كل الصفوف المطابقة.
  ///
  /// Every summary card used to be folded in Dart over the result of
  /// `getInvoicesPaged()`, which is capped at 500 rows. On a branch with a few
  /// thousand invoices, picking a month showed a truncated total — often
  /// `0.00` — and «عدد الفواتير» counted the LOADED rows, not the matching
  /// ones, with no indication anything had been cut off. Adding the requested
  /// «صافي المبيعات» card on top of that base would only have made a wrong
  /// number look better, so the aggregate had to move down here first.
  ///
  /// The date window matches `dayWindowFor` in the controller exactly:
  /// `[start-of-start-day, start-of-day-after-end)`.
  ///
  /// Returns should be interpreted as it does on screen: return invoices are
  /// NOT sales rows (excluded from the count and the gross total) and are
  /// reported separately in [SalesInvoiceSummary.totalReturns].
  ///
  /// ⚠️ والفاتورةُ **المرتجَعة** ليست مستندَ مرتجع: تبقى في العدّ وفي المجمل
  /// بقيمتها الكاملة، ويُطرح المرتجعُ الفعليّ منها في [SalesInvoiceSummary.netSales].
  /// حذفُها من المجمل **مع** عدّها في المرتجعات يخصم المبلغَ مرتين (‏١٠٠٠
  /// مرتجعة ⇒ صفر − ١٠٠٠ = سالب ١٠٠٠). وهي دلالةُ قائمة الدخل: المردوداتُ
  /// حسابٌ مقابلٌ للإيراد لا حذفٌ منه.
  ///
  /// و[SalesInvoiceSummary.totalReturns] يجمع **مصدرَي** المرتجع كما يفعل
  /// [getReturnedAmountsForInvoices] الذي يغذّي «المتبقي» في كلّ صفّ — مستندُ
  /// المرتجع (الشكل ب) واستردادُ الخزينة (الشكل أ). وبلا الثاني تخرج البطاقةُ
  /// **صفراً دائماً** على أيّ تنصيبٍ مستقلّ.
  Future<SalesInvoiceSummary> getSalesInvoiceSummary({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    int? branchId,
    int? costCenterId,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(to.year, to.month, to.day + 1);

    final vars = <Variable>[dateVar(start), dateVar(endExclusive)];
    final boolFalse = sqlBool(false);

    var whFilter = '';
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        whFilter = ' AND 1 = 0';
      } else {
        whFilter =
            ' AND warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    var brFilter = '';
    if (branchId != null) {
      brFilter = ' AND branch_id = ?';
      vars.add(Variable<int>(branchId));
    }
    var ccFilter = '';
    if (costCenterId != null) {
      ccFilter = ' AND cost_center_id = ?';
      vars.add(Variable<int>(costCenterId));
    }

    // Same predicate as getSalesInvoicesPaged: live rows, excluding returns
    // (NULL saleType counts as a normal sale).
    final scope = 'is_deleted = $boolFalse '
        "AND (sale_type IS NULL OR sale_type != 'return') "
        'AND invoice_date >= ? AND invoice_date < ?'
        '$whFilter$brFilter$ccFilter';

    // عدّاداتُ الحالة في **نفس** الاستعلام لا في ثلاثةٍ بعده: الشرائحُ في
    // شريط الترشيح تعرضها، ولو حُسبت من الصفحة المحمَّلة (سقفُها ٥٠٠ صفّ)
    // لأعطت عدداً أقلَّ من الحقيقة بلا ما يشي بذلك.
    //
    // والحدُّ `paid >= total` لا `paid == total`: دفعةٌ زائدةٌ بقروشٍ
    // (تقريبُ ضريبةٍ أو تحصيلٌ مدوَّر) تجعل الفاتورةَ مدفوعةً لا «جزئيّة».
    // ونفسُ ترتيب `_applyFilters` — مدفوعٌ أوّلاً ثمّ جزئيٌّ ثمّ غيرُ مدفوع —
    // كي لا تُعَدَّ فاتورةٌ في خانتين.
    final sales = await customSelect(
      'SELECT COUNT(*) AS n, '
      'COALESCE(SUM(total), 0) AS total, '
      'COALESCE(SUM(paid), 0) AS paid, '
      'SUM(CASE WHEN paid >= total THEN 1 ELSE 0 END) AS n_paid, '
      'SUM(CASE WHEN paid > 0 AND paid < total THEN 1 ELSE 0 END) AS n_partial, '
      'SUM(CASE WHEN paid <= 0 THEN 1 ELSE 0 END) AS n_unpaid '
      'FROM sales_invoices WHERE $scope',
      variables: vars,
      readsFrom: {salesInvoices},
    ).getSingle();

    // Returns for the SAME window/scope. Mirrors getReturnedAmountsForInvoices'
    // two sources so the card can't disagree with the per-row «المتبقي».
    final returnVars = <Variable>[dateVar(start), dateVar(endExclusive)];
    var retWh = '';
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        retWh = ' AND 1 = 0';
      } else {
        retWh =
            ' AND warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        returnVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    if (branchId != null) {
      retWh += ' AND branch_id = ?';
      returnVars.add(Variable<int>(branchId));
    }
    if (costCenterId != null) {
      retWh += ' AND cost_center_id = ?';
      returnVars.add(Variable<int>(costCenterId));
    }

    // ── المصدر ١: مستنداتُ المرتجع (الشكل ب) ────────────────────────────────
    final returns = await customSelect(
      'SELECT COALESCE(SUM(total), 0) AS total FROM sales_invoices '
      "WHERE sale_type = 'return' AND is_deleted = $boolFalse "
      'AND invoice_date >= ? AND invoice_date < ?$retWh',
      variables: returnVars,
      readsFrom: {salesInvoices},
    ).getSingle();

    // ── المصدر ٢: استردادُ الخزينة (الشكل أ) ────────────────────────────────
    //
    // 🔴 هذا هو ما كان ناقصاً. في التنصيب المستقلّ **لا يُكتب مستندُ مرتجعٍ
    // إطلاقاً**: `processSalesReturn` يقلب حالةَ الفاتورة الأصلية ويكتب صفَّ
    // خزينةٍ فقط. فصفوفُ `sale_type='return'` معدومةٌ هناك، وكانت البطاقةُ
    // تخرج **صفراً دائماً** بينما الفاتورةُ المرتجَعة تدخل «إجمالي المبيعات»
    // بقيمتها الكاملة: مبيعاتٌ منتفخة · مرتجعاتٌ صفر · صافٍ = المجمل.
    //
    // والجمعُ لا الاستبدال — مطابقةً لـ[getReturnedAmountsForInvoices] الذي
    // يغذّي «المتبقي» في كلّ صفّ. وكان تعليقُ هذه الدالة يدّعي تلك المطابقةَ
    // ولا يحقّقها، فتخالف البطاقةُ الصفوفَ تحتها.
    //
    // والنافذةُ على `created_at` — تاريخِ **حدوث** المرتجع — تماثلاً مع
    // الشكل ب الذي يُفلتر بتاريخ مستند المرتجع. فالمجملُ بتاريخ البيع
    // والمرتجعُ بتاريخ الرد، وهي دلالةُ قائمة الدخل.
    //
    // والحصرُ يُطبَّق على الفاتورة **الأصلية** بالوصل: `safe_transactions`
    // لا تحمل مخزناً ولا فرعاً ولا مركزَ تكلفة، فبلا الوصل يُخصم مرتجعُ
    // مخزنٍ آخر من هذا المخزن.
    final stVars = <Variable>[dateVar(start), dateVar(endExclusive)];
    var stScope = '';
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        stScope = ' AND 1 = 0';
      } else {
        stScope =
            ' AND si.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        stVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    if (branchId != null) {
      stScope += ' AND si.branch_id = ?';
      stVars.add(Variable<int>(branchId));
    }
    if (costCenterId != null) {
      stScope += ' AND si.cost_center_id = ?';
      stVars.add(Variable<int>(costCenterId));
    }

    final safeReturns = await customSelect(
      'SELECT COALESCE(SUM(st.amount), 0) AS total '
      'FROM safe_transactions st '
      'JOIN sales_invoices si ON si.id = st.reference_id '
      "WHERE st.reference_type = 'sales_return' "
      'AND st.deleted_at IS NULL '
      "AND si.is_deleted = $boolFalse "
      'AND st.created_at >= ? AND st.created_at < ?'
      '$stScope',
      variables: stVars,
      readsFrom: {safeTransactions, salesInvoices},
    ).getSingle();

    final total = (sales.data['total'] as num?)?.toDouble() ?? 0;
    final paid = (sales.data['paid'] as num?)?.toDouble() ?? 0;
    final returned = ((returns.data['total'] as num?)?.toDouble() ?? 0) +
        ((safeReturns.data['total'] as num?)?.toDouble() ?? 0);

    return SalesInvoiceSummary(
      invoiceCount: (sales.data['n'] as num?)?.toInt() ?? 0,
      totalAmount: total,
      totalPaid: paid,
      totalReturns: returned,
      paidCount: (sales.data['n_paid'] as num?)?.toInt() ?? 0,
      partialCount: (sales.data['n_partial'] as num?)?.toInt() ?? 0,
      unpaidCount: (sales.data['n_unpaid'] as num?)?.toInt() ?? 0,
    );
  }

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
    // Resolve the link by the original's globalId when the note carries one
    // (`…|gid:<uuid>`), joining back to the LOCAL row that owns that uuid. This
    // is what keeps the attribution correct after DeltaPull replaces a locally
    // written return row with the server's copy, which carries the SERVER id.
    // Rows written before the gid format fall back to the raw number.
    final invRows = await customSelect(
      'SELECT COALESCE(orig.id, r.legacy_id) AS orig_id, '
      'COALESCE(SUM(r.total), 0) AS total '
      'FROM ('
      '  SELECT total, '
      "    CAST(SUBSTR(notes, INSTR(notes, '#') + 1) AS INTEGER) AS legacy_id, "
      "    CASE WHEN INSTR(notes, '|gid:') > 0 "
      "         THEN SUBSTR(notes, INSTR(notes, '|gid:') + 5) END AS orig_gid "
      '  FROM sales_invoices '
      "  WHERE sale_type = 'return' "
      "    AND notes LIKE 'Return for invoice #%' "
      '    AND is_deleted = 0 '
      ') r '
      'LEFT JOIN sales_invoices orig ON orig.global_id = r.orig_gid '
      'WHERE COALESCE(orig.id, r.legacy_id) IN ($placeholders) '
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
