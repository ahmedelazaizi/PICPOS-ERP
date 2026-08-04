/// ClientScope — defines the operational scope for a client device.
///
/// When the app runs in CLIENT mode, this model determines which
/// branch/warehouses/safes/costCenters the device is allowed to operate on.
/// The server resolves this scope from the client's assigned branch.
class ClientScope {
  final int branchId;
  final String branchName;
  final List<int> allowedWarehouseIds;
  final List<int> allowedSafeIds;
  final List<int> allowedCostCenterIds;

  const ClientScope({
    required this.branchId,
    required this.branchName,
    required this.allowedWarehouseIds,
    required this.allowedSafeIds,
    required this.allowedCostCenterIds,
  });

  /// Whether a given warehouse is within scope
  bool isWarehouseAllowed(int warehouseId) =>
      allowedWarehouseIds.contains(warehouseId);

  /// Whether a given safe is within scope
  bool isSafeAllowed(int safeId) => allowedSafeIds.contains(safeId);

  /// Whether a given cost center is within scope
  bool isCostCenterAllowed(int costCenterId) =>
      allowedCostCenterIds.contains(costCenterId);

  /// An unrestricted scope (used when running as server or standalone)
  static const unrestricted = _UnrestrictedScope();

  /// نطاق مقفول — جهاز عميل من غير `client_branch_id` مضبوط.
  ///
  /// كان بيرجّع [unrestricted] في الحالة دي، يعني جهاز **ناقص التنصيب**
  /// بياخد وصول كامل. ده نفس نمط الفشل اللي اتقفل في مسار المزامنة (G2)
  /// بسنتينل `-1`؛ والقاعدة واحدة: نقص الهوية يفشل **مقفولاً** لا مفتوحاً.
  static const closed = _ClosedScope();

  @override
  String toString() =>
      'ClientScope(branch=$branchId, warehouses=$allowedWarehouseIds, safes=$allowedSafeIds, costCenters=$allowedCostCenterIds)';
}

/// Sentinel class representing no scope restriction (server mode)
class _UnrestrictedScope implements ClientScope {
  const _UnrestrictedScope();

  @override
  int get branchId => -1;
  @override
  String get branchName => 'الكل';
  @override
  List<int> get allowedWarehouseIds => const [];
  @override
  List<int> get allowedSafeIds => const [];
  @override
  List<int> get allowedCostCenterIds => const [];

  @override
  bool isWarehouseAllowed(int warehouseId) => true; // Unrestricted
  @override
  bool isSafeAllowed(int safeId) => true; // Unrestricted
  @override
  bool isCostCenterAllowed(int costCenterId) => true; // Unrestricted

  @override
  String toString() => 'ClientScope.unrestricted';
}

/// Sentinel class representing a fully CLOSED scope — nothing is allowed.
class _ClosedScope implements ClientScope {
  const _ClosedScope();

  @override
  int get branchId => -1;
  @override
  String get branchName => 'بلا فرع';
  @override
  List<int> get allowedWarehouseIds => const [];
  @override
  List<int> get allowedSafeIds => const [];
  @override
  List<int> get allowedCostCenterIds => const [];

  @override
  bool isWarehouseAllowed(int warehouseId) => false;
  @override
  bool isSafeAllowed(int safeId) => false;
  @override
  bool isCostCenterAllowed(int costCenterId) => false;

  @override
  String toString() => 'ClientScope.closed';
}
