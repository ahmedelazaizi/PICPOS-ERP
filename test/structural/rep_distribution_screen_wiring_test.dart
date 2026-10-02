// المرحلة و — «إدارة المناديب والتوزيع» موصولةٌ في كلّ موضع: المعرِّف ·
// `AppScreen` · الصلاحيّة · المدخلُ الجانبيُّ في «المبيعات» · المسار ·
// النطاق · `ScreenConfig` · وتقاريرُ المناديب في مركز التقارير.
//
// شغّله بـ `--dart-define=APP_BRAND=picpos` ليُقاس نطاقُ PicPos الفعليّ.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/core/config/business_profile.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/presentation/shell/screen_breadcrumbs.dart';

void main() {
  const id = ScreenId.repDistribution;

  test('المعرِّفُ و`AppScreen` يحملان الرقمَ نفسَه', () {
    expect(id.navigationIndex, 78);
    expect(AppScreen.repDistribution.value, id.navigationIndex);
  });

  test('الصلاحيّةُ `distribution_view` في الخريطة وفي المدخل الجانبيّ', () {
    expect(screenPermissionMap[id], PermissionCodes.distributionView);
    final item =
        kAllNavItemDefs.where((n) => n.index == id.navigationIndex).toList();
    expect(item, hasLength(1));
    expect(item.single.group, 'sales');
    expect(item.single.permission, screenPermissionMap[id]);
  });

  test('المسارُ «المبيعات ‹ إدارة المناديب والتوزيع»', () {
    final path = resolveScreenPath(id.navigationIndex);
    expect(path, isNotNull);
    expect(path!.label, 'إدارة المناديب والتوزيع');
    expect(path.groupLabel, isNotNull);
  });

  test('النطاقُ: تتبع «التوزيع» وتظهر في PicPos وحدَها', () {
    expect(
        ScreenRegistry.withPicposRepDistribution(
            [ScreenId.loyalty, ScreenId.distribution, ScreenId.hr]),
        [ScreenId.loyalty, ScreenId.distribution, id, ScreenId.hr]);
    if (Brand.isPicPos) {
      expect(ScreenRegistry.forProfile(BusinessProfile.unified), contains(id));
      expect(
          ScreenRegistry.forProfile(BusinessProfile.commercial), contains(id));
      expect(navItemVisibleForBrand(id.navigationIndex), isTrue);
    } else {
      expect(ScreenRegistry.forProfile(BusinessProfile.unified),
          isNot(contains(id)));
      expect(navItemVisibleForBrand(id.navigationIndex), isFalse);
    }
  });

  test('`ScreenConfig` يبني الشاشة', () {
    final src = File('lib/app_main_screen.dart').readAsStringSync();
    expect(src, contains('appScreen: AppScreen.repDistribution'));
    expect(src, contains('const RepDistributionPicPosScreen()'));
  });

  test('تقاريرُ المناديب الأربعة في مركز تقارير PicPos بصلاحيّة', () {
    final hub = File(
            'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart')
        .readAsStringSync();
    expect(hub, contains("id: 'reps'"));
    expect(hub, contains('RepReportKind.values'));
    expect(hub, contains('permission: PermissionCodes.distributionView'));
    final reports = File(
            'lib/presentation/reports_picpos/screens/rep_reports_picpos_screen.dart')
        .readAsStringSync();
    for (final kind in ['rep_summary', 'rep_detail', 'rep_coverage', 'rep_van_stock']) {
      expect(reports, contains("'$kind'"));
    }
    expect(reports, contains('ExcelExportHelper.export'));
  });

  test('الإدارةُ (إنشاء/إسناد) محروسةٌ بـ`distribution_manage`', () {
    final areas = File(
            'lib/presentation/distribution_picpos/screens/dm_areas_tab.dart')
        .readAsStringSync();
    expect(areas, contains('PermissionCodes.distributionManage'));
    final parties = File(
            'lib/presentation/parties_picpos/screens/parties_picpos_screen.dart')
        .readAsStringSync();
    expect(parties, contains('PermissionCodes.distributionManage'));
    final reps = File(
            'lib/presentation/distribution_picpos/screens/dm_reps_tab.dart')
        .readAsStringSync();
    expect(reps, contains('PermissionCodes.inventoryTransfer'));
    expect(reps, contains('PermissionCodes.treasuryTransfer'));
  });
}
