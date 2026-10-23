import 'permission_codes.dart';

/// قاعدةُ «من يحقّ له أن يُوافق» في حوار تصريح المسؤول (AUTHZ-001).
///
/// ‏four-eyes: الموافِقُ **مستخدمٌ آخرُ** غيرُ طالب الإجراء، ويملك الكودَ
/// **منحاً غير مشروط** — فصاحبُ المنحة المشروطة (`cond:<code>`) هو نفسُه
/// يحتاج موافقةً، فلا يصلح أن يُوافق غيرَه. ومدير النظام يوافق إلا على
/// [PermissionCodes.criticalFinancialOps] (فصلُ المهامّ).
class ManagerApprovalRules {
  ManagerApprovalRules._();

  static bool canApprove({
    required int approverId,
    required int? requesterId,
    required List<String> approverPermissions,
    required String permission,
  }) {
    if (requesterId != null && approverId == requesterId) return false;
    final isSystemAdmin = approverPermissions.contains('system_admin') ||
        approverPermissions.contains('*');
    final isCritical = PermissionCodes.criticalFinancialOps.contains(permission);
    if (isSystemAdmin && !isCritical) return true;
    return approverPermissions.contains(permission) &&
        !PermissionCodes.isConditionalIn(approverPermissions, permission);
  }
}
