import '../../data/database/database.dart';

/// Treasury-specific reporting interface
abstract class ITreasuryReportingRepository {
  Future<TreasuryAnalytics> getTreasuryReportAnalytics(
    DateTime start,
    DateTime end, {
    /// H12 · نفسُ فلتر [getTransactionsByDateRange] تحتها بالضبط — بدونه
    /// تتحرّك صفوفُ الجدول وتبقى البطاقاتُ على إجمالي كلّ المستخدمين.
    int? userId,
    int? costCenterId,
    int? safeId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<SafeTransactionData>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    int? costCenterId,
    int? safeId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  });

  Future<List<UserTreasurySummary>> getPerUserTreasurySummary(
    DateTime from,
    DateTime to, {
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  });

  // Financial statements
  Future<List<Map<String, dynamic>>> getTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
  Future<Map<String, dynamic>> getIncomeStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
  Future<Map<String, dynamic>> getBalanceSheet(DateTime atDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
}
