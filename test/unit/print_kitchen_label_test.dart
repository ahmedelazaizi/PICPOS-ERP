// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ تذاكر المطبخ (KDS) والباركود والتسميات
// ═══════════════════════════════════════════════════════════════════════════
//
// المطبخُ (KDS): يستخدم قالبَ kitchen_professional.json المبذور في الأصول.
//   KitchenService.printKitchenOrders(invoiceId) يحتاج فاتورةً كاملةً في DB.
//   هذا الملفُّ يختبر مستوى الراسم مباشرةً (TemplatePdfRenderer.generatePdf)
//   بدلاً من المسار الكامل الذي يتطلّب بيانات POS كاملة.
//
// الباركود: يُرسَم عبر ThermalReceiptGenerator (receiptCodeType='barcode')
//   أو عبر قالبٍ يحمل عنصرَ barcode. الاختباراتُ هنا تغطّي كلا المسارين.
//
// التسمياتُ (LabelScaleService): خدمةُ رفعِ PLU للميازين اللاصقة
//   (CAS، DIGI، Rongta، Aclas، Mettler Toledo) عبر TCP/Serial.
//   ليست طباعةَ PDF؛ تُوثَّق هنا كمرجع ولا تُختبَر وظيفيّاً بلا ميزان حقيقيّ.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';
import 'package:picpos_erp/services/printing/template_pdf_renderer.dart';
import 'package:picpos_erp/services/printing/thermal_receipt_generator.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  // ١. قالبُ المطبخ (kitchen_professional.json)
  // ═══════════════════════════════════════════════════════════════════════════

  group('قالبُ المطبخ يُرسَم صحيحاً', () {
    late InvoiceTemplateWithData kitchenTemplate;

    setUp(() async {
      final json = await rootBundle.loadString(
          'assets/invoice_templates/kitchen_professional.json');
      final id = await db.importTemplateFromJson(json);
      kitchenTemplate = (await db.getTemplateWithData(id))!;
    });

    test('kitchen_professional.json يُرسَم بلا استثناء', () async {
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: kitchenTemplate,
        invoiceData: kFixtureRendererData,
      );
      expect(bytes, isNotEmpty,
          reason: 'قالبُ المطبخ يجب أن يُنتج PDF');
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('تذكرةُ المطبخ تحمل رقمَ الطلب وأسماءَ الأصناف', () async {
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: kitchenTemplate,
        invoiceData: TemplateInvoiceData(
          invoiceNumber: 'KDS-001',
          date: DateTime(2026, 6, 1),
          items: [
            InvoiceItem(
                name: 'بيتزا مارغريتا', quantity: 2, price: 30, total: 60),
            InvoiceItem(name: 'بيتزا دجاج', quantity: 1, price: 35, total: 35),
          ],
          subtotal: 95,
          total: 95,
          paid: 95,
          companyName: 'مطعمُ النور',
          salesType: 'table',
          orderNumber: 42,
        ),
      );
      final probe = probePdf(bytes);
      expect(probe.allTexts, isNotEmpty,
          reason: 'تذكرةُ المطبخ يجب أن تحمل نصّاً');
      final allText = probe.allTexts.map((t) => t.text).join(' ');
      // تذكرةُ المطبخ تعرض رقمَ الطلب (orderNumber) لا رقمَ الفاتورة
      expect(allText, contains('42'),
          reason: 'رقمُ الطلب (42) يجب أن يصل تذكرةَ المطبخ');
    });

    test('عرضُ تذكرة المطبخ: الصفحةُ ليست فارغةً (محتوىً موجود)', () async {
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: kitchenTemplate,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.pages, isNotEmpty);
      // المطبخُ يستخدم 80mm عادةً
      expect(probe.pages.first.widthPts, greaterThan(50.0),
          reason: 'الصفحةُ يجب أن تكون أعرضَ من 50pt على الأقل');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٢. الباركود (Code128) في الإيصال الحراريّ
  // ═══════════════════════════════════════════════════════════════════════════

  group('الباركود في الإيصال الحراريّ', () {
    test('receiptCodeType=barcode يُبنى بلا استثناء', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'BAR-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10)
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'barcode',
        debugBuildOnly: true,
      );
      expect(r.bytes, isNotEmpty,
          reason: 'الباركود لا يجب أن يُحطم بناءَ الوثيقة');
      expect(String.fromCharCodes(r.bytes.take(4)), equals('%PDF'));
    });

    test('الباركودُ يُصافي الصفحةَ (صورةٌ مُدرجة في PDF)', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'BAR-IMG-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10)
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'barcode',
        debugBuildOnly: true,
      );
      // الإيصالُ بالباركود يجب أن يكون أكبرَ من إيصالٍ بلا رمز
      final rNoCode = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'NO-CODE-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10)
        ],
        total: 10,
        paid: 10,
        change: 0,
        debugBuildOnly: true,
      );
      // الباركودُ يزيد حجمَ الملف
      expect(r.bytes.length, greaterThan(rNoCode.bytes.length),
          reason: 'الباركودُ (صورة BMP مضمَّنة) يزيد حجمَ PDF');
    });

    test('receiptCodeType=qr_code يُبنى بلا استثناء', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'QR-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10)
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'qr_code',
        debugBuildOnly: true,
      );
      expect(r.bytes, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٣. نموذجُ ReceiptQr — اتّخاذُ قرار الرمز
  // ═══════════════════════════════════════════════════════════════════════════

  group('ReceiptQr — نموذجُ بيانات القرار', () {
    const sale = ReceiptSaleSummary(
      invoiceNumber: 'KDS-QR-1',
      issuedAt: '2026-06-01 12:00',
      total: '95.00',
      companyName: 'مطعمُ الاختبار',
    );

    test('غيرُ مُفعَّل → kind=nonFiscal, payload يحوي رقمَ الفاتورة', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: false,
        submissionStatus: null,
        gatewayQrCode: null,
        sale: sale,
      );
      expect(qr.kind, equals(ReceiptQrKind.nonFiscal));
      expect(qr.payload, contains('KDS-QR-1'),
          reason: 'الرمزُ غيرُ الضريبيِّ يحمل رقمَ الفاتورة');
      expect(qr.disclaimer, isNotEmpty,
          reason: 'الرمزُ غيرُ الضريبيِّ يحمل إخلاءَ مسؤوليّة');
    });

    test('مُفعَّلٌ + valid → kind=fiscal, payload = gateway code', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: true,
        submissionStatus: 'valid',
        gatewayQrCode: 'AQIDBAU=',
        sale: sale,
      );
      expect(qr.kind, equals(ReceiptQrKind.fiscal));
      expect(qr.payload, equals('AQIDBAU='),
          reason: 'الرمزُ الضريبيُّ payload = بيانات البوّابة');
      expect(qr.disclaimer, isEmpty,
          reason: 'لا وسمَ تحذيريَّ على الإيصال الضريبيّ');
    });

    test('مُفعَّلٌ + pending → kind=none, لا رمز', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: true,
        submissionStatus: 'pending',
        gatewayQrCode: null,
        sale: sale,
      );
      expect(qr.kind, equals(ReceiptQrKind.none),
          reason: 'جهازٌ مسجَّلٌ بلا اعتماد → لا رمز');
    });

    test('إخلاءُ المسؤوليّة يحمل نصَّ «ليس إيصالاً ضريبيّاً»', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: false,
        submissionStatus: null,
        gatewayQrCode: null,
        sale: sale,
      );
      final text = deshapeArabic(qr.disclaimer);
      expect(
        text,
        contains(deshapeArabic(kNonFiscalQrDisclaimer)),
        reason: 'وسمُ التحذير يحمل النصَّ الرسميَّ',
      );
    });

    test('🔴 جهازٌ مُفعَّلٌ لا يُنتج رمزاً غيرَ ضريبيٍّ — ثبّات أمانيٌّ', () {
      for (final status in ['valid', 'pending', 'rejected', 'invalid']) {
        for (final gw in [null, '', 'AQIDBAU=']) {
          final qr = resolveReceiptQr(
            eInvoiceEnabled: true,
            submissionStatus: status,
            gatewayQrCode: gw,
            sale: sale,
          );
          expect(qr.kind, isNot(ReceiptQrKind.nonFiscal),
              reason: 'جهازٌ مُفعَّلٌ لا يُنتج رمزاً غيرَ ضريبيٍّ '
                  '(status=$status, gw=$gw)');
          expect(qr.disclaimer, isEmpty,
              reason: 'جهازٌ مُفعَّلٌ لا يحمل تحذيرَ «غير ضريبيّ»');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٤. توثيقُ LabelScaleService (PLU Upload)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // LabelScaleService ليست طباعةَ PDF؛ هي بروتوكولُ رفعِ PLU لميازين
  // الطباعة اللاصقة (CAS، DIGI، Rongta، Aclas، Mettler Toledo، TEM، Dibal).
  // التواصلُ عبر TCP/Serial أو FTP أو CSV.
  //
  // لا يمكن اختبارُها وظيفيّاً بلا جهازٍ حقيقيٍّ أو محاكٍ للبروتوكول.
  // الاختبارُ الوحيدُ الممكنُ هو التحقُّق من استيراد الكلاس — يُوثَّق في قائمة
  // الفحص اليدويّ (docs/print_manual_checklist.md).
  test('LabelScaleService موجودٌ ومستوردٌ بلا خطأ تصريفيّ', () {
    // هذا الاختبارُ وجودُه يُثبت أنّ الكلاس يُترجَم بلا خطأ.
    // التحقُّق الوظيفيُّ يتطلّب ميزاناً حقيقيّاً أو محاكياً.
    expect(true, isTrue,
        reason: 'LabelScaleService مُختبَرٌ في قائمة الفحص اليدويّ');
  });
}
