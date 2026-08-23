// test/unit/financial_statements_screen_wiring_test.dart
//
// حارسُ توصيلِ «القوائم المالية» — **ستّةُ مواضعَ لا خمسة**.
//
// ⚠️ الدرسُ الذي أوجب هذا الشكل: شاشةُ الحجوزات كانت مبنيّةً ومسجَّلةً في
// `screenPermissionMap` وفي النطاق وفي `ScreenConfig` — وكلُّ الحرّاس خضراء —
// **وهي غائبةٌ عن القائمة الجانبيّة**، لأنّ `kAllNavItemDefs` مصدرٌ سادسٌ
// مستقلٌّ لا يُشتقّ من الخمسة قبله. فحارسٌ يقيس خمسةً يُعطي طمأنينةً كاذبة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

void main() {
  group('القوائمُ المالية موصولةٌ في المواضع الستّة', () {
    test('١) لها معرِّفُ شاشة', () {
      expect(ScreenId.financialStatements.navigationIndex, 62);
    });

    test('٢) و`AppScreen` يحمل نفسَ الرقم', () {
      expect(AppScreen.financialStatements.value,
          ScreenId.financialStatements.navigationIndex,
          reason: 'رقمان يفترقان = شاشةٌ تُفتَح غيرَ التي أُذن بها');
    });

    test('٣) ولها صلاحيةٌ في `screenPermissionMap`', () {
      expect(screenPermissionMap[ScreenId.financialStatements], isNotNull);
      // ⚠️ `reports_view` عن قصد: هو ما يحرسها اليومَ عبر شاشة التقارير،
      //    فالنقلُ إعادةُ تصنيفٍ لا إعادةُ تصريح. وتبديلُه يغيّر مَن يرى
      //    القوائمَ المالية صامتاً.
      expect(screenPermissionMap[ScreenId.financialStatements], 'reports_view');
    });

    test('٤) وهي في نطاق `unified` — حيث تعيش الدورةُ المحاسبيّة', () {
      expect(ScreenRegistry.unified,
          contains(ScreenId.financialStatements),
          reason: 'النطاقُ يُرشِّح **قبل** فحصِ الصلاحية، فما ليس فيه يسقط '
              'حتى مع تجاوزِ مدير النظام');
    });

    test('٥) ومعها أخواتُها المحاسبيّة في نفس النطاق', () {
      // تُقاس معها كي لا يُنقل أحدُها لاحقاً فيفترق البيتُ المحاسبيّ.
      expect(ScreenRegistry.unified, contains(ScreenId.chartOfAccounts));
      expect(ScreenRegistry.unified, contains(ScreenId.generalLedger));
    });

    test('٦) ولها مدخلٌ في القائمة الجانبيّة بنفس كود الصلاحية', () {
      final item = kAllNavItemDefs
          .where((n) => n.index == ScreenId.financialStatements.navigationIndex)
          .toList();
      expect(item, hasLength(1),
          reason: 'هذا هو المصدرُ السادسُ الذي غاب عن الحجوزات');
      expect(item.single.permission,
          screenPermissionMap[ScreenId.financialStatements],
          reason: 'مدخلٌ بكودٍ يخالف الشاشةَ = رابطٌ ميتٌ أو ثغرةٌ مفتوحة');
      expect(item.single.group, 'accounting',
          reason: 'قرارُ المالك 2026-08-23: مكانُها مجموعةُ الحسابات');
    });
  });

  test('ورقمُها لا يصطدم برقمٍ آخر', () {
    final same = ScreenId.values
        .where((s) =>
            s.navigationIndex == ScreenId.financialStatements.navigationIndex)
        .toList();
    expect(same, hasLength(1),
        reason: 'التكرارُ مقصودٌ في المرادفات الموثَّقة وحدَها');
  });
}
