// AR/AP aging report, AR reconciliation vs GL, party balance mismatches + recompute.
part of '../database.dart';

extension PartyReconciliationDao on AppDatabase {
  /// عامل إشارة رصيد الأستاذ لمطابقة بطاقة الطرف: المورد (التزام، حسابه تحت
  /// الدائنين ورصيده الدائن موجب على البطاقة) يُقارَن بـ(دائن − مدين) أي −1،
  /// والعميل (وكذا العميل/المورد الذي حسابه تحت الذمم المدينة) بـ(مدين − دائن).
  String get _ledgerSign =>
      '(CASE WHEN p.is_supplier = ${sqlBool(true)} AND p.is_customer = ${sqlBool(false)} '
      'THEN -1.0 ELSE 1.0 END)';

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
  ///
  /// ⚠️ مختلف عن [getAgedReceivables]/[getAgedPayables]: هنا الحصر **بالطرف**
  /// (الإجمالي = `parties.balance`)، وهناك **بالفاتورة** (راجع توثيق `_agedBalances`).
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
      scopeClause = ' AND (p.is_global = ${sqlBool(true)} OR $ors)';
    }
    // Drift stores DateTime as Unix **seconds** (BIGINT) — see [dateVar]. The
    // age is plain epoch-seconds arithmetic (identical to [_agedBalances]) so
    // the SQL is portable: no julianday(), no scalar MAX(a, b) (RPT-003 — the
    // old text failed on PostgreSQL). Integer division also closes the
    // 30 < age < 31 gap the fractional julianday difference left between buckets.
    final asOf = dateVar(asOfDate);
    final boolFalse = sqlBool(false);
    final boolTrue = sqlBool(true);

    final a = customersOnly ? 'si' : 'pi';
    final age = '(? - COALESCE($a.due_date, $a.invoice_date)) / 86400';
    final open = customersOnly
        ? '($a.total - $a.paid - COALESCE($a.rounding_adjustment, 0))'
        : '($a.total - $a.paid)';
    final remaining = 'CASE WHEN $open > 0 THEN $open ELSE 0 END';
    // Returned/cancelled/voided documents are not debt (RPT-002 b/c); a sales
    // return document (sale_type = 'return') is never a receivable.
    final join = customersOnly
        ? '''sales_invoices si ON si.customer_id = p.id
          AND si.status NOT IN ('returned', 'cancelled', 'voided')
          AND si.is_deleted = $boolFalse
          AND (si.sale_type IS NULL OR si.sale_type != 'return')
          AND si.paid + COALESCE(si.rounding_adjustment, 0) < si.total
          AND si.invoice_date <= ?'''
        : '''purchase_invoices pi ON pi.supplier_id = p.id
          AND pi.status NOT IN ('returned', 'cancelled', 'voided')
          AND pi.is_deleted = $boolFalse
          AND pi.paid < pi.total
          AND pi.invoice_date <= ?''';
    final rows = await customSelect('''
        SELECT
          p.id,
          p.name,
          p.balance,
          COALESCE(SUM(CASE WHEN $age <= 30 THEN $remaining ELSE 0 END), 0) AS bucket_0_30,
          COALESCE(SUM(CASE WHEN $age BETWEEN 31 AND 60 THEN $remaining ELSE 0 END), 0) AS bucket_31_60,
          COALESCE(SUM(CASE WHEN $age BETWEEN 61 AND 90 THEN $remaining ELSE 0 END), 0) AS bucket_61_90,
          COALESCE(SUM(CASE WHEN $age > 90 THEN $remaining ELSE 0 END), 0) AS bucket_90_plus
        FROM parties p
        LEFT JOIN $join
        WHERE p.is_active = $boolTrue
          AND p.${customersOnly ? 'is_customer' : 'is_supplier'} = $boolTrue
          AND p.balance > 0.01
          $scopeClause
        GROUP BY p.id, p.name, p.balance
        ORDER BY p.balance DESC
      ''', variables: [
      asOf, asOf, asOf, asOf, asOf,
    ], readsFrom: {parties, customersOnly ? salesInvoices : purchaseInvoices}).get();

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
  // ═══ M-05/M-06: تقادم الذمم (دائنة/مدينة) — مصدرٌ واحد للصيغتين ═══
  /// Aged payables: supplier balances in 0-30 / 31-60 / 61-90 / 90+ buckets.
  /// الحصر **بالفاتورة** لا بالطرف (عكس [getArAgingReport]) — راجع `_agedBalances`.
  Future<List<Map<String, dynamic>>> getAgedPayables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) =>
      _agedBalances(asOfDate, receivables: false, costCenterId: costCenterId, branchId: branchId, regionId: regionId, allowedBranchIds: allowedBranchIds);

  /// Aged receivables: customer balances in 0-30 / 31-60 / 61-90 / 90+ buckets.
  /// الحصر **بالفاتورة** لا بالطرف (عكس [getArAgingReport]) — راجع `_agedBalances`.
  Future<List<Map<String, dynamic>>> getAgedReceivables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) =>
      _agedBalances(asOfDate, receivables: true, costCenterId: costCenterId, branchId: branchId, regionId: regionId, allowedBranchIds: allowedBranchIds);

  /// - [asOfDate] مرجعُ الأعمار **وحدٌّ أعلى** لتاريخ الفاتورة (`invoice_date <= ?`)؛
  ///   فاتورةٌ بعد التاريخ لم تكن موجودةً بعدُ (نفس إصلاح B2 في [getArAgingReport]).
  /// - بلا أيِّ مرشّحِ فرع/إقليم/صلاحية: الإجماليُّ = `parties.balance` والباقي
  ///   غيرُ المرتبط بفواتير (سندات/قيود يدوية) يُضاف إلى `current`.
  /// - مع أيِّ مرشّح: الإجماليُّ = مجموعُ فواتير النطاق فقط، ولا يُضاف الباقي
  ///   (رصيدُ الطرف عامٌّ على الشركة، فإضافتُه تُظهر دَينَ الفروع الأخرى «حاليّاً»)،
  ///   وتُحذف الأطرافُ التي لا فواتيرَ مفتوحةً لها في النطاق (حتى لو رصيدُها العامّ صفر
  ///   أو دائن). فواتيرُ مستودعاتٍ بلا `branch_id` **مرئيةٌ** في العروض المحصورة (كتقارير الأستاذ).
  ///   عكسُ [getArAgingReport] الذي يحصر بالطرف والإجماليُّ فيه = `parties.balance`.
  Future<List<Map<String, dynamic>>> _agedBalances(
    DateTime asOfDate, {
    required bool receivables,
    int? costCenterId,
    int? branchId,
    int? regionId,
    Set<int>? allowedBranchIds,
  }) async {
    final a = receivables ? 'si' : 'pi';
    final cc = await AccountingReportsDao(this)._buildCostCenterFilter(costCenterId, tableAlias: a, entryAlias: a);
    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);

    var scopeFilter = '';
    final scopeVars = <Variable>[];
    if (branchId != null) {
      scopeFilter = ' AND $a.warehouse_id IN (SELECT id FROM warehouses WHERE (branch_id = ? OR branch_id IS NULL))';
      scopeVars.add(Variable(branchId));
    } else if (regionId != null) {
      scopeFilter = ' AND $a.warehouse_id IN (SELECT id FROM warehouses WHERE (branch_id IS NULL OR branch_id IN (SELECT id FROM branches WHERE region_id = ?)))';
      scopeVars.add(Variable(regionId));
    }
    // FIL-2: auth-scope filter, ANDed on top of the dropdown branch/region filter.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        scopeFilter += ' AND 1 = 0';
      } else {
        scopeFilter += ' AND $a.warehouse_id IN (SELECT id FROM warehouses WHERE (branch_id IS NULL OR branch_id IN (${allowedBranchIds.map((_) => '?').join(', ')})))';
        scopeVars.addAll(allowedBranchIds.map((id) => Variable<int>(id)));
      }
    }
    final scoped = branchId != null || regionId != null || allowedBranchIds != null || costCenterId != null;

    // Epoch-seconds arithmetic works on both SQLite and PostgreSQL.
    final remaining = receivables
        ? 'si.total - si.paid - COALESCE(si.rounding_adjustment, 0)'
        : 'pi.total - pi.paid';
    final age = '(? - COALESCE($a.due_date, $a.invoice_date)) / 86400';
    // الفاتورةُ المرتجعة/الملغاة/المحذوفة ناعماً ليست ديناً (راجع B2/صيغةَ party_dao).
    final join = receivables
        ? '''sales_invoices si ON si.customer_id = p.id
        AND si.status NOT IN ('returned', 'cancelled')
        AND si.is_deleted = $boolFalse
        AND (si.sale_type IS NULL OR si.sale_type != 'return')
        AND si.total > si.paid + COALESCE(si.rounding_adjustment, 0)'''
        : '''purchase_invoices pi ON pi.supplier_id = p.id
        AND pi.status NOT IN ('returned', 'cancelled', 'voided')
        AND pi.is_deleted = $boolFalse
        AND pi.total > pi.paid''';
    final results = await customSelect(
      '''
      SELECT p.id, p.name, p.balance,
             COALESCE(SUM(CASE WHEN $age <= 30 THEN $remaining ELSE 0 END), 0) as current_30,
             COALESCE(SUM(CASE WHEN $age BETWEEN 31 AND 60 THEN $remaining ELSE 0 END), 0) as days_31_60,
             COALESCE(SUM(CASE WHEN $age BETWEEN 61 AND 90 THEN $remaining ELSE 0 END), 0) as days_61_90,
             COALESCE(SUM(CASE WHEN $age > 90 THEN $remaining ELSE 0 END), 0) as over_90
      FROM parties p
      LEFT JOIN $join${cc.filter}$scopeFilter
        AND $a.invoice_date <= ?
      WHERE p.${receivables ? 'is_customer' : 'is_supplier'} = $boolTrue${scoped ? '' : ' AND p.balance > 0.01'}
      GROUP BY p.id, p.name, p.balance
      ORDER BY p.balance DESC
      ''',
      variables: [
        for (var i = 0; i < 4; i++) dateVar(asOfDate),
        ...cc.vars,
        ...scopeVars,
        dateVar(asOfDate),
      ],
      readsFrom: {parties, receivables ? salesInvoices : purchaseInvoices},
    ).get();

    final rows = <Map<String, dynamic>>[];
    for (final r in results) {
      double n(String k) => (r.data[k] as num?)?.toDouble() ?? 0;
      final inv30 = n('current_30');
      final invoiceBased = inv30 + n('days_31_60') + n('days_61_90') + n('over_90');
      final total = scoped ? invoiceBased : n('balance');
      if (scoped && total <= 0.01) continue;
      // Non-invoice remainder (vouchers, manual JEs) → current; company-wide only.
      final remainder = scoped ? 0.0 : (total - invoiceBased).clamp(0.0, double.infinity);
      rows.add({
        'id': r.read<int>('id'),
        'name': r.read<String>('name'),
        'totalBalance': total,
        'current': inv30 + remainder,
        'days31_60': n('days_31_60'),
        'days61_90': n('days_61_90'),
        'over90': n('over_90'),
      });
    }
    if (scoped) {
      rows.sort((x, y) => (y['totalBalance'] as double).compareTo(x['totalBalance'] as double));
    }
    return rows;
  }
  /// GAP-21: AR Reconciliation — compare parties.balance aggregate with GL
  /// receivables account balance. Returns null if receivables account not mapped.
  ///
  /// Note: per-customer reconciliation is not possible without party_id on
  /// journal_entry_lines. This returns aggregate totals only.
  Future<ArReconciliation?> getArReconciliation() async {
    // 1. Sum of all customer card balances
    final customerBalances = await (select(parties)
          ..where((p) => p.isCustomer.equals(true) & p.deletedAt.isNull()))
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
        COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) * $_ledgerSign AS gl_balance
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
      HAVING ABS(p.balance - COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) * $_ledgerSign) > ?
      ORDER BY ABS(p.balance - COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) * $_ledgerSign) DESC
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

  /// Recompute stored party balances from posted, non-deleted ledger lines.
  Future<int> recalculatePartyBalancesFromLedger(int userId) async {
    await PermissionEnforcer(userHasPermission).requireCriticalOp(
      userId: userId,
      code: PermissionCodes.accountingJournal,
      arabicReason: 'لا تملك صلاحية إصلاح أرصدة الأطراف',
    );
    return transaction(() async {
      final rows = await customSelect(
        '''SELECT p.id, p.balance AS old_balance,
          COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) * $_ledgerSign AS ledger_balance
          FROM parties p
          LEFT JOIN (
            SELECT jel.account_id, jel.debit, jel.credit
            FROM journal_entry_lines jel
            INNER JOIN journal_entries je ON je.id = jel.entry_id
              AND je.is_posted = ${sqlBool(true)} AND je.is_deleted = ${sqlBool(false)}
          ) live_jel ON live_jel.account_id = p.account_id
          WHERE p.account_id IS NOT NULL AND p.deleted_at IS NULL
          GROUP BY p.id, p.balance''',
      ).get();
      var repaired = 0;
      for (final row in rows) {
        final oldBalance = (row.data['old_balance'] as num).toDouble();
        final ledgerBalance = (row.data['ledger_balance'] as num).toDouble();
        if ((oldBalance - ledgerBalance).abs() <= 0.01) continue;
        await (update(parties)..where((p) => p.id.equals(row.data['id'] as int)))
            .write(PartiesCompanion(balance: Value(ledgerBalance)));
        repaired++;
      }
      return repaired;
    });
  }
}
