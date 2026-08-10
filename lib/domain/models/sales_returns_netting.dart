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
/// الربحُ يتناسب: `netProfit = grossProfit × (1 − returned/gross)`.
/// ولماذا التناسبُ لا الحسمُ من الأصناف: مسارُ المرتجع عندنا يكتب صفَّ
/// فاتورةٍ **بلا أسطرِ أصناف** (`insertSalesInvoiceWithoutStock`)، فلا وجودَ
/// لتكلفةِ سطرٍ مرتجَعٍ تُخصم. والتناسبُ يحفظ الهامشَ وهو أقربُ تقديرٍ متّسق.
///
/// ولا يُوجَّه الربحُ إلى دفتر الأستاذ: فلاترُ الشاشة (مستخدم · دفع · نوع ·
/// مخزن) بلا مقابلٍ محاسبيّ، فالرقمُ كان سينحرف صامتاً عن الجدول تحتها.
///
/// **عددُ الفواتير لا ينقص**: الفاتورةُ المرتجَعةُ جزئياً ما زالت بيعاً
/// معروضاً في الجدول، فإنقاصُ العدّاد كان سيخالف عددَ الصفوف. والضريبةُ
/// والخصمُ يُتركان كما هما — بطاقةُ الضريبة تقرأ من الأستاذ في شاشتها،
/// وتحريكُها هنا كان سيخالفها.
SalesAnalytics netOfReturns(SalesAnalytics gross, double returnedTotal) {
  if (returnedTotal <= 0) return gross;

  final rawNet = gross.totalSales - returnedTotal;
  final netSales = rawNet < 0 ? 0.0 : rawNet;

  // مبيعاتٌ صفرٌ مع ردٍّ (مدىً لا بيعَ فيه ورَدٌّ على بيعٍ أقدم) ⇒ لا قسمةَ
  // على صفر: المعاملُ صفرٌ والصافي صفر.
  final factor = gross.totalSales > 0 ? netSales / gross.totalSales : 0.0;

  return SalesAnalytics(
    totalSales: netSales,
    totalGrossProfit: gross.totalGrossProfit * factor,
    totalNetProfit: gross.totalNetProfit * factor,
    totalProfit: gross.totalProfit * factor,
    salesCount: gross.salesCount,
    invoiceCount: gross.invoiceCount,
    averageSaleValue:
        gross.salesCount > 0 ? netSales / gross.salesCount : 0.0,
    averageInvoiceValue:
        gross.invoiceCount > 0 ? netSales / gross.invoiceCount : 0.0,
    totalDiscount: gross.totalDiscount,
    totalTax: gross.totalTax,
    totalCOGS: gross.totalCOGS * factor,
    totalNetRevenue: gross.totalNetRevenue * factor,
  );
}
