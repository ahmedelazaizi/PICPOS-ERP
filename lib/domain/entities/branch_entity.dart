/// Domain entity representing a business branch location.
class BranchEntity {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final bool isMain;
  final bool isActive;

  const BranchEntity({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.isMain = false,
    this.isActive = true,
  });

  BranchEntity copyWith({
    int? id,
    String? name,
    String? address,
    String? phone,
    bool? isMain,
    bool? isActive,
  }) =>
      BranchEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        isMain: isMain ?? this.isMain,
        isActive: isActive ?? this.isActive,
      );
}
