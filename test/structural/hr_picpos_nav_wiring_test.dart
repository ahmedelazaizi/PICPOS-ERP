// J4 — «الموارد البشرية» في PicPos موصولةٌ في كلّ موضع: المعرِّفان ·
// `AppScreen` · الصلاحيّة · المداخلُ الجانبيّةُ في مجموعة `hr` · المسار ·
// النطاق · `ScreenConfig` · الإخفاءُ في وضع العميل — وUralCash كما كان.
//
// شغّله بـ `--dart-define=APP_BRAND=picpos` ليُقاس نطاقُ PicPos الفعليّ.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/presentation/shell/screen_breadcrumbs.dart';

void main() {
  const screens = {
    ScreenId.hrEmployees: (79, AppScreen.hrEmployees, 'سجل الموظفين'),
    ScreenId.hrOrganization: (
      80,
      AppScreen.hrOrganization,
      'الأقسام والمسميات الوظيفية',
    ),
  };

  test('المعرِّفان و`AppScreen` يحملان الرقمَ نفسَه', () {
    for (final e in screens.entries) {
      expect(e.key.navigationIndex, e.value.$1);
      expect(e.value.$2.value, e.key.navigationIndex);
    }
  });

  test('الصلاحيّةُ `hr_view` في الخريطة وفي المدخل الجانبيّ بمجموعة hr', () {
    for (final e in screens.entries) {
      expect(screenPermissionMap[e.key], PermissionCodes.hrView);
      final item = kAllNavItemDefs
          .where((n) => n.index == e.key.navigationIndex)
          .toList();
      expect(item, hasLength(1));
      expect(item.single.group, 'hr');
      expect(item.single.label, e.value.$3);
      expect(item.single.permission, screenPermissionMap[e.key]);
      final path = resolveScreenPath(e.key.navigationIndex);
      expect(path, isNotNull);
      expect(path!.label, e.value.$3);
    }
    final hr = kNavGroupDefs.firstWhere((g) => g.key == 'hr');
    expect(hr.label, 'الموارد البشرية');
  });

  test('النطاقُ: تحلّ محلَّ شاشة الموارد البشريّة القديمة حيث تكون', () {
    // J4 (الجزء ٣) — الرواتبُ نُقلت إلى المسيّرات، فلا تبقى `hr` في PicPos.
    expect(
      ScreenRegistry.withPicposHr([
        ScreenId.loyalty,
        ScreenId.hr,
        ScreenId.treasury,
      ]),
      [
        ScreenId.loyalty,
        ScreenId.hrEmployees,
        ScreenId.hrOrganization,
        ScreenId.hrAttendance,
        ScreenId.hrLeave,
        ScreenId.hrShifts,
        ScreenId.hrPayroll,
        ScreenId.hrAdvances,
        ScreenId.hrCommissions,
        ScreenId.treasury,
      ],
    );
    expect(
      ScreenRegistry.withPicposHr([ScreenId.pos]),
      [ScreenId.pos],
      reason: 'a scope without HR (hrEnabled off) gets no HR screen',
    );
  });

  test(
    'PicPos تُظهرها وتُخفي «الحضور والرواتب» القديمة؛ وUralCash كما كان',
    () {
      final legacy = kAllNavItemDefs.singleWhere((i) => i.index == 16);
      if (Brand.isPicPos) {
        for (final id in screens.keys) {
          expect(navItemVisibleForBrand(id.navigationIndex), isTrue);
          expect(
            ScreenRegistry.forProfile(BusinessProfile.unified),
            contains(id),
          );
        }
        expect(legacy.label, kPicPosLegacyHrLabel);
        expect(legacy.group, 'hr');
        final hrItems = [
          for (final i in kAllNavItemDefs)
            if (i.group == 'hr') i.index,
        ];
        expect(hrItems, [79, 80, 81, 82, 83, 84, 85, 86, 16]);
        // J4 (الجزء ٣) — المدخلُ والنطاقُ كلاهما بلا الشاشة القديمة.
        expect(navItemVisibleForBrand(16), isFalse);
        expect(
          ScreenRegistry.forProfile(BusinessProfile.unified),
          isNot(contains(ScreenId.hr)),
        );
      } else {
        for (final id in screens.keys) {
          expect(navItemVisibleForBrand(id.navigationIndex), isFalse);
          expect(
            ScreenRegistry.forProfile(BusinessProfile.unified),
            isNot(contains(id)),
          );
        }
        expect(legacy.label, 'الموظفين');
        expect(legacy.section, 'الموارد البشرية');
        expect(navItemVisibleForBrand(16), isTrue);
        // The only visible HR entry in UralCash is the legacy screen.
        expect(
          [
            for (final i in kAllNavItemDefs)
              if (i.group == 'hr' && navItemVisibleForBrand(i.index)) i.index,
          ],
          [16],
        );
      }
      expect(screenPermissionMap[ScreenId.hr], PermissionCodes.hrView);
    },
  );

  test('`ScreenConfig` يبنيهما خلف كلمةِ سرّ HR، ويُخفيهما وضعُ العميل', () {
    final src = readLibrarySource('lib/app_main_screen.dart');
    expect(src, contains('appScreen: AppScreen.hrEmployees'));
    expect(src, contains('const HrEmployeesPicPosScreen()'));
    expect(src, contains('appScreen: AppScreen.hrOrganization'));
    expect(src, contains('const HrOrganizationPicPosScreen()'));
    final hidden = RegExp(
      r'clientHiddenScreens = <AppScreen>\{([^}]*)\}',
    ).firstMatch(src)!.group(1)!;
    expect(hidden, contains('AppScreen.hrEmployees'));
    expect(hidden, contains('AppScreen.hrOrganization'));
    expect(hidden, contains('AppScreen.hr,'));
  });

  test(
    'الإدارةُ محروسةٌ بـ`hr_manage` وإدارةُ المستخدمين بـ`users_manage`',
    () {
      String read(String f) =>
          File('lib/presentation/hr_picpos/screens/$f').readAsStringSync();
      expect(
        read('hr_employee_file_screen.dart'),
        contains('PermissionCodes.hrManage'),
      );
      expect(
        read('hr_employees_picpos_screen.dart'),
        contains('PermissionCodes.hrManage'),
      );
      expect(
        read('hr_organization_picpos_screen.dart'),
        contains('PermissionCodes.hrManage'),
      );
      final roles = read('ef_roles_tab.dart');
      expect(roles, contains('PermissionCodes.usersManage'));
      expect(
        roles,
        contains('authRepositoryProvider'),
        reason: 'users are created through the existing auth repository',
      );
      expect(
        read('ef_rep_panel.dart'),
        contains('PermissionCodes.distributionManage'),
      );
    },
  );
}
