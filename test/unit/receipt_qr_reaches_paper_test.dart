// ═══════════════════════════════════════════════════════════════════════════
// الرمزُ غيرُ الضريبيِّ يجب أن يُعرَف على الورق — قرارُ المالك 2026-09-02.
// ═══════════════════════════════════════════════════════════════════════════
//
// جهازٌ لم تُفعَّل عليه الفاتورةُ الإلكترونيّة يطبع رمزاً ببيانات البيعة،
// بديلاً رقميّاً عن الورق. وهو **لا يُعترف به ضريبيّاً** — فلا بدّ أن يقول
// ذلك على الورقة نفسِها، وإلّا قُدِّم رمزٌ بلا بياناتٍ ضريبيّةٍ على أنّه
// إيصالٌ ضريبيّ.
//
// و`receipt_qr_decision_test` يقيس القرارَ وحدَه — دالّةً خالصة. وهذا الملفُّ
// يقيس **ما يصل الورقة**: أنّ القرارَ يمرُّ بالراسم فعلاً ولا يسقط في الطريق.
// وهي فجوةٌ مقيسةٌ سلفاً في هذا المستودع: الشعارُ كان يسقط في مسارٍ حيٍّ
// كاملٍ بين طبقتين، والاختبارُ الخالصُ وحدَه لم يكن ليمسكه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/receipt_qr_decision.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late InvoiceTemplateWithData template;

  const sale = ReceiptSaleSummary(
    invoiceNumber: 'TH-1',
    issuedAt: '2026-09-01',
    total: '210.00',
    companyName: 'شركة',
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    final json = await rootBundle
        .loadString('assets/invoice_templates/thermal_modern.json');
    final id = await db.importTemplateFromJson(json);
    template = (await db.getTemplateWithData(id))!;

    // 🔴 مرساةٌ غيرُ دائريّة: القالبُ يحمل عنصرَ `qr_code` فعلاً — وإلّا كان
    //    «لا رمز» نتيجةَ قالبٍ بلا عنصرٍ لا نتيجةَ عطب.
    expect(
      template.elements.where((e) => e.elementType == 'qr_code'),
      isNotEmpty,
      reason: 'thermal_modern يجب أن يحمل عنصرَ `qr_code`',
    );
  });

  tearDown(() => db.close());

  Future<PdfProbe> render(ReceiptQr? qr) async {
    final bytes = await TemplatePdfRenderer.generatePdf(
      templateData: template,
      invoiceData: TemplateInvoiceData(
        invoiceNumber: 'TH-1',
        date: DateTime(2026, 9, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 2, price: 100, total: 200),
        ],
        subtotal: 200,
        tax: 10,
        total: 210,
        paid: 210,
        companyName: 'شركة',
        receiptQr: qr,
      ),
    );
    return probePdf(bytes);
  }

  /// نصُّ الورقة كلُّه مردوداً إلى الحروف الأساسيّة.
  ///
  /// الحزمةُ تكتب العربيَّ بأشكال العرض ومقطّعاً كلمةً كلمة، فالوصلُ بمسافةٍ
  /// ثمّ الردُّ يجعل الجملةَ قابلةً للمطابقة.
  String paperText(PdfProbe pdf) =>
      deshapeArabic(pdf.allTexts.map((t) => t.text).join(' '));

  bool saysNonFiscal(PdfProbe pdf) =>
      paperText(pdf).contains(deshapeArabic(kNonFiscalQrDisclaimer));

  test('مرساة: الورقةُ تُرسَم أصلاً', () async {
    final pdf = await render(null);
    expect(pdf.allTexts, isNotEmpty,
        reason: 'بلا نصٍّ مرسومٍ تمرُّ التوكيداتُ السلبيّةُ أدناه زوراً');
  });

  // 🔴 مرساةُ الأداة: لولاها لكانت التوكيداتُ السلبيّةُ أدناه تمرُّ لأنّ
  //    المطابقةَ مستحيلةٌ — لا لأنّ الوسمَ غائب. فنُثبت أوّلاً أنّ الردَّ
  //    يُخرج عربيّاً مطابِقاً لنصٍّ نعرف أنّه على الورقة.
  test('مرساة: ردُّ أشكال العرض يُنتج عربيّاً قابلاً للمطابقة', () async {
    final pdf = await render(null);
    expect(paperText(pdf), contains('شركة'),
        reason: 'اسمُ المنشأة مطبوعٌ قطعاً — فإن لم يُطابَق بعد الردّ فأداةُ '
            'المطابقة معطّلةٌ وكلُّ توكيدٍ سلبيٍّ بعدها زور');
  });

  test('🔴 غيرُ ضريبيٍّ ⇒ الوسمُ يصل الورقةَ فعلاً', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: false,
      submissionStatus: null,
      gatewayQrCode: null,
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isTrue,
        reason: 'رمزٌ بلا بياناتٍ ضريبيّةٍ خرج بلا وسمٍ يميّزه — فيُقدَّم '
            'على أنّه إيصالٌ ضريبيّ');
  });

  test('🔴 ضريبيٌّ ⇒ لا وسمَ إطلاقاً', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: true,
      submissionStatus: 'valid',
      gatewayQrCode: 'AQ1RUUEBAgMEBQYHCA==',
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isFalse,
        reason: 'وسمُ «غير ضريبيّ» على إيصالٍ ضريبيٍّ صحيحٍ يُبطل قيمتَه');
  });

  test('🔴 مُفعَّلٌ بلا اعتمادٍ بعد ⇒ لا وسمَ ولا رمزَ مضلِّل', () async {
    final pdf = await render(resolveReceiptQr(
      eInvoiceEnabled: true,
      submissionStatus: 'pending',
      gatewayQrCode: null,
      sale: sale,
    ));

    expect(saysNonFiscal(pdf), isFalse,
        reason: 'جهازٌ مسجَّلٌ ضريبيّاً لا يطبع وسمَ «غير ضريبيّ» أبداً');
  });
}
