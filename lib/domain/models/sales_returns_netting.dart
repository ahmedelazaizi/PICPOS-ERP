// ═══════════════════════════════════════════════════════════════════════════
// تقريرُ المبيعات صافياً من المرتجعات — الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// `getSalesAnalytics` يسلّم المبيعاتِ الاعتيادية **خاماً** بعقدٍ موثَّقٍ عنده:
// الاستعلامُ يستثني مستنداتِ `sale_type='return'` كي لا تُطرح القيمةُ مرّتين،
// ويستثني `status IN ('returned','cancelled','voided')` فيخرج المرتجعُ
// **الكاملُ** من المجمل. يبقى المرتجعُ **الجزئيّ** (‏حالتُه `partial_return`)
// داخلَ المجمل بقيمة فاتورته الكاملة — وهذا ما تطرحه الدوالُّ هنا.
//
// ولماذا الحسابُ في ملفٍّ خالصٍ لا داخلَ الشاشة: لأنه المكانُ الذي يُقاس.
// الشاشةُ تركّب فحسب.

// موضعُه `domain/models` لا `data/database/models`: شاشةُ التقرير تستورده،
// وحارسُ `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من
// استيراد `data/database` مباشرةً (‏Constitution §IV)، ونصُّه صريحٌ في أن
// إضافةَ مخالفٍ جديدٍ إلى قائمته البيضاء **ممنوعة**.
import '../../data/database/database.dart';

/// مجموعُ ما رُدَّ فعلاً عن **الفواتير المعروضة وحدَها**، مقصوصاً عند قيمة
/// كلِّ فاتورة.
///
/// [returnedByInvoice] — خرجُ `SalesDao.getReturnedAmountsForInvoices`:
/// `{معرّفُ الفاتورة الأصلية: مجموعُ ما رُدّ}`، جامعاً شكلَي المرتجع
/// (‏حركةَ خزينةٍ `reference_type='sales_return'` ومستندَ `sale_type='return'`).
///
/// [displayedInvoiceTotals] — `{معرّف: إجمالي}` للفواتير التي **يعرضها**
/// الجدولُ بعد كلّ فلتر.
///
/// ⚠️ القصرُ على المعروض ليس تحسيناً بل هو ما يمنع الازدواج **بالبناء**:
/// المرتجعُ الكاملُ مطروحٌ أصلاً بالاستثناء (حالتُه `returned`)، وفاتورتُه
/// ليست في القائمة المعروضة، فلا سبيلَ لطرحه مرّتين. ولو طُرح إجماليُّ
/// مرتجعات الفترة جزافاً لسقط الضمانُ وانحرفت البطاقةُ عن الجدول تحت أيّ
/// فلتر.
///
/// والقصُّ عند قيمة الفاتورة يمنع سطراً سالباً يقاصّ مبيعاتِ فواتيرَ أخرى:
/// ردٌّ بـ٢٥ على فاتورةِ ١٨ كان سينقص المجملَ سبعةً زيادةً على ما رُدّ.
double clampedReturnedTotal({
  required Map<int, double> returnedByInvoice,
  required Map<int, double> displayedInvoiceTotals,
}) {
  if (returnedByInvoice.isEmpty || displayedInvoiceTotals.isEmpty) return 0.0;

  var sum = 0.0;
  for (final entry in displayedInvoiceTotals.entries) {
    final refund = returnedByInvoice[entry.key];
    // صفُّ خزينةٍ معكوسٌ قد يصل سالباً؛ طرحُ سالبٍ كان **يرفع** المبيعات.
    if (refund == null || refund <= 0) continue;
    final cap = entry.value <= 0 ? 0.0 : entry.value;
    sum += refund > cap ? cap : refund;
  }
  return sum;
}

/// يبني نسخةً **صافيةً** من [gross] بعد حسم [returnedTotal].
///
/// الصافي يُبنى مرّةً واحدةً في مكانٍ واحد لأن البطاقاتِ والطباعةَ والتصديرَ
/// تقرأ كائنَ التحليل نفسَه؛ حسمٌ عند كلّ بطاقةٍ على حدة كان سيترك الطباعةَ
/// والتصديرَ على المجمل.
///
/// **الربحُ** — مع [actual] (‏FS-16، ما تمرّره شاشةُ التقرير): يُطرح من صافي
/// الإيراد ومن التكلفة ما قيّده قيدُ كلِّ مرتجعٍ فعلاً (انظر
/// [returnsProfitBasis])، فيطابق `4121 − 4212 − 4211 − 5211` للفواتير
/// المعروضة.
///
/// وبدون [actual] يبقى المسارُ القديمُ كما كان، وهو **تقديرٌ** تناسبيّ:
/// `netProfit = grossProfit × (1 − returned/gross)`. أُبقي لمن لا يملك قيودَ
/// المرتجع (نداءاتٌ قديمةٌ واختباراتُ الحساب الخالص) لا لأنه صحيح: المعاملُ
/// يُبنى من المردود **شاملَ الضريبة** على مجمل كلّ الفواتير، فيخطئ تكلفةَ
/// المرتجع (دورة `fs_01`: ٥٩٫٥٧٤ بدل ٦٠ المقيّدة، والربحُ ١٣٦٫٢٤١ بدل
/// ١٣٦٫٦٦٧)، ويخطئ الإيرادَ متى اختلفت نسبةُ الضريبة أو التوصيل بين الفواتير.
/// وكان مبرَّرُه أن مستندَ المرتجع قد يكون **بلا أسطرِ أصناف**
/// (`insertSalesInvoiceWithoutStock`) — لكن قيدَ المرتجع يحمل التكلفةَ
/// المجمَّدةَ في الحالتين، فلا حاجةَ للأسطر.
///
/// ولا يُوجَّه الربحُ إلى أرصدة الأستاذ للفترة: فلاترُ الشاشة (مستخدم · دفع ·
/// نوع · مخزن) بلا مقابلٍ محاسبيّ، فالرقمُ كان سينحرف صامتاً عن الجدول
/// تحتها. لذا يُقرأ القيدُ **لكلّ فاتورةٍ معروضة** لا للفترة كلّها.
///
/// **عددُ الفواتير لا ينقص**: الفاتورةُ المرتجَعةُ جزئياً ما زالت بيعاً
/// معروضاً في الجدول، فإنقاصُ العدّاد كان سيخالف عددَ الصفوف. والضريبةُ
/// والخصمُ يُتركان كما هما — بطاقةُ الضريبة تقرأ من الأستاذ في شاشتها،
/// وتحريكُها هنا كان سيخالفها.
SalesAnalytics netOfReturns(
  SalesAnalytics gross,
  double returnedTotal, {
  ReturnsProfitBasis? actual,
}) {
  if (returnedTotal <= 0) return gross;

  final rawNet = gross.totalSales - returnedTotal;
  final netSales = rawNet < 0 ? 0.0 : rawNet;

  // مبيعاتٌ صفرٌ مع ردٍّ (مدىً لا بيعَ فيه ورَدٌّ على بيعٍ أقدم) ⇒ لا قسمةَ
  // على صفر: المعاملُ صفرٌ والصافي صفر.
  final factor = gross.totalSales > 0 ? netSales / gross.totalSales : 0.0;

  final netRevenue = actual == null
      ? gross.totalNetRevenue * factor
      : gross.totalNetRevenue - actual.netRevenue;
  final cogs =
      actual == null ? gross.totalCOGS * factor : gross.totalCOGS - actual.cogs;
  // ربحُ المبيعات = صافي الإيراد − التكلفة، بنفس تعريف `getSalesAnalytics`.
  final profit = netRevenue - cogs;

  return SalesAnalytics(
    totalSales: netSales,
    totalGrossProfit: actual == null ? gross.totalGrossProfit * factor : profit,
    totalNetProfit: actual == null ? gross.totalNetProfit * factor : profit,
    totalProfit: actual == null ? gross.totalProfit * factor : profit,
    salesCount: gross.salesCount,
    invoiceCount: gross.invoiceCount,
    averageSaleValue:
        gross.salesCount > 0 ? netSales / gross.salesCount : 0.0,
    averageInvoiceValue:
        gross.invoiceCount > 0 ? netSales / gross.invoiceCount : 0.0,
    totalDiscount: gross.totalDiscount,
    totalTax: gross.totalTax,
    totalCOGS: cogs,
    totalNetRevenue: netRevenue,
  );
}

/// ما يُطرح من صافي الإيراد ومن التكلفة لمرتجعات الفواتير المعروضة.
class ReturnsProfitBasis {
  const ReturnsProfitBasis({
    required this.netRevenue,
    required this.cogs,
    required this.estimatedInvoiceCount,
  });

  /// المردودُ بلا ضريبةٍ ولا حصّةِ توصيل — نفسُ أساس `totalNetRevenue`.
  final double netRevenue;

  /// تكلفةُ البضاعة المرتجَعة كما عكسها قيدُ المرتجع.
  final double cogs;

  /// فواتيرُ رُدّ عليها ولا قيدَ مرتجعٍ لها في هذا المخزن، فحُسبت تقديراً.
  final int estimatedInvoiceCount;

  bool get isEstimated => estimatedInvoiceCount > 0;
}

/// يبني [ReturnsProfitBasis] لكلّ فاتورةٍ معروضةٍ رُدّ عليها.
///
/// [returnedByInvoice] — المردودُ شاملَ الضريبة (‏`getReturnedAmountsForInvoices`).
/// [ledgerByInvoice] — `(cogs, vat)` من قيد المرتجع
/// (‏`getReturnLedgerAmountsForInvoices`).
///
/// لكلّ فاتورة: `cap` = المردودُ مقصوصاً عند إجماليها كما في
/// [clampedReturnedTotal]، وما يُطرح من القيد يُقصّ بالنسبة نفسها
/// (`cap / refund`) كي لا يُطرح من التكلفة أكثرُ ممّا طُرح من الإيراد.
///   * الإيرادُ = `cap − vat − cap × delivery / total`: حصّةُ التوصيل من
///     المردود بالضبط هي `delivery / total` (‏`return_refund_calculator`
///     يوزّع التوصيلَ بنسبة الأسطر المردودة نفسِها)، والتوصيلُ خارجَ
///     `totalNetRevenue` أصلاً فيخرج من المردود كذلك.
///   * التكلفةُ = `cogs` القيد.
///
/// فاتورةٌ بلا قيدٍ محلّيّ (نسخةُ عميلٍ لم يصلها القيدُ بعد) تُحسب **تقديراً**
/// وتُعَدّ في [ReturnsProfitBasis.estimatedInvoiceCount] لتعلنه الشاشة: الإيرادُ
/// بنسبة الفاتورة نفسِها والتكلفةُ بنسبة `COGS/المبيعات` للمجمل — وهو التقديرُ
/// القديمُ مقصوراً على تلك الفاتورة.
ReturnsProfitBasis returnsProfitBasis({
  required SalesAnalytics gross,
  required Map<int, double> returnedByInvoice,
  required List<SalesInvoiceData> displayedInvoices,
  required Map<int, ({double cogs, double vat})> ledgerByInvoice,
}) {
  var netRevenue = 0.0;
  var cogs = 0.0;
  var estimated = 0;
  for (final inv in displayedInvoices) {
    final refund = returnedByInvoice[inv.id];
    if (refund == null || refund <= 0 || inv.total <= 0) continue;
    final cap = refund > inv.total ? inv.total : refund;
    final deliveryShare = cap * inv.deliveryFee / inv.total;
    final ledger = ledgerByInvoice[inv.id];
    if (ledger != null) {
      final share = cap / refund;
      netRevenue += cap - ledger.vat * share - deliveryShare;
      cogs += ledger.cogs * share;
    } else {
      estimated++;
      netRevenue += cap * (inv.total - inv.tax) / inv.total - deliveryShare;
      if (gross.totalSales > 0) cogs += cap * gross.totalCOGS / gross.totalSales;
    }
  }
  return ReturnsProfitBasis(
    netRevenue: netRevenue,
    cogs: cogs,
    estimatedInvoiceCount: estimated,
  );
}
