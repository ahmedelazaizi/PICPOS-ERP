/// Domain entity representing a product category.
class CategoryEntity {
  final int id;
  final String name;
  final String? description;
  final String color;
  final int? parentId;
  final int sortOrder;
  final int? printerId;
  final String? iconName;
  final bool isActive;

  const CategoryEntity({
    required this.id,
    required this.name,
    this.description,
    this.color = '#2563EB',
    this.parentId,
    this.sortOrder = 0,
    this.printerId,
    this.iconName,
    this.isActive = true,
  });

  bool get isRoot => parentId == null;

  CategoryEntity copyWith({
    int? id,
    String? name,
    String? description,
    String? color,
    int? parentId,
    int? sortOrder,
    int? printerId,
    String? iconName,
    bool? isActive,
  }) =>
      CategoryEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        color: color ?? this.color,
        parentId: parentId ?? this.parentId,
        sortOrder: sortOrder ?? this.sortOrder,
        printerId: printerId ?? this.printerId,
        iconName: iconName ?? this.iconName,
        isActive: isActive ?? this.isActive,
      );
}
