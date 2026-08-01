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
}
