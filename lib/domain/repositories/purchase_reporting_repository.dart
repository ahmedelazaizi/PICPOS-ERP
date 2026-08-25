import '../../data/database/database.dart';

/// Purchase-specific reporting interface
abstract class IPurchaseReportingRepository {
  Future<PurchasesAnalytics> getPurchasesReportAnalytics(
    DateTime from,
    DateTime to, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  });

  Future<List<PurchaseInvoiceWithSupplier>> getPurchasesWithSupplierByDateRange(
    DateTime start,
    DateTime end, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  });

  Future<List<Map<String, dynamic>>> getPurchasesBySupplier({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  });

  /// تجميعُ مشترياتِ الفترة لكلّ مورّد — «تحليل سلوك الموردين».
  Future<List<PartyPeriodAggregateRow>> getSupplierPeriodAggregates({
    DateTime? from,
    DateTime? to,
    int limit,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  });
}
