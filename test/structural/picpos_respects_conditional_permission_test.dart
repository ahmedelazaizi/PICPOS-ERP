// حارسُ العقد: «مشروط» يشترط موافقةً على شاشة الكاشير أيضاً.
//
// ═══ فئةُ العطب — بلاغُ المراجعة الأمنيّة 2026-08-30 ═══
//
// الصلاحيةُ المشروطةُ **ممنوحةٌ فعلاً**: صفُّها موجودٌ في `role_permissions`،
// ويُرفَق معها وسمٌ منفصلٌ `cond:<code>` من `_conditionalMarkers`. فمن يفحص
// `codes.contains(code)` وحدَه يرى الصلاحيةَ مملوكةً ويمرّ **بلا حوار** —
// ويصير «مشروط» مِزلاجاً لا يفعل شيئاً.
//
// و`ensurePermission` في `permission_guard.dart` تحترمه منذ البداية. أمّا
// شاشةُ PicPos فلها **ثلاثُ نسخٍ خاصّةٍ** من نفس الفحص لم تحترمه:
//
//   • `_ensure`                 — `picpos_cart_permissions.dart`
//   • `_ensureCartPermission`   — `picpos_pos_operations.dart`
//   • `_userHasPermissionFresh` — `picpos_pos_operations.dart`
//
// فمديرٌ يضبط `pos_discount` أو `pos_price_edit` على «مشروط» ظنّاً أنّ كلَّ
// تنفيذٍ سيمرّ بموافقة — والكاشيرُ يخصم بلا أن يظهر حوارٌ واحد. يشمل ذلك
// ستّةَ عشرَ كوداً على أخطرِ شاشةٍ في النظام.
//
// ═══ لماذا حارسٌ بنيويّ ═══
//
// البديلُ ضخُّ الشاشة بقاعدةٍ ودورٍ مشروطٍ لكلِّ كودٍ من الستّةَ عشر. والمقصودُ
// هنا **وجودُ نقطة الفحص** في المسارات الثلاثة — وهي بالضبط ما غاب.
// والسلوكُ المشروطُ نفسُه مقيسٌ في `test/unit/conditional_permission_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _paths = <String, List<String>>{
  'lib/presentation/pos_picpos/widgets/picpos_cart_permissions.dart': [
    '_ensure',
  ],
  'lib/presentation/pos_picpos/screens/picpos_pos_cart_edit.dart': [
    '_ensureCartPermission',
  ],
  'lib/presentation/pos_picpos/screens/picpos_pos_checkout_support.dart': [
    '_userHasPermissionFresh',
  ],
};

String _read(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ «$p» اختفى');
  return f.readAsStringSync();
}

/// يزيل تعليقاتِ السطر: ذِكرُ الاسم في شرحٍ ليس فحصاً.
String _stripComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .join('\n');

void main() {
  group('شاشةُ الكاشير تحترم الصلاحيةَ المشروطة', () {
    test('المرساة: المرجعُ نفسُه ما زال يحترمها', () {
      // ⚠️ إن سقط هذا فالعقدُ نفسُه تغيّر، لا نسخُ PicPos — والحارسُ يقيس
      // شيئاً لم يعد قائماً.
      final ref = _stripComments(_read('lib/presentation/widgets/permission_guard.dart'));
      expect(ref, contains('PermissionCodes.isConditionalIn'),
          reason: 'المرجعُ `permission_guard` فقد الفحصَ — تغيّر العقد');
    });

    test('والدوالُّ الثلاثُ تفحص `isConditionalIn`', () {
      final missing = <String>[];
      for (final entry in _paths.entries) {
        final src = _stripComments(_read(entry.key));
        if (!src.contains('PermissionCodes.isConditionalIn')) {
          missing.add(entry.key);
        }
      }
      expect(missing, isEmpty,
          reason: 'مسارُ صلاحيةٍ في PicPos بلا فحصِ «مشروط» ⇒ المديرُ يضبطه '
              'ولا يقع شيء:\n  ${missing.join("\n  ")}');
    });

    test('والفحصُ يسبق المِلك — الترتيبُ هو الميزةُ كلُّها', () {
      // ⚠️ فحصٌ بعد المِلك لا يُنفَّذ أبداً: المِلكُ يعود `true` أوّلاً.
      // فنقيس أنّ `isConditionalIn` تقع في **نفس الشرط** لا في سطرٍ تالٍ.
      final cart = _stripComments(
          _read('lib/presentation/pos_picpos/widgets/picpos_cart_permissions.dart'));
      expect(
        cart,
        contains('!PermissionCodes.isConditionalIn(perms, permission) && can(perms)'),
        reason: 'الفحصُ يجب أن يقيّد المِلكَ في نفس الشرط، وإلّا مرّ المشروطُ',
      );

      final cartEdit = _stripComments(
          _read('lib/presentation/pos_picpos/screens/picpos_pos_cart_edit.dart'));
      final ops = _stripComments(_read(
          'lib/presentation/pos_picpos/screens/picpos_pos_checkout_support.dart'));
      expect(
        cartEdit,
        contains('!PermissionCodes.isConditionalIn(perms, permission) && can(perms)'),
        reason: '`_ensureCartPermission` تفحص المِلكَ بلا تقييدٍ بالمشروط',
      );
      expect(
        ops,
        contains('if (PermissionCodes.isConditionalIn(codes, permissionCode)) return false;'),
        reason: '`_userHasPermissionFresh` تمرّر المشروطَ كأنّه مملوك',
      );
    });
  });
}
