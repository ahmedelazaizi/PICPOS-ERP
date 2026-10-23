// J4 (الجزء ٣) — «الرواتب» و«السلف والجزاءات» و«عمولات المندوبين» موصولةٌ في
// كلّ موضع: المعرِّفات · `AppScreen` · الصلاحيّاتُ الستُّ المبذورة · المداخلُ
// الجانبيّةُ في مجموعة `hr` · المسار · النطاق · `ScreenConfig` · الإخفاءُ في
// وضع العميل · تبويبُ ملفّ الموظف · إخفاءُ «الحضور والرواتب» القديمة في
// PicPos — وUralCash كما كان.
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
    ScreenId.hrPayroll: (84, AppScreen.hrPayroll, 'الرواتب'),
    ScreenId.hrAdvances: (85, AppScreen.hrAdvances, 'السلف والجزاءات'),
    ScreenId.hrCommissions: (86, AppScreen.hrCommissions, 'عمولات المندوبين'),
  };

  test(
    'المعرِّفاتُ و`AppScreen` بالرقم نفسِه، والصلاحيّةُ في الخريطة والمدخل',
    () {
      for (final e in screens.entries) {
        expect(e.key.navigationIndex, e.value.$1);
        expect(e.value.$2.value, e.key.navigationIndex);
        expect(screenPermissionMap[e.key], PermissionCodes.hrPayrollView);
        final item = kAllNavItemDefs
            .where((n) => n.index == e.key.navigationIndex)
            .toList();
        expect(item, hasLength(1));
        expect(item.single.group, 'hr');
        expect(item.single.label, e.value.$3);
        expect(item.single.permission, PermissionCodes.hrPayrollView);
        expect(resolveScreenPath(e.key.navigationIndex)?.label, e.value.$3);
        expect(kPicPosOnlyNavIndexes, contains(e.value.$1));
      }
    },
  );

  test('الصلاحيّاتُ الستُّ في القائمة الرئيسة بفئة hr وفي شاشة الأدوار', () {
    final master = {
      for (final p in PermissionCodes.masterList) p['code']: p['category'],
    };
    final categories = File(
      'lib/presentation/screens/role_management/data/permission_categories.dart',
    ).readAsStringSync();
    for (final code in [
      PermissionCodes.hrPayrollView,
      PermissionCodes.hrPayrollEdit,
      PermissionCodes.hrPayrollApprove,
      PermissionCodes.hrPayrollPost,
      PermissionCodes.hrAdvancesManage,
      PermissionCodes.hrCommissionsManage,
    ]) {
      expect(master[code], 'hr', reason: code);
      expect(categories, contains("'$code'"), reason: code);
    }
    final startup = File(
      'lib/data/database/database_startup.dart',
    ).readAsStringSync();
    expect(startup, contains('backfillHrPayrollPermissionsOnce()'));
    expect(startup, contains('migrateLegacyPayroll()'));
    expect(startup, contains('ensureHrPayrollSchema()'));
  });

  test(
    'PicPos تُظهرها بدل «الحضور والرواتب»؛ UralCash لا يراها ويُبقي القديمة',
    () {
      for (final id in screens.keys) {
        if (Brand.isPicPos) {
          expect(navItemVisibleForBrand(id.navigationIndex), isTrue);
          expect(
            ScreenRegistry.forProfile(BusinessProfile.unified),
            contains(id),
          );
        } else {
          expect(navItemVisibleForBrand(id.navigationIndex), isFalse);
          expect(
            ScreenRegistry.forProfile(BusinessProfile.unified),
            isNot(contains(id)),
          );
        }
      }
      if (Brand.isPicPos) {
        expect(navItemVisibleForBrand(ScreenId.hr.navigationIndex), isFalse);
        expect(kPicPosReplacedNavIndexes, contains(16));
      } else {
        expect(
          navItemVisibleForBrand(16),
          isTrue,
          reason: 'UralCash keeps its legacy HR / payroll screen',
        );
        expect(
          ScreenRegistry.forProfile(BusinessProfile.unified),
          contains(ScreenId.hr),
        );
      }
    },
  );

  test('`ScreenConfig` خلف كلمةِ سرّ HR، والإخفاءُ في وضع العميل', () {
    final src = readLibrarySource('lib/app_main_screen.dart');
    for (final (screen, widget) in [
      ('hrPayroll', 'HrPayrollPicPosScreen'),
      ('hrAdvances', 'HrAdvancesPicPosScreen'),
      ('hrCommissions', 'HrCommissionsPicPosScreen'),
    ]) {
      expect(src, contains('appScreen: AppScreen.$screen,'));
      expect(src, contains('const $widget()'));
    }
    final hidden = RegExp(
      r'clientHiddenScreens = <AppScreen>\{([^}]*)\}',
    ).firstMatch(src)!.group(1)!;
    for (final s in ['hrPayroll', 'hrAdvances', 'hrCommissions']) {
      expect(hidden, contains('AppScreen.$s'));
    }
  });

  test(
    'الحراسةُ بالصلاحيّات في الواجهة، وملفُّ الموظف يحمل تبويبَ الرواتب',
    () {
      String read(String f) =>
          File('lib/presentation/hr_picpos/$f').readAsStringSync();
      final run = read('screens/payroll_run_screen.dart');
      for (final code in [
        'PermissionCodes.hrPayrollEdit',
        'PermissionCodes.hrPayrollApprove',
        'PermissionCodes.hrPayrollPost',
      ]) {
        expect(run, contains(code));
      }
      expect(
        read('widgets/advances_view.dart'),
        contains('PermissionCodes.hrAdvancesManage'),
      );
      expect(
        read('widgets/commission_plans_view.dart'),
        contains('PermissionCodes.hrCommissionsManage'),
      );
      expect(
        read('widgets/payroll_adjustments_view.dart'),
        contains('PermissionCodes.hrPayrollApprove'),
      );
      expect(
        read('widgets/payroll_rules_view.dart'),
        contains('PermissionCodes.hrPayrollEdit'),
      );
      expect(
        read('screens/hr_employee_file_screen.dart'),
        contains('EfPayrollTab('),
      );
      // The DAO enforces the same codes (the UI is not the only gate).
      final dao = [
        'hr_payroll_dao.dart',
        'hr_payroll_posting_dao.dart',
        'hr_advances_dao.dart',
        'hr_commission_dao.dart',
      ].map((f) => File('lib/data/database/daos/$f').readAsStringSync()).join();
      for (final code in [
        'PermissionCodes.hrPayrollEdit',
        'PermissionCodes.hrPayrollApprove',
        'PermissionCodes.hrPayrollPost',
        'PermissionCodes.hrAdvancesManage',
        'PermissionCodes.hrCommissionsManage',
      ]) {
        expect(dao, contains(code));
      }
    },
  );

  test('UralCash: الشاشةُ القديمة وتبويباتُها لم تُمسّ', () {
    final src = readLibrarySource('lib/app_main_screen.dart');
    expect(src, contains('child: const HRScreen()'));
    expect(
      src,
      contains(
        "label: Brand.isPicPos ? tr('الحضور والرواتب') : tr('الموظفين')",
      ),
    );
  });
}
