// أهليّةُ صنفِ الميزان وعدّاداتُ شاشة «ميزان PLU» — **حسابٌ خالصٌ بلا واجهةٍ
// ولا قاعدة**.
//
// ═══ لماذا وُجد هذا الملفُّ أصلاً ═══
//
// عدّاداتُ التصميم (`scaleStats`) تحتاج أن تعدّ «أصنافَ الميزان»، والشرطُ
// الذي يعرّفها كان مكتوباً **داخل** `filterProducts` في mixin الشاشة. فنسخُه
// إلى العدّاد كان يعني تعريفَين لنفس المفهوم ينحرفان بأوّل نوعِ ميزانٍ يُضاف
// — فيعرض العدّادُ رقماً والجدولُ صفوفاً لا تطابقه، وهو كذبٌ يصعب تفسيره.
//
// فصار الشرطُ دالّةً واحدةً يقرؤها **الاثنان**.
import '../entities/product_entity.dart';

/// هل هذا الصنفُ من أصناف الميزان؟
///
/// الشرطُ منقولٌ حرفيّاً عن `filterProducts` (‏`scale_logic_picpos.dart`)
/// وصارت تلك تستدعي هذه: ثلاثةُ أنواعِ ميزانٍ صريحةٍ **أو** البيعُ بالوزن.
///
/// ⚠️ و`weightByPiece` **يُعدّ صنفَ ميزانٍ هنا** وإن كان لا يُباع بالوزن في
/// حساب الباركود (‏راجع `scaleItemIsSoldByWeight`). المفهومان مختلفان: هذا
/// «هل يُصدَّر للميزان» وذاك «أيُّ بادئةِ باركودٍ يأخذ». خلطُهما كان يُسقط
/// نوعاً كاملاً من التصدير.
bool picposIsScaleItem(ProductEntity p) =>
    p.scaleType == 'weight' ||
    p.scaleType == 'weightByPiece' ||
    p.scaleType == 'display' ||
    p.isSoldByWeight;

/// عدّاداتُ البطاقات الأربع.
class PicPosScaleStats {
  const PicPosScaleStats({
    required this.scaleItems,
    required this.missingPlu,
    required this.selectedForExport,
    required this.definedScales,
  });

  /// [products] القائمةُ الكاملةُ لا المرشَّحة: العدّادُ يقول «كم عندي» لا
  /// «كم أرىٰ بعد الترشيح» — نفسُ قرارِ شاشة الأطراف.
  factory PicPosScaleStats.from({
    required Iterable<ProductEntity> products,
    required int selectedForExport,
    required int definedScales,
  }) {
    var items = 0;
    var missing = 0;
    for (final p in products) {
      if (!picposIsScaleItem(p)) continue;
      items++;
      // ‏`scalePluNumber` فارغٌ ⇒ الجدولُ يعرض `p.id` بديلاً مؤقّتاً، لكنّ
      // الصنفَ **بلا رقمٍ مخصَّصٍ فعلاً** — وهو ما يهمّ من يجهّز الترحيل.
      if (p.scalePluNumber == null) missing++;
    }
    return PicPosScaleStats(
      scaleItems: items,
      missingPlu: missing,
      selectedForExport: selectedForExport,
      definedScales: definedScales,
    );
  }

  final int scaleItems;
  final int missingPlu;
  final int selectedForExport;
  final int definedScales;
}
