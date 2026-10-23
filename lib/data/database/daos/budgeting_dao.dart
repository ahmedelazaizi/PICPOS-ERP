part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BUDGETING DAO — الموازنات والتنبؤ المالي
// ═══════════════════════════════════════════════════════════════════════════

extension BudgetingDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // BUDGET CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a new budget with auto-distributed monthly lines
  Future<int> createBudget({
    required int fiscalYearId,
    required int accountId,
    required double annualAmount,
    int? costCenterId,
    String? name,
    String distributionMethod = 'equal',
  }) async {
    return transaction(() async {
      final budgetId = await into(budgets).insert(
        BudgetsCompanion.insert(
          fiscalYearId: fiscalYearId,
          accountId: accountId,
          costCenterId: Value(costCenterId),
          name: Value(name),
          annualAmount: Value(annualAmount),
          distributionMethod: Value(distributionMethod),
        ),
      );

      // Auto-generate 12 monthly lines
      final monthlyAmount = annualAmount / 12;
      for (int m = 1; m <= 12; m++) {
        await into(budgetLines).insert(
          BudgetLinesCompanion.insert(
            budgetId: budgetId,
            month: m,
            plannedAmount: Value(monthlyAmount),
          ),
        );
      }

      return budgetId;
    });
  }

  /// Get all budgets for a fiscal year
  Future<List<BudgetData>> getBudgetsForYear(int fiscalYearId) {
    return (select(budgets)
          ..where((b) => b.fiscalYearId.equals(fiscalYearId))
          ..orderBy([(b) => OrderingTerm.asc(b.accountId)]))
        .get();
  }

  /// Get budget lines for a budget
  Future<List<BudgetLineData>> getBudgetLines(int budgetId) {
    return (select(budgetLines)
          ..where((l) => l.budgetId.equals(budgetId))
          ..orderBy([(l) => OrderingTerm.asc(l.month)]))
        .get();
  }

  /// Update actual amounts from GL data
  Future<void> updateBudgetActuals(int budgetId) async {
    final budget = await (select(budgets)
          ..where((b) => b.id.equals(budgetId)))
        .getSingle();
    final fy = await (select(fiscalYears)
          ..where((f) => f.id.equals(budget.fiscalYearId)))
        .getSingle();

    for (int month = 1; month <= 12; month++) {
      final startDate = DateTime(fy.startDate.year, month, 1);
      final endDate = DateTime(fy.startDate.year, month + 1, 0, 23, 59, 59);

      // Query actual from GL
      String query = '''
        SELECT COALESCE(SUM(l.debit - l.credit), 0) as actual
        FROM journal_entry_lines l
        JOIN journal_entries e ON l.entry_id = e.id
        WHERE l.account_id = ? AND e.entry_date BETWEEN ? AND ?
          AND e.is_posted = ${sqlBool(true)} AND e.is_deleted = ${sqlBool(false)}
      ''';
      final variables = <Variable>[
        Variable(budget.accountId),
        dateVar(startDate),
        dateVar(endDate),
      ];

      if (budget.costCenterId != null) {
        query += ' AND e.cost_center_id = ?';
        variables.add(Variable(budget.costCenterId));
      }

      final result = await customSelect(query, variables: variables).getSingle();
      final actualAmount = (result.data['actual'] as num?)?.toDouble() ?? 0;

      // Get planned amount for variance calculation
      final lineResult = await (select(budgetLines)
            ..where((l) => l.budgetId.equals(budgetId) & l.month.equals(month)))
          .getSingleOrNull();

      final planned = lineResult?.plannedAmount ?? 0;

      await (update(budgetLines)
            ..where((l) => l.budgetId.equals(budgetId) & l.month.equals(month)))
          .write(BudgetLinesCompanion(
        actualAmount: Value(actualAmount),
        variance: Value(actualAmount - planned),
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUDGET VS ACTUAL REPORT
  // ─────────────────────────────────────────────────────────────────────────

  /// Get budget vs actual comparison for a fiscal year
  Future<List<Map<String, dynamic>>> getBudgetVsActualReport(int fiscalYearId) async {
    final yearBudgets = await getBudgetsForYear(fiscalYearId);
    final report = <Map<String, dynamic>>[];

    for (final budget in yearBudgets) {
      final lines = await getBudgetLines(budget.id);
      final account = await (select(accounts)
            ..where((a) => a.id.equals(budget.accountId)))
          .getSingleOrNull();

      double totalPlanned = 0;
      double totalActual = 0;
      for (final line in lines) {
        totalPlanned += line.plannedAmount;
        totalActual += line.actualAmount;
      }

      report.add({
        'budgetId': budget.id,
        'accountId': budget.accountId,
        'accountName': account?.name ?? '',
        'accountCode': account?.code ?? '',
        'annualBudget': budget.annualAmount,
        'totalPlanned': totalPlanned,
        'totalActual': totalActual,
        'variance': totalActual - totalPlanned,
        'utilizationPct': totalPlanned > 0 ? (totalActual / totalPlanned * 100) : 0,
        'lines': lines,
      });
    }

    return report;
  }

  /// Check if an expense would exceed budget — returns alert if so
  Future<String?> checkBudgetOverrun({
    required int accountId,
    required double amount,
    int? costCenterId,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    final month = now.month;

    // Find applicable budget
    final query = select(budgets)
      ..where((b) => b.accountId.equals(accountId));

    final applicableBudgets = await query.get();
    if (applicableBudgets.isEmpty) return null;

    for (final budget in applicableBudgets) {
      if (costCenterId != null && budget.costCenterId != costCenterId) continue;

      final line = await (select(budgetLines)
            ..where((l) => l.budgetId.equals(budget.id) & l.month.equals(month)))
          .getSingleOrNull();
      if (line == null) continue;

      final projectedTotal = line.actualAmount + amount;
      if (projectedTotal > line.plannedAmount) {
        final overrun = projectedTotal - line.plannedAmount;
        return '⚠️ تجاوز الموازنة: المبلغ المتوقع ($projectedTotal) يتجاوز المخطط (${line.plannedAmount}) بمقدار $overrun';
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CASH FLOW FORECAST — توقعات التدفق النقدي
  // ─────────────────────────────────────────────────────────────────────────

  /// Simple cash flow forecast based on historical patterns
  Future<List<Map<String, dynamic>>> cashFlowForecast({int monthsAhead = 6}) async {
    final forecast = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (int i = 1; i <= monthsAhead; i++) {
      final targetMonth = DateTime(now.year, now.month + i, 1);
      // Use same month last year as baseline
      final lastYearStart = DateTime(now.year - 1, now.month + i, 1);
      final lastYearEnd = DateTime(now.year - 1, now.month + i + 1, 0, 23, 59, 59);

      final inflows = await customSelect(
        '''SELECT COALESCE(SUM(CASE WHEN sale_type = 'return' THEN -total ELSE total END), 0) as amount FROM sales_invoices
           WHERE invoice_date BETWEEN ? AND ? AND is_deleted = ${sqlBool(false)}
             AND status NOT IN ('cancelled', 'voided')''',
        variables: [dateVar(lastYearStart), dateVar(lastYearEnd)],
      ).getSingle();

      final outflows = await customSelect(
        '''SELECT COALESCE(SUM(total), 0) as amount FROM purchase_invoices
           WHERE invoice_date BETWEEN ? AND ? AND is_deleted = ${sqlBool(false)}
             AND status NOT IN ('cancelled', 'voided', 'returned')''',
        variables: [dateVar(lastYearStart), dateVar(lastYearEnd)],
      ).getSingle();

      forecast.add({
        'month': '${targetMonth.year}-${targetMonth.month.toString().padLeft(2, '0')}',
        'projectedInflows': (inflows.data['amount'] as num?)?.toDouble() ?? 0,
        'projectedOutflows': (outflows.data['amount'] as num?)?.toDouble() ?? 0,
        'projectedNet': ((inflows.data['amount'] as num?)?.toDouble() ?? 0) -
            ((outflows.data['amount'] as num?)?.toDouble() ?? 0),
        'basis': 'Historical (same month previous year)',
      });
    }

    return forecast;
  }
}
