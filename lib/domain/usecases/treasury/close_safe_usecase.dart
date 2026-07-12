import '../../repositories/treasury_repository.dart';

/// Use case: Close a treasury safe for the day.
///
/// Validates that the safe exists, calculates the expected vs actual balance,
/// and creates a closing record.
class CloseSafeUseCase {
  final ITreasuryRepository _repo;

  const CloseSafeUseCase(this._repo);

  /// Closes the specified safe.
  ///
  /// Returns a [SafeClosingResult] with the reconciliation outcome.
  Future<SafeClosingResult> execute({
    required int safeId,
    required double actualBalance,
    String? notes,
  }) async {
    final safe = await _repo.getSafeById(safeId);
    if (safe == null) {
      throw StateError('الخزينة غير موجودة');
    }

    final expectedBalance = safe.balance;
    final difference = actualBalance - expectedBalance;

    await _repo.closeSafe(safeId);

    return SafeClosingResult(
      safeId: safeId,
      expectedBalance: expectedBalance,
      actualBalance: actualBalance,
      difference: difference,
      isBalanced: difference.abs() < 0.01,
    );
  }
}

/// Result of a safe closing operation.
class SafeClosingResult {
  final int safeId;
  final double expectedBalance;
  final double actualBalance;
  final double difference;
  final bool isBalanced;

  const SafeClosingResult({
    required this.safeId,
    required this.expectedBalance,
    required this.actualBalance,
    required this.difference,
    required this.isBalanced,
  });
}
