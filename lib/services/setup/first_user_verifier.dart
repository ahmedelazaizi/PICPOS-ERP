// A1 / P4: the first user of a paired branch / mirror device is verified ON THE
// MAIN, never against the seeded local data (which carries no usable
// credentials - SETUP-001). The sequence:
//
//   1 POST /api/auth/session             (device bearer + user/password)
//   2 temporary password?  -> POST /api/auth/change-password (on the main)
//   3 GET /api/users with that session   -> the branch's users WITH credentials
//   4 apply them with the production user sync strategy
//   5 retire the seeded admin/admin      (the delivered credentials are the
//                                         only logins from now on)
//   6 prove it locally: the user signs in with the delivered hash
//
// The password lives only in this call's memory.
library;

import '../../core/auth/password_policy.dart';
import '../../core/i18n/tr.dart';
import '../../data/database/database.dart';
import '../deployment/mode_activator.dart';
import '../sync/strategies/user_sync_strategy.dart';
import 'branch_account_verifier.dart';
import 'main_auth_port.dart';
import 'seeded_admin_retire.dart';

class FirstUserVerifier implements BranchAccountVerifierPort {
  FirstUserVerifier({
    required this.db,
    required this.port,
    required this.permissionCodes,
    this.saveClientBranchId,
  });

  final AppDatabase db;
  final MainAuthPort port;
  final Future<List<String>> Function(int userId) permissionCodes;

  /// The branch of the device is known BEFORE the main is asked (the host
  /// applies the same branch rule to the session it issues).
  final Future<void> Function(int branchId)? saveClientBranchId;

  @override
  Future<AccountVerification> verify({
    required String username,
    required String password,
    int? branchId,
    String? newPassword,
  }) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      return AccountVerification.failure(
          tr('أدخل اسم المستخدم وكلمة المرور المعتمدين للفرع.'));
    }
    try {
      if (branchId != null) await saveClientBranchId?.call(branchId);

      var effective = password;
      var s = await port.createSession(name, password);
      if (s.outcome == MainAuthOutcome.passwordChangeRequired) {
        final next = newPassword ?? '';
        if (next.isEmpty) {
          return AccountVerification.passwordChangeRequired(tr(
              'هذا الحساب بكلمة مرور مؤقتة. اختر كلمة مرور جديدة ليكتمل التحقق.'));
        }
        final bad = validateNewPassword(name, password, next);
        if (bad != null) return AccountVerification.failure(_policyText(bad));
        s = await port.changePassword(name, password, next);
        effective = next;
      }
      if (!s.ok) return AccountVerification.failure(_outcomeText(s.outcome));

      final feed = await port.fetchUsers(s.token ?? '');
      if (feed == null) {
        return AccountVerification.failure(
            tr('تعذّر استلام مستخدمي الفرع من السيرفر الرئيسي. أعد المحاولة.'));
      }
      await UserSyncStrategy(db).syncFromJson(feed);
      await retireSeededAdmin(db);

      final local = await db.authenticateUser(name, effective);
      if (local == null) {
        return AccountVerification.failure(tr(
            'لم تصل بيانات دخول هذا الحساب إلى الجهاز. تحقق من صلاحية الحساب للفرع ثم أعد المحاولة.'));
      }
      ActivationHints.credentialsDeliveredAt = DateTime.now().toUtc();
      final codes = await permissionCodes(local.user.id);
      return AccountVerification.success(
        userId: local.user.id,
        displayName: local.user.displayName,
        roleName: local.role?.name ?? '—',
        permissionCount: codes.length,
        topPermissions: codes.take(3).toList(),
      );
    } catch (e) {
      return AccountVerification.failure(tr('❌ خطأ: {e}', {'e': e}));
    }
  }

  String _outcomeText(MainAuthOutcome o) => switch (o) {
        MainAuthOutcome.invalidCredentials =>
          tr('اسم المستخدم أو كلمة المرور غير صحيحة.'),
        MainAuthOutcome.branchDenied => tr('ليس لديك صلاحية الدخول لهذا الفرع'),
        MainAuthOutcome.mirrorConsoleDenied =>
          tr('هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له.'),
        MainAuthOutcome.lockedOut =>
          tr('تم قفل الحساب مؤقتاً على النظام الرئيسي.'),
        MainAuthOutcome.passwordRejected =>
          tr('كلمة المرور الجديدة غير مقبولة، اختر كلمة أخرى.'),
        MainAuthOutcome.passwordPolicy =>
          tr('كلمة المرور الجديدة قصيرة أو غير مقبولة، اختر كلمة أخرى.'),
        MainAuthOutcome.offline => tr(
            'تعذّر الاتصال بالسيرفر الرئيسي. تحقق من الشبكة ثم أعد المحاولة.'),
        _ => tr(
            'تعذّر إنشاء جلسة مع السيرفر الرئيسي. تحقق من الاتصال ثم أعد المحاولة.'),
      };

  String _policyText(String code) => switch (code) {
        PasswordPolicyCode.tooShort => tr(
            'كلمة المرور الجديدة قصيرة (٨ أحرف على الأقل).'),
        _ => tr('كلمة المرور الجديدة غير مقبولة، اختر كلمة أخرى.'),
      };
}
