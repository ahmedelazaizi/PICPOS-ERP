// أنواعُ قيود الأصل الثابت — **قائمةٌ واحدةٌ يقرؤها مَن يعرض ومَن يحرس**.
//
// ═══ لماذا قائمةٌ معلَنة ═══
//
// تبويبةُ «الحركات» في بطاقة الأصل (تصميمُ المالك `(9)`) مشتقّةٌ من القيود
// بـ`referenceId = asset.id`. و`referenceId` رقمٌ **مشتركٌ بين كلّ الجداول**:
// قيدُ فاتورةٍ رقمُها يساوي رقمَ الأصل يحمل نفسَ الرقم. فالترشيحُ بالرقم
// وحدَه يُدخل في بطاقةِ أصلٍ قيوداً لا تخصّه — وهي تبدو حركاتِه تماماً.
//
// ⇒ فالترشيحُ بالرقم **والنوع** معاً، والأنواعُ هنا.
//
// ═══ ⚠️ وإضافةُ نوعٍ في المحرّك تُضاف هنا ═══
//
// `fixed_assets_dao_ext.dart` هو الذي يكتب هذه الأنواع. ونوعٌ جديدٌ يُكتَب
// هناك ولا يُذكَر هنا يعني حركةً تقع على الأصل **ولا تظهر في بطاقته** —
// ولا شيءَ يبدو معطوباً: التبويبةُ تعمل وتعرض ما تعرف. ولذلك يقيس حارسٌ
// بنيويٌّ أنّ كلَّ `referenceType` يكتبه ذلك الملفُّ موجودٌ في هذه القائمة.
library;

/// اقتناءُ الأصل — `createFixedAsset`.
const String kAssetJeAcquisition = 'fixed_asset';

/// قسطُ الإهلاك الشهريّ — `runMonthlyDepreciation`.
const String kAssetJeDepreciation = 'asset_depreciation';

/// الاستبعادُ أو البيع — `disposeAsset`.
const String kAssetJeDisposal = 'fixed_asset_disposal';

/// النقلُ بين مراكز التكلفة — `transferAsset`.
const String kAssetJeTransfer = 'asset_transfer';

/// إعادةُ التقييم — `revalueAsset`.
const String kAssetJeRevaluation = 'asset_revaluation';

const List<String> kAssetJeReferenceTypes = [
  kAssetJeAcquisition,
  kAssetJeDepreciation,
  kAssetJeDisposal,
  kAssetJeTransfer,
  kAssetJeRevaluation,
];

/// ما يُقرأ على صفّ الحركة.
String assetMovementLabel(String? referenceType) => switch (referenceType) {
      kAssetJeAcquisition => 'اقتناء',
      kAssetJeDepreciation => 'إهلاك',
      kAssetJeDisposal => 'استبعاد',
      kAssetJeTransfer => 'نقل',
      kAssetJeRevaluation => 'إعادة تقييم',
      _ => 'حركة',
    };
