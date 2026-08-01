// test/unit/screen_permission_map_test.dart
//
// كل شاشة لازم تتربط بكود صلاحيتها هي.
//
// الخريطة كانت بتربط شاشات بأكواد عامة: العروض والطاولات والمطبخ ولوحة
// التحكم كلهم على `pos_access`، ومردودات البيع على `sales_view`. فالمدير
// يسحب `offers_view` وشاشة العروض تفضل ظاهرة لأنها مش مربوطة بيه أصلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';

void main() {
  test('كل كود في الخريطة مسجّل في masterList', () {
    final master = PermissionCodes.masterList.map((m) => m['code']!).toSet();
    for (final entry in screenPermissionMap.entries) {
      expect(master.contains(entry.value), isTrue,
          reason: '${entry.key} مربوطة بكود غير مسجّل: ${entry.value}');
    }
  });

  test('الشاشات اللي ليها كود خاص متربطة بيه مش بكود عام', () {
    const expected = <ScreenId, String>{
      ScreenId.dashboard: 'dashboard_access',
      ScreenId.offers: 'offers_view',
      ScreenId.tables: 'tables_view',
      ScreenId.kitchen: 'kitchen_view',
      ScreenId.salesReturns: 'sales_return_view',
      ScreenId.purchaseReturns: 'purchases_return_view',
      ScreenId.manufacturing: 'manufacturing_view',
      ScreenId.fixedAssets: 'assets_view',
      ScreenId.loyalty: 'loyalty_view',
      ScreenId.distribution: 'distribution_view',
    };
    expected.forEach((screen, code) {
      expect(screenPermissionMap[screen], code,
          reason: '$screen لازم تتحكم بـ $code');
    });
  });

  test('عنصر القائمة بتاع كل شاشة اتصلّحت لازم يتفق مع الخريطة', () {
    // ده بالظبط نوع العطل اللي البلاغ حذّر منه: نصلّح screenPermissionMap
    // ونسيب عنصر القائمة (userNavItemsProvider) على الكود العام القديم —
    // فيبقى فيه رابط في القائمة الجانبية بيوصّل لشاشة ممنوعة، أو العكس:
    // شاشة متاحة من غير رابط ليها في القائمة. حصل بالظبط كده مع لوحة
    // التحكم أول مرة (راجع تعليق `permission: PermissionCodes.dashboardAccess`
    // فوق عنصر "الرئيسية" في auth_providers.dart).
    //
    // النطاق هنا مقصود يقتصر على الشاشات العشرة اللي اتصلّحت في الخريطة
    // فوق. فيه شاشات تانية (زي analytics: مربوطة بـ analytics_view في
    // الخريطة لكن عنصر قائمتها لسه على reports_view) فيها تعارض قديم مش
    // من إصلاح النهارده — ده خارج نطاق التاسك ده ومطروح في مرحلة تانية
    // (مرحلة الـ ٨٨ كود بلا إنفاذ).
    const changedScreens = <ScreenId>{
      ScreenId.dashboard,
      ScreenId.offers,
      ScreenId.tables,
      ScreenId.kitchen,
      ScreenId.salesReturns,
      ScreenId.purchaseReturns,
      ScreenId.manufacturing,
      ScreenId.fixedAssets,
    };

    for (final screen in changedScreens) {
      final navItem = kAllNavItemDefs.firstWhere(
        (item) => ScreenId.fromIndex(item.index) == screen,
        orElse: () =>
            throw StateError('مفيش عنصر قائمة بيفتح شاشة $screen أصلاً'),
      );
      expect(navItem.permission, screenPermissionMap[screen],
          reason:
              'عنصر القائمة بتاع $screen (${navItem.label}) لازم يتفق مع '
              'screenPermissionMap[$screen]');
    }
  });
}
