/// Domain entity representing an application user.
class UserEntity {
  final int id;
  final String username;
  final String displayName;
  final int? roleId;
  final String? roleName;
  final bool isActive;
  final bool isLocked;
  final double? maxDiscountPercent;
  final bool discountLimitIsPercent;
  final String? cardCode;
  final String? defaultScreen;
  final List<String> permissions;

  const UserEntity({
    required this.id,
    required this.username,
    required this.displayName,
    this.roleId,
    this.roleName,
    this.isActive = true,
    this.isLocked = false,
    this.maxDiscountPercent,
    this.discountLimitIsPercent = true,
    this.cardCode,
    this.defaultScreen,
    this.permissions = const [],
  });

  bool get isAdmin => roleName?.toLowerCase() == 'admin' ||
      roleName?.toLowerCase() == 'مدير النظام';

  bool hasPermission(String code) => isAdmin || permissions.contains(code);

  UserEntity copyWith({
    int? id,
    String? username,
    String? displayName,
    int? roleId,
    String? roleName,
    bool? isActive,
    bool? isLocked,
    double? maxDiscountPercent,
    bool? discountLimitIsPercent,
    String? cardCode,
    String? defaultScreen,
    List<String>? permissions,
  }) =>
      UserEntity(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        roleId: roleId ?? this.roleId,
        roleName: roleName ?? this.roleName,
        isActive: isActive ?? this.isActive,
        isLocked: isLocked ?? this.isLocked,
        maxDiscountPercent: maxDiscountPercent ?? this.maxDiscountPercent,
        discountLimitIsPercent:
            discountLimitIsPercent ?? this.discountLimitIsPercent,
        cardCode: cardCode ?? this.cardCode,
        defaultScreen: defaultScreen ?? this.defaultScreen,
        permissions: permissions ?? this.permissions,
      );
}
