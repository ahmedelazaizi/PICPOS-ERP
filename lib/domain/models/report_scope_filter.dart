/// Unified filter contract for all reporting queries.
///
/// Screens build this object from user selections (BranchWarehouseFilterBar,
/// date picker, cost-center dropdown, etc.) and pass it down through the
/// repository layer so that every query is scoped consistently.
class ReportScopeFilter {
  final DateTime from;
  final DateTime to;
  final int? branchId;
  final List<int>? warehouseIds;
  final List<int>? safeIds;
  final int? costCenterId;
  final int? userId;
  final int? safeId;

  const ReportScopeFilter({
    required this.from,
    required this.to,
    this.branchId,
    this.warehouseIds,
    this.safeIds,
    this.costCenterId,
    this.userId,
    this.safeId,
  });

  /// Convenience: true when at least one spatial filter is set.
  bool get hasScopeFilter =>
      branchId != null ||
      (warehouseIds != null && warehouseIds!.isNotEmpty) ||
      (safeIds != null && safeIds!.isNotEmpty) ||
      costCenterId != null;
}
