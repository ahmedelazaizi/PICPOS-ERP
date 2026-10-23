// Purchase invoice totals computed in SQL over all matching rows.
part of '../database.dart';

extension PurchaseSummaryDao on AppDatabase {
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
      // Cancelled invoices stay in the COUNT (they have their own status chip)
      // but carry no money: audit B RPT-007.
      "COALESCE(SUM(CASE WHEN LOWER(status) = 'cancelled' THEN 0 ELSE total END), 0) AS total, "
      "COALESCE(SUM(CASE WHEN LOWER(status) = 'cancelled' THEN 0 ELSE paid END), 0) AS paid, "
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
      "WHERE sm.reference_type = 'purchase_return' AND sm.deleted_at IS NULL AND $retScope",
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
