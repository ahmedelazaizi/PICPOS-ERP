// lib/core/permissions/screen_visibility.dart
//
// الدالّةُ **الوحيدةُ** التي تقرّر: هل تُرى الشاشةُ/تُفتح للمستخدم؟ (B-6)
//
// كانت ثلاثةَ مواضعَ بمصادرِ صلاحيةٍ مختلفة — القائمةُ الجانبيّة بـ
// `item.permission`، ومزوِّدُ الشاشات المسموحة بـ`screenPermissionMap`،
// وقائمةُ «الشاشة الافتراضية» بالاثنين معاً — واستثناءُ الفوترة الإلكترونية
// مكتوبٌ بثلاث صيغٍ (`isAdmin` هنا و`hasSystemAdminBypass` هناك، وفي القائمة
// يتخطّى تجاوزُ المدير فحصَ الكود). فصار الشريطُ يُخفي ما تفتحه القائمةُ
// المنسدلة أو العكس.
//
// الآن كلُّها تنادي هذه الدالّةَ بنفس المدخلات، ويقيس
// `screen_visibility_parity_test` أنّها لا تتباعد.
import 'package:ural_erp/core/navigation/screen_id.dart';

import 'screen_access_resolver.dart';

/// كودُ الشاشة: ما في `screenPermissionMap` أوّلاً، وإلّا كودُ مدخل التنقّل.
String? resolveScreenPrimaryCode(
  Map<ScreenId, String> permissionMap,
  ScreenId id,
  String? navItemPermission,
) =>
    permissionMap[id] ?? navItemPermission;

/// هل [id] مرئيةٌ/مفتوحةٌ لحامل [permissions]؟
///
/// - [bypass]: `hasSystemAdminBypass` (دورُ النظام «مدير النظام» حصراً).
/// - [eInvoicePlatformActive]: هل فُعِّلت منصّةُ فوترةٍ إلكترونية؟ بلاها لا
///   تُفتح الشاشةُ لغير مدير النظام (استثناءٌ واحدٌ، بتجاوز واحد).
///
/// قاعدةُ الكود نفسُها [canOpenScreen] (أيُّ كودٍ من مجموعة الشاشة).
bool screenVisibleToUser(
  Iterable<String> permissions,
  ScreenId id, {
  required String? primaryCode,
  required bool bypass,
  required bool eInvoicePlatformActive,
}) {
  if (id == ScreenId.eInvoice && !eInvoicePlatformActive && !bypass) {
    return false;
  }
  return canOpenScreen(permissions, id,
      primaryCode: primaryCode, bypass: bypass);
}