typedef StatementExportLabel = String Function(String key);

List<List<dynamic>> incomeStatementExportRows(
  Map<String, dynamic> data, {
  required StatementExportLabel label,
}) {
  final rows = <List<dynamic>>[];

  void addDetails(String key, String type) {
    final details = (data[key] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    for (final item in details) {
      rows.add([label(type), item['name'], item['amount']]);
    }
  }

  addDetails('revenueDetails', 'إيراد');
  final returns = (data['salesReturns'] as num?)?.toDouble() ?? 0;
  if (returns != 0) rows.add([label('مردودات المبيعات'), '', returns]);
  final outputVat = (data['outputVatNet'] as num?)?.toDouble() ?? 0;
  if (outputVat != 0) rows.add([label('ضريبة المخرجات (صافية)'), '', outputVat]);

  addDetails('cogsDetails', 'تكلفة');
  rows.add([
    label('إجمالي تكلفة البضاعة المباعة'),
    '',
    data['totalCOGS'] ?? 0,
  ]);
  addDetails('expenseDetails', 'مصروف');
  addDetails('depreciationDetails', 'إهلاك');
  rows.add([
    label('إجمالي الإهلاك'),
    '',
    data['totalDepreciation'] ?? 0,
  ]);
  addDetails('otherIncomeDetails', 'إيراد آخر');
  addDetails('otherExpenseDetails', 'مصروف آخر');
  rows.add(['', label('صافي الربح'), data['netProfit']]);
  return rows;
}
