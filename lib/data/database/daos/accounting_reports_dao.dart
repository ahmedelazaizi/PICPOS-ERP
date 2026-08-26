// =======================================================================
// ACCOUNTING REPORTS DAO
// Extracted from accounting_dao.dart - Sprint 12 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Accounting Financial Reports
extension AccountingReportsDao on AppDatabase {

  /// Resolve a cost center ID to include itself and all descendant children.
  /// If costCenterId is null, returns empty list (no filter).
  Future<List<int>> _resolveCostCenterIds(int? costCenterId) async {
    if (costCenterId == null) return [];
    final ids = <int>[costCenterId];
    // Recursively fetch children
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

  /// Build SQL cost center filter and variables for IN (...) clause
  /// FIX: Also checks parent journal_entries.cost_center_id as fallback
  /// for historical entries where lines may not have cost_center_id set.
  Future<({String filter, List<Variable> vars})> _buildCostCenterFilter(int? costCenterId, {String tableAlias = 'l', String entryAlias = 'e'}) async {
    if (costCenterId == null) return (filter: '', vars: <Variable>[]);
    final ids = await _resolveCostCenterIds(costCenterId);
    final placeholders = ids.map((_) => '?').join(', ');
    // Duplicate placeholders for the fallback OR clause
    final placeholders2 = ids.map((_) => '?').join(', ');
    return (
      filter: ' AND ($tableAlias.cost_center_id IN ($placeholders) OR ($tableAlias.cost_center_id IS NULL AND $entryAlias.cost_center_id IN ($placeholders2)))',
      vars: [...ids.map((id) => Variable<int>(id)), ...ids.map((id) => Variable<int>(id))],
    );
  }

  /// Build SQL branch filter — includes entries for the specified branch(es)
  /// AND global entries (branch_id IS NULL) which belong to all branches.
  ///
  /// Pass [branchIds] to filter on multiple branches at once (e.g. all
  /// branches inside a region). Single-branch callers keep using [branchId].
  /// When both are supplied, [branchIds] wins. Multi-branch is a SINGLE
  /// query with `branch_id IN (...)` — never loop the report over each
  /// branch separately, because every per-branch query also includes the
  /// `branch_id IS NULL` rows and they end up counted once per branch.
  ({String filter, List<Variable> vars}) _buildBranchFilter(
    int? branchId, {
    String tableAlias = 'e',
    List<int>? branchIds,
  }) {
    final ids = (branchIds != null && branchIds.isNotEmpty)
        ? branchIds
        : (branchId != null ? <int>[branchId] : const <int>[]);
    if (ids.isEmpty) return (filter: '', vars: <Variable>[]);
    final placeholders = ids.map((_) => '?').join(', ');
    return (
      filter: ' AND ($tableAlias.branch_id IN ($placeholders) OR $tableAlias.branch_id IS NULL)',
      vars: ids.map<Variable>((id) => Variable<int>(id)).toList(),
    );
  }

  /// Authorization-scope branch filter (FIL-2). Distinct from
  /// [_buildBranchFilter] (the UI dropdown filter) — this enforces the
  /// logged-in user's user_branch_access scope and is ANDed ON TOP of any
  /// dropdown/region filter. NULL-branch rows (global entries) stay visible,
  /// matching BranchScope.isAllowed(null)==true.
  ///   null      → no restriction (admin / full access)
  ///   empty set → AND 1 = 0 (match nothing — defensive)
  ///   {ids}     → AND (alias.branch_id IN (...) OR alias.branch_id IS NULL)
  ({String filter, List<Variable> vars}) _buildAuthScopeFilter(
    Set<int>? allowedBranchIds, {
    String tableAlias = 'e',
  }) {
    if (allowedBranchIds == null) return (filter: '', vars: <Variable>[]);
    if (allowedBranchIds.isEmpty) return (filter: ' AND 1 = 0', vars: <Variable>[]);
    final placeholders = allowedBranchIds.map((_) => '?').join(', ');
    return (
      filter: ' AND ($tableAlias.branch_id IN ($placeholders) OR $tableAlias.branch_id IS NULL)',
      vars: allowedBranchIds.map<Variable>((id) => Variable<int>(id)).toList(),
    );
  }

  /// Get Trial Balance (ميزان المراجعة)
  /// Enhanced: calculates opening balance, period movements, and closing balance
  /// from journal_entry_lines with proper date filtering.
  Future<List<Map<String, dynamic>>> getTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, List<int>? branchIds, Set<int>? allowedBranchIds}) async {
    final allAccounts = await (select(accounts)
      ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .get();

    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    final br = _buildBranchFilter(branchId, branchIds: branchIds);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds);
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);

    // 1. Opening balances: sum of all movements BEFORE the 'from' date
    //    Exclude soft-deleted JEs (belt-and-braces: the mirror-reversal
    //    pattern already nets to zero, but filtering guards against any
    //    future code path that soft-deletes a JE instead of reversing it).
    final openingRows = await customSelect(
      '''
      SELECT l.account_id,
             COALESCE(SUM(l.debit), 0) as total_debit,
             COALESCE(SUM(l.credit), 0) as total_credit
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      WHERE e.entry_date < ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse $ccFilter $brFilter$azFilter
      GROUP BY l.account_id
      ''',
      variables: [dateVar(from), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries},
    ).get();

    final Map<int, Map<String, double>> openingMap = {};
    for (var row in openingRows) {
      openingMap[row.read<int>('account_id')] = {
        'debit': (row.data['total_debit'] as num?)?.toDouble() ?? 0.0,
        'credit': (row.data['total_credit'] as num?)?.toDouble() ?? 0.0,
      };
    }

    // 2. Period movements: sum of debit/credit between 'from' and 'to'
    final movementRows = await customSelect(
      '''
      SELECT l.account_id,
             COALESCE(SUM(l.debit), 0) as total_debit,
             COALESCE(SUM(l.credit), 0) as total_credit
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      WHERE e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue AND e.is_deleted = $boolFalse $ccFilter $brFilter$azFilter
      GROUP BY l.account_id
      ''',
      variables: [dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries},
    ).get();

    final Map<int, Map<String, double>> movementMap = {};
    for (var row in movementRows) {
      movementMap[row.read<int>('account_id')] = {
        'debit': (row.data['total_debit'] as num?)?.toDouble() ?? 0.0,
        'credit': (row.data['total_credit'] as num?)?.toDouble() ?? 0.0,
      };
    }

    // 3. Build result for each account
    final List<Map<String, dynamic>> results = [];
    double totalOpeningDebit = 0, totalOpeningCredit = 0;
    double totalMovementDebit = 0, totalMovementCredit = 0;
    double totalClosingDebit = 0, totalClosingCredit = 0;

    for (var acc in allAccounts) {
      final opening = openingMap[acc.id];
      final movement = movementMap[acc.id];

      final openDebit = opening?['debit'] ?? 0.0;
      final openCredit = opening?['credit'] ?? 0.0;
      final openBalance = openDebit - openCredit;

      final moveDebit = movement?['debit'] ?? 0.0;
      final moveCredit = movement?['credit'] ?? 0.0;

      final closingBalance = openBalance + (moveDebit - moveCredit);

      // Opening balance: show as debit if positive, credit if negative
      final openingDebitDisplay = openBalance > 0 ? openBalance : 0.0;
      final openingCreditDisplay = openBalance < 0 ? openBalance.abs() : 0.0;

      // Closing balance: show as debit if positive, credit if negative
      final closingDebitDisplay = closingBalance > 0 ? closingBalance : 0.0;
      final closingCreditDisplay = closingBalance < 0 ? closingBalance.abs() : 0.0;

      // Skip accounts with no activity at all
      if (openBalance == 0 && moveDebit == 0 && moveCredit == 0) continue;

      totalOpeningDebit += openingDebitDisplay;
      totalOpeningCredit += openingCreditDisplay;
      totalMovementDebit += moveDebit;
      totalMovementCredit += moveCredit;
      totalClosingDebit += closingDebitDisplay;
      totalClosingCredit += closingCreditDisplay;

      results.add({
        'id': acc.id,
        'code': acc.code,
        'name': acc.name,
        'type': acc.accountType,
        'openingDebit': openingDebitDisplay,
        'openingCredit': openingCreditDisplay,
        'movementDebit': moveDebit,
        'movementCredit': moveCredit,
        'closingDebit': closingDebitDisplay,
        'closingCredit': closingCreditDisplay,
      });
    }

    // Add totals row
    results.add({
      'id': -1,
      'code': '',
      'name': 'الإجمالي',
      'type': 'total',
      'openingDebit': totalOpeningDebit,
      'openingCredit': totalOpeningCredit,
      'movementDebit': totalMovementDebit,
      'movementCredit': totalMovementCredit,
      'closingDebit': totalClosingDebit,
      'closingCredit': totalClosingCredit,
    });

    return results;
  }

  /// Get Income Statement (قائمة الدخل)
  /// Enhanced with COGS, operational expenses, and operating profit
  Future<Map<String, dynamic>> getIncomeStatement(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    int? branchId,
    List<int>? branchIds,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    final br = _buildBranchFilter(branchId, branchIds: branchIds);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds);
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);

    // 1. Account-based revenue and expenses
    // C-01: Only include POSTED entries in financial statements (ICR-01 compliance)
    final balances = await customSelect(
      '''
      SELECT a.id, a.name, a.account_type, a.code, SUM(l.debit - l.credit) as movement
      FROM accounts a
      JOIN journal_entry_lines l ON a.id = l.account_id
      JOIN journal_entries e ON l.entry_id = e.id
      WHERE a.account_type IN ('revenue', 'expense', 'contra_revenue')
        AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter
      GROUP BY a.id
      ''',
      variables: [dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars],
      readsFrom: {accounts, journalEntryLines, journalEntries},
    ).get();

    double revenue = 0;
    double cogs = 0; // تكلفة البضاعة المباعة — IAS 2.36
    double expenses = 0;
    double depreciation = 0; // Item 10: مصاريف الإهلاك — IAS 16.73(e)
    final List<Map<String, dynamic>> revenueDetails = [];
    final List<Map<String, dynamic>> cogsDetails = [];
    final List<Map<String, dynamic>> expenseDetails = [];
    final List<Map<String, dynamic>> depreciationDetails = [];
    double otherIncome = 0;   // #2: inventory surplus — non-operating gain
    double otherExpense = 0;  // #2: inventory shrinkage — non-operating loss
    final List<Map<String, dynamic>> otherIncomeDetails = [];
    final List<Map<String, dynamic>> otherExpenseDetails = [];

    // Resolve COGS account code (default: 5101)
    final cogsCode = await accountingDao.getMappedAccountCode(
      'cogs', AccountingDao.accountPurposes['cogs']!,
    );

    // Resolve depreciation expense account code (default: 5207)
    final depreciationCode = await accountingDao.getMappedAccountCode(
      'depreciation_expense', '5207',
    );

    // #2: inventory surplus (4317, a revenue account) and shrinkage (6216, an
    // expense account) are inventory-COUNT adjustments, not sales/operating
    // figures. Classify them as OTHER income/expense so "صافي الإيراد" (net
    // revenue) stays sales-only — adding stock via a تسوية no longer inflates
    // the sales line. Net profit is unchanged numerically (folded back below).
    final surplusCode = await accountingDao.getMappedAccountCode(
      'inventory_surplus', AccountingDao.accountPurposes['inventory_surplus']!,
    );
    final shrinkageCode = await accountingDao.getMappedAccountCode(
      'inventory_shrinkage', AccountingDao.accountPurposes['inventory_shrinkage']!,
    );

    // البند 1 (متطلبات العميل 2026-07-25) — non-SALES revenue must not sit
    // inside «صافي الإيراد». Same treatment `inventory_surplus` already got:
    // routed to otherIncome, and folded back into netProfit so that figure is
    // numerically unchanged.
    //
    // Why it matters: «فائض النقدية» is credited at shift close and «خصم
    // المشتريات المكتسب» when a supplier grants a discount. Both are
    // revenue-typed, so a cash overage in the till used to RAISE the sales
    // figure with no sale behind it — which is a large part of why the
    // customer could not reconcile the dashboard by hand.
    final nonSalesRevenueCodes = <String>{
      for (final purpose in const [
        'purchase_discount',
        'cash_surplus',
        'other_income',
        'rounding_difference',
      ])
        if (AccountingDao.accountPurposes[purpose] != null)
          await accountingDao.getMappedAccountCode(
            purpose,
            AccountingDao.accountPurposes[purpose]!,
          ),
    };

    // البند 1 — the three components that make the on-screen formula legible:
    // «مبيعات شاملة الضريبة − المردودات = صافي الإيراد (منها ضريبة كذا)».
    final salesReturnCode = await accountingDao.getMappedAccountCode(
      'sales_return', AccountingDao.accountPurposes['sales_return']!,
    );
    final outputVatCode = await accountingDao.getMappedAccountCode(
      'output_vat', AccountingDao.accountPurposes['output_vat']!,
    );
    double salesReturns = 0;

    for (var row in balances) {
      final name = row.read<String>('name');
      final type = row.read<String>('account_type');
      final code = row.read<String>('code');
      final netMovement = row.read<double>('movement');

      if (type == 'revenue') {
        // F-03: Revenue is credit-normal → GL stores debit-credit as negative
        // Using -netMovement correctly shows positive for normal credit balances
        final val = -netMovement;
        if (code == surplusCode || nonSalesRevenueCodes.contains(code)) {
          // #2 + البند 1: inventory surplus, cash overage, purchase discounts
          // earned and rounding differences are non-operating gains, not sales.
          otherIncome += val;
          if (val != 0) otherIncomeDetails.add({'name': name, 'amount': val});
        } else {
          revenue += val;
          // البند 1: the sales-returns account is seeded `revenue`-typed, so
          // returns already net out by SIGN (a debit yields a negative val)
          // rather than through the contra_revenue branch below. Capture the
          // magnitude here so the card can show المردودات as its own line.
          if (code == salesReturnCode) salesReturns += -val;
          if (val != 0) revenueDetails.add({'name': name, 'amount': val});
        }
      } else if (type == 'contra_revenue') {
        // Sales returns — debit-normal (IFRS 15.B20)
        // netMovement is positive for contra_revenue (debit > credit)
        final val = netMovement;
        revenue -= val;
        if (code == salesReturnCode) salesReturns += val;
        if (val != 0) revenueDetails.add({'name': name, 'amount': -val});
      } else if (type == 'expense') {
        final val = netMovement;
        // Separate COGS and depreciation from other expenses for proper layering
        if (code == cogsCode) {
          cogs += val;
          if (val != 0) cogsDetails.add({'name': name, 'amount': val});
        } else if (code == depreciationCode) {
          // Item 10: Depreciation shown separately per IAS 16.73(e)
          depreciation += val;
          if (val != 0) depreciationDetails.add({'name': name, 'amount': val});
        } else if (code == shrinkageCode) {
          // #2: inventory shrinkage is a non-operating loss, not an opex.
          otherExpense += val;
          if (val != 0) otherExpenseDetails.add({'name': name, 'amount': val});
        } else {
          expenses += val;
          if (val != 0) expenseDetails.add({'name': name, 'amount': val});
        }
      }
    }

    // C-02 FIX: REMOVED op_expenses dual-source query.
    // The GL (journal_entry_lines) is the SINGLE SOURCE OF TRUTH per IAS 1.
    // Operational expenses are auto-posted to the GL via autoPostOperationalExpense(),
    // so reading from op_expenses table as well would DOUBLE COUNT them.

    // Calculate profit levels (IAS 1.99 / IAS 2.36 / IAS 16.73e)
    // Gross Profit = Revenue - COGS
    final grossProfit = revenue - cogs;
    // Operating Profit = Gross Profit - Operating Expenses
    final operatingProfit = grossProfit - expenses;
    // Net Profit = Operating Profit - Depreciation + other income - other expense.
    // Folding the non-operating inventory adjustments back in keeps netProfit
    // NUMERICALLY IDENTICAL to before — only the operating totalRevenue/
    // totalExpenses now exclude them (so the sales line isn't inflated by a تسوية).
    final netProfit =
        operatingProfit - depreciation + otherIncome - otherExpense;

    // البند 1 — output VAT for the SAME window/scope, so all four numbers on
    // the card share one filter set and the operator's hand arithmetic works.
    // Liability-typed, so it is not in the revenue/expense scan above.
    final vatRow = await customSelect(
      '''
      SELECT COALESCE(SUM(l.credit - l.debit), 0) AS total
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      JOIN accounts a ON l.account_id = a.id
      WHERE a.code = ? AND e.entry_date BETWEEN ? AND ?
        AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter
      ''',
      variables: [
        Variable(outputVatCode),
        dateVar(from),
        dateVar(to),
        ...ccVars,
        ...brVars,
        ...azVars,
      ],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();
    final outputVatNet = (vatRow.data['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalRevenue': revenue,
      // البند 1 — مكوّنات المعادلة الظاهرة على الشاشة:
      //   مبيعات شاملة الضريبة − المردودات = صافي الإيراد (منها الضريبة)
      'salesReturns': salesReturns,
      'outputVatNet': outputVatNet,
      // صافي الإيراد **شاملاً** الضريبة — هذا هو الرقم الذي يحسبه العميل
      // يدوياً. مساوٍ تماماً لـ totalRevenue + outputVatNet، والمردودات
      // مخصومة من الطرفين أصلاً (المبلغ من الإيراد، وضريبتها من الضريبة).
      'netRevenueInclVat': revenue + outputVatNet,
      'totalCOGS': cogs,
      'grossProfit': grossProfit,
      'totalExpenses': expenses,
      'totalDepreciation': depreciation,
      'operatingProfit': operatingProfit,
      'netProfit': netProfit,
      'otherIncome': otherIncome,
      'otherExpense': otherExpense,
      'revenueDetails': revenueDetails,
      'cogsDetails': cogsDetails,
      'expenseDetails': expenseDetails,
      'depreciationDetails': depreciationDetails,
      'otherIncomeDetails': otherIncomeDetails,
      'otherExpenseDetails': otherExpenseDetails,
    };
  }

  /// Get Balance Sheet (الميزانية العمومية)
  Future<Map<String, dynamic>> getBalanceSheet(DateTime atDate, {int? costCenterId, int? branchId, List<int>? branchIds, Set<int>? allowedBranchIds}) async {
    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    final br = _buildBranchFilter(branchId, branchIds: branchIds);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds);
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);

    // Consolidated query for all BS accounts
    // C-01: Only include POSTED entries in balance sheet (ICR-01 compliance)
    final balances = await customSelect(
      '''
      SELECT a.id, a.name, a.account_type, SUM(l.debit - l.credit) as balance
      FROM accounts a
      JOIN journal_entry_lines l ON a.id = l.account_id
      JOIN journal_entries e ON l.entry_id = e.id
      WHERE a.account_type IN ('asset', 'liability', 'equity', 'contra_asset')
        AND e.entry_date <= ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter
      GROUP BY a.id
      ''',
      variables: [dateVar(atDate), ...ccVars, ...brVars, ...azVars],
      readsFrom: {accounts, journalEntryLines, journalEntries},
    ).get();

    double totalAssets = 0;
    double totalLiabilities = 0;
    double totalEquity = 0;

    final List<Map<String, dynamic>> assetDetails = [];
    final List<Map<String, dynamic>> liabilityDetails = [];
    final List<Map<String, dynamic>> equityDetails = [];

    for (var row in balances) {
      final name = row.read<String>('name');
      final type = row.read<String>('account_type');
      final bal = row.read<double>('balance');

      if (type == 'asset') {
        totalAssets += bal;
        if (bal != 0) assetDetails.add({'name': name, 'balance': bal});
      } else if (type == 'contra_asset') {
        // Accumulated depreciation — deducted from assets (IAS 16.73d)
        totalAssets -= bal.abs();
        if (bal != 0) assetDetails.add({'name': name, 'balance': -bal.abs()});
      } else if (type == 'liability') {
        // M-02: Credit-normal accounts have negative debit-credit sum.
        // Use -bal instead of .abs() to preserve sign for edge cases
        // (e.g., overpaid liability with debit balance shows as negative).
        totalLiabilities += -bal;
        if (bal != 0) {
          liabilityDetails.add({'name': name, 'balance': -bal});
        }
      } else if (type == 'equity') {
        // M-02: Same as liabilities — credit-normal, negate for display
        totalEquity += -bal;
        if (bal != 0) {
          equityDetails.add({'name': name, 'balance': -bal});
        }
      }
    }

    // Add Net Profit from P&L to Equity (fiscal year CONTAINING atDate)
    // REP-2 fix (spec 149 B11): resolve the fiscal year that CONTAINS
    // atDate — not "whichever FY is flagged isCurrent" — otherwise running
    // the balance sheet for a prior/closed year mis-scopes the P&L window
    // (fyStart from the CURRENT FY can be after atDate, inverting the
    // range → 0/garbage "صافي الأرباح (دوري)"). Also forward the SAME
    // branch scope (branchIds) used by the equity-account aggregation
    // above so both sides agree — previously only the singular branchId
    // was forwarded, so a multi-branch call scoped equity accounts per
    // branchIds but net income company-wide.
    final atDateFY = await getFiscalYearByDate(atDate);
    final fyStart = atDateFY?.startDate ?? DateTime(atDate.year, 1, 1);
    // FIL-2: forward the SAME auth scope used for the account aggregation
    // above, so the net-profit-in-equity figure doesn't leak other
    // branches' P&L into a restricted user's balance sheet.
    final pl = await getIncomeStatement(fyStart, atDate,
        costCenterId: costCenterId, branchId: branchId, branchIds: branchIds,
        allowedBranchIds: allowedBranchIds);
    final netProfit = pl['netProfit'] as double;
    totalEquity += netProfit;
    equityDetails.add({'name': 'صافي الأرباح (دوري)', 'balance': netProfit});

    return {
      'totalAssets': totalAssets,
      'totalLiabilities': totalLiabilities,
      'totalEquity': totalEquity,
      'assetDetails': assetDetails,
      'liabilityDetails': liabilityDetails,
      'equityDetails': equityDetails,
      'isBalanced':
          (totalAssets - (totalLiabilities + totalEquity)).abs() < 0.01,
    };
  }

  /// Get Cash Flow Statement (قائمة التدفقات النقدية) — IAS 7
  /// Rebuilt to read from journal_entry_lines (GL) instead of safe_transactions.
  /// Uses the indirect method: cash & bank accounts track all cash movements.
  /// H-02: Uses dynamic account resolution instead of hardcoded codes.
  /// C-01: Filters by is_posted = 1.
  Future<Map<String, dynamic>> getCashFlowStatement(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    int? branchId,
    List<int>? branchIds,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'jel', entryAlias: 'je');
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    // D-03: a region maps to MANY branches — pass the full [branchIds] set so
    // the NULL-branch (global) rows are counted once via a single
    // `branch_id IN (..) OR branch_id IS NULL` query, never looped per branch.
    final br = _buildBranchFilter(branchId, tableAlias: 'je', branchIds: branchIds);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'je');
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);

    // H-02: Dynamic account code resolution instead of hardcoded '1101'/'1102'
    // H-02: Dynamic account code resolution instead of hardcoded '1101'/'1102'
    final cashCode = await accountingDao.getMappedAccountCode(
      'cash', AccountingDao.accountPurposes['cash']!,
    );
    final bankCode = await accountingDao.getMappedAccountCode(
      'bank', AccountingDao.accountPurposes['bank']!,
    );
    final cashBankCodes = "'$cashCode', '$bankCode'";

    // ─── Operating Activities (IAS 7.14) ─────────────────────────────────
    final operatingResults = await customSelect(
      '''
      SELECT je.reference_type,
             SUM(jel.debit) as total_debit,
             SUM(jel.credit) as total_credit
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE a.code IN ($cashBankCodes)
        AND je.entry_date BETWEEN ? AND ? AND je.is_posted = $boolTrue $ccFilter $brFilter$azFilter
        AND je.reference_type NOT IN ('asset_acquisition', 'asset_disposal', 'asset_transfer', 'asset_revaluation', 'commercial_paper')
      GROUP BY je.reference_type
      ''',
      variables: [dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).get();

    double operatingInflow = 0;
    double operatingOutflow = 0;
    double salesCash = 0;
    double purchasesCash = 0;
    double salaries = 0;
    double expenses = 0;
    double otherReceipts = 0;
    double otherPayments = 0;

    for (final row in operatingResults) {
      final refType = row.data['reference_type'] as String? ?? '';
      final debits = row.data['total_debit'] as double? ?? 0;
      final credits = row.data['total_credit'] as double? ?? 0;

      // H-02: Precise reference_type matching (not .contains())
      switch (refType) {
        case 'cash_sale':
        case 'credit_sale':
        case 'sale':
        case 'sales_invoice':
          salesCash += debits;
          break;
        case 'sale_return':
        case 'sales_return':
          salesCash -= credits; // Returns reduce sales cash
          break;
        case 'purchase':
        case 'purchase_invoice':
          purchasesCash += credits;
          break;
        case 'purchase_return':
          purchasesCash -= debits; // Returns reduce purchase cash
          break;
        case 'salary':
        case 'payroll':
          salaries += credits;
          break;
        case 'op_expense':
        case 'expense':
        case 'operational_expense':
          expenses += credits;
          break;
        case 'receipt':
          otherReceipts += debits;
          break;
        case 'payment':
          otherPayments += credits;
          break;
        default:
          // Manual JEs and unclassified
          otherReceipts += debits;
          otherPayments += credits;
      }

      operatingInflow += debits;
      operatingOutflow += credits;
    }

    final netOperating = operatingInflow - operatingOutflow;

    // ─── Investing Activities (IAS 7.16) ─────────────────────────────────
    final investingResults = await customSelect(
      '''
      SELECT SUM(jel.debit) as total_debit,
             SUM(jel.credit) as total_credit
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE a.code IN ($cashBankCodes)
        AND je.entry_date BETWEEN ? AND ? AND je.is_posted = $boolTrue $ccFilter $brFilter$azFilter
        AND je.reference_type IN ('asset_acquisition', 'asset_disposal', 'asset_transfer', 'asset_revaluation')
      ''',
      variables: [dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).get();

    double investingInflow = 0;
    double investingOutflow = 0;
    if (investingResults.isNotEmpty) {
      investingInflow = investingResults.first.data['total_debit'] as double? ?? 0;
      investingOutflow = investingResults.first.data['total_credit'] as double? ?? 0;
    }
    final netInvesting = investingInflow - investingOutflow;

    // ─── Financing Activities (IAS 7.17) ──────────────────────────────────
    final financingResults = await customSelect(
      '''
      SELECT SUM(jel.debit) as total_debit,
             SUM(jel.credit) as total_credit
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE a.code IN ($cashBankCodes)
        AND je.entry_date BETWEEN ? AND ? AND je.is_posted = $boolTrue $ccFilter $brFilter$azFilter
        AND je.reference_type = 'commercial_paper'
      ''',
      variables: [dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).get();

    double financingInflow = 0;
    double financingOutflow = 0;
    if (financingResults.isNotEmpty) {
      financingInflow = financingResults.first.data['total_debit'] as double? ?? 0;
      financingOutflow = financingResults.first.data['total_credit'] as double? ?? 0;
    }
    final netFinancing = financingInflow - financingOutflow;

    // ─── Opening & Closing Balances ──────────────────────────────────────
    final openingResult = await customSelect(
      '''
      SELECT SUM(jel.debit - jel.credit) as balance
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE a.code IN ($cashBankCodes)
        AND je.entry_date < ? AND je.is_posted = $boolTrue $ccFilter $brFilter$azFilter
      ''',
      variables: [dateVar(from), ...ccVars, ...brVars, ...azVars],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final openingBalance = openingResult.data['balance'] as double? ?? 0;
    final netChange = netOperating + netInvesting + netFinancing;
    final closingBalance = openingBalance + netChange;

    return {
      'operating': {
        'salesCash': salesCash,
        'receiptsFromCustomers': otherReceipts,
        'purchasesCash': purchasesCash,
        'paymentsToSuppliers': otherPayments,
        'salaries': salaries,
        'expenses': expenses,
        'totalInflow': operatingInflow,
        'totalOutflow': operatingOutflow,
        'net': netOperating,
      },
      'investing': {
        'assetPurchases': investingOutflow,
        'assetDisposals': investingInflow,
        'net': netInvesting,
      },
      'financing': {
        'checksCollected': financingInflow,
        'checksIssued': financingOutflow,
        'net': netFinancing,
      },
      'openingBalance': openingBalance,
      'closingBalance': closingBalance,
      'netChange': netChange,
    };
  }

  /// Get Tax Report (تقرير الضرائب والقيمة)
  /// C-03: Rewritten to read from GL (accounts 2201/1204) instead of source tables.
  /// This ensures tax adjustments via manual JE are reflected, and deferred
  /// revenue invoices (IFRS 15.38) are excluded until posted.
  Future<Map<String, dynamic>> getTaxReport(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    final br = _buildBranchFilter(branchId);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds);
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);

    // Build warehouse filter for VAT queries
    // Since VAT accounts are in GL, we must join with the source invoice (ref_id)
    // to filter by specific warehouses.
    String outputWhFilter = '';
    final outputWhVars = <Variable>[];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        outputWhFilter = 'AND 1 = 0';
      } else {
        // ح-7 (2026-07-25): 'sales_return' MUST be in the reference-type list.
        // Return JEs debit output VAT (they reduce the liability); leaving them
        // out of the EXISTS made every one of them fail the filter, so applying
        // a branch/warehouse filter silently DROPPED the return reversals and
        // reported a LARGER tax liability than the unfiltered view — i.e. the
        // filtered number overstated what is owed to the authority.
        //
        // The trailing OR keeps JEs that have no invoice to join to (manual VAT
        // adjustments, opening balances) in scope; previously a warehouse
        // filter discarded those entirely.
        outputWhFilter = '''
        AND (
          EXISTS (
            SELECT 1 FROM sales_invoices si
            WHERE si.id = e.reference_id
            AND e.reference_type IN ('sale', 'sales_invoice', 'cash_sale', 'sales_return')
            AND si.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})
          )
          OR e.reference_type NOT IN ('sale', 'sales_invoice', 'cash_sale', 'sales_return')
          OR e.reference_type IS NULL
        )
      ''';
        outputWhVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    String inputWhFilter = '';
    final inputWhVars = <Variable>[];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        inputWhFilter = 'AND 1 = 0';
      } else {
        // ح-7 — same fix on the purchase side: 'purchase_invoice' is the alias
        // the inline createPurchaseInvoice path stores, and 'purchase_return'
        // credits input VAT back. Both were dropped by the old filter.
        inputWhFilter = '''
        AND (
          EXISTS (
            SELECT 1 FROM purchase_invoices pi
            WHERE pi.id = e.reference_id
            AND e.reference_type IN ('purchase', 'purchase_invoice', 'purchase_return')
            AND pi.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})
          )
          OR e.reference_type NOT IN ('purchase', 'purchase_invoice', 'purchase_return')
          OR e.reference_type IS NULL
        )
      ''';
        inputWhVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    // C-03: Resolve VAT account codes dynamically
    final outputVatCode = await accountingDao.getMappedAccountCode(
      'output_vat', AccountingDao.accountPurposes['output_vat']!,
    );
    final inputVatCode = await accountingDao.getMappedAccountCode(
      'input_vat', AccountingDao.accountPurposes['input_vat']!,
    );
    final salesCode = await accountingDao.getMappedAccountCode(
      'sales', AccountingDao.accountPurposes['sales']!,
    );

    // Output VAT (ضريبة مبيعات) from GL — credit balance = tax collected
    final outputVatResult = await customSelect(
      '''
      SELECT COALESCE(SUM(l.credit - l.debit), 0) as total
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      JOIN accounts a ON l.account_id = a.id
      WHERE a.code = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter $outputWhFilter
      ''',
      variables: [Variable(outputVatCode), dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars, ...outputWhVars],
      readsFrom: {journalEntryLines, journalEntries, accounts, salesInvoices},
    ).getSingle();

    // Input VAT (ضريبة مدخلات) from GL — debit balance = tax paid
    final inputVatResult = await customSelect(
      '''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) as total
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      JOIN accounts a ON l.account_id = a.id
      WHERE a.code = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter $inputWhFilter
      ''',
      variables: [Variable(inputVatCode), dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars, ...inputWhVars],
      readsFrom: {journalEntryLines, journalEntries, accounts, purchaseInvoices},
    ).getSingle();

    // Sales total (excl tax) from GL — credit balance on sales account
    final salesResult = await customSelect(
      '''
      SELECT COALESCE(SUM(l.credit - l.debit), 0) as total
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      JOIN accounts a ON l.account_id = a.id
      WHERE a.code = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter $outputWhFilter
      ''',
      variables: [Variable(salesCode), dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars, ...outputWhVars],
      readsFrom: {journalEntryLines, journalEntries, accounts, salesInvoices},
    ).getSingle();

    // Purchase total (excl tax) from inventory account movements
    final inventoryCode = await accountingDao.getMappedAccountCode(
      'inventory', AccountingDao.accountPurposes['inventory']!,
    );
    final purchaseResult = await customSelect(
      '''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) as total
      FROM journal_entry_lines l
      JOIN journal_entries e ON l.entry_id = e.id
      JOIN accounts a ON l.account_id = a.id
      WHERE a.code = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter $inputWhFilter
        AND e.reference_type IN ('purchase', 'purchase_invoice')
      ''',
      variables: [Variable(inventoryCode), dateVar(from), dateVar(to), ...ccVars, ...brVars, ...azVars, ...inputWhVars],
      readsFrom: {journalEntryLines, journalEntries, accounts, purchaseInvoices},
    ).getSingle();

    final salesTax = (outputVatResult.data['total'] as num?)?.toDouble() ?? 0.0;
    final purchaseTax = (inputVatResult.data['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'salesTax': salesTax,
      'purchaseTax': purchaseTax,
      'salesTotalExclTax': (salesResult.data['total'] as num?)?.toDouble() ?? 0.0,
      'purchaseTotalExclTax': (purchaseResult.data['total'] as num?)?.toDouble() ?? 0.0,
      'netTax': salesTax - purchaseTax,
    };
  }

  /// البند 8 (متطلبات العميل 2026-07-25) — تفصيل ضريبة المبيعات **لكل صنف**.
  ///
  /// The tax report used to show invoice HEADERS only (رقم الفاتورة · التاريخ ·
  /// الإجمالي · الضريبة), so an invoice mixing a 16% item with a 5% item showed
  /// one lump tax figure and no rate at all. The per-line `tax_rate`/`tax_amount`
  /// were already stored and populated on every write path — the report simply
  /// never read `sales_invoice_items`. No schema change was needed.
  ///
  /// Returns one row per invoice LINE with its own rate, taxable base and tax,
  /// ordered so the UI can group by invoice. Return invoices and
  /// cancelled/voided/soft-deleted invoices are excluded — a VAT return is
  /// filed on live sales, and the returns reversal is reported separately.
  Future<List<Map<String, dynamic>>> getSalesTaxDetailByItem(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async {
    final vars = <Variable>[dateVar(from), dateVar(to)];
    final boolFalse = sqlBool(false);

    var whFilter = '';
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        whFilter = ' AND 1 = 0';
      } else {
        whFilter =
            ' AND si.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    var ccFilter = '';
    if (costCenterId != null) {
      ccFilter = ' AND si.cost_center_id = ?';
      vars.add(Variable<int>(costCenterId));
    }

    var brFilter = '';
    if (branchId != null) {
      brFilter = ' AND (si.branch_id = ? OR si.branch_id IS NULL)';
      vars.add(Variable<int>(branchId));
    }

    var azFilter = '';
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        azFilter = ' AND 1 = 0';
      } else {
        azFilter =
            ' AND (si.branch_id IN (${allowedBranchIds.map((_) => '?').join(', ')})'
            ' OR si.branch_id IS NULL)';
        vars.addAll(allowedBranchIds.map<Variable>((id) => Variable<int>(id)));
      }
    }

    final rows = await customSelect(
      '''
      SELECT si.id                AS invoiceId,
             si.invoice_number    AS invoiceNumber,
             si.invoice_date      AS invoiceDate,
             si.tax               AS invoiceTax,
             p.name               AS customerName,
             pr.name              AS productName,
             sii.quantity         AS quantity,
             sii.unit_price       AS unitPrice,
             sii.total            AS lineTotal,
             (sii.total - sii.tax_amount) AS taxableBase,
             sii.tax_rate         AS taxRate,
             sii.tax_amount       AS taxAmount
      FROM sales_invoice_items sii
      JOIN sales_invoices si ON si.id = sii.invoice_id
      LEFT JOIN products pr  ON pr.id = sii.product_id
      LEFT JOIN parties p    ON p.id  = si.customer_id
      WHERE si.invoice_date BETWEEN ? AND ?
        AND si.is_deleted = $boolFalse
        AND (si.sale_type IS NULL OR si.sale_type != 'return')
        AND (si.status IS NULL OR si.status NOT IN ('cancelled', 'voided'))
        $whFilter$ccFilter$brFilter$azFilter
      ORDER BY si.invoice_date, si.invoice_number, sii.id
      ''',
      variables: vars,
      readsFrom: {salesInvoiceItems, salesInvoices, products, parties},
    ).get();

    return rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
  }

  /// البند 8 — مجاميع فرعية لكل نسبة ضريبة (الشكل الذي يتطلبه الإقرار
  /// الضريبي: وعاء خاضع + ضريبة لكل شريحة). Built from
  /// [getSalesTaxDetailByItem] so the buckets can never disagree with the
  /// detail rows rendered beneath them. Sorted by rate descending.
  Future<List<Map<String, dynamic>>> getSalesTaxByRate(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async {
    final detail = await getSalesTaxDetailByItem(
      from,
      to,
      costCenterId: costCenterId,
      warehouseIds: warehouseIds,
      branchId: branchId,
      allowedBranchIds: allowedBranchIds,
    );

    final buckets = <double, ({double base, double tax})>{};
    for (final r in detail) {
      final rate = (r['taxRate'] as num?)?.toDouble() ?? 0.0;
      final base = (r['taxableBase'] as num?)?.toDouble() ?? 0.0;
      final tax = (r['taxAmount'] as num?)?.toDouble() ?? 0.0;
      final cur = buckets[rate] ?? (base: 0.0, tax: 0.0);
      buckets[rate] = (base: cur.base + base, tax: cur.tax + tax);
    }

    return buckets.entries
        .map((e) => <String, dynamic>{
              'taxRate': e.key,
              'taxableBase': e.value.base,
              'taxAmount': e.value.tax,
            })
        .toList()
      ..sort(
          (a, b) => (b['taxRate'] as double).compareTo(a['taxRate'] as double));
  }

  // ═══ M-04: Hierarchical Trial Balance (ميزان المراجعة التفصيلي) ═══
  /// Returns trial balance grouped by account type with subtotals per group.
  Future<Map<String, dynamic>> getHierarchicalTrialBalance(
    DateTime from, DateTime to, {int? costCenterId, int? branchId, Set<int>? allowedBranchIds}
  ) async {
    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final ccVars = cc.vars;
    final br = _buildBranchFilter(branchId);
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds);
    final azFilter = az.filter;
    final azVars = az.vars;
    final boolTrue = sqlBool(true);

    final rows = await customSelect(
      '''
      SELECT a.id, a.name, a.code, a.account_type, a.parent_id,
             SUM(CASE WHEN e.entry_date < ? THEN (l.debit - l.credit) ELSE 0 END) as opening,
             SUM(CASE WHEN e.entry_date BETWEEN ? AND ? THEN l.debit ELSE 0 END) as period_debit,
             SUM(CASE WHEN e.entry_date BETWEEN ? AND ? THEN l.credit ELSE 0 END) as period_credit,
             SUM(l.debit - l.credit) as closing
      FROM accounts a
      JOIN journal_entry_lines l ON a.id = l.account_id
      JOIN journal_entries e ON l.entry_id = e.id
      WHERE e.entry_date <= ? AND e.is_posted = $boolTrue $ccFilter $brFilter$azFilter
      GROUP BY a.id
      ORDER BY a.code
      ''',
      variables: [
        dateVar(from), dateVar(from), dateVar(to),
        dateVar(from), dateVar(to), dateVar(to), ...ccVars, ...brVars, ...azVars
      ],
      readsFrom: {accounts, journalEntryLines, journalEntries},
    ).get();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    double totalDebit = 0, totalCredit = 0;

    for (final row in rows) {
      final type = row.read<String>('account_type');
      final debit = (row.data['period_debit'] as num?)?.toDouble() ?? 0;
      final credit = (row.data['period_credit'] as num?)?.toDouble() ?? 0;
      totalDebit += debit;
      totalCredit += credit;

      grouped.putIfAbsent(type, () => []);
      grouped[type]!.add({
        'id': row.read<int>('id'),
        'name': row.read<String>('name'),
        'code': row.read<String>('code'),
        'parentId': row.data['parent_id'],
        'opening': (row.data['opening'] as num?)?.toDouble() ?? 0,
        'periodDebit': debit,
        'periodCredit': credit,
        'closing': (row.data['closing'] as num?)?.toDouble() ?? 0,
      });
    }

    return {
      'groups': grouped,
      'totalDebit': totalDebit,
      'totalCredit': totalCredit,
      'isBalanced': (totalDebit - totalCredit).abs() < 0.01,
    };
  }

  // ═══ M-05: Aged Payables Report (تقادم الذمم الدائنة) ═══
  /// Calculates supplier balances aged into 0-30, 31-60, 61-90, 90+ day buckets.
  /// Non-invoice balances (e.g. from payment vouchers) are assigned to 'current'.
  Future<List<Map<String, dynamic>>> getAgedPayables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'pi', entryAlias: 'pi');
    final ccFilter = cc.filter;
    final boolTrue = sqlBool(true);

    // P1-5: Branch/region scope filter
    var scopeFilter = '';
    final scopeVars = <Variable>[];
    if (branchId != null) {
      scopeFilter = ' AND pi.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id = ?)';
      scopeVars.add(Variable(branchId));
    } else if (regionId != null) {
      scopeFilter = ' AND pi.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id IN (SELECT id FROM branches WHERE region_id = ?))';
      scopeVars.add(Variable(regionId));
    }
    // FIL-2: auth-scope filter — restricts the aging buckets (the JOIN)
    // to the user's allowed-branch warehouses. ANDed on top of the
    // dropdown branch/region filter above. NOTE: `p.balance` below stays
    // a global, company-wide figure — parties are shared master data
    // across branches (pre-existing design), so full party-balance
    // branch-partitioning would need a schema change and is deferred.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        scopeFilter += ' AND 1 = 0';
      } else {
        scopeFilter += ' AND pi.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id IN (${allowedBranchIds.map((_) => '?').join(', ')}))';
        scopeVars.addAll(allowedBranchIds.map((id) => Variable<int>(id)));
      }
    }

    final results = await customSelect(
      '''
      SELECT p.id, p.name, p.balance,
             COALESCE(SUM(CASE WHEN (? - COALESCE(pi.due_date, pi.invoice_date)) / 86400 <= 30 THEN pi.total - pi.paid ELSE 0 END), 0) as current_30,
             COALESCE(SUM(CASE WHEN (? - COALESCE(pi.due_date, pi.invoice_date)) / 86400 BETWEEN 31 AND 60 THEN pi.total - pi.paid ELSE 0 END), 0) as days_31_60,
             COALESCE(SUM(CASE WHEN (? - COALESCE(pi.due_date, pi.invoice_date)) / 86400 BETWEEN 61 AND 90 THEN pi.total - pi.paid ELSE 0 END), 0) as days_61_90,
             COALESCE(SUM(CASE WHEN (? - COALESCE(pi.due_date, pi.invoice_date)) / 86400 > 90 THEN pi.total - pi.paid ELSE 0 END), 0) as over_90
      FROM parties p
      LEFT JOIN purchase_invoices pi ON pi.supplier_id = p.id AND pi.total > pi.paid $ccFilter$scopeFilter
      WHERE p.is_supplier = $boolTrue AND p.balance > 0.01
      GROUP BY p.id, p.name, p.balance
      ORDER BY p.balance DESC
      ''',
      variables: [
        dateVar(asOfDate), dateVar(asOfDate),
        dateVar(asOfDate), dateVar(asOfDate),
        ...cc.vars,
        ...scopeVars,
      ],
      readsFrom: {parties, purchaseInvoices},
    ).get();

    return results.map((r) {
      final totalBalance = (r.data['balance'] as num?)?.toDouble() ?? 0;
      final inv30 = (r.data['current_30'] as num?)?.toDouble() ?? 0;
      final inv3160 = (r.data['days_31_60'] as num?)?.toDouble() ?? 0;
      final inv6190 = (r.data['days_61_90'] as num?)?.toDouble() ?? 0;
      final inv90p = (r.data['over_90'] as num?)?.toDouble() ?? 0;
      final invoiceBased = inv30 + inv3160 + inv6190 + inv90p;
      // Non-invoice remainder (vouchers, manual JEs) → assigned to current bucket
      final remainder = (totalBalance - invoiceBased).clamp(0.0, double.infinity);
      return {
        'id': r.read<int>('id'),
        'name': r.read<String>('name'),
        'totalBalance': totalBalance,
        'current': inv30 + remainder,
        'days31_60': inv3160,
        'days61_90': inv6190,
        'over90': inv90p,
      };
    }).toList();
  }

  // ═══ M-06: Aged Receivables Report (تقادم الذمم المدينة) ═══
  /// Calculates customer balances aged into 0-30, 31-60, 61-90, 90+ day buckets.
  /// Non-invoice balances (e.g. from receipt vouchers) are assigned to 'current'.
  Future<List<Map<String, dynamic>>> getAgedReceivables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'si', entryAlias: 'si');
    final ccFilter = cc.filter;
    final boolTrue = sqlBool(true);

    // P1-5: Branch/region scope filter
    var scopeFilter = '';
    final scopeVars = <Variable>[];
    if (branchId != null) {
      scopeFilter = ' AND si.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id = ?)';
      scopeVars.add(Variable(branchId));
    } else if (regionId != null) {
      scopeFilter = ' AND si.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id IN (SELECT id FROM branches WHERE region_id = ?))';
      scopeVars.add(Variable(regionId));
    }
    // FIL-2: auth-scope filter — restricts the aging buckets (the JOIN)
    // to the user's allowed-branch warehouses. ANDed on top of the
    // dropdown branch/region filter above. NOTE: `p.balance` below stays
    // a global, company-wide figure — parties are shared master data
    // across branches (pre-existing design), so full party-balance
    // branch-partitioning would need a schema change and is deferred.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        scopeFilter += ' AND 1 = 0';
      } else {
        scopeFilter += ' AND si.warehouse_id IN (SELECT id FROM warehouses WHERE branch_id IN (${allowedBranchIds.map((_) => '?').join(', ')}))';
        scopeVars.addAll(allowedBranchIds.map((id) => Variable<int>(id)));
      }
    }

    // Use epoch-based date difference (works on both SQLite and PostgreSQL)
    // Drift stores DateTime as seconds since epoch (integer)
    // asOfDate epoch - invoice_date epoch / 86400 = days difference
    final results = await customSelect(
      '''
      SELECT p.id, p.name, p.balance,
             COALESCE(SUM(CASE WHEN (? - COALESCE(si.due_date, si.invoice_date)) / 86400 <= 30 THEN si.total - si.paid ELSE 0 END), 0) as current_30,
             COALESCE(SUM(CASE WHEN (? - COALESCE(si.due_date, si.invoice_date)) / 86400 BETWEEN 31 AND 60 THEN si.total - si.paid ELSE 0 END), 0) as days_31_60,
             COALESCE(SUM(CASE WHEN (? - COALESCE(si.due_date, si.invoice_date)) / 86400 BETWEEN 61 AND 90 THEN si.total - si.paid ELSE 0 END), 0) as days_61_90,
             COALESCE(SUM(CASE WHEN (? - COALESCE(si.due_date, si.invoice_date)) / 86400 > 90 THEN si.total - si.paid ELSE 0 END), 0) as over_90
      FROM parties p
      LEFT JOIN sales_invoices si ON si.customer_id = p.id AND si.total > si.paid $ccFilter$scopeFilter
      WHERE p.is_customer = $boolTrue AND p.balance > 0.01
      GROUP BY p.id, p.name, p.balance
      ORDER BY p.balance DESC
      ''',
      variables: [
        dateVar(asOfDate), dateVar(asOfDate),
        dateVar(asOfDate), dateVar(asOfDate),
        ...cc.vars,
        ...scopeVars,
      ],
      readsFrom: {parties, salesInvoices},
    ).get();

    return results.map((r) {
      final totalBalance = (r.data['balance'] as num?)?.toDouble() ?? 0;
      final inv30 = (r.data['current_30'] as num?)?.toDouble() ?? 0;
      final inv3160 = (r.data['days_31_60'] as num?)?.toDouble() ?? 0;
      final inv6190 = (r.data['days_61_90'] as num?)?.toDouble() ?? 0;
      final inv90p = (r.data['over_90'] as num?)?.toDouble() ?? 0;
      final invoiceBased = inv30 + inv3160 + inv6190 + inv90p;
      // Non-invoice remainder (vouchers, manual JEs) → assigned to current bucket
      final remainder = (totalBalance - invoiceBased).clamp(0.0, double.infinity);
      return {
        'id': r.read<int>('id'),
        'name': r.read<String>('name'),
        'totalBalance': totalBalance,
        'current': inv30 + remainder,
        'days31_60': inv3160,
        'days61_90': inv6190,
        'over90': inv90p,
      };
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقرير مطابقة الترحيل (Posting Reconciliation Report)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compares invoices (sales/purchases) with their journal entries.
  /// Returns a list of results showing each invoice, its JE status, and any discrepancies.
  Future<List<Map<String, dynamic>>> getPostingReconciliation(
    DateTime from,
    DateTime to, {
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async {
    final boolTrue = sqlBool(true);
    // FIL-5: previously an ad-hoc `AND je.branch_id = ?` which EXCLUDED
    // global (NULL-branch) JEs — inconsistent with _buildBranchFilter's
    // convention everywhere else. Routed through the shared helper so
    // global entries stay visible, then AND the auth-scope filter on top.
    final br = _buildBranchFilter(branchId, tableAlias: 'je');
    final brFilter = br.filter;
    final brVars = br.vars;
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'je');
    final azFilter = az.filter;
    final azVars = az.vars;
    // FIL-2 (committee BLOCK fix): the je-side filters above only constrain
    // the JOIN — the driving invoice tables must ALSO be branch-scoped, or a
    // restricted user still reads every branch's invoice rows (and foreign
    // invoices render as false "missing JE"). Scope on the invoice's own
    // branch_id, NULL-inclusive, same contract as the JE side.
    final brSi = _buildBranchFilter(branchId, tableAlias: 'si');
    final azSi = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'si');
    final brPi = _buildBranchFilter(branchId, tableAlias: 'pi');
    final azPi = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'pi');

    // 1. Sales invoices vs journal entries
    final salesResults = await customSelect(
      '''
      SELECT si.id, si.invoice_number, si.invoice_date, si.total, si.paid,
             si.status as si_status,
             je.id as je_id, je.entry_number, je.is_posted,
             COALESCE(SUM(jel.debit), 0) as je_debit_total,
             COALESCE(SUM(jel.credit), 0) as je_credit_total,
             'sale' as source_type
      FROM sales_invoices si
      -- Spec 151: 'sales_return' removed from this IN-list. Return JEs are now
      -- keyed on the ORIGINATING invoice id, so including them here made this
      -- LEFT JOIN match the sale JE AND every return JE — duplicating the
      -- invoice row (one per JE) and reporting a false debit/credit mismatch.
      -- The purchase query below correctly matches only 'purchase'.
      LEFT JOIN journal_entries je ON je.reference_type IN ('sale', 'cash_sale', 'credit_sale')
        AND je.reference_id = si.id $brFilter$azFilter
      LEFT JOIN journal_entry_lines jel ON jel.entry_id = je.id
      WHERE si.invoice_date BETWEEN ? AND ?${brSi.filter}${azSi.filter}
      GROUP BY si.id, si.invoice_number, si.invoice_date, si.total, si.paid,
               si.status, je.id, je.entry_number, je.is_posted
      ORDER BY si.invoice_date DESC
      ''',
      variables: [...brVars, ...azVars, dateVar(from), dateVar(to), ...brSi.vars, ...azSi.vars],
      readsFrom: {salesInvoices, journalEntries, journalEntryLines},
    ).get();

    // 2. Purchase invoices vs journal entries
    final purchaseResults = await customSelect(
      '''
      SELECT pi.id, pi.invoice_number, pi.created_at as invoice_date, pi.total,
             pi.paid,
             je.id as je_id, je.entry_number, je.is_posted,
             COALESCE(SUM(jel.debit), 0) as je_debit_total,
             COALESCE(SUM(jel.credit), 0) as je_credit_total,
             'purchase' as source_type
      FROM purchase_invoices pi
      LEFT JOIN journal_entries je ON je.reference_type = 'purchase'
        AND je.reference_id = pi.id $brFilter$azFilter
      LEFT JOIN journal_entry_lines jel ON jel.entry_id = je.id
      WHERE pi.created_at BETWEEN ? AND ?${brPi.filter}${azPi.filter}
      GROUP BY pi.id, pi.invoice_number, pi.created_at, pi.total, pi.paid,
               je.id, je.entry_number, je.is_posted
      ORDER BY pi.created_at DESC
      ''',
      variables: [...brVars, ...azVars, dateVar(from), dateVar(to), ...brPi.vars, ...azPi.vars],
      readsFrom: {purchaseInvoices, journalEntries, journalEntryLines},
    ).get();

    // 3. Orphan journal entries (JEs without matching invoices)
    final orphanResults = await customSelect(
      '''
      SELECT je.id as je_id, je.entry_number, je.entry_date, je.description,
             je.reference_type, je.reference_id, je.is_posted,
             COALESCE(SUM(jel.debit), 0) as je_debit_total,
             COALESCE(SUM(jel.credit), 0) as je_credit_total
      FROM journal_entries je
      LEFT JOIN journal_entry_lines jel ON jel.entry_id = je.id
      WHERE je.entry_date BETWEEN ? AND ?
        AND je.reference_type IN ('sale', 'cash_sale', 'credit_sale', 'sales_return', 'purchase')
        AND je.is_posted = $boolTrue
        $brFilter$azFilter
        AND je.reference_id NOT IN (
          SELECT id FROM sales_invoices WHERE invoice_date BETWEEN ? AND ?
        )
        AND je.reference_id NOT IN (
          SELECT id FROM purchase_invoices WHERE invoice_date BETWEEN ? AND ?
        )
      GROUP BY je.id, je.entry_number, je.entry_date, je.description,
               je.reference_type, je.reference_id, je.is_posted
      ORDER BY je.entry_date DESC
      ''',
      variables: [dateVar(from), dateVar(to), ...brVars, ...azVars, dateVar(from), dateVar(to), dateVar(from), dateVar(to)],
      readsFrom: {journalEntries, journalEntryLines, salesInvoices, purchaseInvoices},
    ).get();

    final List<Map<String, dynamic>> results = [];

    // Process sales
    for (final row in salesResults) {
      final total = (row.data['total'] as num?)?.toDouble() ?? 0;
      final jeId = row.data['je_id'] as int?;
      final jeDebit = (row.data['je_debit_total'] as num?)?.toDouble() ?? 0;
      final jeCredit = (row.data['je_credit_total'] as num?)?.toDouble() ?? 0;
      final isPosted = row.data['is_posted'];
      final siStatus = row.data['si_status'] as String?;

      String status;
      String statusCode;
      if (jeId == null) {
        status = 'لم يتم الترحيل';
        statusCode = 'missing';
      } else if (isPosted == 0 || isPosted == false) {
        status = 'مسودة (غير مرحل)';
        statusCode = 'draft';
      } else if ((jeDebit - total).abs() > 0.01 && (jeCredit - total).abs() > 0.01) {
        status = 'فرق في القيمة';
        statusCode = 'mismatch';
      } else {
        status = 'مطابق ✓';
        statusCode = 'matched';
      }

      results.add({
        'source': siStatus == 'returned' ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
        'sourceType': 'sale',
        'invoiceId': row.data['id'],
        'invoiceNumber': row.data['invoice_number'] ?? '-',
        'invoiceDate': row.data['invoice_date'],
        'invoiceTotal': total,
        'jeId': jeId,
        'jeNumber': row.data['entry_number'],
        'jeDebit': jeDebit,
        'jeCredit': jeCredit,
        'status': status,
        'statusCode': statusCode,
      });
    }

    // Process purchases
    for (final row in purchaseResults) {
      final total = (row.data['total'] as num?)?.toDouble() ?? 0;
      final jeId = row.data['je_id'] as int?;
      final jeDebit = (row.data['je_debit_total'] as num?)?.toDouble() ?? 0;
      final jeCredit = (row.data['je_credit_total'] as num?)?.toDouble() ?? 0;
      final isPosted = row.data['is_posted'];

      String status;
      String statusCode;
      if (jeId == null) {
        status = 'لم يتم الترحيل';
        statusCode = 'missing';
      } else if (isPosted == 0 || isPosted == false) {
        status = 'مسودة (غير مرحل)';
        statusCode = 'draft';
      } else if ((jeDebit - total).abs() > 0.01 && (jeCredit - total).abs() > 0.01) {
        status = 'فرق في القيمة';
        statusCode = 'mismatch';
      } else {
        status = 'مطابق ✓';
        statusCode = 'matched';
      }

      results.add({
        'source': 'فاتورة مشتريات',
        'sourceType': 'purchase',
        'invoiceId': row.data['id'],
        'invoiceNumber': row.data['invoice_number'] ?? '-',
        'invoiceDate': row.data['invoice_date'],
        'invoiceTotal': total,
        'jeId': jeId,
        'jeNumber': row.data['entry_number'],
        'jeDebit': jeDebit,
        'jeCredit': jeCredit,
        'status': status,
        'statusCode': statusCode,
      });
    }

    // Process orphans
    for (final row in orphanResults) {
      results.add({
        'source': 'قيد يتيم',
        'sourceType': 'orphan',
        'invoiceId': row.data['reference_id'],
        'invoiceNumber': '-',
        'invoiceDate': row.data['entry_date'],
        'invoiceTotal': 0.0,
        'jeId': row.data['je_id'],
        'jeNumber': row.data['entry_number'],
        'jeDebit': (row.data['je_debit_total'] as num?)?.toDouble() ?? 0,
        'jeCredit': (row.data['je_credit_total'] as num?)?.toDouble() ?? 0,
        'status': 'قيد بدون فاتورة',
        'statusCode': 'orphan',
      });
    }

    return results;
  }

  /// PIR P1-01: Get VAT reconciliation data for a given month/year.
  /// Extracted from vat_reconciliation_screen to remove direct DB access from UI.
  Future<VatReconciliationResult> getVatReconciliationData({
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    // أعمدةُ DateTime مخزَّنةٌ بالثواني (‏[dateVar]) — الملّي كان يخرج المدى
    // كلَّه عن نطاق البيانات فلا يقع فيه صفٌّ واحد. وحين يصير الطرفان صفراً
    // يصير الفرقُ صفراً فتُرسَم الشاشةُ خضراء «مطابق» — براءةٌ كاذبة.
    final startVar = dateVar(start);
    final endVar = dateVar(end);

    // 1. Invoice-level tax totals
    final salesRow = await customSelect('''
      SELECT COALESCE(SUM(tax), 0) as total_tax
      FROM sales_invoices
      WHERE invoice_date >= ? AND invoice_date < ?
        AND is_deleted = 0
        AND status NOT IN ('returned', 'cancelled')
    ''', variables: [startVar, endVar],
        readsFrom: {salesInvoices}).getSingle();

    final purchaseRow = await customSelect('''
      SELECT COALESCE(SUM(tax), 0) as total_tax
      FROM purchase_invoices
      WHERE invoice_date >= ? AND invoice_date < ?
        AND is_deleted = 0
    ''', variables: [startVar, endVar],
        readsFrom: {purchaseInvoices}).getSingle();

    final invoiceOutputVat = (salesRow.data['total_tax'] as num).toDouble();
    final invoiceInputVat = (purchaseRow.data['total_tax'] as num).toDouble();

    // 2. GL account balances
    double glOutputVat = 0;
    double glInputVat = 0;
    String outputVatAccCode = '2121';
    String inputVatAccCode = '1141';

    try {
      outputVatAccCode = await getMappedAccountCode(
        'output_vat', AccountingDao.accountPurposes['output_vat']!,
      );
      inputVatAccCode = await getMappedAccountCode(
        'input_vat', AccountingDao.accountPurposes['input_vat']!,
      );

      final outputAcc = await getAccountByCode(outputVatAccCode);
      final inputAcc = await getAccountByCode(inputVatAccCode);

      if (outputAcc != null) {
        final rows = await customSelect('''
          SELECT COALESCE(SUM(jel.credit - jel.debit), 0) as balance
          FROM journal_entry_lines jel
          JOIN journal_entries je ON je.id = jel.entry_id
          WHERE jel.account_id = ?
            AND je.entry_date >= ? AND je.entry_date < ?
            AND je.is_deleted = 0 AND je.is_posted = 1
        ''', variables: [Variable(outputAcc.id), startVar, endVar],
            readsFrom: {journalEntryLines, journalEntries}).getSingle();
        glOutputVat = (rows.data['balance'] as num).toDouble();
      }

      if (inputAcc != null) {
        final rows = await customSelect('''
          SELECT COALESCE(SUM(jel.debit - jel.credit), 0) as balance
          FROM journal_entry_lines jel
          JOIN journal_entries je ON je.id = jel.entry_id
          WHERE jel.account_id = ?
            AND je.entry_date >= ? AND je.entry_date < ?
            AND je.is_deleted = 0 AND je.is_posted = 1
        ''', variables: [Variable(inputAcc.id), startVar, endVar],
            readsFrom: {journalEntryLines, journalEntries}).getSingle();
        glInputVat = (rows.data['balance'] as num).toDouble();
      }
    } catch (_) {
      // GL data unavailable — return invoice data only
    }

    return VatReconciliationResult(
      invoiceOutputVat: invoiceOutputVat,
      invoiceInputVat: invoiceInputVat,
      glOutputVat: glOutputVat,
      glInputVat: glInputVat,
      outputVatAccCode: outputVatAccCode,
      inputVatAccCode: inputVatAccCode,
    );
  }

  /// PHASE-11 (AC1): Validate that the trial balance is balanced
  /// Returns a map with isBalanced flag, totalDebit, totalCredit, and difference.
  /// Can be called automatically after each sync or on-demand.
  Future<Map<String, dynamic>> validateTrialBalance() async {
    final now = DateTime.now();
    final from = DateTime(now.year - 5); // All history
    final result = await getTrialBalance(from, now);
    
    // Last row is totals
    if (result.isEmpty) {
      return {'isBalanced': true, 'totalDebit': 0.0, 'totalCredit': 0.0, 'difference': 0.0};
    }
    
    final totals = result.last;
    final closingDebit = (totals['closingDebit'] as num?)?.toDouble() ?? 0.0;
    final closingCredit = (totals['closingCredit'] as num?)?.toDouble() ?? 0.0;
    final diff = (closingDebit - closingCredit).abs();
    
    if (diff > 0.01) {
      // Day-18: Gate trial-balance mismatch warning behind kDebugMode so it
      // does not pollute release-build console output or crash-log uploads.
      if (kDebugMode) {
        debugPrint('╔══════════════════════════════════════════════════════════════╗');
        debugPrint('║  ⚠️  تحذير: ميزان المراجعة غير متوازن!                       ║');
        debugPrint('║  مدين: $closingDebit | دائن: $closingCredit | فرق: $diff     ║');
        debugPrint('╚══════════════════════════════════════════════════════════════╝');
      }
    }
    
    return {
      'isBalanced': diff <= 0.01,
      'totalDebit': closingDebit,
      'totalCredit': closingCredit,
      'difference': diff,
    };
  }

  /// م-2 (Spec 153) — READ-ONLY reconciliation of the perpetual inventory value
  /// against GL account 1136. Posts nothing and changes no WAC semantics
  /// (products.costPrice stays the SoT); it only surfaces the gap and the two
  /// documented drift sources so an operator can see WHY the inventory report
  /// and the ledger disagree. Mirrors the getArReconciliation() pattern
  /// (party_dao). Returns null if the inventory account is unmapped/missing.
  Future<InventoryGlReconciliation?> getInventoryGlReconciliation() async {
    final invCode = await accountingDao.getMappedAccountCode(
      'inventory', AccountingDao.accountPurposes['inventory']!,
    );
    final invAccount = await accountingDao.getAccountByCode(invCode);
    if (invAccount == null) return null;

    // رصيد المخزون الرقابي = Σ(مدين − دائن) على حسابات المخزون **التلاتة**
    // (خامات ١١٣١ + تحت التشغيل ١١٣٣ + مخزون ١١٣٦).
    //
    // كان بيقارن التقييم بـ١١٣٦ **وحده**، والتقييم بيجمع كل الأصناف
    // المتعقَّبة بغض النظر عن نوعها. مع توجيه الشراء بنوع الصنف (قرار
    // المالك 2026-08-02) الخامات بقت على ١١٣١ والإنتاج الجاري على ١١٣٣،
    // فمقارنة بـ١١٣٦ وحده كانت هترجّع فرق بقيمتهم.
    //
    // الفلتر posted/deleted جوه الـjoin (زي getPartyBalanceMismatches):
    // join تانوي أو LEFT كان هيسرّب سطور قيود محذوفة في الـSUM.
    final controlIds = <int>[];
    for (final purpose in kInventoryControlPurposes) {
      final acc = await accountingDao.getAccountByPurpose(purpose);
      if (acc != null) controlIds.add(acc.id);
    }
    if (controlIds.isEmpty) controlIds.add(invAccount.id);
    final glRow = await customSelect(
      '''
      SELECT COALESCE(SUM(jel.debit) - SUM(jel.credit), 0.0) AS gl_balance
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je
        ON je.id = jel.entry_id AND je.is_posted = 1 AND je.is_deleted = 0
      WHERE jel.account_id IN (${List.filled(controlIds.length, '?').join(',')})
      ''',
      variables: controlIds.map((id) => Variable<int>(id)).toList(),
      readsFrom: {journalEntryLines, journalEntries},
    ).getSingle();
    final glBalance = (glRow.data['gl_balance'] as num?)?.toDouble() ?? 0.0;

    // GL-comparable perpetual value = Σ currentStock × costPrice over
    // inventory-TRACKED products. Services (track_inventory = 0) never post to
    // 1136, so their residual stock value would be phantom drift and is excluded.
    // Deactivated products ARE included: deactivation posts no reversal, so their
    // stock value is still carried in GL 1136.
    final reportRow = await customSelect(
      'SELECT COALESCE(SUM(current_stock * cost_price), 0.0) AS v '
      'FROM products WHERE track_inventory = 1',
      readsFrom: {products},
    ).getSingle();
    final reportValue = (reportRow.data['v'] as num?)?.toDouble() ?? 0.0;

    // Per-warehouse perpetual ledger, valued two ways to isolate the cost-basis
    // divergence: the true per-warehouse average_cost vs the global costPrice
    // that GL was actually posted at on each sale.
    final perpRow = await customSelect(
      '''
      SELECT
        COALESCE(SUM(ib.quantity * p.cost_price), 0.0)    AS at_cost_price,
        COALESCE(SUM(ib.quantity * ib.average_cost), 0.0) AS at_avg_cost
      FROM inventory_balances ib
      JOIN products p ON p.id = ib.product_id
      WHERE p.track_inventory = 1
      ''',
      readsFrom: {inventoryBalances, products},
    ).getSingle();
    final atCostPrice = (perpRow.data['at_cost_price'] as num?)?.toDouble() ?? 0.0;
    final atAvgCost = (perpRow.data['at_avg_cost'] as num?)?.toDouble() ?? 0.0;

    // Drift source 2: inventory-tracked stock on hand carrying a zero cost —
    // CANDIDATE zero_cost_policy=warn moves that skipped the COGS/inventory JE
    // (also legitimately-free items: samples/promo). Informational: contributes 0
    // to the value above but real quantity, so ledger and GL can diverge on it.
    final zeroRow = await customSelect(
      '''
      SELECT COUNT(*) AS cnt, COALESCE(SUM(current_stock), 0.0) AS qty
      FROM products
      WHERE track_inventory = 1 AND cost_price = 0 AND current_stock > 0
      ''',
      readsFrom: {products},
    ).getSingle();
    final zeroCount = (zeroRow.data['cnt'] as num?)?.toInt() ?? 0;
    final zeroQty = (zeroRow.data['qty'] as num?)?.toDouble() ?? 0.0;

    return InventoryGlReconciliation(
      glBalance: glBalance,
      reportValue: reportValue,
      perpetualBalancesAtCostPrice: atCostPrice,
      perpetualBalancesAtAvgCost: atAvgCost,
      delta: reportValue - glBalance,
      costBasisDivergence: atAvgCost - atCostPrice,
      stockVsLedgerDivergence: reportValue - atCostPrice,
      zeroCostItemCount: zeroCount,
      zeroCostStockQty: zeroQty,
      inventoryAccountCode: invCode,
      inventoryAccountName: invAccount.name,
    );
  }
}

/// م-2 (Spec 153) — result of getInventoryGlReconciliation. A point-in-time
/// snapshot; nothing is posted. `isBalanced` uses the same 0.01 tolerance as
/// the other sub-ledger reconciliations (AR, VAT).
class InventoryGlReconciliation {
  final double glBalance; // Σ(debit − credit) on posted, non-deleted 1136 lines
  final double reportValue; // Σ currentStock × costPrice over inventory-tracked products
  final double perpetualBalancesAtCostPrice; // Σ inventory_balances.qty × costPrice (tracked)
  final double perpetualBalancesAtAvgCost; // Σ inventory_balances.qty × average_cost (tracked)
  final double delta; // reportValue − glBalance (the reconciliation gap)
  final double costBasisDivergence; // avgCost perpetual − costPrice perpetual (drift 1)
  final double stockVsLedgerDivergence; // reportValue − perpetualBalancesAtCostPrice:
  // products.currentStock vs Σ inventory_balances.quantity, at costPrice (drift 3)
  final int zeroCostItemCount; // tracked products with on-hand stock but costPrice = 0 (drift 2)
  final double zeroCostStockQty;
  final String inventoryAccountCode;
  final String inventoryAccountName;

  const InventoryGlReconciliation({
    required this.glBalance,
    required this.reportValue,
    required this.perpetualBalancesAtCostPrice,
    required this.perpetualBalancesAtAvgCost,
    required this.delta,
    required this.costBasisDivergence,
    required this.stockVsLedgerDivergence,
    required this.zeroCostItemCount,
    required this.zeroCostStockQty,
    required this.inventoryAccountCode,
    required this.inventoryAccountName,
  });

  bool get isBalanced => delta.abs() < 0.01;
}

/// PIR P1-01: Result model for VAT reconciliation data.
/// Moved out of vat_reconciliation_screen to allow provider-based access.
class VatReconciliationResult {
  final double invoiceOutputVat;
  final double invoiceInputVat;
  final double glOutputVat;
  final double glInputVat;
  final String outputVatAccCode;
  final String inputVatAccCode;

  const VatReconciliationResult({
    required this.invoiceOutputVat,
    required this.invoiceInputVat,
    required this.glOutputVat,
    required this.glInputVat,
    required this.outputVatAccCode,
    required this.inputVatAccCode,
  });
}
