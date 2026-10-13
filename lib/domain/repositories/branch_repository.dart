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

  /// المخازنُ التي يجوز لهذا **الجهاز** أن يُصدر عليها مستنداً (Spec 103).
  ///
  /// على جهاز عميلٍ مربوطٍ بفرع تُحصَر بمخازن فرعه؛ وفيما عدا ذلك هي
  /// [getWarehouses] نفسُها. الجزءُ غيرُ الخالص — `isClientMode` وقراءةُ
  /// `client_branch_id` — يعيش هنا لا في العرض، على نمط [getActiveBranch].
  ///
  /// **ليست بديلاً عامّاً عن [getWarehouses]:** شاشاتُ البيانات الأساسيّة
  /// (تخصيصُ مخزنٍ لصنف، الإعدادات) ومسارُ **تحرير** فاتورةٍ قائمة تحتاج
  /// القائمةَ كاملةً — والثاني خطِرٌ بخاصّة: لو خرج مخزنُ الفاتورة من القائمة
  /// أعاد المحرِّرُ توجيهَها إلى أوّل مخزنٍ صامتاً.
  Future<List<db.Warehouse>> getScopedWarehouses();

  Future<Map<int, double>> getWarehouseStockMap(int warehouseId);
  Future<Map<int, double>> getWarehouseStockMapForWarehouses(
      List<int> warehouseIds);

  /// Get cost center ID for the active branch
  Future<int?> getActiveBranchCostCenterId(int branchId);

  /// Get all active branches
  Future<List<db.Branche>> getActiveBranches();
}
