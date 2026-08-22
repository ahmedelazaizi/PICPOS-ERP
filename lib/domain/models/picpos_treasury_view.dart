// تقسيمُ رصيد الخزينة — `trSplit` في تصميم شاشة الخزينة.
//
// **حسابٌ خالصٌ بلا واجهةٍ ولا قاعدة**: يستقبل أزواجَ (نوعٍ، رصيد) ويُخرج
// شرائحَ بنسبها. فيُختبَر بلا فتحِ قاعدةٍ ولا حقنِ مزوِّد.
import '../../core/constants/app_constants.dart';
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
  factory PicPosTreasurySplit.from(
    Iterable<({String kind, double balance})> safes,
  ) {
    var cashMinor = 0;
    var bankMinor = 0;
    for (final s in safes) {
      final m = FinancialUtils.toMinorUnits(s.balance);
      if (s.kind == 'bank') {
        bankMinor += m;
      } else {
        // أيُّ نوعٍ غيرِ `bank` يُعدُّ نقداً — نفسُ افتراضِ العمود
        // (‏`withDefault('cash')`)، فنوعٌ يُضاف لاحقاً يظهر ولا يختفي.
        cashMinor += m;
      }
    }

    final cash = FinancialUtils.fromMinorUnits(cashMinor);
    final bank = FinancialUtils.fromMinorUnits(bankMinor);
    final totalMinor = cashMinor + bankMinor;
    final total = FinancialUtils.fromMinorUnits(totalMinor);

    double frac(int part) => totalMinor <= 0 ? 0 : part / totalMinor;

    return PicPosTreasurySplit(
      total: total,
      slices: [
        PicPosTreasurySlice(
          kind: 'cash',
          label: 'نقدي',
          value: cash,
          fraction: frac(cashMinor),
        ),
        PicPosTreasurySlice(
          kind: 'bank',
          label: 'بنكي',
          value: bank,
          fraction: frac(bankMinor),
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
