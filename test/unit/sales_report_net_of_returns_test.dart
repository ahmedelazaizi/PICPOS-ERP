// ═══════════════════════════════════════════════════════════════════════════
// §٣-أ — تقريرُ المبيعات صافياً من المرتجعات · الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// البلاغ: فاتورةٌ بـ١٨ ثم مرتجعٌ جزئيٌّ بـ٤ — بطاقةُ «إجمالي المبيعات» ظلّت
// تقول ١٨، فاختلفت عن شاشة الفواتير وعن لوحة التحكم.
//
// العقدُ موثَّقٌ في `sales_analytics_dao.dart` (getSalesAnalytics): «الشاشة
// تستلم المبيعاتِ الاعتيادية خاماً **وتطرح المرتجعَ بنفسها**». الاستعلامُ
// يستثني `status IN ('returned','cancelled','voided')` ومستنداتِ
// `sale_type='return'` فقط ⇒ الفاتورةُ المرتجَعةُ **جزئياً** (‏حالتُها
// `partial_return`) تُحتسب بقيمتها الكاملة ولا يطرحها أحد.
//
// هذا الملفّ يقفل الحسابَ الخالص وحدَه (بلا قاعدة بيانات)؛ ونظيرُه
// `test/integration/sales_report_net_of_returns_e2e_test.dart` يقفل المصدرَين
// على قاعدةٍ حقيقية.
//
// ⚠️ لماذا القصُّ لكلّ فاتورةٍ على حدة ولا يُطرح إجماليُّ المرتجعات جزافاً:
// المرتجعُ **الكامل** مطروحٌ أصلاً بالاستثناء (حالتُه `returned` فلا يدخل
// المجملَ ولا يظهر في الجدول)، فطرحُه ثانيةً يشيله مرّتين. والحسمُ لكلّ
// فاتورةٍ **معروضةٍ** يمنع الازدواجَ بالبناء لا بالانتباه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/sales_returns_netting.dart';
import 'package:picpos_erp/data/database/database.dart';

/// مجملٌ اصطناعيٌّ بهامشٍ معلوم: مبيعاتٌ [sales] وربحٌ [profit].
SalesAnalytics gross({
  required double sales,
  required double profit,
  int count = 1,
}) =>
    SalesAnalytics(
      totalSales: sales,
      totalGrossProfit: profit,
      totalNetProfit: profit,
      totalProfit: profit,
      salesCount: count,
      invoiceCount: count,
      averageSaleValue: count == 0 ? 0 : sales / count,
      averageInvoiceValue: count == 0 ? 0 : sales / count,
      totalDiscount: 0,
      totalTax: 0,
      totalCOGS: sales - profit,
      totalNetRevenue: sales,
    );

void main() {
  group('clampedReturnedTotal — الحسمُ لكلّ فاتورةٍ معروضة', () {
    test('أرقامُ البلاغ: فاتورةُ ١٨ ومرتجعٌ جزئيٌّ بـ٤ ⇒ المحسوم ٤', () {
      final total = clampedReturnedTotal(
        returnedByInvoice: {7: 4.0},
        displayedInvoiceTotals: {7: 18.0},
      );
      expect(total, 4.0);
    });

    test('الردُّ المتجاوزُ يُقَصُّ عند قيمة الفاتورة — لا سطرَ سالب', () {
      // ردٌّ بـ٢٥ على فاتورةِ ١٨ كان سيجعل هذا السطرَ −٧ فيقاصّ مبيعاتِ
      // فواتيرَ أخرى ويُنقص المجملَ بأكثر ممّا رُدّ فعلاً.
      final total = clampedReturnedTotal(
        returnedByInvoice: {7: 25.0},
        displayedInvoiceTotals: {7: 18.0},
      );
      expect(total, 18.0);
    });

    test('المرتجعُ الكاملُ لا يُطرح مرّتين — ليس في القائمة المعروضة أصلاً', () {
      // الفاتورةُ ٩ مرتجَعةٌ كلياً ⇒ حالتُها `returned` ⇒ يستثنيها
      // getSalesAnalytics و getSalesByDateRange(revenueOnly:true) معاً، فلا
      // تظهر في `displayedInvoiceTotals`. وجودُ ردٍّ لها في الخريطة يجب أن
      // يُهمَل، وإلا طُرحت من مبيعاتٍ لم تدخلها.
      final total = clampedReturnedTotal(
        returnedByInvoice: {7: 4.0, 9: 50.0},
        displayedInvoiceTotals: {7: 18.0},
      );
      expect(total, 4.0);
    });

    test('بلا مرتجعاتٍ ⇒ صفر · وبلا فواتيرَ معروضةٍ ⇒ صفر', () {
      expect(
        clampedReturnedTotal(
          returnedByInvoice: const {},
          displayedInvoiceTotals: {7: 18.0},
        ),
        0.0,
      );
      expect(
        clampedReturnedTotal(
          returnedByInvoice: {7: 4.0},
          displayedInvoiceTotals: const {},
        ),
        0.0,
      );
    });

    test('الردُّ السالبُ أو الصفريُّ لا يزيد المبيعات', () {
      // صفُّ خزينةٍ معكوسٌ أو مُلغىً قد يصل سالباً؛ طرحُ سالبٍ كان سيرفع
      // «إجمالي المبيعات» فوق المجمل.
      final total = clampedReturnedTotal(
        returnedByInvoice: {7: -5.0},
        displayedInvoiceTotals: {7: 18.0},
      );
      expect(total, 0.0);
    });

    test('عدّةُ فواتيرَ — كلٌّ تُقَصُّ عند قيمتها هي', () {
      final total = clampedReturnedTotal(
        returnedByInvoice: {1: 4.0, 2: 100.0, 3: 0.0},
        displayedInvoiceTotals: {1: 18.0, 2: 30.0, 3: 12.0},
      );
      expect(total, 34.0); // 4 + 30 (مقصوص) + 0
    });
  });

  group('netOfReturns — البطاقاتُ صافيةً', () {
    test('أرقامُ البلاغ: ١٨ − ٤ ⇒ ١٤', () {
      final net = netOfReturns(gross(sales: 18, profit: 6), 4);
      expect(net.totalSales, 14.0);
    });

    test('الهامشُ محفوظ — الربحُ يتناسب مع ما بقي', () {
      // netProfit = grossProfit × (1 − returned/gross)
      final g = gross(sales: 100, profit: 40); // هامش ٤٠٪
      final net = netOfReturns(g, 25);
      expect(net.totalSales, 75.0);
      expect(net.totalProfit, closeTo(30.0, 1e-9));
      expect(net.totalProfit / net.totalSales, closeTo(0.40, 1e-9));
      // والتكلفةُ تتبع، وإلا تناقض المجموع: صافي المبيعات − صافي الربح.
      expect(net.totalCOGS, closeTo(45.0, 1e-9));
      expect(net.totalSales - net.totalCOGS, closeTo(net.totalProfit, 1e-9));
    });

    test('مبيعاتٌ صفر ⇒ لا قسمةَ على صفر ولا NaN', () {
      final net = netOfReturns(gross(sales: 0, profit: 0, count: 0), 0);
      expect(net.totalSales, 0.0);
      expect(net.totalProfit, 0.0);
      expect(net.totalProfit.isNaN, isFalse);
      expect(net.averageInvoiceValue.isNaN, isFalse);
      expect(net.averageInvoiceValue, 0.0);
    });

    test('ردٌّ بلا مبيعاتٍ لا يولّد NaN ولا سالباً', () {
      final net = netOfReturns(gross(sales: 0, profit: 0, count: 0), 4);
      expect(net.totalSales, 0.0);
      expect(net.totalProfit.isNaN, isFalse);
      expect(net.totalProfit, 0.0);
    });

    test('لا مرتجعَ ⇒ المجملُ كما هو، حرفياً', () {
      final g = gross(sales: 18, profit: 6);
      final net = netOfReturns(g, 0);
      expect(net.totalSales, g.totalSales);
      expect(net.totalProfit, g.totalProfit);
      expect(net.totalCOGS, g.totalCOGS);
    });

    test('عددُ الفواتيرِ لا ينقص — الفاتورةُ المرتجَعةُ جزئياً ما زالت بيعاً',
        () {
      // البطاقةُ يجب أن تطابق **عددَ صفوف الجدول**: الفاتورةُ المرتجَعةُ
      // جزئياً معروضةٌ في الجدول، فإنقاصُ العدّاد كان سيخالفه.
      final net = netOfReturns(gross(sales: 18, profit: 6, count: 3), 4);
      expect(net.invoiceCount, 3);
      expect(net.salesCount, 3);
      // ومتوسطُ الفاتورة يتبع الصافي على نفس العدد.
      expect(net.averageInvoiceValue, closeTo(14.0 / 3, 1e-9));
    });

    test('ردٌّ يساوي المجملَ ⇒ صفرٌ لا سالب', () {
      final net = netOfReturns(gross(sales: 18, profit: 6), 18);
      expect(net.totalSales, 0.0);
      expect(net.totalProfit, closeTo(0.0, 1e-9));
    });
  });
}
