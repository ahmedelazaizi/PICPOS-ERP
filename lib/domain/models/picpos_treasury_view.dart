// تقسيمُ رصيد الخزينة — `trSplit` في تصميم شاشة الخزينة.
//
// **حسابٌ خالصٌ بلا واجهةٍ ولا قاعدة**: يستقبل أزواجَ (نوعٍ، رصيد) ويُخرج
// شرائحَ بنسبها. فيُختبَر بلا فتحِ قاعدةٍ ولا حقنِ مزوِّد.
import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../core/utils/financial_utils.dart';

/// شريحةٌ واحدةٌ في شريط التقسيم.
class PicPosTreasurySlice {
  const PicPosTreasurySlice({
    required this.kind,
    required this.label,
    required this.value,
    required this.fraction,
  });

  /// `cash` أو `bank` — نفسُ قيم عمود `safe_type`.
  final String kind;
  final String label;
  final double value;

  /// نسبةُ هذه الشريحة من المجموع، في المدى `[0, 1]`.
  final double fraction;

  String get valueLabel =>
      value.toStringAsFixed(AppConstants.decimalPlaces);

  /// `62%` — بلا كسور، فالشريطُ قراءةٌ سريعةٌ لا تقريرٌ محاسبيّ.
  String get percentLabel => '${(fraction * 100).toStringAsFixed(0)}%';
}

/// تقسيمُ الرصيد إلى نقديٍّ وبنكيّ.
class PicPosTreasurySplit {
  const PicPosTreasurySplit({required this.total, required this.slices});

  /// [safes] أزواجُ (نوعِ الصندوق، رصيده) — تُبنى في الشاشة من
  /// `scopedSafesProvider`، فلا يعرف هذا الملفُّ صفَّ القاعدة.
  ///
  /// ⚠️ **والمجموعُ قد يكون سالباً أو صفراً**، وكلاهما يقع فعلاً: صندوقٌ
  /// مسحوبٌ عليه أكثرَ ممّا فيه، أو نظامٌ لم يبدأ بعد. وفي الحالتين
  /// [PicPosTreasurySlice.fraction] **صفرٌ لا `NaN`** — القسمةُ على صفرٍ في
  /// Dart تعطي `NaN`/`Infinity` لا استثناءً، فشريطٌ بعرض `NaN` كان يرمي في
  /// طبقة الرسم لا في الحساب، فيصعب تتبّعه.
  /// ⚠️ **ثلاثُ شرائحَ لا اثنتان — وهذا تصحيحُ عطبٍ شُحن.**
  ///
  /// كُتبت هذه الدالّةُ أوّلاً بشريحتَين (نقدي/بنكي) وضمَّت «كلَّ ما ليس بنكاً»
  /// إلى النقديّ، بتعليقٍ يبرّر ذلك بأن نوعاً يُضاف لاحقاً «يظهر ولا يختفي».
  /// والتبريرُ كان باطلاً: `click` **نوعٌ قائمٌ لا مفترَض** — له تبويبُه في
  /// شاشة الخزينة، وشريحتُه في التصميم، وصندوقُه في التنصيبة الحيّة
  /// (‏قِيس 2026-08-22: `bank`×1 · `cash`×2 · `click`×1). فكانت محفظةُ كليك
  /// تُجمَع في خانة النقديّ صامتةً — رقمٌ صحيحُ المجموع خاطئُ التوزيع.
  ///
  /// و`multiple` **ليس نوعَ صندوقٍ** بل تصنيفَ طريقةِ دفعٍ في
  /// `sales_payment_calculator` — فلا شريحةَ له.
  ///
  /// وما لا يُعرَف نوعُه يبقى في النقديّ (افتراضُ العمود `withDefault('cash')`)
  /// كي لا يسقط رصيدٌ من المجموع.
  factory PicPosTreasurySplit.from(
    Iterable<({String kind, double balance})> safes,
  ) {
    var cashMinor = 0;
    var bankMinor = 0;
    var clickMinor = 0;

    for (final s in safes) {
      final m = FinancialUtils.toMinorUnits(s.balance);
      switch (s.kind) {
        case 'bank':
          bankMinor += m;
        case 'click':
          clickMinor += m;
        default:
          cashMinor += m;
      }
    }

    final totalMinor = cashMinor + bankMinor + clickMinor;
    double frac(int part) => totalMinor <= 0 ? 0 : part / totalMinor;

    return PicPosTreasurySplit(
      total: FinancialUtils.fromMinorUnits(totalMinor),
      slices: [
        PicPosTreasurySlice(
          kind: 'cash',
          label: tr('نقدي'),
          value: FinancialUtils.fromMinorUnits(cashMinor),
          fraction: frac(cashMinor),
        ),
        PicPosTreasurySlice(
          kind: 'bank',
          label: tr('بنوك'),
          value: FinancialUtils.fromMinorUnits(bankMinor),
          fraction: frac(bankMinor),
        ),
        PicPosTreasurySlice(
          kind: 'click',
          label: tr('كليك'),
          value: FinancialUtils.fromMinorUnits(clickMinor),
          fraction: frac(clickMinor),
        ),
      ],
    );
  }

  final double total;
  final List<PicPosTreasurySlice> slices;

  String get totalLabel => total.toStringAsFixed(AppConstants.decimalPlaces);

  /// هل يُرسم شريطُ التقسيم أصلاً؟
  ///
  /// لا يُرسم على مجموعٍ غيرِ موجب: شريطٌ فارغٌ أو مقلوبٌ لا يقول شيئاً،
  /// والأرقامُ نفسُها تبقى ظاهرةً في الشرائح.
  bool get hasBar => total > 0;
}
