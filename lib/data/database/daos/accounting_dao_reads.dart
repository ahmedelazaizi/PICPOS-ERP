// ignore_for_file: library_private_types_in_public_api
part of '../database.dart';

extension AccountingDaoReadsExt on AppDatabase {
  /// معرّفات الحساب **وكل أبنائه** بالشجرة (`parent_id`).
  ///
  /// ── ليه مش `code LIKE 'X%'` ────────────────────────────────────────────
  /// البادئة النصية بتشتغل صح للأبناء الحقيقيين (`412` → `4121`) وبتكسر لما
  /// يبقى فيه **شقيق** بادئته أطول. وده موجود في الدليل المزروع فعلاً:
  /// `621` «رواتب وأجور» شقيق لـ`6210`…`6217` (كلهم `detail` تحت `62`) مش
  /// أب ليهم. فكارت أستاذ الرواتب كان بيضم رخص حكومية ونظافة وسفر وإهلاك
  /// ومتنوعة وخصم مسموح وعجز مخزون وعجز نقدي — كارت الأستاذ بيقول رقم
  /// وميزان المراجعة (اللي بيجمّع per-account) بيقول رقم تاني لنفس الحساب.
  ///
  /// نفس الجذر بيضرب مطابقة الذمم: القيود بتنزل على الحساب الفرعي للعميل
  /// (`1121-00001`) مش على حساب المراقبة `1121`، فأي تجميع على المراقبة
  /// وحده بيرجّع صفر.
  ///
  /// الاستعلام تكراري (`WITH RECURSIVE`) ومدعوم في SQLite وPostgreSQL.
  Future<List<int>> accountSubtreeIds(int accountId) async {
    final rows = await customSelect(
      'WITH RECURSIVE sub(id) AS ('
      '  SELECT id FROM accounts WHERE id = ?'
      '  UNION ALL'
      '  SELECT a.id FROM accounts a JOIN sub ON a.parent_id = sub.id'
      ') SELECT id FROM sub',
      variables: [Variable<int>(accountId)],
      readsFrom: {accounts},
    ).get();
    return rows.map((r) => r.data['id'] as int).toList();
  }


  /// Strips audit-trail hash suffix [HASH:...] from description for clean display.
  /// The hash remains in the DB for integrity verification (ICR-03).
  static String _cleanHashFromDescription(dynamic desc) {
    if (desc == null) return '';
    final s = desc.toString();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'\s*\[HASH:[a-f0-9]{64}\]'), '').trim();
  }

  /// Safely parse SQLite booleans from raw dataset, avoiding type cast errors across platforms.
  static bool _parseSystemBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    return value.toString() == '1' || value.toString().toLowerCase() == 'true';
  }

/// Validate that a given date falls within an open fiscal year and an open accounting period.
  /// Throws an [Exception] if no fiscal year exists or the period is closed.
  Future<void> validateFinancialPeriod(DateTime date, {String operation = 'العملية'}) async {
    // Check fiscal year existence and closure
    final fy = await getFiscalYearByDate(date);
    if (fy == null) {
      throw Exception(
        'لا توجد سنة مالية تغطي تاريخ $operation. '
        'يرجى إنشاء سنة مالية أولاً من إعدادات المحاسبة ← السنوات المالية.',
      );
    }
    if (fy.isClosed) {
      throw Exception('لا يمكن تنفيذ $operation في سنة مالية مغلقة (${fy.name})');
    }

    // Check monthly accounting period closure.
    //
    // `getSingleOrNull` throws "Bad state: Too many elements" if the table
    // happens to contain more than one row for the same (month, year) —
    // which we've seen happen in the field due to sync-replay / seed
    // duplication. Adding `.limit(1)` keeps this check defensive even
    // when the data has drifted: we only need to know *whether* a closed
    // period exists for that month, not enumerate every copy of it.
    final closedPeriod = await (select(accountingPeriods)
          ..where((p) => p.month.equals(date.month))
          ..where((p) => p.year.equals(date.year))
          ..where((p) => p.isClosed.equals(true))
          ..limit(1))
        .getSingleOrNull();

    if (closedPeriod != null) {
      throw Exception('لا يمكن تنفيذ $operation في فترة محاسبية مغلقة (${closedPeriod.name})');
    }
  }


  /// PIR D-07: Atomic entry number generation using DocumentSequences table.
  ///
  /// Replaces the racy MAX+1 approach with a serialised counter that is safe
  /// under concurrent writes. The sequence key is `JE-YYYY` so the counter
  /// resets each calendar year, preserving the `JE-2026-00001` output format.
  /// Wrapped in a transaction so the read-increment-write triple is atomic
  /// (SQLite serialises concurrent transactions).
  Future<String> _generateEntryNumber() async {
    final now = DateTime.now();
    final seqPrefix = 'JE-${now.year}';
    final displayPrefix = '$seqPrefix-';

    return transaction(() async {
      var seq = await (select(documentSequences)
            ..where((s) => s.prefix.equals(seqPrefix))
            ..limit(1))
          .getSingleOrNull();

      int nextSeq;
      if (seq == null) {
        // First entry for this year: bootstrap from any existing JE rows so
        // the new counter never re-issues a number already in the DB.
        final maxEntry = journalEntries.entryNumber.max();
        final existing = await (selectOnly(journalEntries)
              ..addColumns([maxEntry])
              ..where(journalEntries.entryNumber.like('$displayPrefix%')))
            .map((row) => row.read(maxEntry))
            .getSingle();

        nextSeq = 1;
        if (existing != null && existing.startsWith(displayPrefix)) {
          final seqStr = existing.substring(displayPrefix.length);
          nextSeq = (int.tryParse(seqStr) ?? 0) + 1;
        }

        await into(documentSequences).insert(
          DocumentSequencesCompanion.insert(
            prefix: seqPrefix,
            nextValue: Value(nextSeq + 1),
          ),
        );
      } else {
        nextSeq = seq.nextValue;
        await (update(documentSequences)
              ..where((s) => s.prefix.equals(seqPrefix)))
            .write(DocumentSequencesCompanion(nextValue: Value(nextSeq + 1)));
      }

      return '$displayPrefix${nextSeq.toString().padLeft(5, '0')}';
    });
  }


  // --- Fiscal Years managed below ---

  /// Get all cost centers (Spec 111 — excludes soft-deleted)
  Future<List<CostCenter>> getCostCenters() {
    return (select(costCenters)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }


  /// Get active cost centers only (Spec 111 — excludes soft-deleted)
  Future<List<CostCenter>> getActiveCostCenters() {
    return (select(costCenters)
          ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.code)]))
        .get();
  }


  /// Watch all cost centers (reactive, Spec 111 — excludes soft-deleted)
  Stream<List<CostCenter>> watchCostCenters() {
    return (select(costCenters)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.code)]))
        .watch();
  }


  /// Spec 150 (b) — surplus "plug" accounts posted by variance/surplus
  /// settlement JEs (cycle count, stock audit, shift-close cash count). Each
  /// such JE is `Dr <asset> / Cr <surplus-revenue>` and createJournalEntry
  /// stamps the source branch's cost center onto EVERY line, so both legs
  /// land on that center and clutter its ledger even though it didn't earn
  /// the surplus. We exclude the WHOLE entry (both legs) — dropping only the
  /// revenue code would orphan the asset debit and skew the balance by the
  /// surplus amount. Matched by exact code, NOT by revenue nature, so a
  /// center's genuine sales/service revenue still shows up.
  static final _costCenterVarianceCodes = [
    accountPurposes['inventory_surplus']!, // 4317 فائض مخزون
    accountPurposes['cash_surplus']!, // 4318 فائض نقدي
  ];

  /// SQL fragment: exclude any journal entry that carries a surplus-plug leg.
  /// Placeholders are bound with [_costCenterVarianceCodes] in order.
  String get _excludeVarianceEntriesSql {
    final ph = List.filled(_costCenterVarianceCodes.length, '?').join(',');
    return 'e.id NOT IN (SELECT l2.entry_id FROM journal_entry_lines l2 '
        'JOIN accounts a2 ON l2.account_id = a2.id WHERE a2.code IN ($ph))';
  }

  /// Get cost center balance summary (total debit & credit from journal lines)
  Future<Map<String, double>> getCostCenterBalance(int costCenterId) async {
    // H-06: Join journal_entries to check is_posted status.
    // Spec 150 (d): header-fallback predicate + is_deleted filter matching
    // getCostCenterLedger, so the balance card reconciles with the ledger.
    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);
    final result = await customSelect(
      '''SELECT COALESCE(SUM(l.debit), 0) as total_debit, COALESCE(SUM(l.credit), 0) as total_credit
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE (l.cost_center_id = ? OR (l.cost_center_id IS NULL AND e.cost_center_id = ?))
           AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse
           AND $_excludeVarianceEntriesSql''',
      variables: [
        Variable(costCenterId),
        Variable(costCenterId),
        ..._costCenterVarianceCodes.map((c) => Variable(c)),
      ],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    return {
      'debit': (result.data['total_debit'] as num?)?.toDouble() ?? 0.0,
      'credit': (result.data['total_credit'] as num?)?.toDouble() ?? 0.0,
    };
  }


  /// Get all activity profiles
  Future<List<ActivityProfile>> getActivityProfiles() {
    return (select(activityProfiles)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }


  // --- Accounts managed below ---

  /// Get journal entries with filtering.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets.
  Future<List<JournalEntryData>> getJournalEntries({
    DateTime? from,
    DateTime? to,
    int limit = 500,
    int offset = 0,
  }) async {
    final query = select(journalEntries).join([
      leftOuterJoin(costCenters, costCenters.id.equalsExp(journalEntries.costCenterId))
    ]);

    Expression<bool> filter = journalEntries.isDeleted.equals(false);
    if (from != null) {
      final startOfDay = DateTime(from.year, from.month, from.day);
      filter = filter & journalEntries.entryDate.isBiggerOrEqual(Variable(startOfDay));
    }
    if (to != null) {
      final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
      filter = filter & journalEntries.entryDate.isSmallerOrEqual(Variable(endOfDay));
    }
    query.where(filter);
    query.orderBy([OrderingTerm.desc(journalEntries.entryDate)]);
    query.limit(limit, offset: offset);

    final rows = await query.get();
    return rows.map((row) {
      final entry = row.readTable(journalEntries);
      final cc = row.readTableOrNull(costCenters);
      if (cc != null) {
        final desc = entry.description ?? '';
        if (!desc.contains(cc.name)) {
          return entry.copyWith(description: Value('$desc [م.ت: ${cc.name}]'));
        }
      }
      return entry;
    }).toList();
  }


  /// Watch journal entries with filtering
  Stream<List<JournalEntryData>> watchJournalEntries({
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(journalEntries).join([
      leftOuterJoin(costCenters, costCenters.id.equalsExp(journalEntries.costCenterId))
    ]);
    
    Expression<bool> filter = journalEntries.isDeleted.equals(false);
    if (from != null) {
      final startOfDay = DateTime(from.year, from.month, from.day);
      filter = filter & journalEntries.entryDate.isBiggerOrEqual(Variable(startOfDay));
    }
    if (to != null) {
      // Extend to end of day to include all entries on the 'to' date
      final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
      filter = filter & journalEntries.entryDate.isSmallerOrEqual(Variable(endOfDay));
    }
    query.where(filter);
    query.orderBy([OrderingTerm.desc(journalEntries.entryDate)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final entry = row.readTable(journalEntries);
        final cc = row.readTableOrNull(costCenters);
        if (cc != null) {
          final desc = entry.description ?? '';
          if (!desc.contains(cc.name)) {
            return entry.copyWith(description: Value('$desc [م.ت: ${cc.name}]'));
          }
        }
        return entry;
      }).toList();
    });
  }


  /// Watch journal entries with pagination and filtering
  Stream<List<JournalEntryData>> watchJournalEntriesPaged({
    required int limit,
    required int offset,
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(journalEntries).join([
      leftOuterJoin(costCenters, costCenters.id.equalsExp(journalEntries.costCenterId))
    ]);
    
    Expression<bool> filter = journalEntries.isDeleted.equals(false);
    if (from != null) {
      final startOfDay = DateTime(from.year, from.month, from.day);
      filter = filter & journalEntries.entryDate.isBiggerOrEqual(Variable(startOfDay));
    }
    if (to != null) {
      final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
      filter = filter & journalEntries.entryDate.isSmallerOrEqual(Variable(endOfDay));
    }
    query.where(filter);
    query.orderBy([OrderingTerm.desc(journalEntries.entryDate)]);
    query.limit(limit, offset: offset);

    return query.watch().map((rows) {
      return rows.map((row) {
        final entry = row.readTable(journalEntries);
        final cc = row.readTableOrNull(costCenters);
        if (cc != null) {
          final desc = entry.description ?? '';
          if (!desc.contains(cc.name)) {
            return entry.copyWith(description: Value('$desc [م.ت: ${cc.name}]'));
          }
        }
        return entry;
      }).toList();
    });
  }


  /// Get account by ID
  Future<Account?> getAccountById(int id) {
    return (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
  }


  /// Centralized purposes for account mapping to avoid hardcoded strings and codes.
  /// Updated v110: Codes match the comprehensive chart of accounts.
  static const Map<String, String> accountPurposes = {
    // Assets
    'cash': '1111',             // الصندوق الرئيسي
    'petty_cash': '1112',       // صندوق العهد والمصروفات
    'bank': '1113',             // البنك الأهلي - حساب جاري
    'bank2': '1114',            // بنك القاهرة - حساب جاري
    'click': '1116',            // حساب Click
    'receivables': '1121',      // ذمم عملاء محليون
    'foreign_receivables': '1122', // ذمم عملاء خارجيون
    'notes_receivable': '1123', // أوراق القبض
    'inventory': '1136',        // مخزون البضاعة للبيع
    'raw_materials': '1131',    // مخزون المواد الخام
    'goods_in_transit': '1134', // مخزون البضاعة التامة
    'wip': '1133',              // مخزون تحت التشغيل
    'input_vat': '1141',        // ض.ق.م مدفوعة
    'prepaid_expenses': '1143', // مصروفات مقدمة
    'employee_advances': '1146', // سلف الموظفين
    'fixed_assets': '1211',     // الأراضي (أول أصل ثابت)
    // Liabilities
    'payables': '2111',         // ذمم موردون محليون
    'foreign_payables': '2112', // ذمم موردون خارجيون
    'notes_payable': '2113',    // أوراق الدفع
    'output_vat': '2121',       // ض.ق.م محصلة
    'income_tax': '2122',       // ضريبة الدخل المستحقة
    'accrued_salaries': '2131', // رواتب مستحقة
    'deferred_revenue': '2133', // إيرادات مقدمة
    'loans_payable': '2141',    // قروض بنكية قصيرة
    // Equity
    'capital': '311',           // رأس المال
    'retained_earnings': '313', // الأرباح المبقاة
    'opening_equity': '313',    // حساب الأرصدة الافتتاحية (defaults to retained_earnings)
    'owner_equity': '315',      // حقوق الشريك / المالك
    // Revenue
    'sales': '4121',            // مبيعات محلية - تجاري
    'export_sales': '4122',     // مبيعات تصدير
    'delivery_revenue': '414',  // إيرادات التوصيل
    'service_revenue': '4131',  // خدمات ما بعد البيع
    'sales_return': '4211',     // مردودات المبيعات
    'sales_discount': '4212',   // خصم المبيعات
    'purchase_discount': '4316', // خصم المشتريات المكتسب
    'discount_received': '4316', // خصم مكتسب
    'other_income': '4315',     // إيرادات متنوعة أخرى
    'inventory_surplus': '4317', // فائض مخزون
    'cash_surplus': '4318',     // فائض نقدي
    // COGS
    'cogs': '5211',             // تكلفة بضاعة تجارية محلية
    'purchases': '5211',        // مشتريات (= COGS التجاري)
    'purchase_return': '5214',  // مردودات المشتريات
    // Spec 146 (S-MFG-GL): credit party for capitalised manufacturing overhead
    // (Dr WIP 1133 / Cr 5138 at order completion). Contra within the 513
    // overhead subtree — credit-normal. Replaces the guide's proposed 2141,
    // which is already loans_payable.
    'applied_overhead': '5138', // تحميل صناعي مطبّق
    // Operating Expenses
    'salary_expense': '621',    // رواتب - إدارة
    'rent_expense': '623',      // مصروف إيجار
    'discount_allowed': '6215', // خصم مسموح به
    'inventory_shrinkage': '6216', // عجز مخزون
    'cash_shortage': '6217',    // عجز نقدي
    'misc_expense': '6214',     // مصروفات متنوعة
    'op_expenses': '6214',      // مصروفات تشغيل (alias of misc_expense — used by shift-closing fallback)
    // Spec 138 cheque-drift repair suspense (Cr side). MUST be a BALANCE-SHEET
    // account so the correction has zero P&L impact (strategy C premise). The
    // seed COA has no dedicated suspense account, so this defaults to the
    // credit-normal balance-sheet clearing account 2135 (حسابات جارية - دائنة).
    // Operators may remap the purpose to their own COA's suspense account.
    'cheque_drift_clearing': '2135',
    // Spec 139 rounding-difference account (both arms). The JE writer books a
    // legitimate sub-cap balance residual here (P&L — a tiny gain/loss),
    // instead of absorbing it into the largest business leg. Remappable; a
    // fresh/seeded install has 4319 «فروق تقريب» (income-side, both directions).
    'rounding_difference': '4319',
  };


  // -----------------------------------------------------------------------
  // AUTO-POSTING ENGINE -- See accounting_autopost_dao.dart
  // -----------------------------------------------------------------------


  // -----------------------------------------------------------------------
  // GENERAL LEDGER (دفتر الأستاذ العام)
  // -----------------------------------------------------------------------

  /// Account ledger with optional pagination.
  /// [limit] defaults to 1000 and [offset] to 0. The opening-balance row is
  /// always included as the first element regardless of offset.
  Future<List<Map<String, dynamic>>> getAccountLedger(
    int accountId,
    DateTime from,
    DateTime to, {
    int? costCenterId,
    int? branchId,
    int limit = 1000,
    int offset = 0,
    /// Phase 5C.5 (Issue 4) — auth-level scope. When non-null, restrict
    /// the result to JEs whose `branch_id` is in this set OR is NULL
    /// (legacy data without a branch link stays visible — matches
    /// `BranchScope.isAllowed(null) == true`). Independent of and AND-ed
    /// with the manual UI [branchId] filter, so a restricted user who
    /// then picks a specific branch in the dropdown sees the
    /// intersection. Pass null (default) for admin / financial-manager
    /// to disable the filter entirely.
    Set<int>? allowedBranchIds,
  }) async {
    // FIX: Cost center filter with header fallback (matches accounting_reports_dao fix)
    // If line-level cost_center_id is NULL, fall back to parent entry's cost_center_id
    final ccFilter = costCenterId != null
        ? 'AND (l.cost_center_id = ? OR (l.cost_center_id IS NULL AND e.cost_center_id = ?))'
        : '';
    final ccVars = costCenterId != null
        ? [Variable<int>(costCenterId), Variable<int>(costCenterId)]
        : <Variable>[];
    // FIX: Strict branch filtering (no NULL fallback) for accurate branch reporting
    final brFilter = branchId != null ? 'AND e.branch_id = ?' : '';
    final brVars = branchId != null ? [Variable<int>(branchId)] : <Variable>[];

    // Phase 5C.5 — auth-scope filter. Empty set is treated like null
    // (no filter) defensively so a misconfigured caller doesn't accidentally
    // hide every row.
    final scopedActive = allowedBranchIds != null && allowedBranchIds.isNotEmpty;
    final scopeFilter = scopedActive
        ? 'AND (e.branch_id IN (${List.filled(allowedBranchIds.length, '?').join(',')}) '
            'OR e.branch_id IS NULL)'
        : '';
    final scopeVars = scopedActive
        ? allowedBranchIds.map((i) => Variable<int>(i)).toList()
        : <Variable>[];

    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);
    
    // Get the selected account's code to find child accounts
    final selectedAccount = await (select(accounts)..where((a) => a.id.equals(accountId))).getSingleOrNull();
    final accountCode = selectedAccount?.code ?? '';

    // Build account filter: include the selected account AND all child accounts.
    // Child accounts have codes that START WITH the parent code (e.g. parent=1201,
    // children=1201001, 1201002). If the account is a leaf, this matches itself.
    //
    // D-PERF-3 (A9): an empty/missing code turned `code LIKE ?` into `LIKE '%'`,
    // which matched EVERY account and dumped the entire journal into this one
    // account's ledger. Fall back to an exact account-id match when there is no
    // usable code (also returns nothing for a non-existent accountId).
    //
    // ⚠️ البادئة النصية اتشالت: `code LIKE '621%'` كان بيلقّط `6210`…`6217`
    // وهم **إخوة** لـ`621` مش أبناؤه (كلهم `detail` تحت `62` في الدليل
    // المزروع). فكارت أستاذ الرواتب كان بيضم عجز المخزون وعجز النقدية
    // وغيرهم، ويخالف ميزان المراجعة لنفس الحساب. التجميع بقى بالشجرة.
    final subtreeIds = await accountSubtreeIds(accountId);
    final String accountFilter = subtreeIds.isEmpty
        ? 'l.account_id = ?'
        : 'l.account_id IN (${List.filled(subtreeIds.length, '?').join(',')})';
    final List<Variable> acctVars = subtreeIds.isEmpty
        ? [Variable<int>(accountId)]
        : subtreeIds.map((id) => Variable<int>(id)).toList();

    final result = await customSelect(
      '''SELECT 
          e.id as entry_id, e.entry_number, e.entry_date, e.description as entry_desc,
          e.reference_type, e.reference_id, e.is_auto_posted,
          l.debit, l.credit, l.description as line_desc, l.cost_center_id,
          cc.name as header_cc_name, cc_line.name as line_cc_name
        FROM journal_entry_lines l
        JOIN journal_entries e ON l.entry_id = e.id
        LEFT JOIN cost_centers cc ON e.cost_center_id = cc.id
        LEFT JOIN cost_centers cc_line ON l.cost_center_id = cc_line.id
        WHERE $accountFilter AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse $ccFilter $brFilter $scopeFilter
        ORDER BY e.entry_date, e.id
        LIMIT ? OFFSET ?''',
      variables: [...acctVars, dateVar(from), dateVar(to), ...ccVars, ...brVars, ...scopeVars, Variable<int>(limit), Variable<int>(offset)],
      readsFrom: {journalEntryLines, journalEntries, accounts, costCenters},
    ).get();

    double runningBalance = 0;
    // Get opening balance (all entries before 'from' date) for this account + children
    final openingResult = await customSelect(
      'SELECT SUM(debit - credit) as balance FROM journal_entry_lines l JOIN journal_entries e ON l.entry_id = e.id WHERE $accountFilter AND e.entry_date < ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse $ccFilter $brFilter $scopeFilter',
      variables: [...acctVars, dateVar(from), ...ccVars, ...brVars, ...scopeVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();
    runningBalance = openingResult.data['balance'] as double? ?? 0;

    final List<Map<String, dynamic>> ledger = [];
    ledger.add({
      'entry_number': '',
      'entry_date': from,
      'description': 'رصيد أول المدة',
      'debit': 0.0,
      'credit': 0.0,
      'balance': runningBalance,
      'reference_type': null,
      'reference_id': null,
      'is_opening': true,
    });

    for (var row in result) {
      final debit = row.data['debit'] as double? ?? 0;
      final credit = row.data['credit'] as double? ?? 0;
      runningBalance += debit - credit;

      final rawLineDesc = _cleanHashFromDescription(row.data['line_desc']);
      final rawHeaderDesc = _cleanHashFromDescription(row.data['entry_desc']);
      final actualLineDesc = rawLineDesc.isNotEmpty ? rawLineDesc : rawHeaderDesc;
      
      final headerCcName = row.data['header_cc_name'] as String?;
      final lineCcName = row.data['line_cc_name'] as String?;
      final actualCcName = lineCcName ?? headerCcName;

      String finalDesc = actualLineDesc;
      if (actualCcName != null && actualCcName.isNotEmpty && !finalDesc.contains(actualCcName)) {
        finalDesc = '$finalDesc [م.ت: $actualCcName]';
      }

      ledger.add({
        'entry_id': row.data['entry_id'],
        'entry_number': row.data['entry_number'],
        'entry_date': () {
          final ed = row.data['entry_date'];
          return ed is DateTime ? ed : DateTime.fromMillisecondsSinceEpoch((ed as int) * 1000);
        }(),
        'description': finalDesc,
        'debit': debit,
        'credit': credit,
        'balance': runningBalance,
        'reference_type': row.data['reference_type'],
        'reference_id': row.data['reference_id'],
        'is_auto_posted': _parseSystemBool(row.data['is_auto_posted']),
        'cost_center_id': row.data['cost_center_id'],
        'is_opening': false,
      });
    }

    return ledger;
  }
  Future<List<Account>> getAllAccounts() {
    return (select(accounts)..orderBy([(a) => OrderingTerm.asc(a.code)])).get();
  }


  /// Watch all accounts as a stream
  Stream<List<Account>> watchAllAccounts() {
    return (select(
      accounts,
    )..orderBy([(a) => OrderingTerm.asc(a.code)])).watch();
  }



  // -----------------------------------------------------------------------
  // FISCAL YEAR MANAGEMENT → See accounting_fiscal_dao.dart
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // COST CENTER LEDGER
  // -----------------------------------------------------------------------

  /// Get cost center ledger
  /// FIX: Also checks parent journal_entries.cost_center_id as fallback
  /// Spec 150 (c): prepends a 'رصيد أول المدة' row (mirrors
  /// [getAccountLedger]'s opening-balance block) and threads a running
  /// `balance` through every row.
  /// Spec 150 (b): excludes the variance/surplus plug accounts (see
  /// [_costCenterVarianceCodes]) from both the opening balance and the range.
  Future<List<Map<String, dynamic>>> getCostCenterLedger(
    int costCenterId,
    DateTime from,
    DateTime to,
  ) async {
    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);
    final varianceVars = _costCenterVarianceCodes.map((c) => Variable(c)).toList();

    final openingResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit - l.credit), 0) as balance
        FROM journal_entry_lines l
        JOIN journal_entries e ON l.entry_id = e.id
        WHERE (l.cost_center_id = ? OR (l.cost_center_id IS NULL AND e.cost_center_id = ?))
          AND e.entry_date < ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse
          AND $_excludeVarianceEntriesSql''',
      variables: [Variable(costCenterId), Variable(costCenterId), dateVar(from), ...varianceVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();
    // COALESCE(...,0) over zero rows comes back as an int, so read as num.
    double runningBalance =
        (openingResult.data['balance'] as num?)?.toDouble() ?? 0;

    final result = await customSelect(
      '''SELECT e.entry_date, e.entry_number, e.description as entry_desc,
          l.debit, l.credit, l.description as line_desc,
          a.code as account_code, a.name as account_name,
          cc.name as header_cc_name, cc_line.name as line_cc_name
        FROM journal_entry_lines l
        JOIN journal_entries e ON l.entry_id = e.id
        JOIN accounts a ON l.account_id = a.id
        LEFT JOIN cost_centers cc ON e.cost_center_id = cc.id
        LEFT JOIN cost_centers cc_line ON l.cost_center_id = cc_line.id
        WHERE (l.cost_center_id = ? OR (l.cost_center_id IS NULL AND e.cost_center_id = ?))
          AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse
          AND $_excludeVarianceEntriesSql
        ORDER BY e.entry_date''',
      variables: [Variable(costCenterId), Variable(costCenterId), dateVar(from), dateVar(to), ...varianceVars],
      readsFrom: {journalEntryLines, journalEntries, accounts, costCenters},
    ).get();

    final ledger = <Map<String, dynamic>>[
      {
        'entry_date': from,
        'entry_number': '',
        'entry_desc': 'رصيد أول المدة',
        'line_desc': 'رصيد أول المدة',
        'debit': 0.0,
        'credit': 0.0,
        'balance': runningBalance,
        'is_opening': true,
      },
    ];

    for (final r in result) {
      final data = Map<String, dynamic>.from(r.data);

      final rawLineDesc = _cleanHashFromDescription(data['line_desc']);
      final rawHeaderDesc = _cleanHashFromDescription(data['entry_desc']);
      final headerCcName = data['header_cc_name'] as String?;
      final lineCcName = data['line_cc_name'] as String?;
      final actualCcName = lineCcName ?? headerCcName;

      if (rawHeaderDesc.isNotEmpty) {
        data['entry_desc'] = actualCcName != null && !rawHeaderDesc.contains(actualCcName)
            ? '$rawHeaderDesc [م.ت: $actualCcName]'
            : rawHeaderDesc;
      }
      if (rawLineDesc.isNotEmpty) {
        data['line_desc'] = actualCcName != null && !rawLineDesc.contains(actualCcName)
            ? '$rawLineDesc [م.ت: $actualCcName]'
            : rawLineDesc;
      }

      final debit = (data['debit'] as num?)?.toDouble() ?? 0;
      final credit = (data['credit'] as num?)?.toDouble() ?? 0;
      runningBalance += debit - credit;
      data['balance'] = runningBalance;
      data['is_opening'] = false;

      ledger.add(data);
    }

    return ledger;
  }
  Stream<List<ActivityProfile>> watchActivityProfiles() {
    return select(activityProfiles).watch();
  }


  /// Get active profile. Defensive `.limit(1)` against mirror duplicates
  /// (Cluster 028 / Bugs 3+4).
  Future<ActivityProfile?> getActiveProfile() {
    return (select(activityProfiles)
          ..where((p) => p.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }


  /// Get mapped account by purpose with hierarchical cost center resolution
  /// Resolution: specific CC → parent CC → global → default code
  Future<Account?> getAccountByPurpose(String purpose, {int? costCenterId}) async {
    if (costCenterId != null) {
      // 1. Try specific cost center mapping. `.limit(1)` is defensive —
      // mirror duplicates of (purpose, costCenterId) crash the
      // commercial-papers + fixed-assets create flows otherwise
      // (Cluster 028 / Bugs 3+4 — "Bad state: too many elements").
      final specific = await (select(accountMappings)
        ..where((m) => m.purpose.equals(purpose) & m.costCenterId.equals(costCenterId))
        ..limit(1))
        .getSingleOrNull();
      if (specific != null) {
        return getAccountById(specific.accountId);
      }
      // 2. Try parent cost center (hierarchical walk-up)
      final cc = await (select(costCenters)
            ..where((c) => c.id.equals(costCenterId))
            ..limit(1))
          .getSingleOrNull();
      if (cc?.parentId != null) {
        return getAccountByPurpose(purpose, costCenterId: cc!.parentId);
      }
    }
    // 3. Global mapping (costCenterId IS NULL). Same defensive limit.
    final globalMapping = await (select(accountMappings)
      ..where((m) => m.purpose.equals(purpose) & m.costCenterId.isNull())
      ..limit(1))
      .getSingleOrNull();
    if (globalMapping != null) {
      return getAccountById(globalMapping.accountId);
    }

    // 4. Fallback to hardcoded default codes
    final defaultCode = accountPurposes[purpose];
    if (defaultCode != null) {
      return getAccountByCode(defaultCode);
    }

    return null;
  }


  /// Gets mapped account code with hierarchical cost center resolution
  Future<String> getMappedAccountCode(
    String purpose,
    String defaultCode, {
    int? costCenterId,
  }) async {
    final acc = await getAccountByPurpose(purpose, costCenterId: costCenterId);
    return acc?.code ?? defaultCode;
  }
  Future<Account?> getAccountByCode(String code) {
    return (select(accounts)..where((a) => a.code.equals(code))..limit(1)).getSingleOrNull();
  }

  /// Cluster 023 / Issue 3 — defensive leaf resolution.
  ///
  /// Walk down the account tree from [parentId] until we hit a `detail`
  /// (postable) account. Returns the first leaf found by deterministic order
  /// (sortOrder, then id). Returns null if none exists. Used by
  /// [getLeafAccountByPurpose] to recover from misconfigured purpose mappings
  /// that point at a `view` (parent) account — without this, the JE validator
  /// rejects the post with a cryptic "code 22" error and the user can't sell.
  Future<Account?> findFirstLeafDescendant(int parentId) async {
    final root = await getAccountById(parentId);
    if (root == null) return null;
    if (root.accountNature != 'view') return root;
    final visited = <int>{parentId};
    final stack = <Account>[root];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final children = await (select(accounts)
            ..where((a) => a.parentId.equals(current.id) & a.isActive.equals(true))
            ..orderBy([
              (a) => OrderingTerm(expression: a.code),
              (a) => OrderingTerm(expression: a.id),
            ]))
          .get();
      for (final child in children) {
        if (!visited.add(child.id)) continue;
        if (child.accountNature != 'view') return child;
        stack.add(child);
      }
    }
    return null;
  }

  /// Cluster 023 / Issue 3 — same as [getAccountByPurpose] but guarantees the
  /// returned account is `detail` (postable). If the mapped account is a
  /// `view` (parent — e.g. the user's seed pointed `output_vat` at code "22"
  /// instead of "2121"), walks down to the first leaf descendant and emits a
  /// `ACCT-WARN` diagnostic line so misconfigured installs surface in the
  /// support log instead of failing every JE post silently.
  ///
  /// Returns null only when no mapping exists at all OR no leaf can be found
  /// under the parent. Callers should still treat null as "missing account"
  /// (their existing MissingAccountException path).
  Future<Account?> getLeafAccountByPurpose(
    String purpose, {
    int? costCenterId,
  }) async {
    final acc = await getAccountByPurpose(purpose, costCenterId: costCenterId);
    if (acc == null) return null;
    if (acc.accountNature != 'view') return acc;
    final leaf = await findFirstLeafDescendant(acc.id);
    if (leaf != null) {
      DiagnosticLogger.log(
        'ACCT-WARN',
        'purpose="$purpose" mapped to view account ${acc.code} (${acc.name}) — '
        'auto-resolved to leaf ${leaf.code} (${leaf.name}). '
        'Fix the mapping in Settings → Chart of Accounts → Account Mappings.',
      );
    }
    return leaf;
  }

  /// Cluster 023 / Issue 3 — leaf-safe variant of [getAccountById]. If the
  /// looked-up account is a `view`, walks down to the first leaf descendant
  /// (with diagnostic warning). Used to defend against parent-account ids
  /// stored on parties / vouchers / etc.
  Future<Account?> getLeafAccountById(int id) async {
    final acc = await getAccountById(id);
    if (acc == null) return null;
    if (acc.accountNature != 'view') return acc;
    final leaf = await findFirstLeafDescendant(acc.id);
    if (leaf != null) {
      DiagnosticLogger.log(
        'ACCT-WARN',
        'accountId=$id (${acc.code} - ${acc.name}) is a view account — '
        'auto-resolved to leaf ${leaf.code} (${leaf.name}).',
      );
    }
    return leaf;
  }




  /// Get pending draft entries for approval
  Future<List<JournalEntryData>> getPendingApprovalEntries() async {
    return (select(journalEntries)
          ..where((e) => e.isPosted.equals(false) & e.needsApproval.equals(true))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
  }


  // ─────────────────────────────────────────────────────────────────────────
  // F-16: PERIOD REOPEN AUDIT — إعادة فتح الفترات المحاسبية
  // ─────────────────────────────────────────────────────────────────────────

  /// Reopen a closed accounting period with audit trail (with reason logging)
  Future<void> reopenAccountingPeriodWithAudit({
    required int periodId,
    required int userId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('يجب ذكر سبب إعادة الفتح');
    }

    final boolFalse = sqlBool(false);
    await customStatement(
      'UPDATE accounting_periods SET is_closed = $boolFalse, reopen_reason = ?, reopened_by = ?, reopened_at = ? WHERE id = ?',
      [reason, userId, DateTime.now().millisecondsSinceEpoch, periodId],
    );

    // Log to activity
    try {
      await logActivity(
        userId: userId,
        userName: 'system',
        action: 'reopen_period',
        entityType: 'accounting_period',
        entityId: periodId,
        description: 'سبب إعادة الفتح: $reason',
      );
    } catch (e) { debugPrint('[ACCOUNTING_WARNING] Activity log for period reopen failed: $e'); }
  }

  // ── Maintenance: Account Balance Integrity Check ─────────────────────────

  /// Verifies that each account's cached `balance` matches the sum of its
  /// posted journal entry lines.  Call from the admin/maintenance screen.
  ///
  /// Returns a list of drift records — empty means the ledger is clean.
  /// Each record contains: accountId, accountCode, accountName,
  /// cachedBalance, actualBalance, drift.
  Future<List<Map<String, dynamic>>> verifyAccountBalancesIntegrity() async {
    const sql = '''
      SELECT
        a.id          AS account_id,
        a.code        AS account_code,
        a.name        AS account_name,
        a.balance     AS cached_balance,
        COALESCE(SUM(jel.debit - jel.credit), 0.0) AS actual_balance,
        ABS(a.balance - COALESCE(SUM(jel.debit - jel.credit), 0.0)) AS drift
      FROM accounts a
      LEFT JOIN journal_entry_lines jel ON jel.account_id = a.id
        AND jel.entry_id IN (
          SELECT id FROM journal_entries WHERE is_posted = 1
        )
      WHERE a.account_nature = 'detail'
        AND (a.deleted_at IS NULL OR a.deleted_at = 0)
      GROUP BY a.id
      HAVING drift > 0.01
      ORDER BY drift DESC
    ''';
    try {
      final results = await customSelect(sql).get();
      return results.map((row) {
        return {
          'accountId': row.read<int>('account_id'),
          'accountCode': row.read<String>('account_code'),
          'accountName': row.read<String>('account_name'),
          'cachedBalance': row.read<double>('cached_balance'),
          'actualBalance': row.read<double>('actual_balance'),
          'drift': row.read<double>('drift'),
        };
      }).toList();
    } catch (e) {
      debugPrint('[ACCOUNTING] verifyAccountBalancesIntegrity error: $e');
      return [];
    }
  }

  /// Phase 5B.7 (Issue 6) — find journal entries with integrity issues.
  ///
  /// Returns a list of `{ entryId, entryNumber, issue, detail }` records,
  /// each describing one of two failure modes that surface as "missing"
  /// rows in the General Ledger:
  ///
  ///   * `unbalanced` — total debit ≠ total credit beyond a 0.01
  ///     rounding tolerance. These are usually the visible symptom of a
  ///     remap failure (5B.3): one or more lines lost their account
  ///     reference and the JE no longer balances.
  ///
  ///   * `orphan_account` — at least one line points to an account_id
  ///     that doesn't exist in the local accounts table. The line is in
  ///     the DB but invisible in any GL screen because the join filters
  ///     it out. Typically arises when JournalSyncStrategy received a
  ///     line for a server-side account that hadn't pulled to the
  ///     client yet.
  ///
  /// Read-only — never mutates state. Intended for an admin diagnostic
  /// screen ("فحص قيود غير سليمة") where the operator can review and
  /// either re-trigger an accounts pull or hand-correct the entries.
  Future<List<Map<String, dynamic>>> findOrphanedJournalEntries({
    int limit = 200,
  }) async {
    final out = <Map<String, dynamic>>[];
    try {
      // Tier 1: unbalanced posted entries.
      final unbalancedRows = await customSelect(
        'SELECT je.id AS entry_id, je.entry_number AS entry_number, '
        '       COALESCE(SUM(jel.debit), 0) AS d, '
        '       COALESCE(SUM(jel.credit), 0) AS c '
        '  FROM journal_entries je '
        '  JOIN journal_entry_lines jel ON jel.entry_id = je.id '
        ' WHERE je.is_posted = 1 AND je.is_deleted = 0 '
        ' GROUP BY je.id, je.entry_number '
        'HAVING ABS(COALESCE(SUM(jel.debit), 0) - COALESCE(SUM(jel.credit), 0)) > 0.01 '
        ' LIMIT ?',
        variables: [Variable.withInt(limit)],
      ).get();
      for (final r in unbalancedRows) {
        final d = (r.data['d'] as num?)?.toDouble() ?? 0;
        final c = (r.data['c'] as num?)?.toDouble() ?? 0;
        out.add({
          'entryId': r.data['entry_id'],
          'entryNumber': r.data['entry_number'],
          'issue': 'unbalanced',
          'detail': 'مدين=$d, دائن=$c, الفرق=${(d - c).abs()}',
        });
      }

      // Tier 2: lines referencing non-existent accounts (FK orphan).
      final orphanRows = await customSelect(
        'SELECT je.id AS entry_id, je.entry_number AS entry_number, '
        '       jel.account_id AS bad_account_id, COUNT(*) AS bad_count '
        '  FROM journal_entry_lines jel '
        '  JOIN journal_entries je ON je.id = jel.entry_id '
        '  LEFT JOIN accounts a ON a.id = jel.account_id '
        ' WHERE a.id IS NULL '
        '   AND je.is_deleted = 0 '
        ' GROUP BY je.id, je.entry_number, jel.account_id '
        ' LIMIT ?',
        variables: [Variable.withInt(limit)],
      ).get();
      for (final r in orphanRows) {
        out.add({
          'entryId': r.data['entry_id'],
          'entryNumber': r.data['entry_number'],
          'issue': 'orphan_account',
          'detail':
              'سطر يشير إلى حساب غير موجود (account_id=${r.data['bad_account_id']}, ${r.data['bad_count']} سطر)',
        });
      }

      if (out.isNotEmpty) {
        debugPrint('[ACCOUNTING] findOrphanedJournalEntries: '
            '${out.length} issues — re-trigger accounts pull and reverify.');
      }
    } catch (e) {
      debugPrint('[ACCOUNTING] findOrphanedJournalEntries error: $e');
    }
    return out;
  }
}
