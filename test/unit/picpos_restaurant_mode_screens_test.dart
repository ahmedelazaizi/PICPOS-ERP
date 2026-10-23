// «وضعُ المطاعم» يُدخل الطاولاتِ والمطبخَ في تشكيلة PicPos-lite.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «شاشةُ الطاولات وأوامرُ المطاعم والمطبخ يجب أن تظهر في النظام — كما في
// ural ولكن بهوية picpos.» وقرارُه بين ثلاثةِ خيارات: **رايةٌ في الإعدادات**
// مطفأةٌ افتراضياً، لا فتحٌ دائم.
//
// ── الوصلةُ المفقودةُ المقيسة ──────────────────────────────────────────────
// `FeatureOverridesNotifier` يحفظ التجاوزاتِ ببادئة `feature.` ويمرّرها على
// `FeatureValidator`، و`tablesEnabled` رايةٌ قائمةٌ في `FeaturePolicy`.
// لكنّ `ScreenRegistry.forProfile` كان يأخذ **البروفايلَ وحدَه** ولا يقرأ
// الراياتِ إطلاقاً — فإشعالُ الرايةِ يُضيء الميزةَ ولا يُدخل الشاشةَ في
// التنقّل. هذا الملفُّ يقيس الوصلة.
//
// ── ⚠️ ولماذا الشاشتان معاً على `tablesEnabled` لا كلٌّ على رايتِه ────────
// `litePicpos.kitchenEnabled` **صحيحٌ سلفاً** منذ قرار المالك 2026-08-12،
// ومعناه هناك «الإضافاتُ والملاحظاتُ تعمل» (‏`ModifierSelectionDialog`) لا
// «شاشةُ KDS معروضة». فتعليقُ `ScreenId.kitchen` على `kitchenEnabled` كان
// سيُظهر شاشةَ المطبخ لكلّ تنصيبةِ PicPos **اليوم** وبلا أن يطلبها أحد.
// فالرايةُ الحاكمةُ للشاشتَين واحدة: `tablesEnabled` = «وضعُ المطاعم».

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/core/config/feature_policy.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';

void main() {
  group('الرايةُ مطفأة — لا شيءَ يتغيّر', () {
    test('التشكيلةُ هي `litePicpos` بالحرف', () {
      expect(
        ScreenRegistry.litePicposWith(FeaturePolicy.litePicpos),
        equals(ScreenRegistry.litePicpos),
      );
    });

    test('ولا شاشةَ مطبخٍ رغم أن `kitchenEnabled` صحيحٌ سلفاً', () {
      // الضابطُ على العطب الذي كاد يقع: المطبخُ مضاءٌ للإضافات، لا للشاشة.
      expect(FeaturePolicy.litePicpos.kitchenEnabled, isTrue,
          reason: 'لو صار false فقد تغيّر أساسُ هذا الحارس — راجِعه');
      expect(
        ScreenRegistry.litePicposWith(FeaturePolicy.litePicpos),
        isNot(contains(ScreenId.kitchen)),
      );
    });
  });

  group('الرايةُ مشتعلة — الشاشتان تدخلان', () {
    final on = FeaturePolicy.litePicpos.copyWith(tablesEnabled: true);

    test('الطاولاتُ تدخل', () {
      expect(ScreenRegistry.litePicposWith(on), contains(ScreenId.tables));
    });

    test('والمطبخُ معها — رايةٌ واحدةٌ لوضعٍ واحد', () {
      expect(ScreenRegistry.litePicposWith(on), contains(ScreenId.kitchen));
    });

    test('ولا تُفقَد شاشةٌ كانت موجودة', () {
      // الإضافةُ إضافةٌ لا استبدال — نفسُ عقدِ `litePicpos` مع `lite`.
      for (final s in ScreenRegistry.litePicpos) {
        expect(ScreenRegistry.litePicposWith(on), contains(s));
      }
    });

    test('ولا تتكرّر شاشةٌ لو أُشعلت الرايةُ مرّتين', () {
      final out = ScreenRegistry.litePicposWith(on);
      expect(out.length, equals(out.toSet().length));
    });
  });

  group('UralCash لا يُمَسّ', () {
    test('`lite` يبقى بلا طاولاتٍ ولا مطبخ مهما كانت الرايات', () {
      // العقدُ المكتوبُ فوق `litePicpos`: «`lite` الخاصُّ بـUralCash يجب أن
      // يبقى بلا تغييرٍ حرفاً — هذه إضافةٌ مقيَّدةٌ بالعلامة، لا استبدال».
      expect(ScreenRegistry.lite, isNot(contains(ScreenId.tables)));
      expect(ScreenRegistry.lite, isNot(contains(ScreenId.kitchen)));
    });

    test('و`forProfile` بلا رايات يعطي ما كان يعطيه بالضبط', () {
      // التوقيعُ توسّع بمعاملٍ اختياريّ؛ والافتراضيُّ يجب أن يحفظ السلوك.
      for (final p in BusinessProfile.values) {
        expect(
          ScreenRegistry.forProfile(p),
          equals(ScreenRegistry.forProfile(p, features: null)),
        );
      }
    });
  });
}
