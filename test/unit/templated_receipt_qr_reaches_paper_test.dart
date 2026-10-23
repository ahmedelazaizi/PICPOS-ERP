// ═══════════════════════════════════════════════════════════════════════════
// المسارُ الأوّلُ لإيصال البيع — `TemplatedInvoiceService` — يحترم قرارَ الرمز.
// ═══════════════════════════════════════════════════════════════════════════
//
// إيصالُ البيع في PicPos له **ثلاثةُ** مواضعِ رسمٍ للرمز، وهذا أوّلُها وأكثرُها
// مروراً: `printing_service` يجرّبه قبل `InvoiceGenerator` وقبل التخطيط
// المكتوب في الكود. وكان يُرمِّز `invoiceNumber` حرفيّاً بلا قرارٍ ولا وسم —
// فجهازٌ مسجَّلٌ ضريبيّاً كان يطبع منه رمزاً غيرَ ضريبيٍّ بلا أن يعرف.
//
// `receipt_qr_reaches_paper_test` يقيس الموضعَ الثاني (‏`TemplatePdfRenderer`).
// وهذا يقيس الأوّل — بنفس الأداة (‏`deshapeArabic`) ونفس المرساتين.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  const sale = ReceiptSaleSummary(
    invoiceNumber: 'TPL-1',
    issuedAt: '2026-09-01',
    total: '210.00',
    companyName: 'شركة',
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();

    final json = await rootBundle
        .loadString('assets/invoice_templates/thermal_modern.json');
    final id = await db.importTemplateFromJson(json);
    await db.setDefaultTemplate(id);

    // 🔴 مرساتان غيرُ دائريّتين: الحاسمُ يختار **هذا** القالبَ بعينه، وهو
    //    يحمل عنصرَ `qr_code` فعلاً — وإلّا كان «لا وسم» نتيجةَ قالبٍ آخر أو
    //    قالبٍ بلا عنصرٍ لا نتيجةَ عطب.
    final resolved = await db.getDefaultTemplateByCategory('thermal', 'receipt');
    expect(resolved?.id, id,
        reason: 'الحاسمُ يجب أن يختار القالبَ المستورَد — وإلّا فالقياسُ على '
            'قالبٍ آخر');
    final withData = await db.getTemplateWithData(id);
    expect(
      withData!.elements.where((e) => e.elementType == 'qr_code'),
      isNotEmpty,
      reason: 'thermal_modern يجب أن يحمل عنصرَ `qr_code`',
    );
  });

  tearDown(() => db.close());

  Future<PdfProbe> render(ReceiptQr? qr) async {
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: 'thermal',
      category: 'receipt',
      invoiceNumber: 'TPL-1',
      date: DateTime(2026, 9, 1),
      customerName: 'عميل',
      customerPhone: null,
      customerAddress: null,
      items: const [
        {'name': 'صنف', 'quantity': 2.0, 'price': 100.0, 'total': 200.0}
      ],
      subtotal: 200.0,
      discount: 0.0,
      tax: 10.0,
      deliveryFee: 0.0,
      total: 210.0,
      paid: 210.0,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
      receiptQr: qr,
    ))
        .bytes;
    return probePdf(bytes);
  }

  String paperText(PdfProbe pdf) =>
      deshapeArabic(pdf.allTexts.map((t) => t.text).join(' '));

  bool saysNonFiscal(PdfProbe pdf) =>
      paperText(pdf).contains(deshapeArabic(kNonFiscalQrDisclaimer));

  test('مرساة: الورقةُ تُرسَم وردُّ العرض يطابق عربيّاً معروفاً', () async {
    final pdf = await render(null);
    expect(pdf.allTexts, isNotEmpty);
    expect(paperText(pdf), contains('شركة'),
        reason: 'إن لم يُطابَق اسمُ المنشأة فأداةُ المطابقة معطّلةٌ وكلُّ '
            'توكيدٍ سلبيٍّ بعدها زور');
  });

  test('🔴 غيرُ ضريبيٍّ ⇒ الوسمُ يصل الورقةَ من هذا المسار', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: false,
      submissionStatus: null,
      gatewayQrCode: null,
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isTrue,
        reason: 'المسارُ الأكثرُ مروراً كان يُرمِّز رقمَ الفاتورة بلا وسم');
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
