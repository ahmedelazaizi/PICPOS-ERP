// «نوع النشاط التجاري» يحكم ظهورَ الطاولات والمطبخ.
//
// ── العطبُ المقيس (2026-08-15) ─────────────────────────────────────────────
// إعداداتُ PicPos تعرض «نوع النشاط التجاري» وفيه خيارٌ نصُّه حرفياً
// **«مطعم (طاولات وصالات)»** — واختيارُه لا يُظهر طاولةً ولا صالة.
// و`IndustryModeNotifier.setMode` يكتب مفتاحاً اسمُه `industry_mode` منفصلاً
// تماماً عن `business_profile`، وقارئوه ثلاثةٌ فقط: استراتيجيّةُ صناعة،
// وحقلُ الباركود، **ورأسُ شاشة UralCash** — لا PicPos.
//
// وهي نفسُ فئةِ عطبِ شريحة «حسب الكاشير»: ضابطٌ يَعِد ولا يفي.
//
// ── وقرارُ المالك (2026-08-15) ─────────────────────────────────────────────
// وصلُ الضابط القائم لا إضافةُ مفتاحٍ ثانٍ بجواره: «ضابطان لشيءٍ واحدٍ
// يربكان من يقرؤهما بعد شهر». فلا رايةَ منفصلةً في الإعدادات.
//
// ── ولماذا لا يُبدَّل البروفايلُ كلُّه ───────────────────────────────────
// `IndustryMode` أربعةُ خيارات وليست `BusinessProfile`. وتبديلُ البروفايل إلى
// `restaurant` يقفز بالتشكيلة من ٢٠ شاشةً إلى ٢٦ فيُدخل التحليلاتِ والفوترةَ
// الإلكترونيةَ وتقاريرَ الضرائب وشاشةَ الأدوار — أثرٌ أوسعُ كثيراً مما طُلب.
// فالوصلُ يمسّ **رايةَ الطاولات وحدَها**.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/feature_key.dart';
import 'package:ural_erp/core/config/industry_tables_policy.dart';

void main() {
  // ── حقنُ التجاوز ────────────────────────────────────────────────────────
  //
  // ⚠️ الفرعُ في `featureFlagsProvider` خلف `Brand.isPicPos`، وهو ثابتُ
  // ترجمةٍ افتراضُه `uralcash` — فالبوابةُ كلُّها ما كانت لتقيسه. فالعلامةُ
  // تُمرَّر معاملاً صريحاً، كما عولجت نفسُ المسألة في `ScreenRegistry.
  // litePicpos` و`FeaturePolicy.litePicpos`.
  group('حقنُ رايةِ الطاولات في خريطة التجاوزات', () {
    test('PicPos + مطعم ⇒ الرايةُ مشتعلة', () {
      expect(
        withIndustryTablesOverride(const {}, 'restaurant', isPicPos: true),
        containsPair(FeatureKey.posTables, true),
      );
    });

    test('PicPos + سوبرماركت ⇒ مطفأةٌ صراحةً لا محذوفة', () {
      // الحذفُ يترك رايةَ البروفايل سارية؛ والإطفاءُ الصريحُ يحسم.
      expect(
        withIndustryTablesOverride(const {}, 'supermarket', isPicPos: true),
        containsPair(FeatureKey.posTables, false),
      );
    });

    test('UralCash لا يُمَسّ مهما كان النشاط', () {
      expect(
        withIndustryTablesOverride(const {}, 'restaurant', isPicPos: false),
        isNot(contains(FeatureKey.posTables)),
      );
    });

    test('ولا تُمسح تجاوزاتٌ أخرى', () {
      final out = withIndustryTablesOverride(
        const {FeatureKey.enterpriseHr: true},
        'restaurant',
        isPicPos: true,
      );
      expect(out, containsPair(FeatureKey.enterpriseHr, true));
    });

    test('والخريطةُ الأصليّةُ لا تُعدَّل في مكانها', () {
      // `ref.watch` يرجع الحالةَ نفسَها — تعديلُها في مكانها يفسدها للجميع.
      const base = <FeatureKey, bool>{};
      withIndustryTablesOverride(base, 'restaurant', isPicPos: true);
      expect(base, isEmpty);
    });
  });

  group('الأنشطةُ التي لها طاولات', () {
    test('مطعم', () {
      expect(industryImpliesTables('restaurant'), isTrue);
    });

    test('وكافيه — «طاولات وصالات» في تسميته أيضاً', () {
      expect(industryImpliesTables('cafe'), isTrue);
    });
  });

  group('والأنشطةُ التي لا طاولاتَ لها', () {
    test('سوبرماركت', () {
      expect(industryImpliesTables('supermarket'), isFalse);
    });

    test('وتجزئة', () {
      expect(industryImpliesTables('retail'), isFalse);
    });
  });

  group('المدخلاتُ الغائبةُ والتالفة', () {
    test('غيرُ مضبوطٍ = لا طاولات — الافتراضيُّ يُطفئ', () {
      // تنصيبةٌ لم تُفتح فيها الشاشةُ قطّ: لا تُفاجَأ بشاشتَي مطاعم.
      expect(industryImpliesTables(null), isFalse);
      expect(industryImpliesTables(''), isFalse);
    });

    test('وقيمةٌ مجهولةٌ تُقرأ إطفاءً لا إشعالاً', () {
      // الفشلُ يُقفِل — نفسُ قاعدة `resolveAllowedPaymentMethods`.
      expect(industryImpliesTables('bakery'), isFalse);
    });

    test('ويتحمّل الفراغَ وحالةَ الأحرف', () {
      // القيمةُ تُكتب من `mode.name` فهي نظيفةٌ اليوم، لكنّ قاعدةً منقولةً
      // يدوياً أو مُرحَّلةً قد تصل بغير ذلك.
      expect(industryImpliesTables('  restaurant  '), isTrue);
      expect(industryImpliesTables('Restaurant'), isTrue);
    });
  });
}
