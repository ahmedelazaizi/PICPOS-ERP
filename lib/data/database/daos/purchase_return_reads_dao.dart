// Purchase/sales return reads: return records, returned totals/qty, returned item details.
part of '../database.dart';

extension PurchaseReturnReadsDao on AppDatabase {
  /// سجلُّ مردودات المشتريات — **من `purchase_returns` بتاريخ المردود**.
  ///
  /// ═══ 🔴 لماذا قراءةٌ جديدةٌ ولم تكفِ القائمة ═══
  ///
  /// [IReturnsRepository.getPurchaseReturnHistory] — القراءةُ الوحيدةُ
  /// القائمةُ اليوم — **لا تلمس `purchase_returns` إطلاقاً**: تقرأ
  /// `purchase_invoices` في مدىً زمنيٍّ ثمّ ترشّح على `status`. وأثرُ ذلك
  /// ثلاثةُ أعطابٍ في قراءةٍ واحدة:
  ///
  ///   • المدى على **تاريخ الفاتورة** لا تاريخ المردود — فمردودُ اليوم على
  ///     فاتورةٍ عمرُها سنتان لا يظهر أبداً. (وتعليقُ المنادي يعترف:
  ///     «History queries by invoice_date, not return_date — wide range
  ///     prevents misses» — ورقعةٌ بمدىً واسعٍ ليست علاجاً.)
  ///   • الصفُّ فاتورةٌ لا مردود — فثلاثةُ مردوداتٍ على فاتورةٍ واحدةٍ تظهر
  ///     صفّاً واحداً بمجموعها، ولا سبيلَ لفتح واحدٍ منها بعينه؛
  ///   • ولا `id` مردودٍ يُفتَح، فمرفقاتُ §٨ بلا مرساة.
  ///
  /// و`branchIds` هي مجموعةُ `branchScopeProvider` (‏Spec 151 Track-3):
  /// `null` = وصولٌ كامل، ومردودٌ بلا فرعٍ يبقى ظاهراً كصفوف ما قبلَه.
  Stream<List<PurchaseReturnRecord>> watchPurchaseReturnRecords({
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
    String? search,
    int limit = 500,
  }) {
    final supplier = alias(parties, 'sup');
    final query = select(purchaseReturns).join([
      leftOuterJoin(purchaseInvoices,
          purchaseInvoices.id.equalsExp(purchaseReturns.originalInvoiceId)),
      leftOuterJoin(supplier, supplier.id.equalsExp(purchaseReturns.supplierId)),
    ]);

    var where = purchaseReturns.isDeleted.equals(false) &
        purchaseReturns.deletedAt.isNull();

    if (from != null && to != null) {
      where = where & purchaseReturns.returnDate.isBetweenValues(from, to);
    } else if (from != null) {
      where = where & purchaseReturns.returnDate.isBiggerOrEqualValue(from);
    } else if (to != null) {
      where = where & purchaseReturns.returnDate.isSmallerOrEqualValue(to);
    }

    if (branchIds != null) {
      where = where &
          (purchaseReturns.branchId.isIn(branchIds) |
              purchaseReturns.branchId.isNull());
    }

    final needle = search?.trim() ?? '';
    if (needle.isNotEmpty) {
      final like = '%$needle%';
      where = where &
          (purchaseInvoices.invoiceNumber.like(like) |
              supplier.name.like(like) |
              purchaseReturns.reason.like(like));
    }

    query
      ..where(where)
      // ⚠️ و`id` فاصلٌ حاسمٌ بعد التاريخ: `return_date` يومٌ بلا ساعةٍ في
      //    أغلب الكتابات، فثلاثةُ مردوداتٍ في يومٍ واحدٍ تتقافز بلا هذا.
      ..orderBy([
        OrderingTerm.desc(purchaseReturns.returnDate),
        OrderingTerm.desc(purchaseReturns.id),
      ])
      ..limit(limit);

    return query.watch().map((rows) => [
          for (final row in rows)
            () {
              final r = row.readTable(purchaseReturns);
              return PurchaseReturnRecord(
                id: r.id,
                originalInvoiceId: r.originalInvoiceId,
                returnDate: r.returnDate,
                subtotal: r.subtotal,
                tax: r.tax,
                total: r.total,
                refundMethod: r.refundMethod,
                isFullReturn: r.isFullReturn,
                originalInvoiceNumber:
                    row.readTableOrNull(purchaseInvoices)?.invoiceNumber,
                supplierId: r.supplierId,
                supplierName: row.readTableOrNull(supplier)?.name,
                reason: r.reason,
              );
            }(),
        ]);
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
}
