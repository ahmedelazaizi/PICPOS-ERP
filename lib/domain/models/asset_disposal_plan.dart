import '../../core/i18n/tr.dart';

// حسابُ طلبِ استبعاد الأصل — **خالصٌ**، بلا قاعدةٍ ولا ودجت.
//
// ═══ 🔴 ولماذا خطّةٌ مستقلّةٌ أصلاً ═══
//
// `disposeAsset` القائمةُ تأخذ `disposalValue` وتاريخاً ومركزَ تكلفةٍ لا
// أكثر، وتقيّد **دائماً** مدينَ نقديّةٍ على الحساب `1111`. فثلاثةُ أشياءَ
// ليس لها موضعٌ فيها:
//   • **طريقةُ الاستبعاد** — بيعٌ أم إعدامٌ أم تبرّعٌ أم تخريد.
//   • **طريقةُ التحصيل** — نقديٌّ أم آجلٌ على ذمّة عميل.
//   • **المشتري** — وبلا طرفٍ مسجَّلٍ لا ذمّةَ تُحمَّل في الآجل.
//
// ═══ 🔴 و«الخسارة المتوقَّعة» تسمية بالعلامة لا ثابتة ═══
//
// التصميمُ `(6)` يسمّي الحقلَ «الخسارة المتوقعة» دائماً. وبيعٌ بأكثرَ من
// القيمة الدفتريّة **ربحٌ**، فعرضُه تحت عنوان «خسارة» — أو عرضُ سالبٍ
// تحته — يقلب إشارةَ رقمٍ يدخل قائمةَ الدخل. فالاسمُ يتبع العلامة.
//
// ═══ 🔴 والبيعُ `sold` وما عداه `disposed` ═══
//
// `'sold'` **مقروءٌ في سبعة مواضعَ ولا كاتبَ له** (‏`asset_card_picpos` ·
// `fixed_assets_picpos_screen` × ٦ · `fixed_assets_dialogs`): `disposeAsset`
// تكتب `'disposed'` دائماً. فوسمُ «بيع» لا يظهر أبداً، ومرشِّحُ «بيع» في
// تبويب الاستبعاد يعدّ **صفراً** مهما بيع من أصول — وكلُّ مبيعٍ يُعرَض
// «إعدام». والطلبُ هنا أوّلُ مَن يعرف الفرقَ، فهو أوّلُ مَن يكتبه.

/// طرائقُ الاستبعاد — بقيمِ العمود لا بعناوينه.
const List<String> kDisposalMethods = ['sale', 'scrap', 'donation', 'writeoff'];

/// طرائقُ التحصيل — `cash` أو `credit`.
const List<String> kDisposalCollectionMethods = ['cash', 'credit'];

String disposalMethodLabel(String method) => switch (method) {
      'sale' => tr('بيع'),
      'scrap' => tr('إعدام'),
      'donation' => tr('تبرّع'),
      'writeoff' => tr('تخريد'),
      _ => method,
    };

String disposalCollectionLabel(String method) =>
    method == 'credit' ? tr('آجل على ذمّة العميل') : tr('نقدي');

/// هل تُحصَّل قيمةٌ من هذه الطريقة؟ — **البيعُ وحدَه**.
///
/// ⚠️ والإعدامُ والتبرّعُ والتخريدُ بلا ثمنٍ **بحكمِ التعريف**: قيمةٌ عليها
///    تعني بيعاً سُمّي بغير اسمه، فيغيب المشتري من الدفتر ويُقيَّد النقدُ
///    بلا مصدرٍ يفسّره.
bool disposalCarriesProceeds(String method) => method == 'sale';

/// نتيجةُ الاستبعاد — **بعلامتها واسمِها الموافق لها**.
typedef DisposalOutcome = ({
  double bookValue,
  double gainLoss,
  bool isGain,
  String label,
});

DisposalOutcome computeDisposalOutcome({
  required double originalCost,
  required double accumulatedDepreciation,
  required double disposalValue,
}) {
  final book = originalCost - accumulatedDepreciation;
  final delta = disposalValue - book;
  return (
    bookValue: book,
    gainLoss: delta,
    isGain: delta > 0,
    label: delta > 0
        ? tr('الربح المتوقَّع')
        : delta < 0
            ? tr('الخسارة المتوقَّعة')
            : tr('بلا ربحٍ ولا خسارة'),
  );
}

/// 🔴 حالةُ الأصل بعد الاعتماد — راجع رأسَ الملفّ.
String assetStatusAfterDisposal(String method) =>
    method == 'sale' ? 'sold' : 'disposed';

/// سببُ منعِ الطلب، أو `null` إن جاز.
///
/// ⚠️ **وهو فحصُ نموذجٍ ومحرّكٍ معاً**: الشاشةُ تعرضه وهو يكتب، والمحرّكُ
///    يُنفّذه داخلَ المعاملة — فقيمةُ الأصل ومجمَّعُه يتغيّران بترحيل إهلاكٍ
///    بين فتحِ النموذج وحفظِه.
String? validateAssetDisposal({
  required String method,
  required double disposalValue,
  required String collectionMethod,
  required int? buyerPartyId,
  required int? safeId,
  required String reason,
  required String assetStatus,
}) {
  if (assetStatus != 'active') {
    return tr('الأصل غير نشط — لا يُستبعَد مرّتين');
  }
  if (!kDisposalMethods.contains(method)) {
    return tr('طريقة استبعاد غير معروفة');
  }
  if (reason.trim().isEmpty) return tr('اكتب سبب الاستبعاد');

  if (!disposalCarriesProceeds(method)) {
    // 🔴 بلا هذا يُقيَّد نقدٌ على «تبرّع» فيدخل الدفترَ مالٌ لم يُقبَض.
    if (disposalValue != 0) {
      return tr('{p0} بلا ثمن — امسح قيمة البيع', {'p0': disposalMethodLabel(method)});
    }
    return null;
  }

  if (disposalValue <= 0) return tr('اكتب قيمة البيع');
  if (!kDisposalCollectionMethods.contains(collectionMethod)) {
    return tr('طريقة تحصيل غير معروفة');
  }
  if (collectionMethod == 'credit' && buyerPartyId == null) {
    // ⚠️ نصٌّ حرٌّ لا يكفي: القيدُ يحتاج حساباً، والذمّةُ تحتاج طرفاً يُطالَب.
    return tr('الآجل يحتاج مشترياً مسجَّلاً — بلا طرفٍ لا ذمّةَ تُحمَّل');
  }
  if (collectionMethod == 'cash' && safeId == null) {
    // 🔴 `disposeAsset` القائمةُ تقيّد مدينَ نقديّةٍ **ولا تحرّك خزنة**، فيزيد
    //    النقدُ في الأستاذ ولا يزيد في أيّ درج. والخزنةُ هنا شرطٌ لا حقلٌ
    //    اختياريّ.
    return tr('اختر الخزينة — وإلّا زاد النقدُ في الدفتر ولم يزد في أيّ درج');
  }
  return null;
}

/// ما يُخزَّن فعلاً بعد التطبيع — **الطريقةُ تحكم لا المستخدم**.
///
/// طريقةٌ بلا ثمنٍ تُصفّر القيمةَ وتُسقط المشتريَ والخزنةَ وتُرجع التحصيلَ
/// إلى `cash` (قيمةُ العمود الافتراضيّة)، فلا يبقى في الصفّ حقلٌ يناقض
/// طريقتَه ويُقرأ لاحقاً على أنّه بيعٌ لم يُقيَّد.
typedef NormalizedDisposal = ({
  String method,
  double disposalValue,
  String collectionMethod,
  int? buyerPartyId,
  int? safeId,
});

NormalizedDisposal normalizeDisposal({
  required String method,
  required double disposalValue,
  required String collectionMethod,
  int? buyerPartyId,
  int? safeId,
}) {
  if (!disposalCarriesProceeds(method)) {
    return (
      method: method,
      disposalValue: 0,
      collectionMethod: 'cash',
      // ⚠️ المتبرَّعُ له يبقى: هو **مَن استلم**، لا مدينٌ على ذمّته.
      buyerPartyId: buyerPartyId,
      safeId: null,
    );
  }
  final credit = collectionMethod == 'credit';
  return (
    method: method,
    disposalValue: disposalValue,
    collectionMethod: credit ? 'credit' : 'cash',
    buyerPartyId: buyerPartyId,
    // الآجلُ لا يدخل درجاً.
    safeId: credit ? null : safeId,
  );
}
