// عقدُ التحقّق من الحساب المركزيّ لجهاز الفرع (P6 · B10) — لا إنشاءَ مستخدمٍ محلّيّ.
//
// يحمل هذا الملفُّ **العقدَ ونتيجتَه فقط** (`BranchAccountVerifierPort` و
// `AccountVerification`). المنفِّذ الوحيد هو `FirstUserVerifier`
// (`first_user_verifier.dart`): يتحقق **على الرئيسي أولًا** ثم يسحب اعتماداتِ
// الفرع ويختم. المنفِّذ المحلّيّ القديم (`BranchAccountVerifier` الذي كان يكتفي
// بـ`authenticateUser` المحلّيّ) حُذف لأنه لا يُستعمل (SEC-004: التحقق المحلّي
// وحده لا يكفي). كلمةُ المرور تبقى في الذاكرة طوالَ النداء ولا تُخزَّن.
library;

class AccountVerification {
  const AccountVerification.success({
    required this.userId,
    required this.displayName,
    required this.roleName,
    required this.permissionCount,
    this.topPermissions = const [],
  })  : ok = true,
        error = null,
        needsPasswordChange = false;

  const AccountVerification.failure(String this.error)
      : ok = false,
        needsPasswordChange = false,
        userId = null,
        displayName = null,
        roleName = null,
        permissionCount = 0,
        topPermissions = const [];

  /// The main accepted the temporary password but requires a new one first.
  const AccountVerification.passwordChangeRequired(String this.error)
      : ok = false,
        needsPasswordChange = true,
        userId = null,
        displayName = null,
        roleName = null,
        permissionCount = 0,
        topPermissions = const [];

  final bool ok;
  final bool needsPasswordChange;
  final String? error;
  final int? userId;
  final String? displayName;
  final String? roleName;
  final int permissionCount;

  /// أوّلُ ثلاثة أكواد صلاحيةٍ للعرض.
  final List<String> topPermissions;
}

abstract interface class BranchAccountVerifierPort {
  /// [branchId] is `null` for a mirror (not branch-bound). [newPassword] answers
  /// a `passwordChangeRequired` result (the temporary password is replaced ON
  /// THE MAIN, never only locally).
  Future<AccountVerification> verify({
    required String username,
    required String password,
    int? branchId,
    String? newPassword,
  });
}

