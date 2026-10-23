import '../../../data/database/database.dart';

/// Result of depreciation run
class DepreciationResult {
  final bool isSuccess;
  final int assetsProcessed;
  final String? error;

  /// Per-asset posting failures (audit B ACC-002) — assets that did NOT advance.
  final List<String> failures;

  DepreciationResult.success({required this.assetsProcessed, this.failures = const []})
      : isSuccess = true,
        error = null;

  DepreciationResult.failure(this.error)
      : isSuccess = false,
        failures = const [],
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
      final failures = <String>[];
      final count = await _db.runMonthlyDepreciation(periodDate, costCenterId: costCenterId, failures: failures);
      return DepreciationResult.success(assetsProcessed: count, failures: failures);
    } catch (e) {
      return DepreciationResult.failure(e.toString());
    }
  }
}
