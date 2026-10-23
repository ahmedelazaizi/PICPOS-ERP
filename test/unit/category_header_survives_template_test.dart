// فاصلُ التصنيف يبقى فاصلاً في مسار القالب — لا يصير صنفاً.
//
// ── فئةُ العطب (‏بلاغٌ ميدانيٌّ من UralCash، وقِيس عندنا 2026-08-12) ───────
// «على فاتورة المطبخ تظهر التصنيفاتُ كصنف. لو بِيع صنفٌ من تصنيف *عرايس*
// يُطبع *عرايس* بدل الصنف. يحدث عند شبك طابعتين؛ وبالطابعة الرئيسية يُطبع
// الصنف.»
//
// و«الطابعتان» ليستا السبب بل العلامة: `held_orders_dialog.dart` يحقن سطرَ
// التصنيف بشرط `grouped.length > 1` — وطابعتان تعنيان عملياً تصنيفَين.
// بتصنيفٍ واحدٍ لا فواصلَ أصلاً فالطباعةُ سليمة.
//
// والسببُ حدُّ تحويلٍ لا رسم: `InvoiceItem.isCategoryHeader` رايةُ **عرضٍ**
// لا بيانات. والمسارُ الحراريُّ يحترمها (`thermal_receipt_generator.dart`
// يرسم `— الاسم —` بعرض الجدول)، بينما مسارُ القالب يحوّل إلى
// `Map<String, dynamic>` بخمسة مفاتيحَ لا سادسَ لها:
//     {'name', 'quantity', 'price', 'total', 'note'}
// فالرايةُ تسقط **بلا خطأ ترجمةٍ ولا اختبارٍ أحمر**، ويصل سطرُ التصنيف
// (كمّيتُه صفر) إلى الجدول صنفاً عادياً.
//
// ── الدرسُ الذي يحرسه هذا الملف ────────────────────────────────────────────
// أيُّ حقلٍ يحمل **معنى عرضٍ** — راية، نوعُ سطر، محاذاة — يضيع في أيّ `map`
// إلى `Map<String, dynamic>` صامتاً. فالحارسُ على حدّ التحويل لا على الرسم.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('حدُّ التحويل لا يُسقط الراية', () {
    test('مسارُ المطبخ يمرّر `isCategoryHeader` إلى القالب', () {
      final src =
          File('lib/services/invoice_generator.dart').readAsStringSync();

      // كتلةُ التحويل داخل `printWorkOrderReceipt` — وهي المسارُ الوحيدُ
      // الذي تُحقن فيه فواصلُ التصنيف اليوم.
      final at = src.indexOf('printWorkOrderReceipt');
      expect(at, greaterThan(0), reason: 'تغيّر اسمُ الدالّة — راجع الحارس');
      final block = src.substring(at, src.indexOf('printWithTemplate', at));

      expect(
        block.contains('isCategoryHeader'),
        isTrue,
        reason: 'رايةُ العرض تسقط في التحويل فيُطبع اسمُ التصنيف صنفاً',
      );
    });
  });

  group('المُصيِّر يميّز سطرَ التصنيف', () {
    test('الرايةُ المرفوعةُ تُقرأ فاصلاً', () {
      expect(
        TemplatedInvoiceService.isCategoryHeaderRow(
            const {'name': 'عرايس', 'isCategoryHeader': true}),
        isTrue,
      );
    });

    test('صنفٌ عاديٌّ ليس فاصلاً', () {
      expect(
        TemplatedInvoiceService.isCategoryHeaderRow(
            const {'name': 'شاورما', 'quantity': 2}),
        isFalse,
      );
    });

    test('قيمةٌ غيرُ منطقيةٍ من JSON لا تُقرأ صحيحاً', () {
      // `as bool?` على قيمةٍ من JSON رميةٌ لا قراءة — ثلاثُ مرّاتٍ في يوم.
      expect(
        TemplatedInvoiceService.isCategoryHeaderRow(
            const {'name': 'س', 'isCategoryHeader': 'true'}),
        isFalse,
      );
    });

    test('جدولٌ فيه فواصلُ تصنيفٍ يُرسم بلا انهيار', () async {
      final bytes = await TemplatedInvoiceService.debugRenderItemsTable(
        items: [
          {'name': 'عرايس', 'quantity': 0.0, 'price': 0.0, 'total': 0.0,
           'isCategoryHeader': true},
          {'name': 'عروسة شاورما', 'code': 'P-1', 'quantity': 2.0,
           'price': 30.0, 'discount': 0.0, 'tax': 0.0, 'total': 60.0},
          {'name': 'مشويات', 'quantity': 0.0, 'price': 0.0, 'total': 0.0,
           'isCategoryHeader': true},
          {'name': 'كفتة', 'code': 'P-2', 'quantity': 1.0,
           'price': 85.0, 'discount': 0.0, 'tax': 0.0, 'total': 85.0},
        ],
      );

      expect(bytes.length, greaterThan(1000));
      // الشكلُ نفسُه — سطرٌ بعرض الجدول لا صفُّ أعمدةٍ — لا يُقاس من بايتاتٍ
      // مضغوطةٍ بخطٍّ مُجزَّأ. يُصرَّح به ويُنظر إليه على الورق.
    });
  });
}
