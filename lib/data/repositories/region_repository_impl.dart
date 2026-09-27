import '../database/database.dart';
import '../database/sync_interceptor.dart';
import '../../domain/repositories/region_repository.dart';
import '../../services/client_write_interceptor.dart';

class RegionRepositoryImpl implements RegionRepository {
  final AppDatabase _db;

  RegionRepositoryImpl(this._db);

  @override
  Stream<List<RegionData>> watchRegions() {
    return _db.watchRegions().map(
      (rows) => rows.map(_toData).toList(),
    );
  }

  @override
  Future<List<RegionData>> getRegions() async {
    final rows = await _db.getRegions();
    return rows.map(_toData).toList();
  }

  @override
  Future<RegionData?> getRegionById(int id) async {
    final row = await _db.getRegionById(id);
    return row != null ? _toData(row) : null;
  }

  @override
  Future<int> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) {
    return _db.createRegion(
      name: name,
      address: address,
      phone: phone,
      costCenterId: costCenterId,
    );
  }

  @override
  Future<bool> updateRegion(RegionData region) {
    return _db.updateRegion(
      Region(
        id: region.id,
        name: region.name,
        address: region.address,
        phone: region.phone,
        costCenterId: region.costCenterId,
        isActive: region.isActive,
        globalId: region.globalId,
        rowVersion: 0,
      ),
    );
  }

  @override
  Future<void> deactivateRegion(int id) {
    return _db.deactivateRegion(id);
  }

  @override
  Stream<List<Branche>> watchBranchesByRegion(int regionId) {
    return _db.watchBranchesByRegion(regionId);
  }

  @override
  Future<List<Branche>> getBranchesByRegion(int regionId) {
    return _db.getBranchesByRegion(regionId);
  }

  @override
  Future<List<int>> getWarehouseIdsForRegion(int regionId) {
    return _db.getWarehouseIdsForRegion(regionId);
  }

  @override
  Future<void> setUserRegionAccess(int userId, List<int> regionIds) async {
    // F3 (MM.E): mirror/client mode hits POST /api/user-region-access so HQ
    // owns the access table. Standalone/server mode keeps writing to the
    // local DAO directly.
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.setUserRegionAccess(userId, regionIds);
      return;
    }
    await _db.setUserRegionAccess(userId, regionIds);
  }

  @override
  Future<List<int>> getUserAccessibleRegionIds(int userId) {
    return _db.getUserAccessibleRegionIds(userId);
  }

  RegionData _toData(Region r) => RegionData(
    id: r.id,
    name: r.name,
    address: r.address,
    phone: r.phone,
    costCenterId: r.costCenterId,
    isActive: r.isActive,
    globalId: r.globalId,
  );
}
