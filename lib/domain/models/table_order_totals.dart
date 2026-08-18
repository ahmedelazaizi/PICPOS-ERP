// ═══════════════════════════════════════════════════════════════════════════
// إجمالياتُ طلبِ الطاولة — الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// كان لطاولةٍ واحدةٍ محرّكا حسابٍ لا واحد: السلّةُ تحسب بـ
// `CalculateInvoiceTotalsUseCase` (ضريبةٌ فوق الصافي وخصومٌ تُطرح)، والطلبُ
// يحسب `SUM(quantity × unitPrice)` ناقصاً خصمَ الطلب. فكان الرقمان يفترقان
// كلّما فُعّلت الضريبة، وحارسُ [checkTableCharge] يرفض التحصيل — بحقّ.
//
// هذا النموذجُ هو المحرّكُ الواحد. خالصٌ بلا Drift ولا Riverpod ولا ودجت، كي
// تستعمله **الخدمةُ والشاشةُ والطباعةُ** جميعاً فيخرج منها رقمٌ واحدٌ لا
// ثلاثة. ودلالاتُه منسوخةٌ عن `CalculateInvoiceTotalsUseCase` بحرفها —
// مواضعُ التقريب نفسُها بـ`NumberUtils.roundCurrency` — فما يتطابقان إلّا
// إلى آخر وحدةٍ نقديّة. وذلك مقيسٌ لا مأمول: انظر اختبارَ التطابق في
// `test/unit/table_order_totals_test.dart`.
//
// **الضريبةُ تُحسب على الصافي بعد الخصم لا على المجمل** (مواصفة ١٣٧،
// BUG-C02/BUG-H01)، ولا تُؤخذ قطُّ من قيمةٍ مخزَّنةٍ سلفاً.

import 'dart:math' as math;

import '../../core/constants/app_constants.dart';
import '../../core/utils/number_utils.dart';
import 'tax_rate_bounds.dart';

/// سطرٌ واحدٌ في طلبِ طاولةٍ، مجرَّداً من الجدول ومن الكيان.
///
/// قِيَمٌ عاريةٌ لا `CartItemEntity` ولا `TableOrderItem`: النموذجُ يُستدعى من
/// طبقاتٍ ثلاثٍ لا تتقاسم نوعاً واحداً، وأخذُه نوعاً منها يجرّ إليه تبعيّتَها.
class TableOrderLine {
  const TableOrderLine({
    required this.quantity,
    required this.unitPrice,
    this.taxRate = 0,
  });

  final double quantity;
  final double unitPrice;

  /// نسبةُ ضريبة **البند**، مئويّةً (16 لا 0.16) — مرآةُ
  /// `TableOrderItems.taxRate` و`CartItemEntity.taxRate`، وكلاهما منسوخٌ عن
  /// `Products.taxRate` المئويّة.
  ///
  /// الصفرُ ليس «معفىً» بل «لا نسبةَ خاصّةً لهذا البند» — فيقع على نسبة
  /// الطلب. وهذه دلالةُ `item.taxRate > 0 ? item.taxRate : taxPercent` في
  /// `CalculateInvoiceTotalsUseCase` نفسِها، لا اجتهاداً جديداً. والإعفاءُ
  /// الحقيقيُّ يكون بإطفاء الضريبة على الطلب كلِّه.
  final double taxRate;

  /// صافي السطر قبل خصم الطلب.
  ///
  /// مقرَّبٌ عند حدّه كما تُقرِّب `CartItemEntity.subtotal`، فالمجموعُ لا يرث
  /// ذيولَ الفاصلة. ولا خصمَ على مستوى البند في طلبات الطاولات — لا عمودَ له
  /// في `TableOrderItems` — فهذا يقابل `subtotal` و`totalBeforeTax` معاً في
  /// نظيره في السلّة.
  double get lineNet => NumberUtils.roundCurrency(quantity * unitPrice);
}

/// إجمالياتُ طلبِ طاولةٍ محسوبةً مرّةً واحدةً لكلّ من يحتاجها.
class TableOrderTotals {
  const TableOrderTotals({
    required this.subtotal,
    required this.discount,
    required this.netAfterDiscount,
    required this.taxAmount,
    required this.total,
    this.lineTotals = const [],
  });

  const TableOrderTotals.empty()
      : subtotal = 0,
        discount = 0,
        netAfterDiscount = 0,
        taxAmount = 0,
        total = 0,
        lineTotals = const [];

  /// مجموعُ صوافي البنود قبل خصم الطلب.
  final double subtotal;

  /// خصمُ الطلب مبلغاً — مقصوصاً عند [subtotal] مهما كان نوعُه أو قيمتُه،
  /// فيبقى الثابتُ `subtotal - discount == netAfterDiscount` صحيحاً دوماً.
  final double discount;

  /// الوعاءُ الخاضعُ للضريبة: [subtotal] ناقصَ [discount]، ولا ينزل عن صفر.
  final double netAfterDiscount;

  /// ضريبةُ المبيعات محسوبةً على [netAfterDiscount]، صفراً إن كانت مُطفأةً.
  final double taxAmount;

  /// المستحقُّ على الطلب: [netAfterDiscount] + [taxAmount].
  final double total;

  /// حصّةُ كلِّ بندٍ من [total] بترتيب البنود الممرَّرة — نصيبُه من الخصم
  /// وضريبتُه فوقه. **مجموعُها يساوي [total] بالضبط**، والفرقُ الكسريُّ
  /// يُحمَّل على البند الأخير كما تفعل `SplitPlan.equal`.
  ///
  /// التقسيمُ بالأصناف يبني عليها. وكان يبني على `TableOrderItems.total`
  /// الخام (كميّة × سعر)، فمجموعُ الحصص لا يبلغ المستحقَّ متى كان على
  /// الطلب خصمٌ أو ضريبة — تُسوَّى الحصصُ كلُّها والطاولةُ لا تصير مدفوعةً
  /// أبداً، بلا رسالةِ خطأٍ واحدة.
  final List<double> lineTotals;

  /// النسبةُ المخزَّنةُ في `TableOrders.taxRate` كسريّةٌ (0.16) لأنها لقطةٌ من
  /// `pos_default_tax_rate` مرآةً لـ`CartState.taxRate`، بينما [compute]
  /// ونِسَبُ البنود مئويّةٌ (16) مرآةً لـ`CalculateInvoiceTotalsUseCase`.
  /// هذه هي النقطةُ **الوحيدةُ** التي يُعبَر عندها الحدُّ بين الوحدتين —
  /// تماماً كما يفعل `CartState.totals` بـ`taxRate * 100`.
  static double taxPercentFromRate(double storedRate) => storedRate * 100;

  /// حارسُ الوحدات — يُطلق في التطوير والاختبارات، ولا أثرَ له في الإصدار.
  ///
  /// خطأُ الوحدة هو الخطأُ **الوحيد** هنا الذي يعبر كلَّ اختبارٍ ثم يظهر على
  /// فاتورة زبون: نسبةٌ كسريّةٌ (0.16) تُقرأ مئويّةً فتُحصَّل ضريبةٌ نسبتُها
  /// ١٦ من عشرة آلاف، أو مئويّةٌ (16) تُقرأ كسريّةً فتُضرب في ١٠٠ فتصير
  /// ١٦٠٠٪. كلاهما رقمٌ «معقول» لا يرمي شيئاً. والمدى يمسكهما معاً.
  ///
  /// والمدى يُقرأ من [TaxRateBounds] لا يُكتَب هنا رقمَين عاريَين: نفسُ الحدِّ
  /// تفرضه شاشةُ الإعدادات عند المدخل، و`setOrderTax` عند المفتاح، وقيدُ
  /// `CHECK` في الجدول. ولو بقي مكرَّراً لَجاز أن يُشَدّ في موضعٍ ويُترَك في
  /// آخر، فيُجيز هذا الحارسُ ما ترفضه الشاشةُ — وهو بابٌ رابعٌ بلا داعٍ.
  ///
  /// **ولا يُعتمَد عليه وحدَه:** `assert` لا يعمل في بناء الإصدار، فالحارسُ
  /// الحقيقيُّ على مسار المال هو القيدُ والعتبةُ لا هذا.
  static void _requirePercent(double rate, String what) {
    assert(
      TaxRateBounds.isValidPercent(rate),
      'نسبةُ الضريبة تُمرَّر مئويّةً (16) لا كسريّةً (0.16): $what = $rate. '
      'الآتيةُ من TableOrders.taxRate تُمرَّر عبر '
      'TableOrderTotals.taxPercentFromRate وحدَها.',
    );
  }

  /// يحسب الإجمالياتِ من بنودِ الطلب وخصمِه وضريبتِه.
  ///
  /// [discountType] بقيمتَي `TableOrders.discountType`: `percent` نسبةً من
  /// [subtotal]، و`amount` مبلغاً مقطوعاً — وأيُّ قيمةٍ أخرى (أو `null`) لا
  /// خصمَ لها. و[taxPercent] نسبةُ الطلب **مئويّةً**؛ انظر
  /// [taxPercentFromRate].
  factory TableOrderTotals.compute({
    required List<TableOrderLine> lines,
    String? discountType,
    double discountValue = 0,
    bool taxEnabled = false,
    double taxPercent = 0,
  }) {
    // **الحارسُ مشروطٌ بالتفعيل.** النسبتان — نسبةُ الطلب ونِسَبُ البنود — لا
    // تدخلان الحسابَ إلّا داخل `if (taxEnabled)` أدناه، فطلبٌ مطفأٌ لا يمكن أن
    // تظهر نسبتُه على فاتورةِ زبونٍ مهما كانت وحدتُها. ولا شيءَ يُمسَك.
    //
    // وهذا تصحيحُ مدىً لا إلغاءُ حارس: ترقيةُ v157 **تُبقي** لقطةً دون الحدّ
    // على طلبٍ مطفأ — القيدُ لا يطارد مطفأً — و`taxPercentFromRate(0.005)`
    // تساوي `0.5`. فحارسٌ غيرُ مشروطٍ كان يُسقط حسابَ تلك الطاولة في التطوير
    // على حالةٍ **قصدَها التصميم**. مقيسٌ لا مفترض:
    // `Failed assertion: نسبةُ الطلب = 0.5` من `totalsFor` على طلبٍ مطفأ.
    if (taxEnabled) _requirePercent(taxPercent, 'نسبةُ الطلب');

    if (lines.isEmpty) return const TableOrderTotals.empty();

    var gross = 0.0;
    for (final line in lines) {
      if (taxEnabled) _requirePercent(line.taxRate, 'نسبةُ البند');
      gross += line.lineNet;
    }
    if (gross < 0) gross = 0;

    var discount = 0.0;
    if (discountValue > 0) {
      if (discountType == 'percent') {
        discount = NumberUtils.roundCurrency(gross * (discountValue / 100));
      } else if (discountType == 'amount') {
        discount = NumberUtils.roundCurrency(discountValue);
      }
      // القصُّ هنا هو ما يمنع الإجماليَّ السالب: خصمُ ١٠٠٪ يُنزله إلى صفرٍ
      // ويقف. و`setOrderDiscount` يحرس المبلغَ عند التثبيت، لكنّ نموذجاً
      // خالصاً يُستدعى من ثلاث طبقاتٍ لا يتّكل على حارسٍ في واحدةٍ منها.
      if (discount > gross) discount = NumberUtils.roundCurrency(gross);
    }

    final net = gross - discount;

    // النسبةُ التي تُنزل صافيَ كلِّ بندٍ إلى الوعاء بعد الخصم، فتبقى نِسَبُ
    // البنود محفوظةً وتقع الضريبةُ مع ذلك على الصافي. منقولةٌ عن
    // `CalculateInvoiceTotalsUseCase` حرفاً.
    final discountRatio = gross > 0 ? (net / gross) : 0.0;

    var taxAmount = 0.0;
    // حصّةُ كلِّ بندٍ من المستحقّ — تُبنى في نفس المرور كي لا تفترق عنه.
    final shares = <double>[];
    for (final line in lines) {
      final base = line.lineNet * discountRatio;
      var lineTax = 0.0;
      if (taxEnabled) {
        final rate = line.taxRate > 0 ? line.taxRate : taxPercent;
        lineTax = NumberUtils.roundCurrency(base * (rate / 100));
        taxAmount += lineTax;
      }
      shares.add(base + lineTax);
    }
    taxAmount = NumberUtils.roundCurrency(taxAmount);

    final total = NumberUtils.roundCurrency(net + taxAmount);

    // الحصصُ تُقاس بوحداتٍ صحيحةٍ ويُحمَّل الفرقُ الكسريُّ على الأخيرة، فيصحّ
    // الثابت: مجموعُ الحصص = المستحقُّ بالضبط. جمعُ `double` المقرَّبةِ
    // إفراديّاً يُنقص وحدةً أو يزيدها، ووحدةٌ واحدةٌ تكفي لتبقى الطاولةُ
    // «غيرَ مدفوعةٍ» بعد تسوية كلِّ حصصها.
    final unitFactor = math.pow(10, AppConstants.decimalPlaces).toDouble();
    final lineUnits = shares.map((s) => (s * unitFactor).round()).toList();
    final drift =
        (total * unitFactor).round() - lineUnits.fold<int>(0, (a, b) => a + b);
    if (lineUnits.isNotEmpty) lineUnits[lineUnits.length - 1] += drift;

    return TableOrderTotals(
      subtotal: NumberUtils.roundCurrency(gross),
      discount: discount,
      netAfterDiscount: NumberUtils.roundCurrency(net),
      taxAmount: taxAmount,
      total: total,
      lineTotals: [for (final u in lineUnits) u / unitFactor],
    );
  }

  @override
  String toString() =>
      'TableOrderTotals(subtotal: $subtotal, discount: $discount, '
      'netAfterDiscount: $netAfterDiscount, taxAmount: $taxAmount, '
      'total: $total)';
}
