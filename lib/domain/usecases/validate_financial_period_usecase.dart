import '../../services/accounting_service.dart';

/// PIR Phase 2 — UseCase: Validate Financial Period
///
/// Ensures that financial operations can only occur within
/// an open fiscal period. This UseCase is reused by all
/// financial operations (sales, purchases, journal entries).
class ValidateFinancialPeriodUseCase {
  final AccountingService _accountingService;

  ValidateFinancialPeriodUseCase(this._accountingService);

  /// Throws if the given date falls within a closed period.
  Future<void> execute(DateTime date) async {
    await _accountingService.ensureOpenFiscalPeriod(date);
  }

  /// Check without throwing — returns true if period is open.
  Future<bool> isPeriodOpen(DateTime date) async {
    try {
      await _accountingService.ensureOpenFiscalPeriod(date);
      return true;
    } catch (_) {
      return false;
    }
  }
}
