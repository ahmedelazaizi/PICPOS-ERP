// Party statement-tab queries: aging invoices, payments, 3-way match, profile rates, papers; batch lookup + search.
part of '../database.dart';

extension PartyProfileDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // كشفُ حساب الطرف — استعلاماتُ التبويبات (تصميمُ 2026-08-26)
  // ═══════════════════════════════════════════════════════════════════════

  /// فواتيرُ طرفٍ **قائمةٌ** بأعمارها — «أعمار الدين» و«المستحق والاستحقاق».
  ///
  /// ⚠️ **العمرُ من `COALESCE(due_date, invoice_date)`** لا من تاريخ الإصدار.
  /// والفراغُ يعني «بلا مهلة»، فتُقرأ فواتيرُ ما قبلَ v164 بعمرها القديم
  /// بالضبط ولا تتحرّك أرقامُ التقادم.
  ///
  /// ⚠️ و**`total > paid`** لا `status`: فاتورةٌ وسمُها «مسدَّدة» ورصيدُها
  /// موجبٌ تبقى ذمّةً — والمالُ لا يتبع وسماً.
  Future<List<PartyOpenInvoiceRow>> getPartyOpenInvoices({
    required int partyId,
    required bool supplier,
    DateTime? asOf,
    int? branchId,
  }) async {
    final at = asOf ?? DateTime.now();
    final table = supplier ? 'purchase_invoices' : 'sales_invoices';
    final fk = supplier ? 'supplier_id' : 'customer_id';
    // المرتجعُ ليس ذمّةً قائمة. و`sale_type` لا وجودَ له على جدول الشراء،
    // فالاستبعادُ يقع على جدول البيع وحدَه.
    final returnFilter = supplier
        ? ''
        : " AND (inv.sale_type IS NULL OR inv.sale_type != 'return')";
    final branchFilter = branchId == null
        ? ''
        : '''
        AND inv.warehouse_id IN (
          SELECT w.id FROM warehouses w
          WHERE w.branch_id = ? OR w.branch_id IS NULL
        )''';

    final rows = await customSelect(
      '''
      SELECT
        inv.id, inv.invoice_number, inv.invoice_date,
        COALESCE(inv.due_date, inv.invoice_date) AS due_at,
        inv.total, inv.paid,
        (? - COALESCE(inv.due_date, inv.invoice_date)) / 86400 AS days_late
      FROM $table inv
      WHERE inv.$fk = ?
        AND inv.is_deleted = 0
        AND inv.total > inv.paid$returnFilter$branchFilter
      ORDER BY due_at ASC
      ''',
      variables: [
        dateVar(at),
        Variable(partyId),
        if (branchId != null) Variable(branchId),
      ],
      readsFrom: {
        if (supplier) purchaseInvoices else salesInvoices,
        if (branchId != null) warehouses,
      },
    ).get();

    DateTime at2(QueryRow r, String key) => DateTime.fromMillisecondsSinceEpoch(
      ((r.data[key] as num?)?.toInt() ?? 0) * 1000,
    );

    return rows
        .map(
          (r) => PartyOpenInvoiceRow(
            invoiceId: (r.data['id'] as num?)?.toInt() ?? 0,
            invoiceNumber: r.data['invoice_number'] as String? ?? '',
            invoiceDate: at2(r, 'invoice_date'),
            dueDate: at2(r, 'due_at'),
            total: (r.data['total'] as num?)?.toDouble() ?? 0,
            paid: (r.data['paid'] as num?)?.toDouble() ?? 0,
            daysLate: (r.data['days_late'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// دفعاتُ طرفٍ ومقدارُ المربوطِ منها بفواتير — «مطابقةُ الدفعات».
  ///
  /// الضمُّ خارجيٌّ عمداً: دفعةٌ بلا تخصيصٍ **هي بالضبط** ما يبحث عنه التقرير،
  /// وضمٌّ داخليٌّ كان سيُخفيها.
  Future<List<PartyPaymentMatchRow>> getPartyPaymentMatches({
    required int partyId,
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime(2020);
    final end = to ?? DateTime.now().add(const Duration(days: 1));

    final rows = await customSelect(
      '''
      SELECT
        p.id, p.payment_number, p.payment_date, p.amount, p.payment_method,
        COALESCE(SUM(a.allocated_amount), 0) AS allocated,
        COUNT(a.id) AS invoice_count
      FROM payments p
      LEFT JOIN payment_allocations a
        ON a.payment_id = p.id AND a.deleted_at IS NULL
      WHERE p.party_id = ?
        AND p.is_deleted = 0
        AND p.payment_date BETWEEN ? AND ?
      GROUP BY p.id, p.payment_number, p.payment_date, p.amount, p.payment_method
      ORDER BY p.payment_date DESC
      ''',
      variables: [Variable(partyId), dateVar(start), dateVar(end)],
      readsFrom: {payments, paymentAllocations},
    ).get();

    return rows
        .map(
          (r) => PartyPaymentMatchRow(
            paymentId: (r.data['id'] as num?)?.toInt() ?? 0,
            paymentNumber: r.data['payment_number'] as String? ?? '',
            paymentDate: DateTime.fromMillisecondsSinceEpoch(
              ((r.data['payment_date'] as num?)?.toInt() ?? 0) * 1000,
            ),
            amount: (r.data['amount'] as num?)?.toDouble() ?? 0,
            allocated: (r.data['allocated'] as num?)?.toDouble() ?? 0,
            method: r.data['payment_method'] as String? ?? '',
            invoiceCount: (r.data['invoice_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// مطابقةُ أمرِ الشراء بالمستلَم بالمفوتَر — «ثلاثيّةُ المطابقة».
  ///
  /// ⚠️ **والمفوتَرُ يُقرأ من فاتورةِ الأمر لا من أيّ فاتورةٍ للمورد**: الربطُ
  /// عبر `purchase_orders.converted_to_invoice_id`. وجمعُ كلّ فواتير المورد
  /// كان سيَنسب إلى الأمر بضاعةً لم تأتِ منه.
  Future<List<PoMatchRow>> getPurchaseOrderMatches({
    required int supplierId,
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime(2020);
    final end = to ?? DateTime.now().add(const Duration(days: 1));

    final rows = await customSelect(
      '''
      SELECT
        po.id AS order_id, po.order_number, po.order_date,
        po.expected_date, po.received_at,
        pr.name AS product_name,
        poi.quantity AS ordered,
        COALESCE(poi.received_quantity, 0) AS received,
        COALESCE((
          SELECT SUM(pii.quantity)
          FROM purchase_invoice_items pii
          WHERE pii.invoice_id = po.converted_to_invoice_id
            AND pii.product_id = poi.product_id
        ), 0) AS invoiced
      FROM purchase_orders po
      JOIN purchase_order_items poi ON poi.order_id = po.id
      JOIN products pr ON pr.id = poi.product_id
      WHERE po.supplier_id = ?
        AND po.deleted_at IS NULL
        AND po.order_date BETWEEN ? AND ?
      ORDER BY po.order_date DESC, poi.id ASC
      ''',
      variables: [Variable(supplierId), dateVar(start), dateVar(end)],
      readsFrom: {
        purchaseOrders,
        purchaseOrderItems,
        products,
        purchaseInvoiceItems,
      },
    ).get();

    DateTime? maybe(QueryRow r, String key) {
      final v = (r.data[key] as num?)?.toInt();
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }

    return rows
        .map(
          (r) => PoMatchRow(
            orderId: (r.data['order_id'] as num?)?.toInt() ?? 0,
            orderNumber: r.data['order_number'] as String? ?? '',
            productName: r.data['product_name'] as String? ?? '',
            ordered: (r.data['ordered'] as num?)?.toDouble() ?? 0,
            received: (r.data['received'] as num?)?.toDouble() ?? 0,
            invoiced: (r.data['invoiced'] as num?)?.toDouble() ?? 0,
            orderDate: maybe(r, 'order_date') ?? DateTime(2020),
            expectedDate: maybe(r, 'expected_date'),
            receivedAt: maybe(r, 'received_at'),
          ),
        )
        .toList();
  }

  /// معدّلاتُ ملفّ الطرف — **مشتقّةٌ من تواريخَ حقيقيّةٍ لا مكتوبةٌ بيد**.
  ///
  /// «سلوكُ السداد»: لكلّ فاتورةٍ سُدّدت كاملاً، الفرقُ بين آخرِ دفعةٍ خُصّصت
  /// لها واستحقاقِها. وسالبٌ = سدّد قبل الاستحقاق.
  ///
  /// «الالتزامُ بالتوريد»: أوامرُ الشراء التي **اكتمل استلامُها** وحدَها،
  /// و`received_at <= expected_date` هو الالتزام. وأمرٌ مفتوحٌ لا يدخل
  /// الحساب — فتحُّه ليس تأخّراً.
  Future<PartyProfileMetrics> getPartyProfileMetrics({
    required int partyId,
    required bool supplier,
  }) async {
    final table = supplier ? 'purchase_invoices' : 'sales_invoices';
    final fk = supplier ? 'supplier_id' : 'customer_id';
    final invType = supplier ? 'purchase' : 'sales';

    final settle = await customSelect(
      '''
      SELECT
        COUNT(*) AS n,
        COALESCE(AVG(gap_days), 0) AS avg_days,
        COALESCE(SUM(CASE WHEN gap_days <= 0 THEN 1 ELSE 0 END), 0) AS on_time
      FROM (
        SELECT
          (MAX(pay.payment_date) - COALESCE(inv.due_date, inv.invoice_date))
            / 86400 AS gap_days
        FROM $table inv
        JOIN payment_allocations a
          ON a.invoice_id = inv.id AND a.invoice_type = ?
             AND a.deleted_at IS NULL
        JOIN payments pay ON pay.id = a.payment_id AND pay.is_deleted = 0
        WHERE inv.$fk = ? AND inv.is_deleted = 0 AND inv.paid >= inv.total
        GROUP BY inv.id
      )
      ''',
      variables: [Variable(invType), Variable(partyId)],
      readsFrom: {
        if (supplier) purchaseInvoices else salesInvoices,
        paymentAllocations,
        payments,
      },
    ).getSingle();

    var received = 0;
    var onTimeOrders = 0;
    if (supplier) {
      final po = await customSelect(
        '''
        SELECT
          COUNT(*) AS n,
          COALESCE(SUM(CASE
            WHEN expected_date IS NULL THEN 1
            WHEN received_at <= expected_date THEN 1
            ELSE 0 END), 0) AS on_time
        FROM purchase_orders
        WHERE supplier_id = ? AND deleted_at IS NULL AND received_at IS NOT NULL
        ''',
        variables: [Variable(partyId)],
        readsFrom: {purchaseOrders},
      ).getSingle();
      received = (po.data['n'] as num?)?.toInt() ?? 0;
      onTimeOrders = (po.data['on_time'] as num?)?.toInt() ?? 0;
    }

    return PartyProfileMetrics(
      settledInvoices: (settle.data['n'] as num?)?.toInt() ?? 0,
      avgSettlementDays: (settle.data['avg_days'] as num?)?.toDouble() ?? 0,
      onTimeSettlements: (settle.data['on_time'] as num?)?.toInt() ?? 0,
      receivedOrders: received,
      onTimeOrders: onTimeOrders,
    );
  }

  /// آخرُ فواتيرِ طرفٍ **صفّاً صفّاً** بتاريخ آخرِ سدادٍ لكلٍّ منها.
  ///
  /// يسند رسمَي «سلوك السداد — آخر ٦ فواتير» في كشف العميل و«الخصم النقدي —
  /// المُستغَل مقابل المُهدَر» في كشف المورد. وكلاهما كان متعذّراً لأنّ
  /// [getPartyProfileMetrics] يعود بمتوسّطاتٍ مجمَّعةٍ لا بصفوف.
  ///
  /// ⚠️ **آخرُ سدادٍ لا أوّلُه**: `MAX(payment_date)` على تخصيصات الفاتورة.
  /// الفاتورةُ قد تُسدَّد على دفعات، و«سُدّدت في كم يوماً» تعني حتى **إقفالها**
  /// لا حتى أوّلِ قسطٍ منها.
  ///
  /// ⚠️ **والضمُّ يقع على `invoice_type` أيضاً**: `payment_allocations` يخدم
  /// جدولَي البيع والشراء معاً، ومعرِّفُ الفاتورة يتكرّر بينهما. فبلا النوع
  /// تُنسَب دفعةُ فاتورةِ شراءٍ إلى فاتورةِ بيعٍ تحمل نفسَ الرقم.
  ///
  /// ⚠️ **والمرتجعُ مستبعَد**: `sale_type='return'` ليس فاتورةً يُقاس سلوكُ
  /// سدادها — ولا وجودَ للعمود على جدول الشراء، فالاستبعادُ على البيع وحدَه.
  Future<List<PartySettlementRow>> getPartySettlementRows({
    required int partyId,
    required bool supplier,
    int limit = 6,
  }) async {
    final table = supplier ? 'purchase_invoices' : 'sales_invoices';
    final fk = supplier ? 'supplier_id' : 'customer_id';
    final invType = supplier ? 'purchase' : 'sales';
    final returnFilter = supplier
        ? ''
        : " AND (inv.sale_type IS NULL OR inv.sale_type != 'return')";

    final rows = await customSelect(
      '''
      SELECT
        inv.id, inv.invoice_number, inv.invoice_date,
        COALESCE(inv.due_date, inv.invoice_date) AS due_at,
        inv.total, inv.paid,
        (SELECT MAX(pay.payment_date)
           FROM payment_allocations a
           JOIN payments pay ON pay.id = a.payment_id AND pay.is_deleted = 0
          WHERE a.invoice_id = inv.id
            AND a.invoice_type = ?
            AND a.deleted_at IS NULL) AS last_paid_at,
        (SELECT COUNT(*)
           FROM payment_allocations a2
          WHERE a2.invoice_id = inv.id
            AND a2.invoice_type = ?
            AND a2.deleted_at IS NULL) AS alloc_count
      FROM $table inv
      WHERE inv.$fk = ?
        AND inv.is_deleted = 0$returnFilter
      ORDER BY inv.invoice_date DESC, inv.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable(invType),
        Variable(invType),
        Variable(partyId),
        Variable(limit),
      ],
      readsFrom: {
        if (supplier) purchaseInvoices else salesInvoices,
        paymentAllocations,
        payments,
      },
    ).get();

    DateTime at(QueryRow r, String key) => DateTime.fromMillisecondsSinceEpoch(
      ((r.data[key] as num?)?.toInt() ?? 0) * 1000,
    );

    return rows.map((r) {
      final lastPaid = (r.data['last_paid_at'] as num?)?.toInt();
      return PartySettlementRow(
        invoiceId: (r.data['id'] as num?)?.toInt() ?? 0,
        invoiceNumber: r.data['invoice_number'] as String? ?? '',
        invoiceDate: at(r, 'invoice_date'),
        dueDate: at(r, 'due_at'),
        total: (r.data['total'] as num?)?.toDouble() ?? 0,
        paid: (r.data['paid'] as num?)?.toDouble() ?? 0,
        // صفرٌ من `MAX` على مجموعةٍ فارغةٍ لا يقع (تعود `NULL`)، لكنّ صفراً
        // مخزَّناً يعني ١٩٧٠ — وهو ليس تاريخَ سدادٍ فيُقرأ «لم يُسدَّد».
        lastPaymentDate: (lastPaid == null || lastPaid <= 0)
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastPaid * 1000),
        allocationCount: (r.data['alloc_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// أوراقُ طرفٍ التجاريّة — «الأوراق والضمانات» / «الأوراق والمقايضات».
  Future<List<CommercialPaperData>> getPartyPapers(int partyId) {
    return (select(commercialPapers)
          ..where((p) => p.partyId.equals(partyId) & p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.dueDate)]))
        .get();
  }

  Future<Party?> getPartyById(int id) {
    return (select(parties)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Batch-load multiple parties in a single query — avoids N+1 in list views.
  Future<Map<int, String>> getPartyNamesMap(List<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (select(parties)..where((p) => p.id.isIn(ids))).get();
    return {for (final p in rows) p.id: p.name};
  }

  /// Search parties by name, phone or address using FTS5
  Stream<List<Party>> searchParties(String query) {
    if (query.isEmpty) {
      return watchAllParties();
    }

    // Process query for FTS prefix matching
    final processedQuery = query
        .trim()
        .split(RegExp(r'\s+'))
        .map((e) => '$e*')
        .join(' ');

    return customSelect(
      '''
      SELECT p.* FROM parties p
      INNER JOIN parties_fts f ON p.id = f.rowid
      WHERE parties_fts MATCH ? AND p.is_active = ${sqlBool(true)}
      ORDER BY bm25(parties_fts) ASC
      ''',
      variables: [Variable.withString(processedQuery)],
      readsFrom: {parties},
    ).watch().map((rows) => rows.map((row) => parties.map(row.data)).toList());
  }
}
