// ═══════════════════════════════════════════════════════════════════════════
// الإيصال كان بيحسب رسوم التوصيل مرتين ⇒ «متبقي» على فاتورة مدفوعة بالكامل
// ═══════════════════════════════════════════════════════════════════════════
//
// `salesInvoices.total` المخزَّن **بيشمل رسوم التوصيل بالفعل**:
//     finalTotal = subtotal − discount + tax + deliveryFee
//     (sales_transaction_orchestrator.dart:635-636)
//
// وطبقة الطباعة كانت بتجمعها تاني (`grandTotal = total + deliveryFee`)،
// وبتشتق «الباقي» و«المتبقي» من الرقم المتضخّم ده.
//
// الفئة دي **لم تُقَس قط**: مفيش اختبار واحد في المستودع بيمسّ أي مولّد
// طباعة. الحساب اتشال من جوّه باني الـPDF لكلاس صغير عشان يبقى قابلاً
// للاختبار — ده كان السبب الحقيقي إن العطل عاش.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/thermal_receipt_generator.dart';

void main() {
  group('ReceiptTotals — فاتورة توصيل', () {
    // أصناف ١٠٠ · توصيل ٥ · بلا خصم أو ضريبة ⇒ المخزَّن total = ١٠٥
    // والعميل دفع ١٠٥ كاملة.
    ReceiptTotals subject() => ReceiptTotals.from(
          total: 105,
          paid: 105,
          deliveryFee: 5,
        );

    test('الإجمالي = المخزَّن، من غير ما يتجمع عليه التوصيل تاني', () {
      expect(subject().grandTotal, closeTo(105, 0.0005),
          reason: 'التوصيل اتحسب مرتين');
    });

    test('المجموع الفرعي = مجموع الأصناف من غير التوصيل', () {
      expect(subject().itemsSubtotal, closeTo(100, 0.0005));
    });

    test('فاتورة مدفوعة بالكامل مالهاش «متبقي»', () {
      expect(subject().remaining, closeTo(0, 0.0005),
          reason: 'الورقة بتقول العميل مديون والقاعدة بتقول صفر');
    });

    test('ومالهاش «باقي» كمان', () {
      expect(subject().change, closeTo(0, 0.0005));
    });
  });

  group('ReceiptTotals — الحالات العادية لسه مظبوطة', () {
    test('بيعة بسيطة بلا توصيل: الإجمالي = المخزَّن', () {
      final t = ReceiptTotals.from(total: 50, paid: 50);
      expect(t.grandTotal, closeTo(50, 0.0005));
      expect(t.itemsSubtotal, closeTo(50, 0.0005));
      expect(t.change, closeTo(0, 0.0005));
      expect(t.remaining, closeTo(0, 0.0005));
    });

    test('العميل دفع أكتر ⇒ باقي، ومفيش متبقي', () {
      final t = ReceiptTotals.from(total: 50, paid: 60);
      expect(t.change, closeTo(10, 0.0005));
      expect(t.remaining, closeTo(0, 0.0005));
    });

    test('العميل دفع أقل ⇒ متبقي، ومفيش باقي', () {
      final t = ReceiptTotals.from(total: 50, paid: 30);
      expect(t.remaining, closeTo(20, 0.0005));
      expect(t.change, closeTo(0, 0.0005));
    });

    test('خصم وضريبة: المجموع الفرعي بيترجع لمجموع الأصناف', () {
      // أصناف ٢٠٠ · خصم ٢٠ · ضريبة ١٦ · توصيل ٥ ⇒ total = ٢٠١
      final t = ReceiptTotals.from(
          total: 201, paid: 201, discount: 20, tax: 16, deliveryFee: 5);
      expect(t.itemsSubtotal, closeTo(200, 0.0005));
      expect(t.grandTotal, closeTo(201, 0.0005));
      expect(t.remaining, closeTo(0, 0.0005));
    });
  });
}
