import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/providers.dart';

/// Use case that calculates a cash flow forecast extending X months ahead.
/// Extracts logic from the _buildCashFlowForecast method in budget_screen.dart.
class CashFlowForecastUseCase {
  final Ref ref;

  CashFlowForecastUseCase(this.ref);

  /// Get forecast extending [monthsAhead]
  Future<List<Map<String, dynamic>>> execute({int monthsAhead = 6}) async {
    final repo = ref.read(budgetRepositoryProvider);
    try {
      return await repo.cashFlowForecast(monthsAhead: monthsAhead);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}

final cashFlowForecastUseCaseProvider = Provider((ref) {
  return CashFlowForecastUseCase(ref);
});
