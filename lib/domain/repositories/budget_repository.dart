import '../../data/database/database.dart';

abstract class IBudgetRepository {
  Future<int> createBudget({
    required int fiscalYearId,
    required int accountId,
    required double annualAmount,
    int? costCenterId,
    String? name,
    String distributionMethod = 'equal',
  });

  Future<List<BudgetData>> getBudgetsForYear(int fiscalYearId);

  Future<List<BudgetLineData>> getBudgetLines(int budgetId);

  Future<void> updateBudgetActuals(int budgetId);

  Future<List<Map<String, dynamic>>> getBudgetVsActualReport(int fiscalYearId);

  Future<String?> checkBudgetOverrun({
    required int accountId,
    required double amount,
    int? costCenterId,
    DateTime? date,
  });

  Future<List<Map<String, dynamic>>> cashFlowForecast({int monthsAhead = 6});

  Future<void> updateBudgetLines({
    required int budgetId,
    required List<BudgetLineData> lines,
    required double annualAmount,
  });
}
