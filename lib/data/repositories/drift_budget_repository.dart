import 'package:drift/drift.dart' show Value;
import '../../domain/repositories/budget_repository.dart';
import '../database/database.dart';

class DriftBudgetRepository implements IBudgetRepository {
  final AppDatabase _db;

  DriftBudgetRepository(this._db);

  @override
  Future<int> createBudget({
    required int fiscalYearId,
    required int accountId,
    required double annualAmount,
    int? costCenterId,
    String? name,
    String distributionMethod = 'equal',
  }) {
    return _db.createBudget(
      fiscalYearId: fiscalYearId,
      accountId: accountId,
      annualAmount: annualAmount,
      costCenterId: costCenterId,
      name: name,
      distributionMethod: distributionMethod,
    );
  }

  @override
  Future<List<BudgetData>> getBudgetsForYear(int fiscalYearId) {
    return _db.getBudgetsForYear(fiscalYearId);
  }

  @override
  Future<List<BudgetLineData>> getBudgetLines(int budgetId) {
    return _db.getBudgetLines(budgetId);
  }

  @override
  Future<void> updateBudgetActuals(int budgetId) {
    return _db.updateBudgetActuals(budgetId);
  }

  @override
  Future<List<Map<String, dynamic>>> getBudgetVsActualReport(int fiscalYearId) {
    return _db.getBudgetVsActualReport(fiscalYearId);
  }

  @override
  Future<String?> checkBudgetOverrun({
    required int accountId,
    required double amount,
    int? costCenterId,
    DateTime? date,
  }) {
    return _db.checkBudgetOverrun(
      accountId: accountId,
      amount: amount,
      costCenterId: costCenterId,
      date: date,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> cashFlowForecast({int monthsAhead = 6}) {
    return _db.cashFlowForecast(monthsAhead: monthsAhead);
  }

  @override
  Future<void> updateBudgetLines({
    required int budgetId,
    required List<BudgetLineData> lines,
    required double annualAmount,
  }) {
    return _db.transaction(() async {
      for (var line in lines) {
        await (_db.update(_db.budgetLines)..where((l) => l.id.equals(line.id))).write(
          BudgetLinesCompanion(
            plannedAmount: Value(line.plannedAmount),
            actualAmount: Value(line.actualAmount),
            variance: Value(line.actualAmount - line.plannedAmount),
          ),
        );
      }

      await (_db.update(_db.budgets)..where((b) => b.id.equals(budgetId))).write(
        BudgetsCompanion(
          annualAmount: Value(annualAmount),
          distributionMethod: const Value('manual'),
        ),
      );
    });
  }
}
