// test/unit/financial_statements_screen_wiring_test.dart
//
// حارسُ توصيلِ «القوائم المالية» — **ستّةُ مواضعَ لا خمسة**.
//
// ⚠️ الدرسُ الذي أوجب هذا الشكل: شاشةُ الحجوزات كانت مبنيّةً ومسجَّلةً في
// `screenPermissionMap` وفي النطاق وفي `ScreenConfig` — وكلُّ الحرّاس خضراء —
// **وهي غائبةٌ عن القائمة الجانبيّة**، لأنّ `kAllNavItemDefs` مصدرٌ سادسٌ
// مستقلٌّ لا يُشتقّ من الخمسة قبله. فحارسٌ يقيس خمسةً يُعطي طمأنينةً كاذبة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';

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

    test('٦) ✅ وتعريفُ المدخل **سُحب** — والصلاحيةُ باقيةٌ كما هي', () {
      // كان هنا: «تعريفُ مدخلِها باقٍ بنفس كود الصلاحية» — وهو المصدرُ
      // السادسُ الذي غاب عن الحجوزات.
      //
      // ✅ **وسُحب 2026-09-20 بأمر المالك**: بابُها التقارير وحدَها.
      //
      // ⚠️ **والسحبُ يمسّ المدخلَ لا الصلاحية**: الشاشةُ ما زالت ممنوحةً
      //    في `screenPermissionMap` وفي نطاق `unified`، ولها `ScreenConfig`
      //    يبنيها. فمن مُنحت له يفتحها من التقارير، ومن لم تُمنَح له
      //    يُرفَض — كما كان.
      final item = kAllNavItemDefs
          .where((n) => n.index == ScreenId.financialStatements.navigationIndex)
          .toList();
      expect(item, isEmpty, reason: 'عاد المدخلُ الجانبيُّ إلى الشريط');

      expect(screenPermissionMap[ScreenId.financialStatements], 'reports_view',
          reason: 'سحبُ المدخل لا يمسّ الصلاحيةَ — وإلّا فُتحت أو أُغلقت '
              'الشاشةُ على من لا يُقصَد');
    });

    test('٧) ✅ وفي PicPos **لا مدخلَ لها** — بابُها التقارير', () {
      // ═══ ثلاثةُ قراراتٍ متتاليةٍ — والأحدثُ يحكم ═══
      //
      // 2026-08-23: نُقلت من التقارير إلى مجموعة الحسابات.
      // 2026-08-27: صارت شريحةً ثامنةً في الحاوية (`fs`).
      // **2026-09-20: الحاويةُ حُذفت، والمدخلُ سُحِب — بابٌ
      //   واحدٌ في التقارير.**
      //
      // 🔴 **والسببُ أنَّ ثلاثةَ أبوابٍ لشاشةٍ واحدة تفترق**:
      //    كلُّ بابٍ يمرِّر مُعامِلاتٍ غيرَ مُعامِلات أخيه (`view`
      //    و`initialTabIndex`)، فيرى المستخدمُ شاشتين مختلفتين باسمٍ
      //    واحد ويظنُّ إحداهما معطوبة.
      final item = kAllNavItemDefs.where(
          (i) => i.index == ScreenId.financialStatements.navigationIndex);
      expect(item, isEmpty,
          reason: 'عاد المدخلُ الجانبيُّ — والقرارُ بابٌ واحدٌ في '
              'التقارير');

      // ⚠️ **و`ScreenConfig` يبقى**: الشاشةُ ممنوحةٌ وفي النطاق،
      //    و`allowed_screens_can_render_test` يشترط لها بنّاءً. سحبُ
      //    المدخل يمسّ البابَ لا الشاشة.
      expect(AppScreen.financialStatements.value,
          ScreenId.financialStatements.navigationIndex);
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
