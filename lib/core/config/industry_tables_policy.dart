// «نوع النشاط التجاري» ⇒ هل تظهر الطاولاتُ والمطبخ؟
//
// ── العطبُ الذي يسدّه هذا الملفّ (مقيسٌ 2026-08-15) ────────────────────────
// إعداداتُ PicPos تعرض «نوع النشاط التجاري» وفيه خيارٌ نصُّه حرفياً «مطعم
// (طاولات وصالات)» — واختيارُه **لا يُظهر طاولةً ولا صالة**.
// `IndustryModeNotifier.setMode` يكتب `industry_mode` وحدَه، وهو منفصلٌ تماماً
// عن `business_profile` وعن `FeaturePolicy`؛ وقارئوه ثلاثةٌ لا رابعَ لهم:
// استراتيجيّةُ الصناعة، وحقلُ الباركود، ورأسُ شاشة **UralCash**.
//
// فالضابطُ كان يَعِد ولا يفي — نفسُ فئةِ عطبِ شريحة «حسب الكاشير» في §٤.
//
// ── قرارُ المالك 2026-08-15 ────────────────────────────────────────────────
// وصلُ الضابط القائم، لا مفتاحٌ ثانٍ بجواره. فهذه الدالّةُ هي الوصلة، وهي
// **خالصةٌ** كي تُقاس بلا قاعدةٍ ولا ودجت.
//
// ⚠️ ولا تُبدّل البروفايلَ: `IndustryMode` أربعةُ خيارات وليست
// `BusinessProfile`. التبديلُ إلى `restaurant` يقفز بالتشكيلة من ٢٠ شاشةً إلى
// ٢٦ فيُدخل التحليلاتِ والفوترةَ الإلكترونيةَ وتقاريرَ الضرائب وشاشةَ
// الأدوار — أثرٌ أوسعُ كثيراً مما طُلب. المسموسُ هنا رايةُ الطاولات وحدَها.

import 'feature_key.dart';

/// مفتاحُ الإعداد الذي يحمل «نوع النشاط التجاري».
///
/// ⚠️ لا بدّ أن يكون في `preloadKeys` بـ`main.dart`: القراءةُ متزامنةٌ عبر
/// `SettingsRepositoryCached.get`، وهي ترجع `null` عند إخفاق الكاش بنفس ما
/// ترجعه عند غياب المفتاح — فمفتاحٌ خارجَ التحميل يُقرأ `null` **دائماً**.
/// محروسٌ في `test/unit/industry_mode_preloaded_test.dart`.
const String industryModeSettingKey = 'industry_mode';

/// أنشطةٌ تُدار بالطاولات — وتسميتاهما في الشاشة تقولان ذلك صراحةً
/// («مطعم (طاولات وصالات)» · «كافيه / كوفي شوب»).
const Set<String> _tableServiceIndustries = <String>{'restaurant', 'cafe'};

/// هل يستلزم [industryModeName] إظهارَ الطاولات والمطبخ؟
///
/// [industryModeName] قيمةُ الإعداد `industry_mode` كما تُخزَّن (`mode.name`).
///
/// ⚠️ الغائبُ والمجهولُ يُقرآن **إطفاءً** لا إشعالاً: تنصيبةٌ لم تُضبط بعد
/// لا يصحّ أن تُفاجأ بشاشتَي مطاعمَ لا تحتاجهما، وقيمةٌ تالفةٌ لا يصحّ أن
/// تفتح سطحاً. نفسُ قاعدة «الفشلُ يُقفِل» في `resolveAllowedPaymentMethods`.
bool industryImpliesTables(String? industryModeName) {
  if (industryModeName == null) return false;
  return _tableServiceIndustries.contains(industryModeName.trim().toLowerCase());
}

/// يحقن رايةَ الطاولات في خريطة التجاوزات بحسب «نوع النشاط».
///
/// ⚠️ **دالّةٌ مستقلّةٌ لا سطرٌ داخل `featureFlagsProvider`**: الفرعُ هناك خلف
/// `Brand.isPicPos`، وهو ثابتُ ترجمةٍ افتراضُه `uralcash` — فالبوابةُ كلُّها
/// تشتغل على فرع UralCash ولم تكن لتقيسه أصلاً. تمريرُ [isPicPos] معاملاً
/// صريحاً يجعله مقيساً. نفسُ علاج `ScreenRegistry.litePicpos` و
/// `FeaturePolicy.litePicpos`.
///
/// ويرجع **نسخةً**: [base] هي حالةُ `featureOverridesProvider` نفسُها،
/// وتعديلُها في مكانها يفسدها لكلّ قارئ.
///
/// والإطفاءُ **صريحٌ** لا حذف: حذفُ المفتاح يترك رايةَ البروفايل سارية، بينما
/// المقصودُ أن «نوع النشاط» هو الحاكم.
Map<FeatureKey, bool> withIndustryTablesOverride(
  Map<FeatureKey, bool> base,
  String? industryModeName, {
  required bool isPicPos,
}) {
  if (!isPicPos) return base;
  return {
    ...base,
    FeatureKey.posTables: industryImpliesTables(industryModeName),
  };
}
