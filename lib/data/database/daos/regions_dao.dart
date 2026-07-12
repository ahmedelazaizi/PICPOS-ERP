part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REGIONS DAO - Multi-Region Management (middle tier: admin → region → branch)
// ═══════════════════════════════════════════════════════════════════════════

extension RegionsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // REGIONS CRUD
  // ═══════════════════════════════════════════════════════════════════════

  Stream<List<Region>> watchRegions() {
    return (select(regions)
          ..where((r) => r.isActive.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.name)]))
        .watch();
  }

  Future<List<Region>> getRegions() {
    return (select(regions)
          ..where((r) => r.isActive.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.name)]))
        .get();
  }

  Future<Region?> getRegionById(int id) {
    return (select(regions)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  Future<int> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) {
    return into(regions).insert(
      RegionsCompanion.insert(
        name: name,
        address: Value(address),
        phone: Value(phone),
        costCenterId: Value(costCenterId),
        // UUID-First (Phase 1): upgraded to UUID v7 (time-ordered).
        globalId: Value(UuidV7.generate()),
      ),
    );
  }

  Future<bool> updateRegion(Region region) {
    return update(regions).replace(region);
  }

  /// Deactivate a region. Cluster 027: wrap the precondition check + the
  /// update in a single transaction so concurrent writers (e.g. a sync
  /// push that just inserted a branch into this region) can't slip
  /// between them and leave us with a deactivated region pointing at
  /// an active branch. Also explicitly check active warehouses — the
  /// previous version only checked branches and would silently orphan
  /// region-scoped warehouses.
  Future<void> deactivateRegion(int id) async {
    await transaction(() async {
      final activeBranches = await (select(branches)
            ..where((b) => b.regionId.equals(id) & b.isActive.equals(true)))
          .get();
      if (activeBranches.isNotEmpty) {
        throw Exception(
          'لا يمكن تعطيل المنطقة: يوجد ${activeBranches.length} فرع نشط مرتبط بها',
        );
      }
      final activeWarehouses = await (select(warehouses)
            ..where((w) => w.regionId.equals(id) & w.isActive.equals(true)))
          .get();
      if (activeWarehouses.isNotEmpty) {
        throw Exception(
          'لا يمكن تعطيل المنطقة: يوجد ${activeWarehouses.length} مخزن نشط مرتبط بها',
        );
      }
      await (update(regions)..where((r) => r.id.equals(id))).write(
        const RegionsCompanion(isActive: Value(false)),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REGION ↔ BRANCH / WAREHOUSE QUERIES
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<Branche>> getBranchesByRegion(int regionId) {
    return (select(branches)
          ..where(
            (b) => b.regionId.equals(regionId) & b.isActive.equals(true),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .get();
  }

  Stream<List<Branche>> watchBranchesByRegion(int regionId) {
    return (select(branches)
          ..where(
            (b) => b.regionId.equals(regionId) & b.isActive.equals(true),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .watch();
  }

  /// All warehouse IDs for a region: direct region warehouses + all branch warehouses
  Future<List<int>> getWarehouseIdsForRegion(int regionId) async {
    final directWhs = await (select(warehouses)
          ..where((w) => w.regionId.equals(regionId) & w.isActive.equals(true)))
        .get();
    final regionBranches = await getBranchesByRegion(regionId);
    final branchIds = regionBranches.map((b) => b.id).toList();
    final branchWhs = branchIds.isNotEmpty
        ? await (select(warehouses)
              ..where(
                (w) => w.branchId.isIn(branchIds) & w.isActive.equals(true),
              ))
            .get()
        : <Warehouse>[];
    return {
      ...directWhs.map((w) => w.id),
      ...branchWhs.map((w) => w.id),
    }.toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // USER REGION ACCESS CONTROL
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> setUserRegionAccess(int userId, List<int> regionIds) async {
    await (delete(userRegionAccess)..where((a) => a.userId.equals(userId))).go();
    for (final rId in regionIds) {
      await into(userRegionAccess).insertOnConflictUpdate(
        UserRegionAccessCompanion.insert(userId: userId, regionId: rId),
      );
    }
  }

  Future<List<int>> getUserAccessibleRegionIds(int userId) async {
    final rows = await (select(userRegionAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    return rows.map((r) => r.regionId).toList();
  }

  /// Branch IDs accessible via region grants — merged into getUserAccessibleBranchIds()
  Future<List<int>> getBranchIdsForUserRegionAccess(int userId) async {
    final regionIds = await getUserAccessibleRegionIds(userId);
    if (regionIds.isEmpty) return [];
    final branchRows = await (select(branches)
          ..where(
            (b) => b.regionId.isIn(regionIds) & b.isActive.equals(true),
          ))
        .get();
    return branchRows.map((b) => b.id).toList();
  }
}
