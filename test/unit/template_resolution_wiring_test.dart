// test/unit/template_resolution_wiring_test.dart
//
// حارسُ توصيل شاشة حسم القوالب — **ستّةُ** مواضعَ لا خمسة.
//
// ⚠️ والسادسُ (`kAllNavItemDefs`) مصدرٌ مستقلٌّ لا يُشتقّ من الخمسة: شاشةٌ
// صحيحةٌ في `ScreenId` و`AppScreen` وخريطةِ الصلاحيات والنطاقِ و`ScreenConfig`
// تبقى **غائبةً عن القائمة الجانبيّة** بلا سطرٍ فيه. وقع فعلاً مع الحجوزات
// 2026-08-22 وكلُّ الحرّاس خضراء.
//
// ⚠️ **والنطاقُ يُرشِّح قبل الصلاحية**: `userAllowedScreensProvider` يحذف ما
// ليس في `flavorAllowedScreenIds` **ثمّ** يفحص الكود — فما سقط من نطاقٍ لا
// يُبلَغ حتى بتجاوزِ مدير النظام.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

void main() {
  group('الشاشةُ موصولةٌ في المواضع الستّة', () {
    test('١) لها معرِّفُ شاشةٍ برقمٍ لا يصطدم', () {
      expect(ScreenId.templateResolution.navigationIndex, 64);
      final same = ScreenId.values
          .where((s) =>
              s.navigationIndex ==
              ScreenId.templateResolution.navigationIndex)
          .toList();
      // ⚠️ `ScreenId` فيه مرادفاتٌ **مقصودةٌ** (`scalePlu`/`pluManager` ·
      //    `cycleCounting`/`fieldAudit`)، فالفحصُ على هذا الرقم وحدَه لا
      //    على «لا تكرارَ مطلقاً» — ذاك يُحمِّر على قرارَين صحيحَين.
      expect(same, hasLength(1));
    });

    test('٢) و`AppScreen` يحمل نفسَ الرقم', () {
      expect(AppScreen.templateResolution.value,
          ScreenId.templateResolution.navigationIndex,
          reason: 'رقمان يفترقان = شاشةٌ تُفتَح غيرَ التي أُذن بها');
    });

    test('٣) ولها صلاحيةٌ — القائمةُ `settings_printer` لا كودٌ جديد', () {
      expect(screenPermissionMap[ScreenId.templateResolution],
          PermissionCodes.settingsPrinter);
      expect(PermissionCodes.settingsPrinter, 'settings_printer',
          reason: 'الكودُ نفسُه تغيّر — تُراجَع منحُ الأدوار');
    });

    test('٤) وهي في **كلِّ** نطاقٍ: كلُّ ملفٍّ يطبع', () {
      final scopes = <String, List<ScreenId>>{
        'restaurant': ScreenRegistry.restaurant,
        'cafe': ScreenRegistry.cafe,
        'supermarket': ScreenRegistry.supermarket,
        'supermarketPro': ScreenRegistry.supermarketPro,
        'supermarketPlus': ScreenRegistry.supermarketPlus,
        'commercial': ScreenRegistry.commercial,
        'unified': ScreenRegistry.unified,
        'lite': ScreenRegistry.lite,
        'litePicpos': ScreenRegistry.litePicpos,
        'restaurantPicpos': ScreenRegistry.restaurantPicpos,
      };

      // ضابطٌ على القياس: عشرةُ نطاقاتٍ مرصودةٌ — لا تسعةٌ ولا صفر.
      expect(scopes, hasLength(10));

      scopes.forEach((name, ids) {
        expect(ids, contains(ScreenId.templateResolution),
            reason: 'سقطت من `$name` — والنطاقُ يُرشِّح قبل الصلاحية');
      });
    });

    test('٥) ولها مدخلٌ واحدٌ في القائمة الجانبيّة بنفس كود الصلاحية', () {
      final item = kAllNavItemDefs
          .where((n) => n.index == ScreenId.templateResolution.navigationIndex)
          .toList();
      expect(item, hasLength(1),
          reason: 'المصدرُ السادسُ المستقلُّ — هو الذي غاب عن الحجوزات');
      expect(item.single.permission,
          screenPermissionMap[ScreenId.templateResolution],
          reason: 'مدخلٌ بكودٍ يخالف شاشتَه = رابطٌ ميتٌ أو ثغرة');
      expect(item.single.group, 'system');
    });

    // الموضعُ السادسُ (`ScreenConfig` في `app_main_screen.dart`) يقيسه
    // `test/widget/…_composition_test.dart` ببناء الشاشة فعلاً: استيرادُ
    // `app_main_screen` هنا يجرّ شجرةَ التطبيق كاملةً بقاعدتها.
    test('٦) و`ScreenConfig` مسجَّلٌ لها في `app_main_screen`', () {
      // فحصٌ بنيويٌّ لا سلوكيّ — بناءُ القائمة يتطلّب `Brand` وقاعدةً.
      final src =
          _read('lib/app_main_screen.dart');
      expect(src, contains('appScreen: AppScreen.templateResolution'),
          reason: 'بلا `ScreenConfig` لا شيءَ يُبنى عند اختيار المدخل');
      expect(src, contains('TemplateResolutionPicposScreen()'),
          reason: 'مسجَّلٌ ببانٍ يبني شاشةً أخرى');
    });
  });

  group('ضابط: الحارسُ يمسك غيابَ أيِّ موضع', () {
    test('عددُ النطاقات المفحوصةِ يطابق ما يعلنه السجلّ', () {
      // نطاقٌ جديدٌ يُضاف غداً ولا يُفحَص هنا = شاشةٌ تسقط منه صامتةً.
      final src = _read('lib/core/navigation/screen_registry.dart');
      final declared = RegExp(r'static const List<ScreenId> (\w+)')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, hasLength(10),
          reason: 'قوائمُ النطاقات المعلَنةُ ${declared.toList()..sort()} — '
              'حدِّث الفحصَ أعلاه معها');
    });
  });
}

/// ملفّاتُ المستودع CRLF و`core.autocrlf = true` — فالمقارنةُ تُسوَّى، وإلّا
/// سقطت في أوّل استنساخٍ على منصّةٍ أخرى.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
