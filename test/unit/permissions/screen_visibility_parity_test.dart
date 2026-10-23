// B-6/B-7: القائمةُ الجانبيّة ومزوّدُ الشاشات المسموحة وقائمةُ «الشاشة
// الافتراضية» تقرّر كلُّها بنفس الدالّة (`screenVisibleToUser`) — هذا الاختبارُ
// يقيس أنّها لا تتباعد لأيّ مستخدمٍ ولأيّ `ScreenId`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/permissions/screen_access_resolver.dart';
import 'package:ural_erp/core/permissions/screen_visibility.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/screen_access_selectors.dart';
import 'package:ural_erp/presentation/shared_widgets/default_screen_dropdown.dart';

/// شاشاتُ أدواتٍ تُستثنى من قائمة «الشاشة الافتراضية» وحدَها (لا من الفتح).
const _notLanding = {
  ScreenId.floorPlanDesigner,
  ScreenId.helpCenter,
  ScreenId.syncConflicts,
};

void main() {
  final allIds = ScreenId.values.toSet();
  final navIds = {
    for (final i in kAllNavItemDefs) ?ScreenId.fromIndex(i.index),
  };

  // كلُّ كودٍ تعرفه خريطةُ الشاشات أو قوائمُ الأفعال — مستخدمٌ بكلّ كودٍ وحده.
  final allCodes = <String>{
    ...screenPermissionMap.values,
    for (final l in screenActionCodes.values) ...l,
    for (final i in kAllNavItemDefs) ?i.permission,
  };

  final users = <String, ({Set<String> perms, bool bypass})>{
    'بلا صلاحيات': (perms: <String>{}, bypass: false),
    'مدير نظام (تجاوز)': (perms: <String>{}, bypass: true),
    'كلُّ الأكواد': (perms: allCodes, bypass: false),
    'بيع فقط': (perms: {'pos_access', 'sales_create'}, bypass: false),
    for (final c in allCodes) 'كود $c': (perms: {c}, bypass: false),
  };

  for (final platform in <String?>[null, 'eta']) {
    for (final u in users.entries) {
      test('تطابقٌ — ${u.key} · منصّة=$platform', () {
        final menu = {
          for (final i in selectMenuItems(
            navItems: kAllNavItemDefs,
            permissions: u.value.perms,
            bypass: u.value.bypass,
            eInvoicePlatform: platform,
            flavorAllowed: allIds,
            brandVisible: (_) => true,
          ))
            ScreenId.fromIndex(i.index)!,
        };
        final allowed = {
          for (final i in selectAllowedScreenIndexes(
            navItems: kAllNavItemDefs,
            permissions: u.value.perms,
            bypass: u.value.bypass,
            eInvoicePlatform: platform,
            flavorAllowed: allIds,
          ))
            ScreenId.fromIndex(i)!,
        };
        final dropdown = {
          for (final o in defaultScreenOptions(
            rolePermissions: u.value.perms,
            bypass: u.value.bypass,
            eInvoiceAvailable: platform != null,
            flavorAllowed: allIds,
            brandVisible: (_) => true,
          ))
            o.id,
        };

        // ظاهرٌ في القائمة ⇒ مسموح (وإلّا يموت نقرُه).
        expect(allowed.containsAll(menu), isTrue,
            reason: 'في القائمة وغيرُ مسموح: ${menu.difference(allowed)}');
        // كلُّ شاشةٍ لها مدخلٌ: القائمةُ ⇔ المسموح.
        for (final id in allIds.intersection(navIds)) {
          expect(menu.contains(id), allowed.contains(id),
              reason: '$id: القائمة=${menu.contains(id)} '
                  'مسموح=${allowed.contains(id)}');
        }
        // القائمةُ المنسدلة = القائمةُ ناقصَ شاشات الأدوات.
        expect(dropdown, menu.difference(_notLanding));
        // وكلُّ ما فيها مسموح.
        expect(allowed.containsAll(dropdown), isTrue);

        // كلُّ فرعٍ يوافق الدالّة الوحيدة لكلّ شاشة.
        for (final id in allIds) {
          final primary = resolveScreenPrimaryCode(screenPermissionMap, id,
              kAllNavItemDefs
                  .where((i) => i.index == id.navigationIndex)
                  .firstOrNull
                  ?.permission);
          final expected = screenVisibleToUser(u.value.perms, id,
              primaryCode: primary,
              bypass: u.value.bypass,
              eInvoicePlatformActive: platform != null);
          if (navIds.contains(id)) {
            expect(allowed.contains(id), expected, reason: '$id مسموح');
          }
        }
      });
    }
  }

  test('الفوترة الإلكترونية: بلا منصّة تُخفى عن غير مدير النظام فقط، في الثلاثة',
      () {
    final held = {'einvoice_view'};
    bool inAll(bool bypass, String? platform) {
      final m = selectMenuItems(
        navItems: kAllNavItemDefs,
        permissions: held,
        bypass: bypass,
        eInvoicePlatform: platform,
        flavorAllowed: allIds,
        brandVisible: (_) => true,
      ).any((i) => i.index == ScreenId.eInvoice.navigationIndex);
      final a = selectAllowedScreenIndexes(
        navItems: kAllNavItemDefs,
        permissions: held,
        bypass: bypass,
        eInvoicePlatform: platform,
        flavorAllowed: allIds,
      ).contains(ScreenId.eInvoice.navigationIndex);
      final d = defaultScreenOptions(
        rolePermissions: held,
        bypass: bypass,
        eInvoiceAvailable: platform != null,
        flavorAllowed: allIds,
        brandVisible: (_) => true,
      ).any((o) => o.id == ScreenId.eInvoice);
      expect(m, a);
      expect(d, a);
      return a;
    }

    expect(inAll(false, null), isFalse);
    expect(inAll(false, 'eta'), isTrue);
    expect(inAll(true, null), isTrue);
  });

  test('B-7: بلا أيِّ صلاحيةٍ ⇒ لا شاشةَ مسموحة (لا حقنَ للوحة التحكم)', () {
    final allowed = selectAllowedScreenIndexes(
      navItems: kAllNavItemDefs,
      permissions: const <String>{},
      bypass: false,
      eInvoicePlatform: null,
      flavorAllowed: allIds,
    );
    // الشاشاتُ بلا بوّابة (كود null) مفتوحةٌ للجميع بتصميمها — تُستبعد من
    // الفحص؛ المهمُّ ألّا تُحقَن لوحةُ التحكم قسراً.
    expect(allowed.contains(ScreenId.dashboard.navigationIndex), isFalse,
        reason: 'لوحةُ التحكم لا تُحقَن لمن لا يملك dashboard_access');
  });
}