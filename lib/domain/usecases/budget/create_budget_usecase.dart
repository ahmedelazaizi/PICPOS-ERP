import '../../repositories/budget_repository.dart';

/// Use case: Create a new budget with period validation.
///
/// Validates that amount > 0 and fiscal year is provided,
/// then delegates to the budget repository.
class CreateBudgetUseCase {
  final IBudgetRepository _repo;

  const CreateBudgetUseCase(this._repo);

  /// Creates a budget for the given fiscal year and account.
  Future<int> execute({
    required int fiscalYearId,
    required int accountId,
    required double annualAmount,
    int? costCenterId,
    String? name,
    String distributionMethod = 'equal',
  }) async {
    if (annualAmount <= 0) {
      throw ArgumentError('مبلغ الموازنة يجب أن يكون أكبر من صفر');
    }
    if (fiscalYearId <= 0) {
      throw ArgumentError('السنة المالية غير صحيحة');
    }
    if (accountId <= 0) {
      throw ArgumentError('الحساب غير صحيح');
    }

    return _repo.createBudget(
      fiscalYearId: fiscalYearId,
      accountId: accountId,
      annualAmount: annualAmount,
      costCenterId: costCenterId,
      name: name,
      distributionMethod: distributionMethod,
    );
  }

  /// Checks if a transaction would exceed the budget allocation.
  /// Returns a warning message if overrun detected, null otherwise.
  Future<String?> checkOverrun({
    required int accountId,
    required double amount,
    int? costCenterId,
  }) {
    return _repo.checkBudgetOverrun(
      accountId: accountId,
      amount: amount,
      costCenterId: costCenterId,
    );
  }
}
