import '../../repositories/reporting_repository.dart';
import '../../../domain/models/report_scope_filter.dart';

/// Use case: Generate a report for a date range.
///
/// Supports sales, purchases, treasury, and inventory report types.
/// All methods accept an optional [ReportScopeFilter] to restrict
/// data to a specific branch/warehouse/cost-center scope.
class GenerateReportUseCase {
  final IReportingRepository _repo;

  const GenerateReportUseCase(this._repo);

  /// Generates a sales analytics report.
  ///
  /// B11 REP-1 (spec 149): the returned [SalesAnalytics.totalNetProfit] /
  /// [SalesAnalytics.totalProfit] is a sales-level figure (revenue −
  /// discount − COGS − tax). It never touches the GL and structurally
  /// omits operating expenses/salaries/depreciation, so callers must NOT
  /// present it as the company's "صافي الربح" (net profit). The
  /// GL-sourced true net profit is `AccountingReportsDao.getIncomeStatement`
  /// (via `IReportingRepository.getIncomeStatement`) — no callers of this
  /// use case exist today, but keep this contract in mind if one is added.
  Future<dynamic> generateSalesReport(
    DateTime start,
    DateTime end, {
    ReportScopeFilter? scope,
  }) async {
    _validateDateRange(start, end);
    return _repo.getSalesAnalytics(
      start, end,
      costCenterId: scope?.costCenterId,
      warehouseIds: scope?.warehouseIds,
    );
  }

  /// Generates a purchases analytics report.
  Future<dynamic> generatePurchasesReport(
    DateTime start,
    DateTime end, {
    ReportScopeFilter? scope,
  }) async {
    _validateDateRange(start, end);
    return _repo.getPurchasesReportAnalytics(
      start, end,
      costCenterId: scope?.costCenterId,
      warehouseIds: scope?.warehouseIds,
    );
  }

  /// Generates a treasury analytics report.
  Future<dynamic> generateTreasuryReport(
    DateTime start,
    DateTime end, {
    ReportScopeFilter? scope,
  }) async {
    _validateDateRange(start, end);
    return _repo.getTreasuryReportAnalytics(
      start, end,
      costCenterId: scope?.costCenterId,
      safeIds: scope?.safeIds,
    );
  }

  /// Generates an inventory analytics report (snapshot, no date range).
  Future<dynamic> generateInventoryReport() {
    return _repo.getInventoryReportAnalytics();
  }

  void _validateDateRange(DateTime start, DateTime end) {
    if (end.isBefore(start)) {
      throw ArgumentError('تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
    }
  }
}
