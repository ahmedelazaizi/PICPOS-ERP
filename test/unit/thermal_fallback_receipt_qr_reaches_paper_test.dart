// ═══════════════════════════════════════════════════════════════════════════
// الموضعُ الثالثُ لإيصال البيع — التخطيطُ المكتوبُ في الكود — يحترم قرارَ الرمز.
// ═══════════════════════════════════════════════════════════════════════════
//
// `ThermalReceiptGenerator` هو ما يسقط إليه `InvoiceGenerator` حين لا قالبَ
// أو حين يخفق القالب. وكان يُرمِّز `invoiceNumber` في `_buildCodes` بلا قرارٍ
// ولا وسم — والسقوطُ إليه **صامت** (‏`catch` يطبع سطراً ويمضي)، فجهازٌ مسجَّلٌ
// ضريبيّاً قد يطبع منه رمزاً غيرَ ضريبيٍّ يوماً كاملاً دون أن يعرف أحدٌ أنّ
// القالبَ سقط.
//
// ولم يكن له مِقبضُ بايتات: يبني ويدفع إلى الطابعة في نفس النَّفَس. فأُضيف
// `debugBuildOnly` على عقد `TemplatedInvoiceService` نفسِه — الوثيقةُ ذاتُها
// تُبنى في الحالتين، وتُعاد بلا دفع.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/receipt_qr_decision.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/thermal_receipt_generator.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sale = ReceiptSaleSummary(
    invoiceNumber: 'TH-1',
    issuedAt: '2026-09-01',
    total: '210.00',
    companyName: 'شركة',
  );

  Future<PdfProbe> render(ReceiptQr? qr) async {
    final r = await ThermalReceiptGenerator.printThermalReceipt(
      invoiceNumber: 'TH-1',
      date: DateTime(2026, 9, 1),
      items: [InvoiceItem(name: 'صنف', quantity: 2, price: 100, total: 200)],
      total: 210,
      paid: 210,
      change: 0,
      tax: 10,
      companyName: 'شركة',
      // 🔴 بدونه لا يرسم `_buildCodes` شيئاً أصلاً — فتمرُّ التوكيداتُ
      //    السلبيّةُ زوراً على إيصالٍ بلا رمزٍ لا على قرارٍ صحيح.
      receiptCodeType: 'qr_code',
      receiptQr: qr,
      debugBuildOnly: true,
    );
    return probePdf(r.bytes);
  }

  String paperText(PdfProbe pdf) =>
      deshapeArabic(pdf.allTexts.map((t) => t.text).join(' '));

  bool saysNonFiscal(PdfProbe pdf) =>
      paperText(pdf).contains(deshapeArabic(kNonFiscalQrDisclaimer));

  test('مرساة: الورقةُ تُرسَم وردُّ العرض يطابق عربيّاً معروفاً', () async {
    final pdf = await render(null);
    expect(pdf.allTexts, isNotEmpty);
    expect(paperText(pdf), contains('شركة'));
  });

  test('🔴 غيرُ ضريبيٍّ ⇒ الوسمُ يصل الورقةَ من المسار الساقط', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: false,
      submissionStatus: null,
      gatewayQrCode: null,
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isTrue,
        reason: 'السقوطُ إلى هذا المسار صامت — فلو فاته الوسمُ لم يعرف أحد');
  });

  test('🔴 ضريبيٌّ ⇒ لا وسمَ إطلاقاً', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: true,
      submissionStatus: 'valid',
      gatewayQrCode: 'AQ1RUUEBAgMEBQYHCA==',
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isFalse);
  });

  test('🔴 مُفعَّلٌ بلا اعتمادٍ بعد ⇒ لا وسمَ', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: true,
      submissionStatus: 'pending',
      gatewayQrCode: null,
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isFalse);
  });
}
