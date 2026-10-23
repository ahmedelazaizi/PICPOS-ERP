// lib/data/providers/screen_access_selectors.dart
//
// اختيارُ مدخلات القائمة الجانبيّة والشاشات المسموحة — دوالُّ خالصةٌ تنادي
// [screenVisibleToUser] وحدَها (B-6). المزوّدان في `auth_providers.dart`
// يمرّران لها المدخلاتِ فقط، فلا منطقَ صلاحيةٍ ثانياً يتباعد.
//
// الاستيراد الدائريُّ مع `auth_providers.dart` مقصود (النوعُ `NavItemDef`
// والخريطةُ `screenPermissionMap` يعيشان هناك والملفُّ على سقف الحجم).
import '../../core/navigation/screen_id.dart';
import '../../core/permissions/screen_visibility.dart';
import 'auth_providers.dart' show NavItemDef, screenPermissionMap;

/// مدخلاتُ القائمة الجانبيّة التي يراها المستخدم.
///
/// [eInvoicePlatform]: `'eta'`/`'jofotara'`/غيرها أو `null` إن لم تُفعَّل.
List<NavItemDef> selectMenuItems({
  required Iterable<NavItemDef> navItems,
  required Set<String> permissions,
  required bool bypass,
  required String? eInvoicePlatform,
  required Set<ScreenId> flavorAllowed,
  required bool Function(int index) brandVisible,
  bool hideDashboard = false,
}) {
  final out = <NavItemDef>[];
  for (final item in navItems) {
    final id = ScreenId.fromIndex(item.index);
    if (id == null || !flavorAllowed.contains(id)) continue;
    if (!brandVisible(item.index)) continue;
    if (id == ScreenId.dashboard && hideDashboard) continue;
    if (!screenVisibleToUser(permissions, id,
        primaryCode:
            resolveScreenPrimaryCode(screenPermissionMap, id, item.permission),
        bypass: bypass,
        eInvoicePlatformActive: eInvoicePlatform != null)) {
      continue;
    }
    if (id == ScreenId.eInvoice) {
      final label = switch (eInvoicePlatform) {
        'eta' => 'الفوترة الإلكترونية (مصر)',
        'jofotara' => 'الفوترة الإلكترونية (الأردن)',
        _ => item.label,
      };
      out.add(NavItemDef(
        icon: item.icon,
        label: label,
        permission: item.permission,
        index: item.index,
        section: item.section,
        group: item.group,
      ));
      continue;
    }
    out.add(item);
  }
  return out;
}

/// فهارسُ الشاشات التي يفتحها المستخدم (مرتَّبة). فارغةٌ ⇒ لا شاشةَ يفتحها.
///
/// تغطّي كلَّ شاشةٍ في `screenPermissionMap` **وكلَّ مدخلٍ في [navItems]**:
/// مدخلٌ ظاهرٌ في القائمة لا يجوز ألّا يكون مسموحاً (فيموت نقرُه).
List<int> selectAllowedScreenIndexes({
  required Iterable<NavItemDef> navItems,
  required Set<String> permissions,
  required bool bypass,
  required String? eInvoicePlatform,
  required Set<ScreenId> flavorAllowed,
}) {
  final codes = <ScreenId, String?>{
    for (final item in navItems)
      ?ScreenId.fromIndex(item.index): item.permission,
    for (final e in screenPermissionMap.entries) e.key: e.value,
  };
  final out = <int>[];
  for (final e in codes.entries) {
    if (!flavorAllowed.contains(e.key)) continue;
    if (screenVisibleToUser(permissions, e.key,
        primaryCode: e.value,
        bypass: bypass,
        eInvoicePlatformActive: eInvoicePlatform != null)) {
      out.add(e.key.navigationIndex);
    }
  }
  return out..sort();
}