import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database.dart';
import '../database/sync_interceptor.dart';
import '../../domain/models/warehouse_branch_scope.dart';
import '../../domain/repositories/branch_repository.dart';
import '../../services/client_write_interceptor.dart';
import '../../services/network_service.dart';

class BranchRepositoryImpl implements IBranchRepository {
  final AppDatabase _db;

  BranchRepositoryImpl(this._db);

  @override
  Stream<List<Branche>> watchAllBranches() => _db.watchBranches();

  @override
  Future<List<Branche>> getAllBranches() => _db.getBranches();

  @override
  Future<List<Branche>> getBranches() => _db.getBranches();

  @override
  Future<Branche?> getBranchById(int id) => _db.getBranchById(id);

  @override
  Future<Branche?> getActiveBranch() async {
    // In client mode, honour the branch assigned to this device in Settings.
    if (SyncInterceptor.isClientMode) {
      final prefs = await SharedPreferences.getInstance();
      final clientBranchId = prefs.getInt('client_branch_id');
      if (clientBranchId != null) {
        final branch = await (_db.select(_db.branches)
              ..where((t) =>
                  t.id.equals(clientBranchId) & t.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();
        if (branch != null) return branch;
      }
    }
    // Standalone / server mode — single-branch: return first active branch.
    final list = await (_db.select(_db.branches)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .get();
    return list.firstOrNull;
  }

  @override
  Future<int> insertBranch(BranchesCompanion branch) => _db.insertBranch(branch);

  @override
  Future<bool> updateBranch(Branche branch) async {
    // Intercepted modes (client + mirror) push the change to the server
    // first; the local DB row catches up via the next DeltaPull instead
    // of being mutated locally. Without this route, mirror-mode admins
    // would update only their own SQLite copy and never reach HQ.
    if (SyncInterceptor.isClientMode) {
      return ClientWriteInterceptor.updateBranch(branch.id, {
        'name': branch.name,
        'code': branch.code,
        'address': branch.address,
        'phone': branch.phone,
        'costCenterId': branch.costCenterId,
        'regionId': branch.regionId,
        'isActive': branch.isActive,
      });
    }
    return _db.updateBranch(branch);
  }

  @override
  Future<void> deleteBranch(int id, {int? reassignUsersToBranchId}) async {
    if (SyncInterceptor.isClientMode) {
      // Mirror mode — route through the interceptor so the server runs
      // the same soft-delete + reassign. The interceptor accepts the
      // reassign id verbatim; null means "no reassign" which the server
      // surfaces as the same Arabic FK-prevention error the DAO uses.
      await ClientWriteInterceptor.deleteBranch(
        id,
        reassignUsersToBranchId: reassignUsersToBranchId,
      );
      return;
    }
    await _db.deleteBranch(id,
        reassignUsersToBranchId: reassignUsersToBranchId);
  }

  @override
  Future<int> countUsersWithBranchAccess(int id) {
    return _db.countUsersWithBranchAccess(id);
  }

  @override
  Future<int> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
  }) async {
    if (SyncInterceptor.isClientMode) {
      // Mirror/client path. Returns the server's row id when reachable;
      // falls back to 0 when the write was queued offline (client mode)
      // or threw MirrorOfflineException (mirror mode — caller surfaces).
      final id = await ClientWriteInterceptor.createBranch(
        name: name,
        code: code,
        address: address,
        phone: phone,
        costCenterId: costCenterId,
        regionId: regionId,
      );
      return id ?? 0;
    }
    return _db.createBranch(
      name: name,
      code: code,
      address: address,
      phone: phone,
      costCenterId: costCenterId,
      regionId: regionId,
    );
  }

  @override
  Future<BranchSalesSummary> getBranchSalesSummary(int branchId, {DateTime? from, DateTime? to}) =>
      _db.getBranchSalesSummary(branchId, from: from, to: to);

  @override
  Future<double> getBranchInventoryValue(int branchId) => _db.getBranchInventoryValue(branchId);

  @override
  Stream<List<Warehouse>> watchAllWarehouses() => _db.select(_db.warehouses).watch();

  @override
  Future<List<Warehouse>> getWarehousesByBranch(int branchId) => _db.getWarehousesByBranch(branchId);

  @override
  Future<int> insertWarehouse(WarehousesCompanion warehouse) =>
      _db.into(_db.warehouses).insert(warehouse);

  @override
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
    bool isDefault = false,
  }) =>
      _db.createWarehouseForBranch(
        name: name,
        branchId: branchId,
        isDefault: isDefault,
      );

  @override
  Future<bool> updateWarehouse(Warehouse warehouse) => _db.update(_db.warehouses).replace(warehouse);

  @override
  Future<void> deleteWarehouse(int id) => (_db.delete(_db.warehouses)..where((w) => w.id.equals(id))).go();

  @override
  Future<int?> getWarehouseIdByName(String name) async {
    if (name.isEmpty) return null;
    final list = await (_db.select(_db.warehouses)..where((w) => w.name.equals(name))..limit(1)).get();
    return list.firstOrNull?.id;
  }

  @override
  Future<Warehouse?> getWarehouseById(int id) async {
    return (_db.select(_db.warehouses)..where((w) => w.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<int>> getUserAccessibleBranchIds(int userId) =>
      // Delegate to the DAO so the same role-based bypass logic is used
      // everywhere. The previous in-repo implementation used
      // `role.isSystemRole == true` as the "full access" trigger — but
      // `isSystemRole` is set to true on every seeded role (cashier,
      // accountant, system manager, financial manager, …) to mark them
      // as system-defined / undeletable. Treating that flag as
      // "unrestricted access" silently bypassed the user_branch_access
      // table for every cashier and was the root cause of the user-
      // management dialog re-opening empty after save: the DAO write
      // landed correctly, but the read path hit the bypass and returned
      // []. The DAO version already uses the correct bypass — only
      // role.name == "مدير النظام" or "مدير مالي" (or userId == 1)
      // grants unrestricted access — and merges in region-grant
      // inheritance, so the answer matches branchScopeProvider too.
      _db.getUserAccessibleBranchIds(userId);

  @override
  Future<List<int>> getUserAccessibleWarehouseIds(int userId) =>
      _db.getUserAccessibleWarehouseIds(userId);

  @override
  Future<void> setDefaultWarehouse(int warehouseId) async {
    // Per-branch: only reset defaults within the same branch
    final warehouse = await (_db.select(_db.warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
    if (warehouse == null) return;
    await (_db.update(_db.warehouses)..where((w) => w.branchId.equalsNullable(warehouse.branchId)))
        .write(const WarehousesCompanion(isDefault: Value(false)));
    await (_db.update(_db.warehouses)..where((w) => w.id.equals(warehouseId)))
        .write(const WarehousesCompanion(isDefault: Value(true)));
  }

  @override
  Future<void> unsetDefaultWarehouse(int warehouseId) async {
    await (_db.update(_db.warehouses)..where((w) => w.id.equals(warehouseId)))
        .write(const WarehousesCompanion(isDefault: Value(false)));
  }

  @override
  Future<void> setUserBranchAccess(int userId, List<int> branchIds) async {
    // F3 (MM.E): mirror/client mode routes through PUT /api/users/{id}
    // with `branchIds` so HQ persists the change before the local DeltaPull
    // can overwrite it. Standalone/server mode keeps writing to the DAO,
    // which wraps DELETE+INSERT in a single transaction (the previous raw
    // customStatement impl bypassed Drift's markTablesUpdated and made
    // saves visibly "lose" the selection on dialog reopen).
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateUser(userId, {
        'branchIds': branchIds,
      });
      return;
    }
    await _db.setUserBranchAccess(userId, branchIds);
  }

  @override
  Future<void> setUserWarehouseAccess(int userId, List<int> warehouseIds) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateUser(userId, {
        'warehouseIds': warehouseIds,
      });
      return;
    }
    await _db.setUserWarehouseAccess(userId, warehouseIds);
  }

  @override
  Future<List<Warehouse>> getWarehouses() => _db.select(_db.warehouses).get();

  @override
  Future<List<Warehouse>> getScopedWarehouses() async {
    final all = await getWarehouses();
    if (!SyncInterceptor.isClientMode) return all;
    final prefs = await SharedPreferences.getInstance();
    return narrowWarehousesToClientBranch<Warehouse>(
      warehouses: all,
      clientBranchId: prefs.getInt('client_branch_id'),
      branchIdOf: (w) => w.branchId,
    );
  }

  @override
  Future<Map<int, double>> getWarehouseStockMap(int warehouseId) => _db.getWarehouseStockMap(warehouseId);

  @override
  Future<int?> getActiveBranchCostCenterId(int branchId) async {
    final branch = await _db.getBranchById(branchId);
    return branch?.costCenterId;
  }

  @override
  Future<List<Branche>> getActiveBranches() =>
      (_db.select(_db.branches)..where((b) => b.isActive.equals(true))).get();
}
