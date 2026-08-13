// حراسةُ شاشة إدارة المستخدمين في PicPos.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// الشاشةُ (٨٩٤ سطراً) تُسنِد الأدوارَ وتصفّر كلماتِ المرور وتضبط PIN وتفعّل
// وتقفل وتحذف وتمنح صلاحياتِ الفروع والمخازن — وكانت فيها **صفرُ** فحوصِ
// صلاحية. حمايتُها كلُّها كانت على **مداخلها**: لفّةٌ في شاشة الإعدادات،
// ومدخلٌ في كتالوج التقارير نُسي فيه `permission:` أصلاً (‏تصعيدُ امتيازٍ
// كامل، أُغلق 2026-08-13).
//
// وحراسةُ المداخل وحدَها هي بعينها العطبُ الذي طاردناه اليوم كلَّه: بابٌ
// يُحرَس وبابٌ يُنسى. فالفحصُ ينتقل إلى الشاشة نفسِها — نقطةٌ واحدةٌ يمرّ بها
// كلُّ مدخلٍ حاليٍّ ومستقبليّ.
//
// ── لماذا كودان لا كودٌ واحد ──────────────────────────────────────────────
// فتحُ الشاشة `users_manage`. أمّا **إسنادُ الدور** فهو `roles_manage`: منحُ
// دورٍ لمستخدمٍ قرارُ صلاحياتٍ لا تحريرُ سجلّ مستخدم، وهو المسارُ الذي يصنع
// مديرَ نظامٍ جديداً. وكان حارسُه الوحيدُ «الموافقة الثنائية» (سبيك ٠٦٣) وهي
// **مطفأةٌ افتراضياً**، فلم يكن ثمّة فحصٌ فعليٌّ إطلاقاً.
//
// والنمطُ يطابق `picpos_cart_permissions_test` المجاور: دوالُّ قرارٍ خالصةٌ
// تُختبر هنا، ووصلُها بالمعالِجات محروسٌ بنيوياً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/users_picpos/screens/users_management_picpos_screen.dart';

const _screenPath =
    'lib/presentation/users_picpos/screens/users_management_picpos_screen.dart';

/// نزعُ التعليقات وحدَها — السلاسلُ تُترك كما هي (ماسحٌ يدويٌّ لها قد يفقد
/// التزامنَ على استقراءٍ متداخل فيبتلع بقيةَ الملفّ).
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

void main() {
  final cases = <String, bool Function(List<String>)>{
    PermissionCodes.usersManage: canManageUsersCodes,
    PermissionCodes.rolesManage: canAssignUserRoleCodes,
  };

  cases.forEach((code, can) {
    group(code, () {
      test('مرفوضٌ بلا الكود', () {
        expect(can(const []), isFalse,
            reason: 'الشاشةُ كانت مفتوحةً بلا أيّ فحص');
      });

      test('مسموحٌ مع الكود', () {
        expect(can([code]), isTrue);
      });

      test('ومديرُ النظام يمرّ', () {
        expect(can(const ['system_admin']), isTrue);
        expect(can(const ['*']), isTrue);
      });

      test('وكودٌ آخرُ لا يفتحه', () {
        expect(can(const ['pos_access']), isFalse);
      });
    });
  });

  test('فتحُ الشاشة لا يمنح إسنادَ الدور', () {
    // ⚠️ الضابطُ الأهمّ: من يملك `users_manage` وحدَه يدير الحسابات ولا
    // يصنع مديرَ نظام. ولولاه لمرّ حلٌّ يفحص كوداً واحداً للاثنين — وهو
    // بعينه مسارُ التصعيد الذي أُغلق اليوم.
    expect(canManageUsersCodes(const [PermissionCodes.usersManage]), isTrue);
    expect(canAssignUserRoleCodes(const [PermissionCodes.usersManage]), isFalse);
  });

  test('والكودان متمايزان', () {
    expect(cases.keys.toSet(), hasLength(2));
  });

  // ── وصلُ الدوالّ بالشاشة ─────────────────────────────────────────────────
  // الدوالُّ الخالصةُ أعلاه تمرّ خضراءَ ولو حُذفت البوّابةُ من `build`
  // كلياً — وهو بعينه «حارسٌ يبدو أنه يعمل». فهذه المجموعةُ تقيس الوصل.
  group('البوّابتان موصولتان فعلاً بالشاشة', () {
    // ⚠️ يُقاس على الكود **بلا تعليقات**. أوّلُ صياغةٍ لهذا الاختبار سقطت
    // حمراءَ لأن `indexOf('DualApprovalService')` طابق ذِكرَه في تعليقٍ
    // **قبل** الفحص — فبدا الترتيبُ معكوساً وهو صحيح. نفسُ العطب الذي كان
    // يُسكت حارسَ التكافؤ: التعليقُ ليس كوداً.
    late final String src = _stripComments(File(_screenPath).readAsStringSync());

    /// جسمُ دالّةٍ من توقيعها إلى التوقيع التالي — يكفي لقياس الوصل.
    String bodyOf(String signature) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(-1), reason: '«$signature» اختفى من الشاشة');
      final next = src.indexOf('\n  Future<void> _', start + signature.length);
      return src.substring(start, next == -1 ? src.length : next);
    }

    /// موضعُ [needle] في [body]، ويفشل صراحةً إن غاب — `indexOf` يرجع `-1`
    /// وهو «أصغرُ من» كلِّ شيء، فكان الغيابُ يمرّ خضراءَ في قياس الترتيب.
    int at(String body, String needle) {
      final i = body.indexOf(needle);
      expect(i, greaterThan(-1), reason: '«$needle» غير موجود');
      return i;
    }

    test('`build` يفحص قبل أن يقرأ أيَّ بيانات', () {
      final body = bodyOf('Widget build(BuildContext context)');
      expect(body.contains('canManageUsersCodes'), isTrue,
          reason: 'بلا هذا تُفتح الشاشةُ لأيّ مدخلٍ يبلغها');
      expect(at(body, 'canManageUsersCodes'),
          lessThan(at(body, 'ref.watch(allUsersProvider)')),
          reason: 'الفحصُ يجب أن يسبق قراءةَ المستخدمين وبناءَ الشاشة');
    });

    test('و`_updateUserRole` يفحص قبل الموافقة الثنائية وقبل الكتابة', () {
      final body = bodyOf('Future<void> _updateUserRole(');
      expect(body.contains('canAssignUserRoleCodes'), isTrue);
      // الترتيبُ جزءٌ من الحراسة: `DualApprovalService` مطفأٌ افتراضياً،
      // ووضعُ الفحص بعده كان سيستدعي مُوافقاً ثانياً لعمليةٍ سترفض أصلاً.
      expect(at(body, 'canAssignUserRoleCodes'),
          lessThan(at(body, 'DualApprovalService')),
          reason: 'الفحصُ يجب أن يسبق طلبَ الموافقة الثنائية');
      expect(at(body, 'canAssignUserRoleCodes'),
          lessThan(at(body, 'ClientWriteInterceptor.updateUser')),
          reason: 'الفحصُ يجب أن يسبق الكتابة');
    });
  });
}
