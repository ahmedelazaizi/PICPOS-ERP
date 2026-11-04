part of '../database.dart';

typedef _OperatingCashRowQuery = ({
  DateTime from,
  DateTime to,
  String cashBankFilter,
  Set<int> cashBankIds,
  String boolTrue,
  String ccFilter,
  String brFilter,
  String azFilter,
  List<Variable> ccVars,
  List<Variable> brVars,
  List<Variable> azVars,
});

typedef _SalesInvoiceDiscountQuery = ({
  DateTime from,
  DateTime to,
  int? costCenterId,
  int? branchId,
  Set<int>? allowedBranchIds,
  List<int>? warehouseIds,
});

extension AccountingReportAdjustments on AppDatabase {
  String _knownOperatingRefTypes() => sqlRefTypeList({
        'cash_sale', 'credit_sale', 'sale', 'sales_invoice', 'sale_return',
        'sales_return', 'purchase', 'purchase_invoice', 'purchase_return',
        'salary', 'payroll', 'salary_payment', 'payroll_run', 'op_expense',
        'expense', 'operational_expense', 'receipt', 'payment',
        'receipt_voucher', 'payment_voucher', 'commercial_paper',
      });

  String _investingRefTypes() => sqlRefTypeList(kInvestingJeReferenceTypes);
  String _financingRefTypes() => sqlRefTypeList(kFinancingJeReferenceTypes);
  String _nonOperatingRefTypes() => sqlRefTypeList(
        {...kInvestingJeReferenceTypes, ...kFinancingJeReferenceTypes},
      );

  // Depreciation posting currently targets 6213. Honor an explicit purpose
  // mapping first, then the posted-account code, and retain 5207 for legacy
  // databases. This is report-only: the amount remains an expense once.
  Future<String> _resolveDepreciationReportCode() async {
    final mappedCode = await accountingDao.getMappedAccountCode(
      'depreciation_expense', '6213',
    );
    return (await accountingDao.getAccountByCode(mappedCode))?.code ??
        (await accountingDao.getAccountByCode('6213'))?.code ??
        (await accountingDao.getAccountByCode('5207'))?.code ??
        mappedCode;
  }

  Future<List<QueryRow>> _selectKnownOperatingCashRows(
    _OperatingCashRowQuery query,
  ) {
    return customSelect(
      '''
      SELECT je.id AS entry_id, je.reference_type,
             SUM(jel.debit) AS total_debit,
             SUM(jel.credit) AS total_credit,
             CASE WHEN EXISTS (
               SELECT 1 FROM journal_entry_lines counter_line
               INNER JOIN accounts counter_account ON counter_account.id = counter_line.account_id
               WHERE counter_line.entry_id = je.id
                 AND counter_line.account_id NOT IN (${query.cashBankIds.isEmpty ? '-1' : query.cashBankIds.join(', ')})
                 AND counter_account.code LIKE '2131%'
             ) THEN 1 ELSE 0 END AS salary_counter
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE ${query.cashBankFilter}
        AND je.entry_date BETWEEN ? AND ? AND je.is_posted = ${query.boolTrue}
        AND je.is_deleted = ${sqlBool(false)} ${query.ccFilter} ${query.brFilter}${query.azFilter}
        AND je.reference_type IN (${_knownOperatingRefTypes()})
      GROUP BY je.id, je.reference_type
      ''',
      variables: [
        dateVar(query.from),
        dateVar(query.to),
        ...query.ccVars,
        ...query.brVars,
        ...query.azVars,
      ],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).get();
  }

  Future<double> _sumSalesInvoiceDiscounts(
    _SalesInvoiceDiscountQuery query,
  ) async {
    final salesBranch = _buildBranchFilter(query.branchId, tableAlias: 'si');
    final salesAuth = AccountingReportsDao(this)
        ._buildAuthScopeFilter(query.allowedBranchIds, tableAlias: 'si');
    var costCenterFilter = '';
    var warehouseFilter = '';
    final variables = <Variable>[dateVar(query.from), dateVar(query.to)];
    if (query.costCenterId != null) {
      final ids = await AccountingReportsDao(this)
          ._resolveCostCenterIds(query.costCenterId!);
      if (ids.isEmpty) {
        costCenterFilter = ' AND 1 = 0';
      } else {
        costCenterFilter =
            ' AND si.cost_center_id IN (${ids.map((_) => '?').join(', ')})';
        variables.addAll(ids.map((id) => Variable<int>(id)));
      }
    }
    if (query.warehouseIds != null) {
      if (query.warehouseIds!.isEmpty) {
        warehouseFilter = ' AND 1 = 0';
      } else {
        warehouseFilter =
            ' AND si.warehouse_id IN (${query.warehouseIds!.map((_) => '?').join(', ')})';
        variables.addAll(query.warehouseIds!.map((id) => Variable<int>(id)));
      }
    }
    variables.addAll(salesBranch.vars);
    variables.addAll(salesAuth.vars);
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(si.discount), 0) AS total
      FROM sales_invoices si
      WHERE si.invoice_date BETWEEN ? AND ? AND si.is_deleted = ${sqlBool(false)}
        $costCenterFilter $warehouseFilter
        ${salesBranch.filter.replaceAll('e.', 'si.')}
        ${salesAuth.filter.replaceAll('e.', 'si.')}
      ''',
      variables: variables,
      readsFrom: {salesInvoices},
    ).getSingle();
    return (result.data['total'] as num?)?.toDouble() ?? 0.0;
  }
}
