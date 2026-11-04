import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/accounting_picpos/income_statement_export_rows.dart';

void main() {
  test('income statement export includes cost, depreciation and non-sales lines', () {
    final rows = incomeStatementExportRows(
      {
        'revenueDetails': [{'name': 'Sales', 'amount': 80}],
        'salesReturns': 5,
        'outputVatNet': 11,
        'cogsDetails': [{'name': 'COGS', 'amount': 20}],
        'totalCOGS': 20,
        'expenseDetails': [{'name': 'Rent', 'amount': 3}],
        'depreciationDetails': [{'name': 'Depreciation', 'amount': 2}],
        'totalDepreciation': 2,
        'otherIncomeDetails': [{'name': 'Gain', 'amount': 1}],
        'otherExpenseDetails': [{'name': 'Loss', 'amount': 1}],
        'netProfit': 61,
      },
      label: (key) => key,
    );

    final exportedValues = rows.expand((row) => row).toList();
    expect(exportedValues, containsAll([
      'Sales', 'مردودات المبيعات', 'ضريبة المخرجات (صافية)', 'COGS',
      'إجمالي تكلفة البضاعة المباعة', 'Rent', 'Depreciation', 'إجمالي الإهلاك',
      'Gain', 'Loss', 'صافي الربح',
    ]));
  });
}
