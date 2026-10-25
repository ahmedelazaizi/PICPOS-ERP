import '../../data/database/database.dart';

/// The main system accepted the credential but demands a NEW password first
/// (HTTP 403 `password_change_required`). Carries no secret: the caller already
/// holds the credential the user typed. [viaCard]: the proof was a card code.
class PasswordChangeRequired implements Exception {
  const PasswordChangeRequired({this.userId, required this.username, this.viaCard = false});
  final int? userId;
  final String username;
  final bool viaCard;
  @override
  String toString() => 'PasswordChangeRequired(user=$username)';
}

/// A sign-in refused for a reason the OPERATOR must read (branch, lock-out,
/// revoked device, "not delivered by the main", expired grace...). A StateError
/// so existing handlers keep working; screens show [message] as written.
class AuthRejectedException extends StateError {
  AuthRejectedException(super.message);
}

/// Authentication and User Management Repository Interface
abstract class IAuthRepository {
  // Users
  Stream<List<UserWithRole>> watchAllUsers();
  Future<UserWithRole?> getUserById(int id);
  Future<UserWithRole?> getUserByUsername(String username);
  Future<int> createUser({
    int? id,
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent,
    String? cardCode,
    String? defaultScreen,
    bool forcePasswordChange = false,
    // UUID-First (Phase 1): optional client-supplied UUID v7 so the same
    // row identity lands on client and server after sync.
    String? globalId,
  });
  Future<void> updateUserInfo({
    required int userId,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent,
    String? cardCode,
    String? defaultScreen,
    bool? forcePasswordChange,
    // Issue 7 (Feature 018): optional rename — null leaves it unchanged.
    String? username,
  });
  Future<void> updateUserPassword({
    required int userId,
    required String newPassword,
  });
  Future<void> toggleUserActive({
    required int userId,
    required bool isActive,
  });
  Future<void> assignRoleToUser(int userId, int? roleId);
  Future<bool> setUserLocked(int userId, bool isLocked);

  // Branch Access
  Future<List<int>> getUserAccessibleBranchIds(int userId);
  Future<void> setUserBranchAccess(int userId, List<int> branchIds);
  
  // Authentication
  Future<UserWithRole?> authenticateUser(String username, String password);
  Future<UserWithRole?> authenticateByCardCode(String cardCode);
  Future<UserWithRole?> authenticateByPasswordOrCard(String input);

  /// عميل/مرآة، متصلٌ فقط: المستخدم يغيّر كلمته على الرئيسي (لا طابور)، ثم تُكتب
  /// البصمةُ المُعادة محليًّا. يرمي StateError برسالةٍ مترجَمة عند أيّ إخفاق.
  /// في المستقلّ/الرئيسي: مساره المحلي `updateUserPassword`.
  Future<void> changeOwnPassword({
    required String username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  });
  
  // Roles & Permissions
  Future<List<Role>> getAllRoles();
  Stream<List<Role>> watchRoles();
  Future<Role?> getRoleById(int id);
  Future<int> insertRole({
    required String name,
    String? description,
    bool isSystemRole,
  });
  Future<bool> updateRole({
    required int id,
    required String name,
    String? description,
  });
  Future<bool> deleteRole(int id);
  
  Future<List<Permission>> getAllPermissions();
  Future<List<Permission>> getPermissionsForRole(int roleId);
  Future<bool> userHasPermission(int userId, String permissionCode);
  Future<List<String>> getUserPermissionCodes(int userId);
  /// [modes] معرِّفُ الصلاحية → `allow` أو `conditional`. وما لا مدخلَ له
  /// فيها يُكتَب `allow`.
  Future<void> setRolePermissions(
    int roleId,
    List<int> permissionIds, {
    Map<int, String>? modes,
  });

  /// أنماطُ منح الدور — معرِّفُ الصلاحية → نمطُ المنح.
  Future<Map<int, String>> getRolePermissionModes(int roleId);
  
  // PIN tokens
  Future<bool> updateUserPin(int userId, String? pin);
  Future<bool> verifyUserPin(int userId, String pin);
}
