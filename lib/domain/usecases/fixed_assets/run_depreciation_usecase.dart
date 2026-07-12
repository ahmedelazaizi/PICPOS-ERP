import '../../../data/database/database.dart';

/// Result of depreciation run
class DepreciationResult {
  final bool isSuccess;
  final int assetsProcessed;
  final String? error;

  DepreciationResult.success({required this.assetsProcessed})
      : isSuccess = true,
        error = null;

  DepreciationResult.failure(this.error)
      : isSuccess = false,
        assetsProcessed = 0;
}

/// Use case: Run monthly depreciation for all active assets
class RunDepreciationUseCase {
  final AppDatabase _db;

  RunDepreciationUseCase(this._db);

  /// Execute monthly depreciation with journal entries
  /// Returns the number of assets processed
  Future<DepreciationResult> execute(DateTime periodDate, {int? costCenterId}) async {
    try {
      final count = await _db.runMonthlyDepreciation(periodDate, costCenterId: costCenterId);
      return DepreciationResult.success(assetsProcessed: count);
    } catch (e) {
      return DepreciationResult.failure(e.toString());
    }
  }
}
