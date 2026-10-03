// J4 (الجزء ٢) — «الحضور والانصراف» و«الإجازات» و«الورديات» موصولةٌ في كلّ
// موضع: المعرِّفات · `AppScreen` · الصلاحيّاتُ الخمسُ المبذورة · المداخلُ
// الجانبيّةُ في مجموعة `hr` · المسار · النطاق · `ScreenConfig` · الإخفاءُ في
// وضع العميل · تبويبا ملفّ الموظف — وUralCash كما كان.
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
  const screens = {
    ScreenId.hrAttendance: (
      81,
      AppScreen.hrAttendance,
      'الحضور والانصراف',
      PermissionCodes.hrAttendanceView,
    ),
    ScreenId.hrLeave: (
      82,
      AppScreen.hrLeave,
      'الإجازات',
      PermissionCodes.hrLeaveRequest,
    ),
    ScreenId.hrShifts: (
      83,
      AppScreen.hrShifts,
      'الورديات',
      PermissionCodes.hrShiftsManage,
    ),
  };

  test('المعرِّفاتُ و`AppScreen` بالرقم نفسِه، والصلاحيّةُ في الخريطة والمدخل',
      () {
    for (final e in screens.entries) {
      expect(e.key.navigationIndex, e.value.$1);
      expect(e.value.$2.value, e.key.navigationIndex);
      expect(screenPermissionMap[e.key], e.value.$4);
      final item = kAllNavItemDefs
          .where((n) => n.index == e.key.navigationIndex)
          .toList();
      expect(item, hasLength(1));
      expect(item.single.group, 'hr');
      expect(item.single.label, e.value.$3);
      expect(item.single.permission, e.value.$4);
      expect(resolveScreenPath(e.key.navigationIndex)?.label, e.value.$3);
      expect(kPicPosOnlyNavIndexes, contains(e.value.$1));
    }
  });

  test('الصلاحيّاتُ الخمسُ في القائمة الرئيسة بفئة hr', () {
    final master = {
      for (final p in PermissionCodes.masterList) p['code']: p['category'],
    };
    for (final code in [
      PermissionCodes.hrAttendanceView,
      PermissionCodes.hrAttendanceEdit,
      PermissionCodes.hrLeaveRequest,
      PermissionCodes.hrLeaveApprove,
      PermissionCodes.hrShiftsManage,
    ]) {
      expect(master[code], 'hr', reason: code);
    }
    expect(PermissionCodes.criticalFinancialOps,
        isNot(contains(PermissionCodes.hrLeaveApprove)),
        reason: 'admin receives the new codes through syncAllPermissions');
    final startup =
        File('lib/data/database/database_startup.dart').readAsStringSync();
    expect(startup, contains('backfillHrAttendancePermissionsOnce()'));
    expect(startup, contains('migrateLegacyHrAttendance()'));
  });

  test('PicPos تُظهرها في نطاقها؛ UralCash لا يراها', () {
    for (final id in screens.keys) {
      if (Brand.isPicPos) {
        expect(navItemVisibleForBrand(id.navigationIndex), isTrue);
        expect(ScreenRegistry.forProfile(BusinessProfile.unified), contains(id));
      } else {
        expect(navItemVisibleForBrand(id.navigationIndex), isFalse);
        expect(ScreenRegistry.forProfile(BusinessProfile.unified),
            isNot(contains(id)));
      }
    }
    if (!Brand.isPicPos) {
      expect(
          [
            for (final i in kAllNavItemDefs)
              if (i.group == 'hr' && navItemVisibleForBrand(i.index)) i.index,
          ],
          [16],
          reason: 'UralCash keeps only its legacy HR screen');
    }
  });

  test('`ScreenConfig` خلف كلمةِ سرّ HR، والإخفاءُ في وضع العميل', () {
    final src = File('lib/app_main_screen.dart').readAsStringSync();
    for (final (screen, widget) in [
      ('hrAttendance', 'HrAttendancePicPosScreen'),
      ('hrLeave', 'HrLeavePicPosScreen'),
      ('hrShifts', 'HrShiftsPicPosScreen'),
    ]) {
      expect(src, contains('appScreen: AppScreen.$screen,'));
      expect(src, contains('const $widget()'));
    }
    final hidden = RegExp(r'clientHiddenScreens = <AppScreen>\{([^}]*)\}')
        .firstMatch(src)!
        .group(1)!;
    for (final s in ['hrAttendance', 'hrLeave', 'hrShifts']) {
      expect(hidden, contains('AppScreen.$s'));
    }
  });

  test('الحراسةُ بالصلاحيّات، وملفُّ الموظف يحمل تبويبَي الحضور والإجازات', () {
    String read(String f) =>
        File('lib/presentation/hr_picpos/$f').readAsStringSync();
    expect(read('widgets/attendance_board_view.dart'),
        contains('PermissionCodes.hrAttendanceEdit'));
    expect(read('widgets/hr_holidays_view.dart'),
        contains('PermissionCodes.hrAttendanceEdit'));
    final requests = read('widgets/leave_requests_view.dart');
    expect(requests, contains('PermissionCodes.hrLeaveApprove'));
    expect(requests, contains('PermissionCodes.hrLeaveRequest'));
    expect(read('widgets/leave_types_view.dart'),
        contains('PermissionCodes.hrLeaveApprove'));
    expect(read('screens/hr_shifts_picpos_screen.dart'),
        contains('PermissionCodes.hrShiftsManage'));
    final file = read('screens/hr_employee_file_screen.dart');
    expect(file, contains('EfAttendanceTab('));
    expect(file, contains('EfLeaveTab('));
    expect(file, contains("subtitle: source == null ? tr('ملف الموظف') : null"),
        reason: 'the composite «code · title · department» line is no longer '
            'handed to the header (which passes its subtitle to tr())');
  });
}
