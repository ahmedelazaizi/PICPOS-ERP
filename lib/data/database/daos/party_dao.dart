// ═══════════════════════════════════════════════════════════════════════════
// PARTY DAO - Customer and Supplier Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all party-related (customers/suppliers) database operations.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

// Spec 115 (L1 + L2) — معالجة rebuild loop على server-mode.
//
// **L1 — distinct(_partyListEquals)**: على server-mode، عمليات clients
// المتعدّدة (sales, payments, balance adjustments) تُولِّد كتابات متكررة
// على parties. Drift يُصدر stream emit على كل write حتى لو محتوى القائمة
// لم يتغيّر. الـ distinct comparator deep-equal يبتلع no-op emissions.
//
// **L2 — debounceTime(200ms)**: حتى مع distinct، burst writes (5 clients
// يدفعون 10 سندات في 1s) تُولِّد ~50 emissions distinct. debounceTime
// يجمّعها في windows 200ms (السقف 200ms مقبول ضمن FR-004 SLA = ≤ 2s).
//
// مرجع: specs/115-parties-rebuild-loop/research.md § الحل المتعدّد الطبقات.
const Duration _kPartyStreamDebounce = Duration(milliseconds: 200);

bool _partyListEquals(List<Party> a, List<Party> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false; // Party.== مُوَلَّد من Drift codegen
  }
  return true;
}

extension on Stream<List<Party>> {
  // الترتيب يهم: distinct أولاً لإلغاء no-op، ثم debounce لتجميع burst.
  Stream<List<Party>> get _coalesced =>
      distinct(_partyListEquals).debounceTime(_kPartyStreamDebounce);
}

/// Extension for Party-related database operations
extension PartyDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // PARTY CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all customers
  Stream<List<Party>> watchCustomers() {
    return (select(parties)
          ..where((p) => p.isActive.equals(true) & p.isCustomer.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch()
        ._coalesced; // Spec 115 L1+L2
  }

  /// Watch every party flagged as a customer regardless of `isActive`.
  ///
  /// Spec 002 (B4): use this for the *name lookup map* in invoice list
  /// views — the map must resolve the FK on every existing invoice, even
  /// when the customer was later deactivated, soft-deleted, or arrived
  /// via a sync that landed after [watchCustomers] had already emitted.
  ///
  /// Selectors (POS dropdown, "new invoice → pick customer") keep using
  /// [watchCustomers] so users only choose from active rows.
  Stream<List<Party>> watchAllCustomersForLookup() {
    return (select(parties)
          ..where((p) => p.isCustomer.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Watch all suppliers
  Stream<List<Party>> watchSuppliers() {
    return (select(parties)
          ..where((p) => p.isActive.equals(true) & p.isSupplier.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch()
        ._coalesced; // Spec 115 L1+L2
  }

  /// Watch all delivery companies (Parties with isDeliveryCompany = true)
  Stream<List<Party>> watchDeliveryParties() {
    return (select(parties)
          ..where(
            (p) => p.isActive.equals(true) & p.isDeliveryCompany.equals(true),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Get active suppliers (PIR P1-05: paginated to avoid OOM on large datasets)
  Future<List<Party>> getSuppliers({
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) {
    return (select(parties)
          ..where((p) => p.isActive.equals(true) & p.isSupplier.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get ALL suppliers with optional pagination.
  /// Defaults to 500 rows to prevent unbounded loads. Callers that truly need
  /// every supplier (e.g. dropdowns with few entries) can pass a large limit.
  Future<List<Party>> getAllSuppliers({
    int limit = 500,
    int offset = 0,
  }) {
    return (select(parties)
          ..where((p) => p.isActive.equals(true) & p.isSupplier.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Watch all parties
  Stream<List<Party>> watchAllParties() {
    return (select(parties)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch()
        ._coalesced; // Spec 115 L1+L2
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BRANCH-SCOPED VARIANTS (Issue 9 — multi-branch / multi-client mode)
  //
  // Parties carry a CSV `branch_ids` and an `is_global` flag (commit
  // d7b7d3c). On a client / branch-restricted user we must hide rows
  // that aren't tagged for any branch the user can see, otherwise a
  // cashier in فرع المعان sees customers created for فرع العقبة.
  //
  // The CSV is wrapped in commas before LIKE so a single pattern
  // `,<id>,` matches an id at any position (start / middle / end /
  // single-element list) without four separate clauses.
  //
  // `is_global = 1` rows are always included — they're the "applies
  // everywhere" set (cash customers, delivery couriers, suppliers
  // without branch affinity).
  // ═══════════════════════════════════════════════════════════════════════

  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowedBranchIds) {
    if (allowedBranchIds == null) return watchAllParties();
    return _watchPartiesForBranches(allowedBranchIds, '');
  }

  Stream<List<Party>> watchCustomersForBranches(Set<int>? allowedBranchIds) {
    if (allowedBranchIds == null) return watchCustomers();
    return _watchPartiesForBranches(
        allowedBranchIds, 'AND is_customer = ${sqlBool(true)}');
  }

  Stream<List<Party>> watchSuppliersForBranches(Set<int>? allowedBranchIds) {
    if (allowedBranchIds == null) return watchSuppliers();
    return _watchPartiesForBranches(
        allowedBranchIds, 'AND is_supplier = ${sqlBool(true)}');
  }

  Stream<List<Party>> _watchPartiesForBranches(
    Set<int> allowedBranchIds,
    String typeFilter,
  ) {
    // Empty set should never happen (full-access maps to null upstream)
    // but guard anyway so a misconfigured user gets an empty list rather
    // than a SQL syntax error from `OR ` with no clauses.
    if (allowedBranchIds.isEmpty) {
      return Stream<List<Party>>.value(const []);
    }
    final ids = allowedBranchIds.toList();
    final orClauses =
        ids.map((_) => "(',' || COALESCE(branch_ids, '') || ',') LIKE ?")
            .join(' OR ');
    final patterns = [for (final id in ids) Variable.withString('%,$id,%')];

    return customSelect(
      '''
      SELECT * FROM parties
      WHERE is_active = ${sqlBool(true)}
        $typeFilter
        AND (is_global = ${sqlBool(true)} OR $orClauses)
      ORDER BY name ASC
      ''',
      variables: patterns,
      readsFrom: {parties},
    )
        .watch()
        .map((rows) => rows.map((row) => parties.map(row.data)).toList())
        ._coalesced; // Spec 115 L1+L2
  }

  /// صفحةٌ من العملاء أو الموردين — **بسقفٍ وبحثٍ في SQL**.
  ///
  /// ═══ لماذا وُجدت ═══
  ///
  /// `watchCustomers`/`watchSuppliers` و`_watchPartiesForBranches` تُرجع
  /// **كلَّ** الصفوف بلا `LIMIT`، مبثوثةً في `StreamProvider`. والعرضُ مسقوفٌ
  /// بـ«تحميل المزيد» في الشاشة، لكنّ ذلك يسقّف **الرسمَ** لا **البيانات**:
  /// عشرةُ آلاف طرفٍ تعني عشرةَ آلاف كائنٍ يُبنى في كلّ بثّةٍ من جدول
  /// `parties`، ويُمرَّر عليه فلترُ Dart مع **كلّ ضغطة مفتاح** في خانة البحث.
  ///
  /// فالسقفُ والبحثُ نزلا إلى الاستعلام. والدلالةُ لم تتغيّر: البحثُ على
  /// الاسم أو الهاتف — نفسُ ما كان فلترُ Dart يفعله بالضبط — والترتيبُ
  /// بالاسم كما كان.
  ///
  /// [limit] سقفُ الصفوف المعادة. [search] فارغاً ⇒ لا شرطَ بحث.
  Stream<List<Party>> watchPartiesPage({
    required bool isCustomer,
    Set<int>? allowedBranchIds,
    String search = '',
    int limit = 200,
  }) {
    // فارغةٌ لا تحدث (الوصولُ الكاملُ يُخرَّج null فوق) لكنّ الحراسةَ تبقى:
    // `OR ` بلا بنودٍ خطأٌ نحويٌّ لا قائمةٌ فارغة.
    if (allowedBranchIds != null && allowedBranchIds.isEmpty) {
      return Stream<List<Party>>.value(const []);
    }

    final typeFilter =
        isCustomer ? 'AND is_customer = ${sqlBool(true)}' : 'AND is_supplier = ${sqlBool(true)}';

    final vars = <Variable>[];
    var branchClause = '';
    if (allowedBranchIds != null) {
      final ids = allowedBranchIds.toList();
      final orClauses = ids
          .map((_) => "(',' || COALESCE(branch_ids, '') || ',') LIKE ?")
          .join(' OR ');
      branchClause = 'AND (is_global = ${sqlBool(true)} OR $orClauses)';
      vars.addAll([for (final id in ids) Variable.withString('%,$id,%')]);
    }

    var searchClause = '';
    final q = search.trim();
    if (q.isNotEmpty) {
      // `COALESCE` على الهاتف **دفاعيّةٌ لا مُصلِحةٌ لعطب**: `NULL LIKE ?`
      // تُنتج NULL، لكنّ `TRUE OR NULL` = TRUE في منطق SQL الثلاثيّ — فصفٌّ
      // بلا هاتفٍ يطابق اسمُه يظهر بالحالتين. (قِيس: إزالتُها لم تُحمِّر
      // اختباراً، وهو ما صحّح تبريراً كان مكتوباً هنا خطأً.)
      //
      // وتبقى لأنها تُثبِّت الدلالةَ إن أُعيدت صياغةُ الشرط لاحقاً — ‏`AND`
      // بدل `OR`، أو نقلُ الهاتف إلى شرطٍ مستقلّ — فحينها يصير NULL قاتلاً.
      searchClause =
          "AND (name LIKE ? OR COALESCE(phone, '') LIKE ?)";
      vars.add(Variable.withString('%$q%'));
      vars.add(Variable.withString('%$q%'));
    }

    vars.add(Variable.withInt(limit));

    return customSelect(
      '''
      SELECT * FROM parties
      WHERE is_active = ${sqlBool(true)}
        $typeFilter
        $branchClause
        $searchClause
      ORDER BY name ASC
      LIMIT ?
      ''',
      variables: vars,
      readsFrom: {parties},
    )
        .watch()
        .map((rows) => rows.map((row) => parties.map(row.data)).toList())
        ._coalesced; // Spec 115 L1+L2
  }

  /// Get party by ID

  /// استحقاقُ فاتورةٍ تُصدَر الآن لطرفٍ — **لقطةٌ تُكتَب مرّةً**.
  ///
  /// يُقرأ `payment_terms_days` من الطرف ويُضاف إلى تاريخ الفاتورة. وصفرٌ
  /// (وهو الافتراض) يعطي `null` لا تاريخاً مساوياً للإصدار — والفرقُ مقصود:
  /// `null` تعني «بلا مهلة» فتقرؤها كلُّ الاستعلامات
  /// `COALESCE(due_date, invoice_date)`، وكتابةُ تاريخٍ مطابقٍ كانت تملأ
  /// عموداً بلا بيانةٍ زائدة.
  ///
  /// و[partyId] فارغاً (بيعٌ نقديٌّ عابر) ⇒ `null` — لا طرفَ فلا مهلة.
  Future<DateTime?> resolveInvoiceDueDate({
    required int? partyId,
    required DateTime invoiceDate,
  }) async {
    if (partyId == null) return null;
    final party = await (select(parties)..where((p) => p.id.equals(partyId)))
        .getSingleOrNull();
    final days = party?.paymentTermsDays ?? 0;
    if (days <= 0) return null;
    return invoiceDate.add(Duration(days: days));
  }


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
  }) async {
    final at = asOf ?? DateTime.now();
    final table = supplier ? 'purchase_invoices' : 'sales_invoices';
    final fk = supplier ? 'supplier_id' : 'customer_id';
    // المرتجعُ ليس ذمّةً قائمة. و`sale_type` لا وجودَ له على جدول الشراء،
    // فالاستبعادُ يقع على جدول البيع وحدَه.
    final returnFilter = supplier
        ? ''
        : " AND (inv.sale_type IS NULL OR inv.sale_type != 'return')";

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
        AND inv.total > inv.paid$returnFilter
      ORDER BY due_at ASC
      ''',
      variables: [dateVar(at), Variable(partyId)],
      readsFrom: {if (supplier) purchaseInvoices else salesInvoices},
    ).get();

    DateTime at2(QueryRow r, String key) =>
        DateTime.fromMillisecondsSinceEpoch(
            ((r.data[key] as num?)?.toInt() ?? 0) * 1000);

    return rows
        .map((r) => PartyOpenInvoiceRow(
              invoiceId: (r.data['id'] as num?)?.toInt() ?? 0,
              invoiceNumber: r.data['invoice_number'] as String? ?? '',
              invoiceDate: at2(r, 'invoice_date'),
              dueDate: at2(r, 'due_at'),
              total: (r.data['total'] as num?)?.toDouble() ?? 0,
              paid: (r.data['paid'] as num?)?.toDouble() ?? 0,
              daysLate: (r.data['days_late'] as num?)?.toInt() ?? 0,
            ))
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
        .map((r) => PartyPaymentMatchRow(
              paymentId: (r.data['id'] as num?)?.toInt() ?? 0,
              paymentNumber: r.data['payment_number'] as String? ?? '',
              paymentDate: DateTime.fromMillisecondsSinceEpoch(
                  ((r.data['payment_date'] as num?)?.toInt() ?? 0) * 1000),
              amount: (r.data['amount'] as num?)?.toDouble() ?? 0,
              allocated: (r.data['allocated'] as num?)?.toDouble() ?? 0,
              method: r.data['payment_method'] as String? ?? '',
              invoiceCount: (r.data['invoice_count'] as num?)?.toInt() ?? 0,
            ))
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
        .map((r) => PoMatchRow(
              orderId: (r.data['order_id'] as num?)?.toInt() ?? 0,
              orderNumber: r.data['order_number'] as String? ?? '',
              productName: r.data['product_name'] as String? ?? '',
              ordered: (r.data['ordered'] as num?)?.toDouble() ?? 0,
              received: (r.data['received'] as num?)?.toDouble() ?? 0,
              invoiced: (r.data['invoiced'] as num?)?.toDouble() ?? 0,
              orderDate: maybe(r, 'order_date') ?? DateTime(2020),
              expectedDate: maybe(r, 'expected_date'),
              receivedAt: maybe(r, 'received_at'),
            ))
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
        ((r.data[key] as num?)?.toInt() ?? 0) * 1000);

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

  // ═══════════════════════════════════════════════════════════════════════
  // PARTY CODE + CHART-OF-ACCOUNTS INTEGRATION (Phase 1)
  // ═══════════════════════════════════════════════════════════════════════

  /// Parent account codes that every newly-created party is hung beneath.
  /// Customers → 1121 (ذمم عملاء محليون). Suppliers and delivery companies →
  /// 2111 (ذمم موردون محليون). Both codes are seeded by
  /// [seedChartOfAccounts] under their proper hierarchy (`1121` under `112`,
  /// `2111` under `211`).
  ///
  /// **Feature 005 (2026-05-03)** — pre-005 these were `'1201'` and `'2101'`,
  /// codes that existed in [accountPurposes] map historically but were never
  /// added to the seeder. The result was a chart with two parallel control
  /// accounts: the seeded `2111` and the runtime-created `2101` orphan,
  /// each holding a different subset of supplier sub-accounts. Aligning to
  /// the seeder removes the duplication and makes the seeded chart the
  /// single source of truth.
  static const String _arParentCode = '1121';
  static const String _apParentCode = '2111';

  /// Makes sure the two parent accounts used for party linking exist in
  /// the Chart of Accounts. Idempotent — safe to call on every insert.
  /// Returns a map keyed by code to the account id, e.g.
  /// `{'1121': 42, '2111': 57}`.
  ///
  /// On normally-seeded installs both accounts already exist (from
  /// `seedChartOfAccounts`) and this method is a fast no-op lookup. The
  /// fallback insert path is kept as a safety net for partially-seeded
  /// databases (e.g. tests that build the schema without the seeder).
  Future<Map<String, int>> ensurePartyParentAccounts() async {
    Future<int> ensure(String code, String name, String type) async {
      final existing = await (select(accounts)
            ..where((a) => a.code.equals(code)))
          .getSingleOrNull();
      if (existing != null) return existing.id;
      // Parent missing — create a system account. isSystem=true protects
      // it from being accidentally deleted via the normal COA UI.
      return into(accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          isSystem: const Value(true),
          // UUID-First (Phase 1): stable cross-install identity for sync.
          globalId: Value(UuidV7.generate()),
        ),
      );
    }

    return {
      _arParentCode:
          await ensure(_arParentCode, 'ذمم عملاء محليون', 'asset'),
      _apParentCode:
          await ensure(_apParentCode, 'ذمم موردون محليون', 'liability'),
    };
  }

  /// Computes the prefix used for a party's auto-generated code based on
  /// the party's role flags. Kept as a helper so the UI can preview the
  /// prefix before a save.
  ///
  /// Rules (most specific wins):
  ///   1. Delivery companies → `DLV`
  ///   2. Both customer AND supplier → `CS`
  ///   3. Customer only → `CUST`
  ///   4. Supplier only → `SUP`
  static String partyCodePrefix({
    required bool isCustomer,
    required bool isSupplier,
    required bool isDeliveryCompany,
  }) {
    if (isDeliveryCompany) return 'DLV';
    if (isCustomer && isSupplier) return 'CS';
    if (isCustomer) return 'CUST';
    if (isSupplier) return 'SUP';
    // Defensive fallback — a party must be at least one role, but if
    // none are set we still return a sensible prefix.
    return 'PRT';
  }

  /// Generates the next sequential party code for the given role flags.
  ///
  /// Output format: `<PREFIX>-<5-digit zero-padded>` (e.g. `CUST-00001`,
  /// `SUP-00042`). The counter is scoped per-prefix so customers and
  /// suppliers have independent sequences.
  ///
  /// NOTE: this is a _suggestion_. The caller can override it; uniqueness
  /// is only enforced inside [insertParty].
  Future<String> getNextPartyCode({
    required bool isCustomer,
    required bool isSupplier,
    bool isDeliveryCompany = false,
  }) async {
    final prefix = partyCodePrefix(
      isCustomer: isCustomer,
      isSupplier: isSupplier,
      isDeliveryCompany: isDeliveryCompany,
    );

    // Find the highest existing numeric suffix with this prefix. We use
    // a LIKE query + Drift's max() so it works on both SQLite and the
    // PostgreSQL server backend.
    final codeLike = '$prefix-%';
    final rows = await (select(parties)
          ..where((p) => p.code.like(codeLike)))
        .get();

    int nextSeq = 1;
    for (final row in rows) {
      final c = row.code;
      if (c == null || !c.startsWith('$prefix-')) continue;
      final suffix = c.substring(prefix.length + 1);
      final n = int.tryParse(suffix);
      if (n != null && n >= nextSeq) nextSeq = n + 1;
    }
    return '$prefix-${nextSeq.toString().padLeft(5, '0')}';
  }

  /// Checks if a party code is already in use. Used for manual-entry
  /// validation and as a safety check inside [insertParty].
  Future<bool> isPartyCodeInUse(String code, {int? excludeId}) async {
    final query = select(parties)..where((p) => p.code.equals(code));
    if (excludeId != null) {
      query.where((p) => p.id.equals(excludeId).not());
    }
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// Insert a new party
  Future<int> insertParty(PartiesCompanion party) async {
    return transaction(() async {
      if (AppConfig.isDemo) {
        // Check HMAC-verified activation status (cached at app startup)
        if (!TrialState.isActivatedCached) {
          final isCustomer = party.isCustomer.value;
          final isSupplier = party.isSupplier.value;
          final policy = TrialState.activePolicy;

          if (isCustomer && policy.maxCustomers != null) {
            final count =
                await (selectOnly(parties)
                      ..addColumns([parties.id.count()])
                      ..where(parties.isCustomer.equals(true)))
                    .map((row) => row.read(parties.id.count()))
                    .getSingle();
            if ((count ?? 0) >= policy.maxCustomers!) {
              throw Exception(
                'تم الوصول للحد الأقصى للعملاء في النسخة التجريبية (${policy.maxCustomers} عميل)',
              );
            }
          }

          if (isSupplier && policy.maxSuppliers != null) {
            final count =
                await (selectOnly(parties)
                      ..addColumns([parties.id.count()])
                      ..where(parties.isSupplier.equals(true)))
                    .map((row) => row.read(parties.id.count()))
                    .getSingle();
            if ((count ?? 0) >= policy.maxSuppliers!) {
              throw Exception(
                'تم الوصول للحد الأقصى للموردين في النسخة التجريبية (${policy.maxSuppliers} مورد)',
              );
            }
          }
        }
      }

      // ── Phase 1: Atomic party+account creation ──────────────────────
      //
      // 1. Ensure both parent accounts (1121, 2111) exist — they are
      //    seeded by seedChartOfAccounts(), so this is a no-op lookup
      //    on normal installs. Test-only databases may need the insert
      //    fallback inside ensurePartyParentAccounts().
      // 2. Resolve the party code: honour any caller-supplied code after
      //    a uniqueness check, otherwise auto-generate `CUST-XXXXX` etc.
      // 3. Insert the party row with the resolved code.
      // 4. For roles that should appear in the Chart of Accounts (all
      //    but a pure "nobody" party), create a sub-account whose code
      //    mirrors the party's suffix so the two are visually linked:
      //        CUST-00042 ↔ 1121-00042
      //        SUP-00042  ↔ 2111-00042
      //        CS-00042   ↔ 1121-00042  (primary AR side)
      //        DLV-00042  ↔ 2111-00042  (payable)
      // 5. Link `parties.accountId` to the new sub-account.
      //
      // Everything runs inside the outer transaction — any failure
      // rolls back the entire operation. No silent fallback (the old
      // behaviour left orphaned parties without accounts).

      final parentAccounts = await ensurePartyParentAccounts();
      final isCustomer = party.isCustomer.present ? party.isCustomer.value : false;
      final isSupplier = party.isSupplier.present ? party.isSupplier.value : false;
      final isDelivery = party.isDeliveryCompany.present
          ? party.isDeliveryCompany.value
          : false;

      // ─── Resolve party code ───────────────────────────────────────
      String partyCode;
      if (party.code.present &&
          party.code.value != null &&
          party.code.value!.trim().isNotEmpty) {
        partyCode = party.code.value!.trim();
        final dup = await isPartyCodeInUse(partyCode);
        if (dup) {
          throw Exception('الكود "$partyCode" مستخدم بالفعل لطرف آخر');
        }
      } else {
        partyCode = await getNextPartyCode(
          isCustomer: isCustomer,
          isSupplier: isSupplier,
          isDeliveryCompany: isDelivery,
        );
      }

      // ─── Decide which parent account, if any ──────────────────────
      // A customer-supplier (both) uses the AR parent; that's the
      // convention already used in the journal_entry_factory too.
      int? parentAccountId;
      String parentAccountType = 'asset';
      String namePrefix = 'عميل';
      if (isCustomer) {
        parentAccountId = parentAccounts[_arParentCode];
        parentAccountType = 'asset';
        namePrefix = isSupplier ? 'عميل/مورد' : 'عميل';
      } else if (isSupplier) {
        parentAccountId = parentAccounts[_apParentCode];
        parentAccountType = 'liability';
        namePrefix = 'مورد';
      } else if (isDelivery) {
        parentAccountId = parentAccounts[_apParentCode];
        parentAccountType = 'liability';
        namePrefix = 'شركة توصيل';
      }

      // ─── Insert the party with its resolved code ──────────────────
      // UUID-First (Phase 1): mint a global_id if the caller didn't supply
      // one, so every party has a stable cross-install identity from the
      // moment it's created.
      final partyHasGid = party.globalId.present &&
          (party.globalId.value?.isNotEmpty ?? false);
      final partyWithCode = party.copyWith(
        code: Value(partyCode),
        globalId: partyHasGid ? party.globalId : Value(UuidV7.generate()),
      );
      final partyId = await into(parties).insert(partyWithCode);

      // ─── Create and link sub-account if role warrants it ──────────
      if (parentAccountId != null) {
        // Mirror the party's numeric suffix into the account code.
        // e.g. "CUST-00042" → "00042" → "1121-00042".
        final dashIdx = partyCode.indexOf('-');
        final suffix = dashIdx >= 0 && dashIdx < partyCode.length - 1
            ? partyCode.substring(dashIdx + 1)
            : partyCode;
        final parentCode = isCustomer ? _arParentCode : _apParentCode;
        final accountCode = '$parentCode-$suffix';

        // Spec 118 (Bug X) — recover-on-collision بدلاً من throw.
        //
        // الـ field log أظهر [MIRROR-WRITE] parties/insert failed (500):
        // "كود الحساب الفرعى '1121-00002' مستخدم بالفعل" 3 مرات. السبب:
        // الـ mirror يولّد party code من local max() لكن الـ local قد
        // يفتقد parties من delta pull غير مكتمل، فيُرسل partyCode جديد
        // محلياً لكن مُكافئه accountCode يتصادم مع party سابق على السيرفر
        // (بـ partyCode مختلف).
        //
        // الـ recovery: لو الـ accountCode موجود، جرّب suffix التالي
        // (numeric increment). نحاول حتى 100 مرة قبل الاستسلام.
        String resolvedAccountCode = accountCode;
        int? numericSuffix = int.tryParse(suffix);
        if (numericSuffix != null) {
          for (var attempt = 0; attempt < 100; attempt++) {
            final dupAcc = await (select(accounts)
                  ..where((a) => a.code.equals(resolvedAccountCode)))
                .getSingleOrNull();
            if (dupAcc == null) break;
            numericSuffix = numericSuffix! + 1;
            resolvedAccountCode = '$parentCode-${numericSuffix.toString().padLeft(suffix.length, '0')}';
          }
        }
        // فحص نهائي — لو ما زال يوجد collision بعد 100 محاولة (نادر جداً)،
        // نرفع كمجال للنظر فيه.
        final finalDup = await (select(accounts)
              ..where((a) => a.code.equals(resolvedAccountCode)))
            .getSingleOrNull();
        if (finalDup != null) {
          throw Exception(
            'كود الحساب الفرعى "$resolvedAccountCode" مستخدم بالفعل — '
            'تحقق من دليل الحسابات.',
          );
        }

        final accountName = '$namePrefix: ${party.name.value} ($partyCode)';
        final accId = await into(accounts).insert(
          AccountsCompanion.insert(
            code: resolvedAccountCode,
            name: accountName,
            accountType: parentAccountType,
            parentId: Value(parentAccountId),
            isSystem: const Value(false),
            // UUID-First (Phase 1): stable cross-install identity for sync.
            globalId: Value(UuidV7.generate()),
          ),
        );

        await (update(parties)..where((p) => p.id.equals(partyId))).write(
          PartiesCompanion(accountId: Value(accId)),
        );

        // ─── Opening balance JE ───────────────────────────────────────
        // Audit finding #1 (02_accounting_correctness.md): a non-zero
        // opening `balance` used to update `parties.balance` + link the
        // sub-account without posting any JE — trial balance diverged
        // from `parties.balance` the moment any party was created with
        // a non-zero opening. Post the offsetting entry here so the GL
        // stays balanced from day one.
        //
        // Counterpart = retained_earnings (313), same convention the
        // fiscal-year opening JE already uses (accounting_fiscal_dao).
        // If the mapping isn't present, skip the JE with a loud debug —
        // same fallback policy as the fiscal flow.
        final openingBalance = party.balance.present
            ? (party.balance.value)
            : 0.0;
        if (openingBalance.abs() > 0.001) {
          final retainedEarnings =
              await accountingDao.getAccountByPurpose('retained_earnings');
          if (retainedEarnings == null) {
            debugPrint(
              '[PartyDao] ⚠️ opening balance JE skipped — '
              'retained_earnings mapping missing (party $partyCode, '
              'balance $openingBalance)',
            );
          } else {
            final openingLines = <JournalLine>[];
            final absAmount = openingBalance.abs();
            final desc = 'رصيد افتتاحى — $namePrefix: '
                '${party.name.value} ($partyCode)';
            final partySideDebits = (isCustomer && openingBalance > 0) ||
                (!isCustomer && openingBalance < 0);
            if (partySideDebits) {
              openingLines.add(JournalLine(
                accountId: accId,
                debit: absAmount,
                description: desc,
              ));
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                credit: absAmount,
                description: desc,
              ));
            } else {
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                debit: absAmount,
                description: desc,
              ));
              openingLines.add(JournalLine(
                accountId: accId,
                credit: absAmount,
                description: desc,
              ));
            }
            await accountingDao.createJournalEntry(
              description: desc,
              date: DateTime.now(),
              lines: openingLines,
              referenceType: 'party_opening_balance',
              referenceId: partyId,
              isAutoPosted: true,
            );
          }
        }
      }

      return partyId;
    });
  }

  /// Update a party
  Future<bool> updateParty(Party party) {
    return update(parties).replace(party);
  }

  /// Check if party has any transaction history
  Future<bool> partyHasTransactions(int partyId) async {
    // Check sales invoices
    final salesCount =
        await (selectOnly(salesInvoices)
              ..addColumns([salesInvoices.id.count()])
              ..where(salesInvoices.customerId.equals(partyId)))
            .map((row) => row.read(salesInvoices.id.count())!)
            .getSingle();
    if (salesCount > 0) return true;

    // Check purchase invoices
    final purchaseCount =
        await (selectOnly(purchaseInvoices)
              ..addColumns([purchaseInvoices.id.count()])
              ..where(purchaseInvoices.supplierId.equals(partyId)))
            .map((row) => row.read(purchaseInvoices.id.count())!)
            .getSingle();
    if (purchaseCount > 0) return true;

    // Check safe transactions (payments/receipts)
    final transactionCount =
        await (selectOnly(safeTransactions)
              ..addColumns([safeTransactions.id.count()])
              ..where(safeTransactions.partyId.equals(partyId)))
            .map((row) => row.read(safeTransactions.id.count())!)
            .getSingle();
    return transactionCount > 0;
  }

  /// Spec 114 — Repair parties that exist without a linked COA sub-account.
  ///
  /// Historical gap: `api_handler_base.resolvePartyId` used to mint placeholder
  /// parties via a direct `insert(parties)` call, bypassing the atomic
  /// party+sub-account creation that `insertParty` runs. The placeholder ended
  /// up with `accountId = null`, so every JE that referenced it tried to post
  /// against the parent control account (2111 / 1121) and got rejected by the
  /// "حساب رئيسي" guard — silently dropping every transaction from the GL
  /// while still showing it in the party's statement (which reads invoices
  /// directly, not JE lines).
  ///
  /// This routine walks every party with `accountId IS NULL` whose role
  /// warrants a COA presence (customer / supplier / delivery company), mints
  /// the matching sub-account using the same suffix-mirroring convention as
  /// `insertParty`, and links it back. Idempotent — running twice is a no-op
  /// for already-repaired rows.
  ///
  /// Returns a small map with counters so the UI can show "X parties
  /// repaired, Y skipped, Z failed".
  Future<Map<String, int>> repairMissingPartySubAccounts({
    int Function()? logTick,
  }) async {
    return transaction(() async {
      await ensurePartyParentAccounts();
      // Re-fetch parent IDs inside the transaction so we always read the
      // freshly-ensured rows.
      final arParent = await (select(accounts)
            ..where((a) => a.code.equals(_arParentCode))
            ..limit(1))
          .getSingleOrNull();
      final apParent = await (select(accounts)
            ..where((a) => a.code.equals(_apParentCode))
            ..limit(1))
          .getSingleOrNull();

      int repaired = 0;
      int skipped = 0;
      int failed = 0;

      final orphans = await (select(parties)
            ..where((p) =>
                p.accountId.isNull() &
                (p.isCustomer.equals(true) |
                    p.isSupplier.equals(true) |
                    p.isDeliveryCompany.equals(true))))
          .get();

      for (final p in orphans) {
        try {
          // Pick parent: AR for customers (or customer-supplier), AP for
          // pure suppliers and delivery companies. Matches insertParty.
          int? parentAccountId;
          String parentType;
          String namePrefix;
          String parentCode;
          if (p.isCustomer) {
            parentAccountId = arParent?.id;
            parentType = 'asset';
            namePrefix = p.isSupplier ? 'عميل/مورد' : 'عميل';
            parentCode = _arParentCode;
          } else if (p.isSupplier) {
            parentAccountId = apParent?.id;
            parentType = 'liability';
            namePrefix = 'مورد';
            parentCode = _apParentCode;
          } else if (p.isDeliveryCompany) {
            parentAccountId = apParent?.id;
            parentType = 'liability';
            namePrefix = 'شركة توصيل';
            parentCode = _apParentCode;
          } else {
            skipped++;
            continue;
          }

          if (parentAccountId == null) {
            skipped++;
            continue;
          }

          // Use the party's code suffix to keep CUST-00042 ↔ 1121-00042
          // visually aligned. Parties created before code auto-generation
          // may have a free-form code or no code; in that case fall back
          // to the party id as the suffix so the new account code is still
          // unique and deterministic.
          String suffix;
          final code = p.code ?? '';
          if (code.isNotEmpty) {
            final dashIdx = code.indexOf('-');
            suffix = (dashIdx >= 0 && dashIdx < code.length - 1)
                ? code.substring(dashIdx + 1)
                : code;
          } else {
            suffix = p.id.toString().padLeft(5, '0');
          }

          var accountCode = '$parentCode-$suffix';

          // Collision guard — if the deterministic code is already taken
          // (very rare; legacy data), append the party id to disambiguate.
          var existing = await (select(accounts)
                ..where((a) => a.code.equals(accountCode))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            accountCode = '$parentCode-${suffix}_${p.id}';
            existing = await (select(accounts)
                  ..where((a) => a.code.equals(accountCode))
                  ..limit(1))
                .getSingleOrNull();
            if (existing != null) {
              skipped++;
              continue;
            }
          }

          final displayCode = code.isNotEmpty ? code : 'PID-${p.id}';
          final accountName = '$namePrefix: ${p.name} ($displayCode)';
          final accId = await into(accounts).insert(
            AccountsCompanion.insert(
              code: accountCode,
              name: accountName,
              accountType: parentType,
              parentId: Value(parentAccountId),
              isSystem: const Value(false),
              globalId: Value(UuidV7.generate()),
            ),
          );

          await (update(parties)..where((row) => row.id.equals(p.id))).write(
            PartiesCompanion(accountId: Value(accId)),
          );

          repaired++;
          if (logTick != null) logTick();
        } catch (e) {
          debugPrint('[REPAIR-PARTY-SUBACCOUNT] partyId=${p.id} '
              'name="${p.name}" failed: $e');
          failed++;
        }
      }

      debugPrint('[REPAIR-PARTY-SUBACCOUNT] done: '
          'repaired=$repaired skipped=$skipped failed=$failed '
          'total-orphans=${orphans.length}');

      return {
        'repaired': repaired,
        'skipped': skipped,
        'failed': failed,
        'total': orphans.length,
      };
    });
  }

  /// Spec 114c — Rewire historical JE lines from the parent control
  /// account to the party's sub-account.
  ///
  /// When the system creates a JE for an invoice involving a party WITHOUT
  /// a sub-account (legacy data, the old placeholder-creation gap, etc.),
  /// the AR/AP leg lands on the PARENT account (1121 / 2111). The
  /// `_resolvePartySubAccount` helper that we use today falls back to the
  /// parent control when `parties.accountId IS NULL`. Spec 114 now creates
  /// sub-accounts for those parties — but the existing JE lines keep
  /// pointing at the parent. Result: the party's sub-account ledger looks
  /// empty even though the transactions exist in the GL (they just sit
  /// against the wrong account).
  ///
  /// This routine walks every party that DOES have a linked sub-account
  /// (parties.accountId set) and migrates the JE lines belonging to its
  /// invoices / safe transactions / commercial papers FROM the parent
  /// control account TO the sub-account. Idempotent — running twice is a
  /// no-op for already-rewired lines.
  ///
  /// Returns counters: `linesMoved`, `partiesScanned`, `failed`.
  Future<Map<String, int>> rewireJELinesToPartySubAccounts() async {
    return transaction(() async {
      await ensurePartyParentAccounts();
      final arParent = await (select(accounts)
            ..where((a) => a.code.equals(_arParentCode))
            ..limit(1))
          .getSingleOrNull();
      final apParent = await (select(accounts)
            ..where((a) => a.code.equals(_apParentCode))
            ..limit(1))
          .getSingleOrNull();

      int linesMoved = 0;
      int partiesScanned = 0;
      int failed = 0;

      final wired = await (select(parties)
            ..where((p) => p.accountId.isNotNull()))
          .get();

      for (final p in wired) {
        partiesScanned++;
        try {
          // Determine the parent control account this party's sub-account
          // descends from. Customers/customer-suppliers → AR (1121),
          // pure suppliers / delivery companies → AP (2111).
          int? parentAccountId;
          if (p.isCustomer) {
            parentAccountId = arParent?.id;
          } else if (p.isSupplier || p.isDeliveryCompany) {
            parentAccountId = apParent?.id;
          }
          if (parentAccountId == null) continue;
          final subAccountId = p.accountId!;
          if (subAccountId == parentAccountId) continue;

          // JEs tied to sales invoices for this customer
          final salesEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN sales_invoices si ON si.id = je.reference_id '
            'WHERE je.reference_type IN (\'sale\', \'sales_invoice\', \'sales_return\') '
            '  AND si.customer_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, salesInvoices},
          ).get();

          // JEs tied to purchase invoices for this supplier
          final purchaseEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN purchase_invoices pi ON pi.id = je.reference_id '
            'WHERE je.reference_type IN (\'purchase\', \'purchase_invoice\', \'purchase_return\') '
            '  AND pi.supplier_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, purchaseInvoices},
          ).get();

          // JEs tied to safe transactions (receipts / payments / refunds)
          // attributed to this party.
          final safeTxnEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN safe_transactions st ON st.id = je.reference_id '
            'WHERE je.reference_type IN (\'receipt_voucher\', \'payment_voucher\', '
            '   \'safe_transaction\', \'sales_return\') '
            '  AND st.party_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, safeTransactions},
          ).get();

          // JEs tied to commercial papers (cheques) for this party
          final paperEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN commercial_papers cp ON cp.id = je.reference_id '
            'WHERE je.reference_type = \'commercial_paper\' '
            '  AND cp.party_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, commercialPapers},
          ).get();

          final entryIds = <int>{
            for (final row in salesEntryIds) row.data['id'] as int,
            for (final row in purchaseEntryIds) row.data['id'] as int,
            for (final row in safeTxnEntryIds) row.data['id'] as int,
            for (final row in paperEntryIds) row.data['id'] as int,
          };

          if (entryIds.isEmpty) continue;

          // Move every line of these JEs that currently sits on the parent
          // control account onto the party's sub-account. The party-side
          // lines are the AR/AP legs; the other legs (cash / sales /
          // inventory / VAT) live on different accounts and are left alone.
          final updated = await (update(journalEntryLines)
                ..where((line) =>
                    line.entryId.isIn(entryIds) &
                    line.accountId.equals(parentAccountId!)))
              .write(JournalEntryLinesCompanion(
            accountId: Value(subAccountId),
          ));
          linesMoved += updated;
        } catch (e) {
          debugPrint('[REWIRE-JE] partyId=${p.id} name="${p.name}" failed: $e');
          failed++;
        }
      }

      // After moving lines, account balances on both the parent and the
      // sub-account need a recompute so the COA tree displays correctly.
      // Walk every account that received a moved line + the parent rows
      // and recompute their balance from journal_entry_lines.
      if (linesMoved > 0) {
        await customStatement('''
          UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(jel.debit), 0) - COALESCE(SUM(jel.credit), 0)
            FROM journal_entry_lines jel
            INNER JOIN journal_entries je ON je.id = jel.entry_id
            WHERE jel.account_id = accounts.id AND je.is_posted = 1
          )
          WHERE accounts.id IN (
            SELECT DISTINCT account_id FROM journal_entry_lines
          )
        ''');
      }

      debugPrint('[REWIRE-JE] done — linesMoved=$linesMoved '
          'partiesScanned=$partiesScanned failed=$failed');

      return {
        'linesMoved': linesMoved,
        'partiesScanned': partiesScanned,
        'failed': failed,
      };
    });
  }

  /// Soft delete a party (with transaction history check)
  Future<void> deleteParty(int partyId) async {
    // Check for transaction history before allowing deletion
    final hasTransactions = await partyHasTransactions(partyId);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا العميل/المورد - يوجد سجل معاملات مرتبط به. استخدم إلغاء التفعيل بدلاً من ذلك.',
      );
    }

    // Soft delete - mark as inactive
    await (update(parties)..where((p) => p.id.equals(partyId))).write(
      const PartiesCompanion(isActive: Value(false)),
    );
  }

  /// Adjust party balance with atomic read-modify-write.
  /// Wrapped in transaction to prevent Lost Update race condition.
  /// PIR P1-02: Logs balance changes to field_audit_logs for financial audit trail.
  Future<void> adjustPartyBalance(
    int partyId,
    double amount, {
    int changedBy = 0,
    String changedByName = 'SYSTEM',
    String? changeReason,
  }) async {
    return transaction(() async {
      // Read old balance for audit trail
      final party = await (select(parties)
            ..where((p) => p.id.equals(partyId)))
          .getSingleOrNull();

      if (party != null) {
        final oldBalance = party.balance;
        final newBalance = oldBalance + amount;

        // CRITICAL: Atomic balance update using SQL-level arithmetic
        // to prevent Lost Update race condition between concurrent transactions.
        await customStatement(
          'UPDATE parties SET balance = balance + ? WHERE id = ?',
          [amount, partyId],
        );

        // P1-02: Log balance change for AR/AP audit trail.
        // Skip when changedBy <= 0: server-side paths (client API requests) have no
        // authenticated user context; inserting changed_by=0 violates the FK to users
        // and under PostgreSQL poisons the whole transaction (25P02 at COMMIT).
        if (changedBy > 0) {
          try {
            await logFieldChange(
              entityType: 'party',
              entityId: partyId,
              fieldName: 'رصيد الطرف',
              fieldKey: 'balance',
              oldValue: oldBalance.toStringAsFixed(4),
              newValue: newBalance.toStringAsFixed(4),
              changedBy: changedBy,
              changedByName: changedByName,
              changeReason: changeReason,
              transactionId: 'balance-adj-$partyId-${DateTime.now().millisecondsSinceEpoch}',
            );
          } catch (e) {
            debugPrint('[FieldAudit] Failed to log party balance change: $e');
          }
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PARTY REPORTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get parties with outstanding balances.
  /// PIR P1-05: Paginated to prevent loading all AR/AP records at once.
  Future<List<Party>> getPartiesWithBalance({
    bool? isCustomer,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    var query = select(parties)
      ..where(
        (p) => p.isActive.equals(true) & p.balance.isBiggerThan(const Variable(0)),
      );

    if (isCustomer != null) {
      if (isCustomer) {
        query = query..where((p) => p.isCustomer.equals(true));
      } else {
        query = query..where((p) => p.isSupplier.equals(true));
      }
    }

    return (query
          ..orderBy([(p) => OrderingTerm.desc(p.balance)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get total receivables (customer balances)
  Future<double> getTotalReceivables() async {
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(balance), 0) as total 
      FROM parties 
      WHERE is_active = ${sqlBool(true)} AND balance > 0 AND is_customer = ${sqlBool(true)}
      ''',
      readsFrom: {parties},
    ).getSingle();
    return result.data['total'] as double? ?? 0;
  }

  /// Get total payables (supplier balances)
  Future<double> getTotalPayables() async {
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(balance), 0) as total 
      FROM parties 
      WHERE is_active = ${sqlBool(true)} AND balance > 0 AND is_supplier = ${sqlBool(true)}
      ''',
      readsFrom: {parties},
    ).getSingle();
    return result.data['total'] as double? ?? 0;
  }

  /// Get total balance owed by all customers (Legacy Support)
  Future<double> getTotalCustomersBalance() => getTotalReceivables();

  /// Get total balance owed to all suppliers (Legacy Support)
  Future<double> getTotalSuppliersBalance() => getTotalPayables();

  /// Get party summary with totals
  Future<PartySummary> getPartySummary(int partyId) async {
    final party = await getPartyById(partyId);
    if (party == null) {
      throw Exception('Party not found');
    }

    double totalInvoices = 0;
    double totalPayments = 0;
    int invoiceCount = 0;
    int paymentCount = 0;

    // Get purchase invoices for supplier
    if (party.isSupplier) {
      final purchases = await (select(
        purchaseInvoices,
      )..where((p) => p.supplierId.equals(partyId))).get();

      for (final p in purchases) {
        totalInvoices += p.total;
      }
      invoiceCount = purchases.length;
    }

    // Get sales invoices for customer
    if (party.isCustomer) {
      final sales = await (select(
        salesInvoices,
      )..where((s) => s.customerId.equals(partyId))).get();

      for (final s in sales) {
        totalInvoices += s.total;
      }
      invoiceCount = sales.length;
    }

    // Get payments/receipts
    final transactions = await (select(
      safeTransactions,
    )..where((t) => t.partyId.equals(partyId))).get();

    for (final t in transactions) {
      totalPayments += t.amount;
    }
    paymentCount = transactions.length;

    return PartySummary(
      partyId: partyId,
      partyName: party.name,
      isCustomer: party.isCustomer,
      isSupplier: party.isSupplier,
      currentBalance: party.balance,
      totalInvoices: totalInvoices,
      totalPayments: totalPayments,
      invoiceCount: invoiceCount,
      paymentCount: paymentCount,
    );
  }

  /// Get party by name (Unique to db.dart)
  Future<Party?> getPartyByName(String name, bool isSupplier) {
    return (select(parties)..where(
          (p) =>
              p.name.equals(name) &
              p.isSupplier.equals(isSupplier) &
              p.isActive.equals(true),
        ))
        .getSingleOrNull();
  }

  /// Hard delete a party (PROTECTED - only for parties without transaction history)
  Future<int> hardDeleteParty(int partyId) async {
    // Check for transaction history before allowing hard deletion
    final hasTransactions = await partyHasTransactions(partyId);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا العميل/المورد نهائياً - يوجد سجل معاملات مرتبط به.',
      );
    }
    return (delete(parties)..where((p) => p.id.equals(partyId))).go();
  }

  /// Get party transaction history (sales/purchases + payments)
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) async {
    final party = await getPartyById(partyId);
    if (party == null) return [];

    // Normalize dates to include full day range (matching getSalesByDateRange behavior)
    final from = fromDate ?? DateTime(2020);
    final to = toDate != null
        ? DateTime(
            toDate.year,
            toDate.month,
            toDate.day,
          ).add(const Duration(days: 1))
        : DateTime.now().add(const Duration(days: 1));

    final entries = <PartyStatementEntry>[];

    if (party.isCustomer) {
      // Get sales invoices for customers
      final salesQuery = select(salesInvoices)
        ..where(
          (i) =>
              i.customerId.equals(partyId) &
              i.invoiceDate.isBetween(Variable(from), Variable(to)),
        );
      if (branchId != null) {
        salesQuery.where((i) => i.warehouseId.isInQuery(
          selectOnly(warehouses)
            ..addColumns([warehouses.id])
            ..where(warehouses.branchId.equals(branchId) | warehouses.branchId.isNull())
        ));
      }
      salesQuery.orderBy([(i) => OrderingTerm.asc(i.invoiceDate)]);
      final sales = await salesQuery.get();

      for (final sale in sales) {
        // Spec 113 — sales returns (saleType='return') live in the SAME
        // table as regular sales. Pre-113 the loop labelled them all as
        // "فاتورة مبيعات" and put the amount in the DEBIT column, which
        // (a) lied about the document type and (b) increased the
        // customer's apparent debt instead of decreasing it. Now we
        // branch on `saleType` to flip the label and the column.
        final isReturn = sale.saleType == 'return';
        entries.add(
          PartyStatementEntry(
            date: sale.invoiceDate,
            description: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
            invoiceNumber: sale.invoiceNumber,
            entryType: isReturn ? 'sales_return' : 'invoice',
            debit: isReturn ? 0.0 : sale.total,
            credit: isReturn ? sale.total : 0.0,
            balance: 0.0, // Calculated on display
            referenceId: sale.id,
            referenceType: isReturn ? 'sales_return' : 'sales_invoice',
          ),
        );
      }
    }

    if (party.isSupplier) {
      // Get purchase invoices for suppliers
      final purchasesQuery = select(purchaseInvoices)
        ..where(
          (i) =>
              i.supplierId.equals(partyId) &
              i.invoiceDate.isBetween(Variable(from), Variable(to)),
        );
      if (branchId != null) {
        purchasesQuery.where((i) => i.warehouseId.isInQuery(
          selectOnly(warehouses)
            ..addColumns([warehouses.id])
            ..where(warehouses.branchId.equals(branchId) | warehouses.branchId.isNull())
        ));
      }
      purchasesQuery.orderBy([(i) => OrderingTerm.asc(i.invoiceDate)]);
      final purchases = await purchasesQuery.get();

      for (final purchase in purchases) {
        String desc = 'فاتورة مشتريات';
        if (purchase.supplierInvoiceNumber != null && purchase.supplierInvoiceNumber!.isNotEmpty) {
          desc += ' - وثيقة المورد: ${purchase.supplierInvoiceNumber!}';
        }
        if (purchase.notes != null && purchase.notes!.isNotEmpty) {
          desc += ' - ملاحظات: ${purchase.notes!}';
        }
        entries.add(
          PartyStatementEntry(
            date: purchase.invoiceDate,
            description: desc,
            invoiceNumber: purchase.invoiceNumber,
            entryType: 'purchase',
            debit: 0.0,
            credit: purchase.total,
            balance: 0.0, // Calculated on display
            referenceId: purchase.id,
            referenceType: 'purchase_invoice',
          ),
        );
      }
    }

    // Get Safe Transactions (Payments/Receipts)
    final stQuery = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId))
    ])..where(safeTransactions.partyId.equals(partyId) &
              safeTransactions.createdAt.isBetween(Variable(from), Variable(to)));

    if (branchId != null) {
      stQuery.where(safes.branchId.equals(branchId) | safes.branchId.isNull());
    }

    final transactionRows = await stQuery.get();
    final transactions = transactionRows.map((row) => row.readTable(safeTransactions)).toList();

    for (final t in transactions) {
      // Spec 113 — safe-transaction rows generated by the return flow
      // (sales_mutations_dao._recordSalesReceipt creates a PV/PMT for the
      // "paid" leg of a return) duplicate the return invoice row already
      // emitted by the salesInvoices loop above. Skip them to keep the
      // statement showing exactly one entry per economic event.
      //
      // Also skip the 'memo' AR-adjustment rows for the same reason:
      // pre-113 they were the only visible signal that the return
      // happened (because the invoice row was mis-labelled); now the
      // invoice row carries the information directly.
      // Spec 136 ISS-14 — purchase returns have NO row in purchaseInvoices
      // (unlike sales returns, which live in salesInvoices as saleType='return'
      // and are emitted by the loop above). They exist ONLY as a
      // 'purchase_return_balance' memo in safe_transactions. The Spec 113 skip
      // below assumed every return has an invoice-table row carrying it — true
      // for sales, false for purchases — so the memo was dropped and the
      // supplier statement never showed the return. Emit it here as a DEBIT
      // (reduces the AP credit balance), matching the opening-balance calc that
      // subtracts these same memos. The cash-refund leg ('purchase_return',
      // type 'receipt') stays skipped: it offsets cash already paid, not AP, so
      // surfacing it would double-reduce the supplier balance.
      if (party.isSupplier && t.category == 'purchase_return_balance') {
        entries.add(
          PartyStatementEntry(
            date: t.createdAt,
            description: t.description ?? 'مرتجع مشتريات',
            invoiceNumber: t.voucherNumber,
            entryType: t.transactionType, // 'memo'
            debit: t.amount,
            credit: 0.0,
            balance: 0.0,
            referenceId: t.id,
            referenceType: 'safe_transaction',
          ),
        );
        continue;
      }

      // Spec 136 ISS-26 — the customer-side mirror of the ISS-14 fix above.
      // A sales return created from the returns dialog
      // (returns_repository_impl) exists ONLY as a 'sales_return_balance' memo
      // in safe_transactions — it writes NO sales_invoices row (verified: only
      // the POS quick-return path writes saleType='return', which the sales
      // loop above already shows). The Spec 113 skip below dropped this memo,
      // so dialog-path sales returns never appeared in the customer statement
      // even though the memo carries the AR reduction (and the opening-balance
      // calc already subtracts it). Emit it as a CREDIT (reduces the
      // customer's AR debit balance). No double-count: the two return paths
      // are disjoint (memo XOR invoice row). referenceType is
      // 'sales_return_balance' so party_statement_dialogs renders the proper
      // label + print template.
      if (party.isCustomer && t.category == 'sales_return_balance') {
        entries.add(
          PartyStatementEntry(
            date: t.createdAt,
            description: t.description ?? 'مرتجع مبيعات',
            invoiceNumber: t.voucherNumber,
            entryType: t.transactionType, // 'memo'
            debit: 0.0,
            credit: t.amount,
            balance: 0.0,
            referenceId: t.id,
            referenceType: 'sales_return_balance',
          ),
        );
        continue;
      }

      if (t.category == 'return' ||
          t.category == 'sales_return' ||
          t.category == 'sales_return_balance' ||
          t.category == 'purchase_return' ||
          t.category == 'purchase_return_balance') {
        continue;
      }

      double debit = 0;
      double credit = 0;

      if (party.isCustomer) {
        if (t.transactionType == 'receipt') {
          credit = t.amount;
        } else if (t.transactionType == 'payment') {
          credit = t.amount;
        }
      } else if (party.isSupplier) {
        if (t.transactionType == 'payment') {
          debit = t.amount;
        } else if (t.transactionType == 'receipt') {
          debit = t.amount;
        }
      }

      entries.add(
        PartyStatementEntry(
          date: t.createdAt,
          description: t.description ?? (t.transactionType == 'receipt' ? 'سند قبض' : t.transactionType == 'memo' ? 'تسوية رصيد' : 'سند صرف'),
          invoiceNumber: t.voucherNumber,
          entryType: t.transactionType,
          debit: debit,
          credit: credit,
          balance: 0.0,
          referenceId: t.id,
          referenceType: 'safe_transaction',
        ),
      );

      // Settlement discount (خصم معجّل دفع) — createPaymentVoucher /
      // createReceiptVoucher reduce parties.balance by (amount + discount) but
      // only `amount` is the cash that moved. Pre-fix the statement rendered
      // debit/credit = amount only and dropped the discount entirely, so the
      // كشف حساب kept a phantom residual equal to the discount that never
      // matched the party-card balance. Emit the discount as its own line so
      // the running balance reconciles with parties.balance. Direction mirrors
      // the voucher: supplier payment → خصم مكتسب (debit, cuts our AP);
      // customer receipt → خصم مسموح به (credit, cuts their AR).
      if (t.discount > 0) {
        double discountDebit = 0;
        double discountCredit = 0;
        if (party.isSupplier && t.transactionType == 'payment') {
          discountDebit = t.discount;
        } else if (party.isCustomer && t.transactionType == 'receipt') {
          discountCredit = t.discount;
        }
        if (discountDebit > 0 || discountCredit > 0) {
          entries.add(
            PartyStatementEntry(
              date: t.createdAt,
              description: party.isSupplier ? 'خصم مكتسب (تسوية)' : 'خصم مسموح به (تسوية)',
              invoiceNumber: t.voucherNumber,
              entryType: 'discount',
              debit: discountDebit,
              credit: discountCredit,
              balance: 0.0,
              referenceId: t.id,
              referenceType: 'safe_transaction',
            ),
          );
        }
      }
    }

    double chequeOpeningBalance = 0;

    void addCommercialPaperStatementEntry({
      required CommercialPaperData paper,
      required DateTime date,
      required String status,
    }) {
      double debit = 0;
      double credit = 0;
      String? description;

      if (party.isCustomer && paper.direction == 'received') {
        if (status == 'pending') {
          credit = paper.amount;
          description = 'استلام شيك رقم ${paper.paperNumber}';
        } else if (status == 'bounced') {
          debit = paper.amount;
          description = 'ارتجاع شيك رقم ${paper.paperNumber}';
        }
      }

      if (party.isSupplier && paper.direction == 'issued') {
        if (status == 'pending') {
          debit = paper.amount;
          description = 'إصدار شيك رقم ${paper.paperNumber}';
        } else if (status == 'bounced') {
          credit = paper.amount;
          description = 'ارتجاع شيك صادر رقم ${paper.paperNumber}';
        }
      }

      if (description == null) return;

      if (date.isBefore(from)) {
        chequeOpeningBalance += party.isCustomer
            ? debit - credit
            : credit - debit;
        return;
      }

      if (!date.isBefore(to)) return;

      entries.add(
        PartyStatementEntry(
          date: date,
          description: description,
          invoiceNumber: paper.paperNumber,
          entryType: 'commercial_paper',
          debit: debit,
          credit: credit,
          balance: 0.0,
          referenceId: paper.id,
          referenceType: 'commercial_paper',
        ),
      );
    }

    // Spec 101: commercial-paper rows are not safe transactions. Add only
    // party-balance transitions so supplier/customer statements match the
    // cheque side-effects applied in commercial_papers_dao.
    final paperRows = await (select(commercialPapers)
          ..where((p) => p.partyId.equals(partyId))
          ..where((p) => p.createdAt.isSmallerThanValue(to)))
        .get();
    for (final paper in paperRows) {
      addCommercialPaperStatementEntry(
        paper: paper,
        date: paper.createdAt,
        status: 'pending',
      );

      final histories = await (select(paperStatusHistory)
            ..where((h) => h.paperId.equals(paper.id))
            ..where((h) => h.changedAt.isSmallerThanValue(to))
            ..orderBy([(h) => OrderingTerm.asc(h.changedAt)]))
          .get();
      for (final history in histories) {
        addCommercialPaperStatementEntry(
          paper: paper,
          date: history.changedAt,
          status: history.toStatus,
        );
      }
    }

    // Sort by date
    entries.sort((a, b) => a.date.compareTo(b.date));

    // Calculate running balance
    // For customers: Balance = Opening + Sum(Debit) - Sum(Credit) 
    // For suppliers: Balance = Opening + Sum(Credit) - Sum(Debit) (Assuming normal Credit balance)
    
    // As a simplification, we could calculate the Opening Balance from before 'from'
    // But assuming the frontend expects the exact window's running offset or total:
    // Actually, in many cases, we just want the running balance of the *visible* rows or a cumulative one.
    // Let's get the opening balance before the 'from' date.
    
    double openingBalance = 0;
    
    // Calculate opening from sales/purchases and transactions before 'from'
    if (party.isCustomer) {
      final pastSales = await customSelect(
        'SELECT COALESCE(SUM(total), 0) as amt FROM sales_invoices WHERE customer_id = ? AND invoice_date < ? ${branchId != null ? 'AND (warehouse_id IN (SELECT id FROM warehouses WHERE branch_id = ?))' : ''}',
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Include the settlement discount: a receipt voucher reduces the
      // customer's AR by (amount + discount), so the opening balance must too
      // — matching the discount statement line emitted in the window above.
      final pastReceipts = await customSelect(
        "SELECT COALESCE(SUM(t.amount + COALESCE(t.discount, 0)), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.transaction_type = 'receipt' AND t.created_at < ? ${branchId != null ? 'AND (s.branch_id = ?)' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      final pastPayments = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.transaction_type = 'payment' AND t.created_at < ? ${branchId != null ? 'AND (s.branch_id = ?)' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();

      final pastSalesReturnMemos = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t WHERE t.party_id = ? AND t.transaction_type = 'memo' AND t.category = 'sales_return_balance' AND t.created_at < ? ${branchId != null ? 'AND (t.safe_id IN (SELECT id FROM safes WHERE branch_id = ?))' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Customer balance = sales − receipts − cash refunds − balance adjustments from returns
      openingBalance = (pastSales.read<double>('amt') ?? 0)
                     - (pastReceipts.read<double>('amt') ?? 0)
                     - (pastPayments.read<double>('amt') ?? 0)
                     - (pastSalesReturnMemos.read<double>('amt') ?? 0)
                     + chequeOpeningBalance;
    } else {
      final pastPurchases = await customSelect(
        'SELECT COALESCE(SUM(total), 0) as amt FROM purchase_invoices WHERE supplier_id = ? AND invoice_date < ? ${branchId != null ? 'AND (warehouse_id IN (SELECT id FROM warehouses WHERE branch_id = ?))' : ''}',
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Include the settlement discount: a payment voucher reduces our AP to
      // the supplier by (amount + discount), so the opening balance must too
      // — matching the discount statement line emitted in the window above.
      final pastPayments = await customSelect(
        "SELECT COALESCE(SUM(t.amount + COALESCE(t.discount, 0)), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.transaction_type = 'payment' AND t.created_at < ? ${branchId != null ? 'AND (s.branch_id = ?)' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      final pastReceipts = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.transaction_type = 'receipt' AND t.created_at < ? ${branchId != null ? 'AND (s.branch_id = ?)' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      final pastPurchaseReturnMemos = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t WHERE t.party_id = ? AND t.transaction_type = 'memo' AND t.category = 'purchase_return_balance' AND t.created_at < ? ${branchId != null ? 'AND (t.safe_id IN (SELECT id FROM safes WHERE branch_id = ?))' : ''}",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Supplier balance = purchases − payments − cash receipts from supplier − balance adjustments from returns
      openingBalance = (pastPurchases.read<double>('amt') ?? 0)
                     - (pastPayments.read<double>('amt') ?? 0)
                     - (pastReceipts.read<double>('amt') ?? 0)
                     - (pastPurchaseReturnMemos.read<double>('amt') ?? 0)
                     + chequeOpeningBalance;
    }

    if (openingBalance != 0) {
      entries.insert(0, PartyStatementEntry(
        date: from,
        description: 'رصيد افتتاحي (سابق للفترة)',
        entryType: 'opening',
        debit: party.isCustomer && openingBalance > 0 ? openingBalance : (party.isSupplier && openingBalance < 0 ? openingBalance.abs() : 0),
        credit: party.isSupplier && openingBalance > 0 ? openingBalance : (party.isCustomer && openingBalance < 0 ? openingBalance.abs() : 0),
        balance: openingBalance, // Will be replaced by running balance loop
      ));
    }

    double runningBalance = openingBalance;
    final List<PartyStatementEntry> populatedEntries = [];
    
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.entryType == 'opening') {
         populatedEntries.add(e);
         continue; // balance already set to openingBalance above, runningBalance initialized
      }
      
      if (party.isCustomer) {
        runningBalance += e.debit - e.credit;
      } else {
        runningBalance += e.credit - e.debit; // supplier balance is Credit normal
      }
      
      populatedEntries.add(PartyStatementEntry(
        date: e.date,
        description: e.description,
        invoiceNumber: e.invoiceNumber,
        entryType: e.entryType,
        debit: e.debit,
        credit: e.credit,
        balance: runningBalance,
        referenceId: e.referenceId,
        referenceType: e.referenceType,
      ));
    }

    // Spec 136 field diagnostic — pin why receipts / sales-returns may not
    // surface in the customer statement on the mirror. Shows whether the rows
    // EXIST locally (creation/sync issue) vs are filtered out (display issue).
    try {
      final stByTypeCat = <String, int>{};
      for (final t in transactions) {
        final k = '${t.transactionType}/${t.category}';
        stByTypeCat[k] = (stByTypeCat[k] ?? 0) + 1;
      }
      final entryTypes = <String, int>{};
      for (final e in populatedEntries) {
        entryTypes[e.entryType] = (entryTypes[e.entryType] ?? 0) + 1;
      }
      unawaited(DiagnosticLogger.log(
          'PARTY-STATEMENT',
          'partyId=$partyId isCustomer=${party.isCustomer} '
          'safeTxnRows=${transactions.length} byTypeCat=$stByTypeCat '
          'commercialPapers=${paperRows.length} '
          'entries=${populatedEntries.length} entryTypes=$entryTypes'));
    } catch (e) {
      // Spec 136 item 6 — don't let the diagnostic hook fail silently. Stays
      // non-fatal (statement rendering must not break on a logging glitch),
      // but a swallowed error is now visible in the run log.
      debugPrint('[PartyDao] PARTY-STATEMENT diagnostic failed (non-fatal): $e');
    }

    return populatedEntries;
  }

  /// Get party transactions for statement
  Future<List<SafeTransactionData>> getPartyTransactions(int partyId) async {
    return (select(safeTransactions)
          ..where((t) => t.partyId.equals(partyId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// GAP-22: AR/AP Aging Report — overdue balances split by age buckets.
  /// [customersOnly] = true → customers (AR), false → suppliers (AP).
  /// [allowedBranchIds] بيحصر **أي أطراف تظهر** — نفس قاعدة
  /// `_watchPartiesForBranches` بالظبط: null = الكل، {ids} = الفروع دي +
  /// الأطراف العامة، {} = لا شيء.
  ///
  /// الحصر على مستوى الطرف لا الفاتورة بقصد: `p.balance` رصيد الطرف **الكلي**،
  /// والأعمار محسوبة منه. لو حصرنا الفواتير بفرع وسبنا الرصيد كلياً، الأعمدة
  /// ما تجمعش على الرصيد المعروض جنبها — نفس فئة العطل اللي في تسوية الضريبة.
  /// فالتقرير بيفضل متّسقاً داخلياً، والمحصور بيشوف أطراف فرعه وحدها.
  Future<List<ArAgingRow>> getArAgingReport({
    required DateTime asOfDate,
    bool customersOnly = true,
    Set<int>? allowedBranchIds,
  }) async {
    // نفس شكل الفلتر في _watchPartiesForBranches — CSV مطابَق بـLIKE على
    // branch_ids، مع إبقاء الأطراف العامة مرئية.
    final String scopeClause;
    if (allowedBranchIds == null) {
      scopeClause = '';
    } else if (allowedBranchIds.isEmpty) {
      scopeClause = ' AND 1 = 0'; // فشل مقفول
    } else {
      final ors = allowedBranchIds
          .map((id) =>
              "(',' || COALESCE(p.branch_ids, '') || ',') LIKE '%,$id,%'")
          .join(' OR ');
      scopeClause = ' AND (p.is_global = 1 OR $ors)';
    }
    // Drift stores DateTime as Unix **seconds** (BIGINT) — see [dateVar] in
    // database.dart. So the comparison is `julianday(col, 'unixepoch')`.
    // القسمةُ على ألفٍ هنا كانت تقع **مرّتين** (drift + SQL) فينهار كلُّ تاريخٍ
    // إلى ١٩٧٠ ويصير عمرُه ~٢٠٬٠٠٠ يوم ⇒ كلُّ فاتورةٍ غير مسدَّدة في خانة ٩٠+.
    final asOf = dateVar(asOfDate);

    if (customersOnly) {
      // AR aging — join sales_invoices on customer_id
      final rows = await customSelect('''
        SELECT
          p.id,
          p.name,
          p.balance,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(si.due_date, si.invoice_date), 'unixepoch') <= 30
            THEN MAX(si.total - si.paid - COALESCE(si.rounding_adjustment, 0), 0) ELSE 0 END), 0) AS bucket_0_30,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(si.due_date, si.invoice_date), 'unixepoch') BETWEEN 31 AND 60
            THEN MAX(si.total - si.paid - COALESCE(si.rounding_adjustment, 0), 0) ELSE 0 END), 0) AS bucket_31_60,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(si.due_date, si.invoice_date), 'unixepoch') BETWEEN 61 AND 90
            THEN MAX(si.total - si.paid - COALESCE(si.rounding_adjustment, 0), 0) ELSE 0 END), 0) AS bucket_61_90,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(si.due_date, si.invoice_date), 'unixepoch') > 90
            THEN MAX(si.total - si.paid - COALESCE(si.rounding_adjustment, 0), 0) ELSE 0 END), 0) AS bucket_90_plus
        FROM parties p
        LEFT JOIN sales_invoices si
          ON si.customer_id = p.id
          AND si.status NOT IN ('returned', 'cancelled')
          AND si.is_deleted = 0
          AND si.paid + COALESCE(si.rounding_adjustment, 0) < si.total
          AND si.invoice_date <= ?
        WHERE p.is_active = 1
          AND p.is_customer = 1
          AND p.balance > 0.01
          $scopeClause
        GROUP BY p.id
        ORDER BY p.balance DESC
      ''', variables: [
        asOf, asOf, asOf, asOf, asOf,
      ], readsFrom: {parties, salesInvoices}).get();

      return rows.map((r) => ArAgingRow(
        partyId:      r.data['id'] as int,
        partyName:    r.data['name'] as String,
        totalBalance: (r.data['balance'] as num).toDouble(),
        bucket0_30:   (r.data['bucket_0_30'] as num).toDouble(),
        bucket31_60:  (r.data['bucket_31_60'] as num).toDouble(),
        bucket61_90:  (r.data['bucket_61_90'] as num).toDouble(),
        bucket90Plus: (r.data['bucket_90_plus'] as num).toDouble(),
      )).toList();
    } else {
      // AP aging — join purchase_invoices on supplier_id
      final rows = await customSelect('''
        SELECT
          p.id,
          p.name,
          p.balance,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(pi.due_date, pi.invoice_date), 'unixepoch') <= 30
            THEN MAX(pi.total - pi.paid, 0) ELSE 0 END), 0) AS bucket_0_30,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(pi.due_date, pi.invoice_date), 'unixepoch') BETWEEN 31 AND 60
            THEN MAX(pi.total - pi.paid, 0) ELSE 0 END), 0) AS bucket_31_60,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(pi.due_date, pi.invoice_date), 'unixepoch') BETWEEN 61 AND 90
            THEN MAX(pi.total - pi.paid, 0) ELSE 0 END), 0) AS bucket_61_90,
          COALESCE(SUM(CASE WHEN julianday(?, 'unixepoch') - julianday(COALESCE(pi.due_date, pi.invoice_date), 'unixepoch') > 90
            THEN MAX(pi.total - pi.paid, 0) ELSE 0 END), 0) AS bucket_90_plus
        FROM parties p
        LEFT JOIN purchase_invoices pi
          ON pi.supplier_id = p.id
          AND pi.is_deleted = 0
          AND pi.paid < pi.total
          AND pi.invoice_date <= ?
        WHERE p.is_active = 1
          AND p.is_supplier = 1
          AND p.balance > 0.01
          $scopeClause
        GROUP BY p.id
        ORDER BY p.balance DESC
      ''', variables: [
        asOf, asOf, asOf, asOf, asOf,
      ], readsFrom: {parties, purchaseInvoices}).get();

      return rows.map((r) => ArAgingRow(
        partyId:      r.data['id'] as int,
        partyName:    r.data['name'] as String,
        totalBalance: (r.data['balance'] as num).toDouble(),
        bucket0_30:   (r.data['bucket_0_30'] as num).toDouble(),
        bucket31_60:  (r.data['bucket_31_60'] as num).toDouble(),
        bucket61_90:  (r.data['bucket_61_90'] as num).toDouble(),
        bucket90Plus: (r.data['bucket_90_plus'] as num).toDouble(),
      )).toList();
    }
  }

  /// GAP-21: AR Reconciliation — compare parties.balance aggregate with GL
  /// receivables account balance. Returns null if receivables account not mapped.
  ///
  /// Note: per-customer reconciliation is not possible without party_id on
  /// journal_entry_lines. This returns aggregate totals only.
  Future<ArReconciliation?> getArReconciliation() async {
    // 1. Sum of all customer card balances
    final customerBalances = await (select(parties)
          ..where((p) => p.isCustomer.equals(true) & p.isActive.equals(true)))
        .get();
    final totalCardBalance = customerBalances.fold(0.0, (sum, p) => sum + p.balance);

    // 2. Find the receivables account
    final arCode = await accountingDao.getMappedAccountCode(
      'receivables', AccountingDao.accountPurposes['receivables']!,
    );
    final arAccount = await accountingDao.getAccountByCode(arCode);
    if (arAccount == null) return null;

    // 3. رصيد الأستاذ للذمم = حساب المراقبة **وكل الحسابات الفرعية تحته**.
    //
    // القيود عمرها ما بتنزل على المراقبة نفسه: `_resolvePartySubAccount`
    // بيرجّع `party.accountId` — الحساب الفرعي للعميل (`1121-00001`) اللي
    // بيتخلق تحت ١١٢١ عند إنشاء أي عميل. فالتجميع على المراقبة وحده كان
    // بيرجّع **صفر دايماً**، و`difference` = كل رصيد العملاء.
    //
    // النتيجة: `reconciliation_service.dart:377` بيسجّل إنذار في
    // `field_audit_logs` وشاشة التقارير بتعرض فرق وهمي بقيمة الـAR كلها،
    // والدفاتر سليمة ١٠٠٪. ده على الأغلب مصدر «الإيجابيات الكاذبة» في
    // التقارير السابقة.
    //
    // والفلتر `is_posted`/`is_deleted` كان ناقص كمان — على عكس
    // `getPartyBalanceMismatches` في نفس الملف اللي بيفلتر صح، فمسودّة قيد
    // أو قيد محذوف كان بيتحسب في الرصيد.
    final arSubtree = await accountSubtreeIds(arAccount.id);
    final placeholders = List.filled(arSubtree.length, '?').join(',');
    final glRow = await customSelect(
      'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS bal '
      'FROM journal_entry_lines l '
      'JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE l.account_id IN ($placeholders) '
      'AND e.is_posted = ${sqlBool(true)} AND e.is_deleted = ${sqlBool(false)}',
      variables: arSubtree.map((id) => Variable<int>(id)).toList(),
      readsFrom: {journalEntryLines, journalEntries},
    ).getSingle();
    final totalGlBalance = (glRow.data['bal'] as num).toDouble();

    return ArReconciliation(
      totalCardBalance: totalCardBalance,
      totalGlBalance: totalGlBalance,
      difference: totalCardBalance - totalGlBalance,
      customerCount: customerBalances.length,
      receivablesAccountCode: arCode,
      receivablesAccountName: arAccount.name,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Day-17: Per-Party Balance Reconciliation
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns every party whose `parties.balance` deviates from the sum of
  /// posted GL journal-entry lines on its dedicated sub-account by more than
  /// [tolerance] (default 0.01).
  ///
  /// Only parties with a linked GL account (`accountId IS NOT NULL`) and that
  /// have not been soft-deleted are considered. Journal entries with
  /// `is_deleted = 1` are excluded so reversals are counted correctly.
  ///
  /// Use this for nightly reconciliation jobs or an admin health-check screen.
  Future<List<PartyBalanceMismatch>> getPartyBalanceMismatches({
    double tolerance = 0.01,
  }) async {
    // Note: the filter on is_posted/is_deleted must live inside the derived
    // table (live_jel), NOT as a secondary LEFT JOIN on journal_entries.
    // A two-step LEFT JOIN keeps deleted-entry JEL rows in the result set
    // (LEFT JOIN only NULLs out the je.* columns, not the jel.* ones),
    // causing those lines to be included in SUM(jel.debit). The derived
    // table pre-filters to posted, non-deleted entries before joining.
    final rows = await customSelect(
      '''
      SELECT
        p.id          AS party_id,
        p.name        AS party_name,
        p.is_customer AS is_customer,
        p.is_supplier AS is_supplier,
        p.balance     AS card_balance,
        COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) AS gl_balance
      FROM parties p
      LEFT JOIN (
        SELECT jel.account_id, jel.debit, jel.credit
        FROM journal_entry_lines jel
        INNER JOIN journal_entries je
               ON je.id = jel.entry_id
              AND je.is_posted = 1
              AND je.is_deleted = 0
      ) live_jel ON live_jel.account_id = p.account_id
      WHERE p.account_id IS NOT NULL
        AND p.deleted_at IS NULL
      GROUP BY p.id, p.name, p.is_customer, p.is_supplier, p.balance
      HAVING ABS(p.balance - COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0)) > ?
      ORDER BY ABS(p.balance - COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0)) DESC
      ''',
      variables: [Variable<double>(tolerance)],
    ).get();

    return rows.map((r) {
      final cardBalance = (r.data['card_balance'] as num).toDouble();
      final glBalance   = (r.data['gl_balance']   as num).toDouble();
      return PartyBalanceMismatch(
        partyId:     r.data['party_id'] as int,
        partyName:   r.data['party_name'] as String,
        isCustomer:  r.data['is_customer'] == true || r.data['is_customer'] == 1,
        isSupplier:  r.data['is_supplier'] == true || r.data['is_supplier'] == 1,
        cardBalance: cardBalance,
        glBalance:   glBalance,
        delta:       cardBalance - glBalance,
      );
    }).toList();
  }
}

/// Helper class for party summary with totals
class PartySummary {
  final int partyId;
  final String partyName;
  final bool isCustomer;
  final bool isSupplier;
  final double currentBalance;
  final double totalInvoices;
  final double totalPayments;
  final int invoiceCount;
  final int paymentCount;

  PartySummary({
    required this.partyId,
    required this.partyName,
    required this.isCustomer,
    required this.isSupplier,
    required this.currentBalance,
    required this.totalInvoices,
    required this.totalPayments,
    required this.invoiceCount,
    required this.paymentCount,
  });
}

/// Party statement entry for account statements
class PartyStatementEntry {
  final DateTime date;
  final String description;
  final String? invoiceNumber;
  final String entryType; // 'opening', 'invoice', 'payment', 'receipt'
  final double debit;
  final double credit;
  final double balance;
  final int? referenceId;
  final String? referenceType;

  PartyStatementEntry({
    required this.date,
    required this.description,
    this.invoiceNumber,
    required this.entryType,
    required this.debit,
    required this.credit,
    required this.balance,
    this.referenceId,
    this.referenceType,
  });
}

/// GAP-21: AR reconciliation result — aggregate comparison of parties.balance vs GL
class ArReconciliation {
  final double totalCardBalance;   // SUM(parties.balance) for all customers
  final double totalGlBalance;     // SUM(debit-credit) on receivables account in GL
  final double difference;         // cardBalance - glBalance (should be ~0.0)
  final int customerCount;
  final String receivablesAccountCode;
  final String receivablesAccountName;

  const ArReconciliation({
    required this.totalCardBalance,
    required this.totalGlBalance,
    required this.difference,
    required this.customerCount,
    required this.receivablesAccountCode,
    required this.receivablesAccountName,
  });

  bool get isBalanced => difference.abs() < 0.01;
}

/// GAP-22: Single row in an AR/AP aging report.
class ArAgingRow {
  final int partyId;
  final String partyName;
  final double totalBalance;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90Plus;

  const ArAgingRow({
    required this.partyId,
    required this.partyName,
    required this.totalBalance,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90Plus,
  });

  double get outstandingTotal => bucket0_30 + bucket31_60 + bucket61_90 + bucket90Plus;
}

/// Day-17: A single party whose `parties.balance` does not match the
/// sum of posted GL journal-entry lines on its dedicated sub-account.
class PartyBalanceMismatch {
  final int partyId;
  final String partyName;
  final bool isCustomer;
  final bool isSupplier;

  /// The balance stored directly on the `parties` row.
  final double cardBalance;

  /// SUM(debit) − SUM(credit) for all posted, non-deleted JE lines on
  /// the party's linked GL sub-account.
  final double glBalance;

  /// `cardBalance − glBalance` (positive → card is higher than GL).
  final double delta;

  const PartyBalanceMismatch({
    required this.partyId,
    required this.partyName,
    required this.isCustomer,
    required this.isSupplier,
    required this.cardBalance,
    required this.glBalance,
    required this.delta,
  });

  bool get isBalanced => delta.abs() < 0.01;
}

// ═══════════════════════════════════════════════════════════════════════════
// PARTY GROUP DAO — تصنيفات العملاء والموردين
// ═══════════════════════════════════════════════════════════════════════════

/// Snapshot of a party group together with a live member count. Used by
/// the management screen so the admin can see group sizes at a glance.
class PartyGroupWithCount {
  final PartyGroup group;
  final int memberCount;
  const PartyGroupWithCount(this.group, this.memberCount);
}

extension PartyGroupDao on AppDatabase {
  /// Watch ALL party groups (active + archived) ordered alphabetically.
  /// The UI layer decides whether to hide archived ones.
  Stream<List<PartyGroup>> watchPartyGroups() {
    return (select(partyGroups)
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .watch();
  }

  /// Watch active party groups only — useful for dropdowns where
  /// archived groups shouldn't appear.
  Stream<List<PartyGroup>> watchActivePartyGroups() {
    return (select(partyGroups)
          ..where((g) => g.isActive.equals(true))
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .watch();
  }

  /// Get active party groups filtered by type.
  /// [type] must be `'customer'`, `'supplier'`, or `'both'`. Rows
  /// tagged `'both'` always match — they work for either side.
  Future<List<PartyGroup>> getPartyGroupsByType(String type) {
    return (select(partyGroups)
          ..where((g) => g.type.equals(type) | g.type.equals('both'))
          ..where((g) => g.isActive.equals(true))
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .get();
  }

  /// Stream the list of groups together with their current member counts.
  /// Triggers on any write to `parties` or `partyGroups` so the UI
  /// stays live without explicit invalidations.
  Stream<List<PartyGroupWithCount>> watchPartyGroupsWithCounts() {
    final groupCount = parties.id.count();
    final query = select(partyGroups).join([
      leftOuterJoin(
        parties,
        parties.groupId.equalsExp(partyGroups.id) &
            parties.isActive.equals(true),
      ),
    ])
      ..addColumns([groupCount])
      ..groupBy([partyGroups.id])
      ..orderBy([OrderingTerm.asc(partyGroups.name)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final g = row.readTable(partyGroups);
        final count = row.read(groupCount) ?? 0;
        return PartyGroupWithCount(g, count);
      }).toList();
    });
  }

  /// Count a single group's active members.
  Future<int> getGroupMemberCount(int groupId) async {
    final cnt = parties.id.count();
    final row = await (selectOnly(parties)
          ..addColumns([cnt])
          ..where(parties.groupId.equals(groupId) & parties.isActive.equals(true)))
        .getSingle();
    return row.read(cnt) ?? 0;
  }

  /// Stream active members of a given group, ordered by name.
  Stream<List<Party>> watchGroupMembers(int groupId) {
    return (select(parties)
          ..where((p) => p.groupId.equals(groupId) & p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Create a party group with full business-rule metadata.
  /// Only `name` is required; the rest default to sensible values.
  Future<int> createPartyGroup({
    required String name,
    String type = 'both',
    String? description,
    double defaultDiscount = 0,
    String? defaultPaymentTerms,
    String? priceLevel,
    String? notes,
    int? parentGroupId,
  }) async {
    final companion = PartyGroupsCompanion.insert(
      name: name,
      type: Value(type),
      description: Value(description),
      defaultDiscount: Value(defaultDiscount),
      defaultPaymentTerms: Value(defaultPaymentTerms),
      priceLevel: Value(priceLevel),
      notes: Value(notes),
      parentGroupId: Value(parentGroupId),
      globalId: Value(UuidV7.generate()),
    );
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createPartyGroup(companion);
      if (serverId != null) return serverId;
    }
    return into(partyGroups).insert(companion);
  }

  /// Update a party group using a Companion.
  Future<bool> updatePartyGroup(int id, PartyGroupsCompanion data) async {
    if (SyncInterceptor.isClientMode) {
      final map = <String, dynamic>{};
      if (data.name.present) map['name'] = data.name.value;
      if (data.type.present) map['type'] = data.type.value;
      if (data.description.present) map['description'] = data.description.value;
      if (data.defaultDiscount.present) map['defaultDiscount'] = data.defaultDiscount.value;
      if (data.defaultPaymentTerms.present) map['defaultPaymentTerms'] = data.defaultPaymentTerms.value;
      if (data.priceLevel.present) map['priceLevel'] = data.priceLevel.value;
      if (data.notes.present) map['notes'] = data.notes.value;
      if (data.isActive.present) map['isActive'] = data.isActive.value;
      await SyncInterceptor.instance?.updatePartyGroup(id, map);
    }
    return (update(partyGroups)..where((g) => g.id.equals(id)))
        .write(data)
        .then((rows) => rows > 0);
  }

  /// Delete a party group. Refuses if it still has members.
  Future<bool> deletePartyGroup(int id) async {
    final membersRemaining = await getGroupMemberCount(id);
    if (membersRemaining > 0) {
      throw Exception(
        'لا يمكن حذف المجموعة لأن بها $membersRemaining طرف. '
        'انقل الأطراف لمجموعة أخرى أولاً أو قم بتعطيل المجموعة بدلاً من الحذف.',
      );
    }
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deletePartyGroup(id);
    }
    final rows = await (delete(partyGroups)..where((g) => g.id.equals(id))).go();
    return rows > 0;
  }

  /// Toggle the active state of a group (soft archive/restore).
  Future<bool> setPartyGroupActive(int id, bool isActive) {
    return (update(partyGroups)..where((g) => g.id.equals(id)))
        .write(PartyGroupsCompanion(isActive: Value(isActive)))
        .then((rows) => rows > 0);
  }

  /// Assign or detach a single party from a group. Pass `null` to detach.
  Future<void> assignPartyToGroup(int partyId, int? groupId) {
    return (update(parties)..where((p) => p.id.equals(partyId)))
        .write(PartiesCompanion(groupId: Value(groupId)));
  }

  /// Bulk-assign a list of parties to a group. Useful for the group
  /// detail screen's "add members" dialog.
  Future<void> assignPartiesToGroup(List<int> partyIds, int? groupId) async {
    if (partyIds.isEmpty) return;
    await transaction(() async {
      for (final pid in partyIds) {
        await (update(parties)..where((p) => p.id.equals(pid)))
            .write(PartiesCompanion(groupId: Value(groupId)));
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVER-SIDE DUPLICATE PARTIES DEDUP (Spec 084d)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Field smoke V148 reported 3 delivery-company parties duplicated 2-3
  // times each on a production server (only the first row of each name
  // had a balance; copies had 0.000). The sync strategy emits a
  // SYNC-WARN line on name+phone fallback matches but never merges —
  // operator had to fix manually via SQL.
  //
  // Mirrors Spec 084c (branches dedup) — keep the two implementations
  // in lockstep when the audit/repair pattern evolves.
  //
  // Server mode only. The Settings UI gates the section on
  // `NetworkService.instance.isServerRunning`.

  /// Find groups of active parties sharing a name. Within each group,
  /// the row with the highest reference count is the suggested
  /// canonical pick (ties broken by lowest id). For parties, the
  /// "attached transactional refs" check is wider than branches —
  /// sales/purchase invoices, safe transactions (vouchers), and
  /// commercial papers all anchor a party to real money in the books.
  Future<List<DuplicatePartyGroup>> auditDuplicateParties() async {
    final rows = await customSelect(r'''
      WITH dup_names AS (
        SELECT name FROM parties
        WHERE is_active = TRUE
        GROUP BY name HAVING COUNT(*) > 1
      ),
      ref_counts AS (
        SELECT p.id, p.name, p.phone, p.balance, p.is_customer, p.is_supplier,
               p.global_id,
               (SELECT COUNT(*) FROM sales_invoices    WHERE customer_id = p.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE supplier_id = p.id)
             + (SELECT COUNT(*) FROM safe_transactions WHERE party_id    = p.id)
             + (SELECT COUNT(*) FROM commercial_papers WHERE party_id    = p.id)
               AS ref_count,
               (SELECT COUNT(*) FROM sales_invoices    WHERE customer_id = p.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE supplier_id = p.id)
             + (SELECT COUNT(*) FROM safe_transactions WHERE party_id    = p.id)
             + (SELECT COUNT(*) FROM commercial_papers WHERE party_id    = p.id)
               AS attached_txn_refs
        FROM parties p
        WHERE p.is_active = TRUE
          AND p.name IN (SELECT name FROM dup_names)
      )
      SELECT id, name, phone, balance, is_customer, is_supplier,
             global_id, ref_count, attached_txn_refs
      FROM ref_counts
      ORDER BY name, ref_count DESC, id ASC
    ''').get();

    final byName = <String, List<DuplicatePartyRow>>{};
    for (final r in rows) {
      final name = r.read<String>('name');
      byName.putIfAbsent(name, () => []).add(DuplicatePartyRow(
            id: r.read<int>('id'),
            name: name,
            phone: r.read<String?>('phone'),
            balance: (r.data['balance'] as num?)?.toDouble() ?? 0,
            isCustomer: (r.data['is_customer'] as int? ?? 0) == 1 ||
                r.data['is_customer'] == true,
            isSupplier: (r.data['is_supplier'] as int? ?? 0) == 1 ||
                r.data['is_supplier'] == true,
            globalId: r.read<String?>('global_id'),
            refCount: r.read<int>('ref_count'),
            attachedTxnRefs: r.read<int>('attached_txn_refs'),
          ));
    }

    return byName.entries.map((e) {
      final all = e.value;
      return DuplicatePartyGroup(
        name: e.key,
        canonical: all.first,
        duplicates: all.skip(1).toList(),
      );
    }).toList();
  }

  /// Run the dedup repair. Duplicates with ANY attached transactional
  /// row (invoice / voucher / commercial paper) are SKIPPED — those
  /// must be manually merged via party-merge tools (not part of this
  /// spec). Duplicates with zero refs are safely soft-deleted.
  ///
  /// All steps run inside `transaction()`; any exception rolls back.
  /// Each merged or skipped duplicate emits one `DiagnosticLogger`
  /// line tagged `PARTY-DEDUP`.
  Future<PartyDedupResult> repairDuplicateParties() async {
    return await transaction(() async {
      final groups = await auditDuplicateParties();
      final merged = <MergedPartyDedupRecord>[];
      final skipped = <SkippedPartyDedupRecord>[];

      for (final g in groups) {
        for (final dup in g.duplicates) {
          if (dup.attachedTxnRefs > 0) {
            skipped.add(SkippedPartyDedupRecord(
              dupId: dup.id,
              canonicalId: g.canonical.id,
              name: g.name,
              attachedTxnRefs: dup.attachedTxnRefs,
              balance: dup.balance,
            ));
            await DiagnosticLogger.log(
              'PARTY-DEDUP',
              'SKIP dupId=${dup.id} → canonicalId=${g.canonical.id} '
                  'name="${g.name}" attachedTxnRefs=${dup.attachedTxnRefs} '
                  'balance=${dup.balance}',
            );
            continue;
          }

          // Soft-delete the duplicate. Parties without any
          // transactional refs are safe to retire — they're typically
          // sync-fallback duplicates that never accumulated history.
          // The party's balance is non-load-bearing in this case
          // (transactions adjust it; with zero refs the balance
          // must also be zero or close to it).
          await (update(parties)..where((p) => p.id.equals(dup.id))).write(
            PartiesCompanion(
              isActive: const Value(false),
              deletedAt: Value(DateTime.now()),
              lastModifiedAt: Value(DateTime.now()),
            ),
          );

          merged.add(MergedPartyDedupRecord(
            dupId: dup.id,
            canonicalId: g.canonical.id,
            name: g.name,
          ));
          await DiagnosticLogger.log(
            'PARTY-DEDUP',
            'merged dupId=${dup.id} → canonicalId=${g.canonical.id} '
                'name="${g.name}" (no attached refs — safe soft-delete)',
          );
        }
      }

      return PartyDedupResult(merged: merged, skipped: skipped);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Spec 084d — parties dedup data classes
// ═══════════════════════════════════════════════════════════════════════════

class DuplicatePartyRow {
  final int id;
  final String name;
  final String? phone;
  final double balance;
  final bool isCustomer;
  final bool isSupplier;
  final String? globalId;
  final int refCount;
  final int attachedTxnRefs;

  const DuplicatePartyRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.isCustomer,
    required this.isSupplier,
    required this.globalId,
    required this.refCount,
    required this.attachedTxnRefs,
  });
}

class DuplicatePartyGroup {
  final String name;
  final DuplicatePartyRow canonical;
  final List<DuplicatePartyRow> duplicates;

  const DuplicatePartyGroup({
    required this.name,
    required this.canonical,
    required this.duplicates,
  });

  bool get hasDuplicates => duplicates.isNotEmpty;
}

class MergedPartyDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;

  const MergedPartyDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
  });
}

class SkippedPartyDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;
  final int attachedTxnRefs;
  final double balance;

  const SkippedPartyDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
    required this.attachedTxnRefs,
    required this.balance,
  });
}

class PartyDedupResult {
  final List<MergedPartyDedupRecord> merged;
  final List<SkippedPartyDedupRecord> skipped;

  const PartyDedupResult({
    required this.merged,
    required this.skipped,
  });

  int get mergedCount => merged.length;
  int get skippedCount => skipped.length;
  bool get hasSkipped => skipped.isNotEmpty;
}
