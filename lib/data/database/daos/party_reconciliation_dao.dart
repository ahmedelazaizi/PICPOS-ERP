// AR/AP aging report, AR reconciliation vs GL, party balance mismatches + recompute.
part of '../database.dart';

extension PartyReconciliationDao on AppDatabase {
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
          -- ⚠️ مستندُ المرتجع **ليس ديناً على العميل**. يعيش في نفس الجدول
          -- بـ`sale_type = 'return'` وبإجماليٍّ موجب و`paid = 0`، فشرطُ
          -- «المتبقي > صفر» أدناه يلتقطه ويحسبه **مديونيّةً**: مرتجعٌ بـ٨٠٠
          -- كان يَزيد أعمارَ العميل ٨٠٠ بدل أن ينقصها — انعكاسُ إشارةٍ كامل
          -- على تقريرٍ يُبنى عليه قرارُ التحصيل ووقفُ التعامل.
          -- والصيغةُ نفسُها مستعملةٌ في تسعةِ استعلاماتٍ أخرى عبر المستودع
          -- (`sales_analytics_dao` · `accounting_reports_dao` · وأعلى هذا
          -- الملفّ) — هذا الاستعلامُ أغفلها وحدَه.
          AND (si.sale_type IS NULL OR si.sale_type != 'return')
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
          COALESCE(SUM(live_jel.debit) - SUM(live_jel.credit), 0.0) AS ledger_balance
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
