// قيمُ عناصر قالب إغلاق الوردية.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// محرِّرُ القوالب يعرض نوعَ قالبٍ كاملاً (`shift_closing`) و**ستّةَ عشرَ**
// عنصراً تحته، ويزرع قالباً افتراضياً باسم «تقرير إغلاق الوردية». والمستخدمُ
// يصمّم ويحفظ — ثم لا يُطبع شيءٌ من ذلك أبداً:
//
//   · الإقفالُ يطبع من مولّدٍ **ثابت** (`shift_closing_print.dart`)
//   · و`printWithTemplate` لا تُنادى إلا للفواتير
//   · ولو نُوديت، فـ`_getDataValue` لا تعرف `shift_*` فترجّع `''`، وعنصرٌ
//     بلا تسميةٍ وبلا قيمةٍ يرجع `SizedBox()` — أي **يختفي**
//
// فالمحرِّرُ يَعِد بما لا يفي به. وهذا الملفُّ يقيس نصفَ الوعد الأول: أن
// القيمةَ تُحلّ أصلاً. (‏الوصلُ بمسار الطباعة يقيسه
// `shift_template_wired_test`.)

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/shift_closing_snapshot.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

/// لقطةٌ بأرقامٍ **مميَّزةٍ لكلّ حقل** — لو تبادل حقلان مكانَيهما ظهر ذلك.
const _snap = ShiftClosingSnapshot(
  invoiceCount: 17,
  totalSales: 1234.5,
  systemCash: 900.25,
  systemCard: 200.75,
  systemClick: 133.5,
  actualCash: 890.25,
  actualCard: 205.75,
  actualClick: 133.5,
  cashVariance: -10.0,
  cardVariance: 5.0,
  clickVariance: 0.0,
  totalVariance: -5.0,
  totalExpenses: 60.0,
  cashRefunds: 25.0,
  cashIncome: 40.0,
  creditSales: 300.0,
  creditSalesCount: 3,
  openingBalance: 100.0,
  employeeName: 'صبري',
  companyName: 'سوبر ماركت',
);

void main() {
  group('كلُّ عنصرِ ورديةٍ يعرضه المحرر له قيمةٌ تُحلّ', () {
    // نقارن **بالرقم** لا بالنصّ المنسَّق كي لا يتعلّق الاختبارُ بالتنسيق.
    const expected = <String, double>{
      'shift_invoice_count': 17,
      'shift_total_sales': 1234.5,
      'shift_system_cash': 900.25,
      'shift_actual_cash': 890.25,
      'shift_cash_variance': -10.0,
      'shift_system_card': 200.75,
      'shift_actual_card': 205.75,
      'shift_card_variance': 5.0,
      'shift_total_variance': -5.0,
      'shift_total_expenses': 60.0,
      'shift_cash_refunds': 25.0,
      // المجاميعُ المشتقّة — لا حقلَ لها في اللقطة فتُحسب
      'shift_total_system': 900.25 + 200.75 + 133.5,
      'shift_total_actual': 890.25 + 205.75 + 133.5,
    };

    expected.forEach((type, value) {
      test(type, () {
        final out = TemplatedInvoiceService.resolveShiftValue(type, _snap);
        expect(out, isNotNull,
            reason: '«$type» معروضٌ في المحرر ولا قيمةَ له ⇒ العنصرُ يختفي '
                'من المطبوع بلا أن ينطق شيء');
        expect(
          double.tryParse(out!.replaceAll(',', '')),
          closeTo(value, 0.001),
          reason: '«$type» رجع "$out" والمتوقَّع $value',
        );
      });
    });

    test('shift_status ينطق بالعجز أو الزيادة', () {
      final out = TemplatedInvoiceService.resolveShiftValue(
          'shift_status', _snap);
      expect(out, isNotNull);
      expect(out, contains('عجز'),
          reason: 'الفرقُ ‑٥ ⇒ عجز. حالةٌ فارغةٌ تخفي أهمَّ رقمٍ في التقرير');
    });

    test('shift_number يرجّع نصّاً غيرَ فارغ', () {
      expect(TemplatedInvoiceService.resolveShiftValue('shift_number', _snap),
          isNotNull);
    });

    test('ضابط: نوعٌ ليس من الورديّة يرجّع null لا صفراً', () {
      // لولا هذا لمرّ الحلُّ بإرجاع '0' لكلّ شيء.
      expect(TemplatedInvoiceService.resolveShiftValue('company_name', _snap),
          isNull);
    });
  });
}
