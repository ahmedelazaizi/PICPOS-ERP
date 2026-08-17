import '../../data/database/database.dart' as db;

abstract class IBranchRepository {
  Stream<List<db.Branche>> watchAllBranches();
  Future<List<db.Branche>> getAllBranches();
  Future<List<db.Branche>> getBranches();
  Future<db.Branche?> getBranchById(int id);
  Future<db.Branche?> getActiveBranch();
  Future<int> insertBranch(db.BranchesCompanion branch);
  Future<bool> updateBranch(db.Branche branch);
  /// Feature 049 (v131) — soft-delete a branch.
  /// [reassignUsersToBranchId]: when supplied, every `user_branch_access`
  /// row pointing at the deleted branch is moved to that destination
  /// inside the same transaction. Null = no reassign (DAO throws if any
  /// user is still assigned). Mirrors the Feature 045 categories pattern.
  Future<void> deleteBranch(int id, {int? reassignUsersToBranchId});

  /// Feature 049 — pre-flight count of user_branch_access rows referencing
  /// [id]. The delete-branch UI uses this to decide between empty-confirm
  /// and bulk-reassign flows.
  Future<int> countUsersWithBranchAccess(int id);
  Future<int> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
  });

  // Statistics
  Future<db.BranchSalesSummary> getBranchSalesSummary(int branchId, {DateTime? from, DateTime? to});
  Future<double> getBranchInventoryValue(int branchId);

  // Warehouses
  Stream<List<db.Warehouse>> watchAllWarehouses();
  Future<List<db.Warehouse>> getWarehousesByBranch(int branchId);
  Future<int> insertWarehouse(db.WarehousesCompanion warehouse);
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
    bool isDefault = false,
  });
  Future<bool> updateWarehouse(db.Warehouse warehouse);
  Future<void> deleteWarehouse(int id);
  Future<int?> getWarehouseIdByName(String name);
  Future<db.Warehouse?> getWarehouseById(int id);

  // User Access
  Future<List<int>> getUserAccessibleBranchIds(int userId);
  Future<List<int>> getUserAccessibleWarehouseIds(int userId);

  // Settings
  Future<void> setDefaultWarehouse(int warehouseId);
  Future<void> unsetDefaultWarehouse(int warehouseId);

  // Access Control
  Future<void> setUserBranchAccess(int userId, List<int> branchIds);
  Future<void> setUserWarehouseAccess(int userId, List<int> warehouseIds);
  Future<List<db.Warehouse>> getWarehouses();

  /// معرّفُ الفرعِ الذي تُنسَب إليه المستنداتُ الجديدةُ على هذا الجهاز،
  /// أو `null` = بلا حصر (خادم/مستقلّ، أو عميلٌ لم يُقترن بفرعٍ بعد).
  ///
  /// نطاقُ **نسبةٍ** لا رؤية — انظر `branch_assignment_scope.dart`.
  Future<int?> getAssignmentBranchId();

  /// المخازنُ التي يجوز نسبةُ مستندٍ جديدٍ إليها على هذا الجهاز:
  /// [getWarehouses] مقصورةً بـ[getAssignmentBranchId] وفق
  /// `restrictForAssignment` (مساواةٌ صارمة + احتياطُ عدمِ التفريغ).
  ///
  /// هي المصدرُ الوحيدُ لهذا القصّ — كان منسوخاً في ستِّ شاشات. ومَن أراد
  /// مخازنَ فرعٍ **بعينه** (كإعداداتِ فرعٍ في شاشةِ إدارة) فليستعمل
  /// [getWarehousesByBranch]: صارمٌ بلا احتياط، لأن «لا مخزنَ لهذا الفرع»
  /// جوابٌ صحيحٌ هناك لا تعطيلٌ للعمل.
  Future<List<db.Warehouse>> getAssignableWarehouses();

  Future<Map<int, double>> getWarehouseStockMap(int warehouseId);

  /// Get cost center ID for the active branch
  Future<int?> getActiveBranchCostCenterId(int branchId);

  /// Get all active branches
  Future<List<db.Branche>> getActiveBranches();
}
