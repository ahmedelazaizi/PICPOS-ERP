part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// USER, SESSION & ROLE OPERATIONS
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerUsers on ActivityLogger {
  Future<void> logLogin(int userId, String userName, {String? deviceInfo}) {
    return log(userId: userId, userName: userName, action: 'login', entityType: 'session',
        description: 'تسجيل دخول', deviceInfo: deviceInfo);
  }

  Future<void> logLogout(int userId, String userName) {
    return log(userId: userId, userName: userName, action: 'logout', entityType: 'session', description: 'تسجيل خروج');
  }

  Future<void> logUserCreate(int userId, String userName, String newUserName) {
    return log(userId: userId, userName: userName, action: 'user_create', entityType: 'user',
        description: 'إنشاء مستخدم جديد: $newUserName');
  }

  Future<void> logUserPermChange(int userId, String userName, String targetUser, String oldRole, String newRole) {
    return log(userId: userId, userName: userName, action: 'perm_change', entityType: 'user',
        description: 'تغيير صلاحيات $targetUser', oldValue: oldRole, newValue: newRole);
  }

  Future<void> logUserEdit(int userId, String userName, String targetUser, String changeType,
      {String? oldValue, String? newValue}) {
    return log(userId: userId, userName: userName, action: 'user_edit', entityType: 'user',
        description: '$changeType: $targetUser', oldValue: oldValue, newValue: newValue);
  }

  Future<void> logUserToggleActive(int userId, String userName, String targetUser, bool isNowActive) {
    return log(userId: userId, userName: userName,
        action: isNowActive ? 'user_activate' : 'user_deactivate', entityType: 'user',
        description: '${isNowActive ? "تفعيل" : "تعطيل"} مستخدم: $targetUser');
  }

  Future<void> logUserToggleLock(int userId, String userName, String targetUser, bool isNowLocked) {
    return log(userId: userId, userName: userName,
        action: isNowLocked ? 'user_lock' : 'user_unlock', entityType: 'user',
        description: '${isNowLocked ? "قفل" : "فك قفل"} مستخدم: $targetUser');
  }

  Future<void> logUserResetPassword(int userId, String userName, String targetUser) {
    return log(userId: userId, userName: userName, action: 'user_reset_password', entityType: 'user',
        description: 'إعادة تعيين كلمة مرور: $targetUser');
  }

  Future<void> logAdminElevation(int userId, String userName, String elevatedAs) {
    return log(userId: userId, userName: userName, action: 'admin_elevation', entityType: 'session',
        description: 'رفع صلاحيات مؤقت — الدخول كـ $elevatedAs');
  }

  Future<void> logRoleCreate(int userId, String userName, String roleName) {
    return log(userId: userId, userName: userName, action: 'role_create', entityType: 'role',
        description: 'إنشاء دور جديد: $roleName');
  }

  Future<void> logRoleDelete(int userId, String userName, String roleName) {
    return log(userId: userId, userName: userName, action: 'role_delete', entityType: 'role',
        description: 'حذف دور: $roleName');
  }

  Future<void> logUpdateRolePermissions(int userId, String userName, String roleName, [int? permCount]) {
    return log(userId: userId, userName: userName, action: 'role_perm_update', entityType: 'role',
        description: 'تحديث صلاحيات الدور: $roleName${permCount != null ? " ($permCount صلاحية)" : ""}');
  }
}
