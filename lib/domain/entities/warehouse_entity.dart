/// Domain entity representing a storage warehouse.
class WarehouseEntity {
  final int id;
  final String name;
  final String? location;
  final int? branchId;
  final bool isDefault;
  final bool isActive;

  const WarehouseEntity({
    required this.id,
    required this.name,
    this.location,
    this.branchId,
    this.isDefault = false,
    this.isActive = true,
  });

  WarehouseEntity copyWith({
    int? id,
    String? name,
    String? location,
    int? branchId,
    bool? isDefault,
    bool? isActive,
  }) =>
      WarehouseEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        location: location ?? this.location,
        branchId: branchId ?? this.branchId,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
      );
}
