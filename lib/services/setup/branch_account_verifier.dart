// تحقّقُ الحساب المركزيّ المعتمد لجهاز الفرع (P6 · B10) — لا إنشاءَ مستخدمٍ محلّيّ.
//
// يلفّ `authenticateUser` الموجود (‏التحقّق من الـhash المزامَن + حارس وصول الفرع
// + طلب جلسة الخادم) ويُرجع الدورَ وأبرزَ الصلاحيات.
//
// ⚠️ SEC-004: صفُّ `users` الذي وصل بلا بيانات اعتماد يحمل كلمةً مؤقتةً متوقَّعة،
// فالتحقّق المحلّيّ وحده لا يكفي: لا يُقبل الحسابُ إلا بعد **نجاح جلسة الخادم**
// للمستخدم نفسه. وكلمةُ المرور تبقى في الذاكرة طوالَ النداء ولا تُخزَّن.
library;

import '../../core/i18n/tr.dart';
import '../../domain/repositories/auth_repository.dart';

class AccountVerification {
  const AccountVerification.success({
    required this.userId,
    required this.displayName,
    required this.roleName,
    required this.permissionCount,
    this.topPermissions = const [],
  })  : ok = true,
        error = null;

  const AccountVerification.failure(String this.error)
      : ok = false,
        userId = null,
        displayName = null,
        roleName = null,
        permissionCount = 0,
        topPermissions = const [];

  final bool ok;
  final String? error;
  final int? userId;
  final String? displayName;
  final String? roleName;
  final int permissionCount;

  /// أوّلُ ثلاثة أكواد صلاحيةٍ للعرض.
  final List<String> topPermissions;
}

abstract interface class BranchAccountVerifierPort {
  Future<AccountVerification> verify({
    required String username,
    required String password,
    required int branchId,
  });
}

class BranchAccountVerifier implements BranchAccountVerifierPort {
  BranchAccountVerifier({
    required this.auth,
    required this.hasServerSession,
    required this.saveClientBranchId,
  });

  final IAuthRepository auth;

  /// هل لدى هذا المستخدم جلسةُ خادمٍ موقَّعة (‏`ServerProxy.hasSessionToken`)؟
  final bool Function(int userId) hasServerSession;

  /// فرعُ الجهاز يجب أن يُعرَف قبل التحقّق، وإلا تخطّى الحارسُ فحصَ الفرع.
  final Future<void> Function(int branchId) saveClientBranchId;

  @override
  Future<AccountVerification> verify({
    required String username,
    required String password,
    required int branchId,
  }) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      return AccountVerification.failure(
          tr('أدخل اسم المستخدم وكلمة المرور المعتمدين للفرع.'));
    }
    try {
      await saveClientBranchId(branchId);
      final result = await auth.authenticateUser(name, password);
      if (result == null) {
        return AccountVerification.failure(
            tr('اسم المستخدم أو كلمة المرور غير صحيحة.'));
      }
      final id = result.user.id;
      if (!hasServerSession(id)) {
        // الخادم يرفض الجلسة (403 password_change_required) لحسابٍ ملزَمٍ بتغيير
        // كلمته الأوّليّة — سببٌ محدَّدٌ يُشرح بدل «تعذّر الاتصال».
        if (result.user.forcePasswordChange) {
          return AccountVerification.failure(tr(
              'هذا الحساب ملزم بتغيير كلمة المرور الأولية قبل أول اتصال. غيّرها من الجهاز الرئيسي أو اطلب من المسؤول تعطيل الإلزام ثم أعد التحقق.'));
        }
        return AccountVerification.failure(tr(
            'تعذّر إنشاء جلسة مع السيرفر الرئيسي. تحقق من الاتصال ثم أعد المحاولة.'));
      }
      final codes = await auth.getUserPermissionCodes(id);
      return AccountVerification.success(
        userId: id,
        displayName: result.user.displayName,
        roleName: result.role?.name ?? '—',
        permissionCount: codes.length,
        topPermissions: codes.take(3).toList(),
      );
    } on StateError catch (e) {
      // رسائلُ المستودع بالعربيّة: «ليس لديك صلاحية الدخول لهذا الفرع»…
      return AccountVerification.failure(e.message);
    } catch (e) {
      return AccountVerification.failure(tr('❌ خطأ: {e}', {'e': e}));
    }
  }
}
