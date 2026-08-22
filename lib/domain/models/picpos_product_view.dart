// حسابُ العمودَين اللذَين يضيفهما تصميمُ «الأصناف» — **حسابٌ خالصٌ بلا واجهةٍ
// ولا قاعدة**، فيُختبَر بلا بناءِ شجرةِ ودجت.
//
// العمودان: **الهامش** و**الوحدة**. وكلاهما يستحقُّ تعليقاً لأن أحدهما حسابٌ
// ماليٌّ يسهل قلبُه، والآخرَ ليس ما يبدو عليه اسمُه.
import '../../core/constants/app_constants.dart';

/// هامشُ الربح كنسبةٍ مئويّة.
///
/// ═══ البسطُ والمقام — والفرقُ ليس تجميليّاً ═══
///
/// يُحسب **على سعر البيع** (‏`(بيع − تكلفة) ÷ بيع`) لا على التكلفة. والفرقُ
/// كبيرٌ ويُقرأ خطأً بسهولة: صنفٌ تكلفتُه ١٠ ويُباع بـ٢٠ هامشُه **٥٠٪** على
/// البيع و**١٠٠٪** على التكلفة (وتلك «نسبةُ الإضافة» markup لا الهامش).
/// فتسميةُ العمود «الهامش» تُلزم القسمةَ على البيع.
///
/// `null` حين لا يُعرَف — لا صفر:
///  • سعرُ بيعٍ صفرٌ (أو سالب) ⇒ القسمةُ على صفرٍ تعطي `Infinity` في Dart لا
///    استثناءً، فـ«‏∞٪» كانت ستُطبع بلا هذا الحارس.
///  • تكلفةٌ صفرٌ ⇒ الهامشُ ١٠٠٪ حسابيّاً، لكنّها غالباً «لم تُدخَل بعد» لا
///    «مجّانيّة». وإظهارُ «١٠٠٪» على صنفٍ لم تُسجَّل تكلفتُه ادّعاءُ ربحٍ لا
///    أساسَ له — وهو أسوأُ من خانةٍ فارغة.
double? picposMarginPercent({
  required double salePrice,
  required double costPrice,
}) {
  if (salePrice <= 0) return null;
  if (costPrice <= 0) return null;
  return (salePrice - costPrice) / salePrice * 100;
}

/// نصُّ الهامش — `40%` أو `—` حين لا يُعرَف.
String picposMarginLabel({
  required double salePrice,
  required double costPrice,
}) {
  final m = picposMarginPercent(salePrice: salePrice, costPrice: costPrice);
  if (m == null) return '—';
  return '${m.toStringAsFixed(0)}%';
}

/// تصنيفُ الهامش لتلوين الشارة.
///
/// العتباتُ **عرضٌ لا سياسة**: لا يوجد في النظام إعدادُ «حدّ الهامش الأدنى»،
/// فهذه ألوانُ قراءةٍ سريعةٍ لا حكمٌ محاسبيّ. ولو أُضيف الإعدادُ يوماً فمكانُه
/// هنا لا في الودجت.
enum PicPosMarginBand { unknown, negative, low, healthy }

PicPosMarginBand picposMarginBand({
  required double salePrice,
  required double costPrice,
}) {
  final m = picposMarginPercent(salePrice: salePrice, costPrice: costPrice);
  if (m == null) return PicPosMarginBand.unknown;
  if (m < 0) return PicPosMarginBand.negative;
  if (m < 15) return PicPosMarginBand.low;
  return PicPosMarginBand.healthy;
}

/// تسميةُ وحدةِ البيع.
///
/// ⚠️ **وهذه ليست «الوحدة» بالمعنى الكامل.** جدولُ `product_units` يحمل وحداتٍ
/// متعدّدةً لكلّ صنف (كرتونة · عبوة · كيس…)، ولا يحمل `ProductEntity` وحدةً
/// أساسيّةً إطلاقاً. فقراءتُها الصادقةُ كانت تعني استعلاماً لكلّ صفّ (N+1) في
/// جدولٍ يعرض مئات الأصناف.
///
/// فالمعروضُ هنا **كيف يُباع الصنف** — وهو حقلٌ حقيقيٌّ (`isSoldByWeight`)
/// يقرّر سلوكَ نقطة البيع فعلاً. والتسميةُ صادقةٌ بما تعرضه ولا تدّعي أنها
/// وحدةُ التعبئة.
String picposSaleUnitLabel({required bool isSoldByWeight}) =>
    isSoldByWeight ? 'كجم' : 'قطعة';

/// عدّاداتُ بطاقاتِ «الأصناف» الأربع.
///
/// ⚠️ **تُحسب على الصفحة المحمَّلة لا على الجدول كلِّه.** شاشةُ الأصناف
/// مُصفَّحةٌ (`loadNextPage`)، فما في الذاكرة شريحةٌ لا الكلّ. والتسمياتُ في
/// الودجت تقول «في الصفحة» صراحةً كي لا يُقرأ العددُ إجماليّاً — عدٌّ إجماليٌّ
/// صادقٌ يحتاج `COUNT(*)` في SQL، وهو بندٌ مستقلّ.
class PicPosProductKpis {
  const PicPosProductKpis({
    required this.loaded,
    required this.active,
    required this.belowMinStock,
    required this.missingCost,
  });

  factory PicPosProductKpis.from(
    Iterable<
            ({
              double salePrice,
              double costPrice,
              double currentStock,
              double minStock,
              bool trackInventory,
              bool isActive,
            })>
        rows,
  ) {
    var loaded = 0;
    var active = 0;
    var below = 0;
    var missingCost = 0;

    for (final r in rows) {
      loaded++;
      if (r.isActive) active++;
      // ‏`minStock` صفرٌ يعني «لا حدَّ أدنى مضبوطاً» لا «الحدُّ صفر» — نفسُ
      // منطقِ حدّ الائتمان في شاشة الأطراف. ولا يُنبَّه على صنفٍ لا يُتابَع
      // مخزونُه أصلاً.
      if (r.trackInventory && r.minStock > 0 && r.currentStock < r.minStock) {
        below++;
      }
      if (r.costPrice <= 0) missingCost++;
    }

    return PicPosProductKpis(
      loaded: loaded,
      active: active,
      belowMinStock: below,
      missingCost: missingCost,
    );
  }

  final int loaded;
  final int active;
  final int belowMinStock;
  final int missingCost;
}

/// نصُّ مبلغٍ بعملة النظام — يُستعمل في خلايا التكلفة والسعر.
String picposMoneyLabel(double v) =>
    v.toStringAsFixed(AppConstants.decimalPlaces);
