// Party reads: watchers, paged lists, branch-scoped streams, getPartyById, invoice due-date snapshot.
part of '../database.dart';

extension PartyReadsDao on AppDatabase {
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
    // 🔴 **القاعدةُ في `domain/models` لا هنا.** الشاشةُ تعرض الاستحقاقَ
    // مرآةً قبل الحفظ (قرارُ المالك 2026-09-18)، وحارسُ
    // `presentation_db_import_guard` يمنعها من مناداة هذه الدالّة. فلو
    // بقيت القاعدةُ هنا لكتبتها الشاشةُ بيدها — ومرآةٌ تحسب بنفسها ليست
    // مرآة: يقرأ المستخدمُ تاريخاً ويُختَم على المستند غيرُه، وعليه تُبنى
    // أعمارُ الدين وتنبيهاتُ التأخّر.
    return resolveDueDateFromTerms(
      invoiceDate: invoiceDate,
      paymentTermsDays: party?.paymentTermsDays,
    );
  }
}
