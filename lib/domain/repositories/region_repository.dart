import '../../data/database/database.dart' show Branche;

abstract class RegionRepository {
  Stream<List<RegionData>> watchRegions();
  Future<List<RegionData>> getRegions();
  Future<RegionData?> getRegionById(int id);
  Future<int> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  });
  Future<bool> updateRegion(RegionData region);
  Future<void> deactivateRegion(int id);
  Stream<List<Branche>> watchBranchesByRegion(int regionId);
  Future<List<Branche>> getBranchesByRegion(int regionId);
  Future<List<int>> getWarehouseIdsForRegion(int regionId);
  Future<void> setUserRegionAccess(int userId, List<int> regionIds);
  Future<List<int>> getUserAccessibleRegionIds(int userId);
}

class RegionData {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final int? costCenterId;
  final bool isActive;
  final String? globalId;

  const RegionData({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.costCenterId,
    required this.isActive,
    this.globalId,
  });

  RegionData copyWith({
    String? name,
    String? address,
    String? phone,
    int? costCenterId,
    bool? isActive,
  }) {
    return RegionData(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      costCenterId: costCenterId ?? this.costCenterId,
      isActive: isActive ?? this.isActive,
      globalId: globalId,
    );
  }
}
