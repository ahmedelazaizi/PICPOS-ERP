// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ الخطّ: لا Courier، لا Emoji، المطهِّر يعمل
// ═══════════════════════════════════════════════════════════════════════════
//
// يُغطِّي هذا الملفُّ:
//   • ملفُّ PDF الناتجُ لا يحمل /BaseFont /Courier (اسمُ الخطِّ في بيانات PDF)
//   • المطهِّر sanitizeForPdf() يُزيل الـ emoji ويُبقي العربيَّ والإنجليزيَّ
//   • الإيصالُ الحراريُّ المبذور (الفاتورة الحرارية) والقالبُ المبذورُ A4
//     والمطبخُ — كلُّها بلا Courier
//   • الأصنافُ ذاتُ emoji في أسمائها (من asset thermal_modern.json) تُطبع
//     بلا استثناء
//
// كيفيّةُ البحث عن Courier في ملفِّ PDF:
//   /BaseFont /Courier يظهر داخل كائنِ Dictionary لخطٍّ مُضمَّن في الـPDF.
//   package:pdf يُسمّي الخطوطَ المضمَّنةَ بأسمائها الحقيقيّة، فوجودُ
//   /Courier يعني أنّ نصّاً ما استخدم الخطَّ الافتراضيَّ بدلاً من Noto/Cairo.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/printing/pdf_text_sanitizer.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';
import 'package:ural_erp/services/printing/thermal_receipt_generator.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // ١. sanitizeForPdf — اختباراتٌ وحديّة
  // ═══════════════════════════════════════════════════════════════════════════

  group('sanitizeForPdf — المطهِّر', () {
    test('النصُّ العربيُّ النقيُّ يمرُّ كاملاً', () {
      const input = 'مؤسّسةُ النور التجاريّة';
      expect(sanitizeForPdf(input), equals(input));
    });

    test('النصُّ الإنجليزيُّ يمرُّ كاملاً', () {
      const input = 'Olive Oil 1L Extra Virgin';
      expect(sanitizeForPdf(input), equals(input));
    });

    test('الأرقامُ والعلاماتُ الأساسيّةُ تمرُّ', () {
      const input = '12,345.67 ر.س — 15%';
      expect(sanitizeForPdf(input), equals(input));
    });

    test('emoji 🛒 يُزال', () {
      expect(sanitizeForPdf('🛒 العميل'), equals(' العميل'));
    });

    test('emoji 💰 يُزال', () {
      expect(sanitizeForPdf('💰'), isEmpty);
    });

    test('emoji ✨ يُزال', () {
      expect(sanitizeForPdf('✨ شكراً ✨'), equals(' شكراً '));
    });

    test('📝 يُزال من notes', () {
      expect(sanitizeForPdf('📝 ملاحظة'), equals(' ملاحظة'));
    });

    test('نصٌّ مختلطٌ: Arabic + Emoji → يُبقي العربيَّ فقط', () {
      final result = sanitizeForPdf('شركة 🛒 النور 💰');
      expect(result.contains('شركة'), isTrue);
      expect(result.contains('النور'), isTrue);
      expect(result.contains('🛒'), isFalse);
      expect(result.contains('💰'), isFalse);
    });

    test('سلسلةٌ فارغة تُعيد فارغة', () {
      expect(sanitizeForPdf(''), isEmpty);
    });

    test('أشكالُ العرض العربيّة (U+FBxx) تمرُّ', () {
      // ﻻ = U+FEFB (ARABIC LIGATURE LAM WITH ALEF ISOLATED FORM)
      const formA = '\uFEFB'; // from Arabic Pres Forms-B
      expect(sanitizeForPdf(formA), equals(formA));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٢. لا /BaseFont /Courier في PDF المولِّد الاحتياطيّ
  // ═══════════════════════════════════════════════════════════════════════════

  group('لا Courier في المولِّد الاحتياطيّ', () {
    Future<bool> hasCourier(List<int> bytes) async {
      final s = String.fromCharCodes(bytes);
      return s.contains('/Courier') || s.contains('/BaseFont/Courier');
    }

    test('إيصالٌ حراريٌّ بلا QR: لا Courier', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'FC-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنفٌ تجريبيٌّ', quantity: 1, price: 10, total: 10),
        ],
        total: 10,
        paid: 10,
        change: 0,
        companyName: 'شركة',
        debugBuildOnly: true,
      );
      expect(await hasCourier(r.bytes), isFalse,
          reason: 'لا يجب أن يظهر Courier في PDF الإيصال الحراريّ');
    });

    test('إيصالٌ حراريٌّ بـbarcode (Code128): لا Courier', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'FC-BAR-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10),
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'barcode',
        debugBuildOnly: true,
      );
      expect(await hasCourier(r.bytes), isFalse,
          reason: 'BarcodeWidget.textStyle يجب أن يستخدم Noto لا Courier');
    });

    test('إيصالٌ حراريٌّ بـqr_code: لا Courier', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'FC-QR-001',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10),
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'qr_code',
        debugBuildOnly: true,
      );
      expect(await hasCourier(r.bytes), isFalse,
          reason: 'QR widget لا يجب أن يُدخل Courier');
    });

    test('إيصالٌ حراريٌّ 58mm بـbarcode: لا Courier', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'FC-58-BAR',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10),
        ],
        total: 10,
        paid: 10,
        change: 0,
        receiptCodeType: 'barcode',
        paperWidthMm: 58,
        debugBuildOnly: true,
      );
      expect(await hasCourier(r.bytes), isFalse,
          reason: '58mm + barcode: لا Courier');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٣. لا Courier في قوالب الـDB المبذورة (ar وen)
  // ═══════════════════════════════════════════════════════════════════════════

  group('لا Courier في القوالب المبذورة', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting();
      await db.seedDefaultTemplates();
    });
    tearDown(() => db.close());

    Future<bool> hasCourier(List<int> bytes) async {
      final s = String.fromCharCodes(bytes);
      return s.contains('/Courier') || s.contains('/BaseFont/Courier');
    }

    for (final (type, cat, locale) in [
      ('thermal', 'receipt', 'ar'),
      ('thermal', 'receipt', 'en'),
      ('a4', 'invoice', 'ar'),
      ('a4', 'invoice', 'en'),
    ]) {
      test('القالبُ ($type/$cat/$locale): لا Courier', () async {
        final bytes = (await TemplatedInvoiceService.printWithTemplate(
          db: db,
          debugBuildOnly: true,
          type: type,
          category: cat,
          invoiceNumber: 'FONT-$type-$locale',
          date: DateTime(2026, 6, 1),
          customerName: locale == 'ar' ? 'عميل' : 'Customer',
          customerPhone: null,
          customerAddress: null,
          items: const [
            {'name': 'صنف', 'quantity': 1.0, 'price': 10.0, 'total': 10.0}
          ],
          subtotal: 10.0,
          discount: 0.0,
          tax: 0.0,
          deliveryFee: 0.0,
          total: 10.0,
          paid: 10.0,
          companyName: locale == 'ar' ? 'شركة' : 'Company',
          companyAddress: '',
          companyPhone: '',
          companyTaxId: null,
          locale: locale,
        )).bytes;
        expect(await hasCourier(bytes), isFalse,
            reason: 'القالبُ ($type/$cat/$locale) يجب أن لا يستخدم Courier');
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٤. قالبُ thermal_modern.json (يحمل emoji) — لا استثناء، لا Courier
  // ═══════════════════════════════════════════════════════════════════════════

  group('thermal_modern.json: emoji يُزال، لا Courier', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('يُبنى بلا استثناء ولا Courier رغم وجود emoji في labelAr', () async {
      // thermal_modern.json يحمل: "🛒 العميل"، "💰"، "✨ شكراً..."
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;

      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'),
          reason: 'ملفُّ PDF صحيح رغم emoji في عناصر القالب');

      final s = String.fromCharCodes(bytes);
      expect(s.contains('/Courier') || s.contains('/BaseFont/Courier'), isFalse,
          reason: 'لا Courier حتّى حين يحمل القالبُ emoji');
    });

    test('المجسُّ يستخرج نصّاً: الورقةُ ليست فارغة', () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.allTexts, isNotEmpty,
          reason: 'المطهِّرُ يُزيل emoji ولا يُفرغ الورقة');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٥. قالبُ المطبخ: لا Courier
  // ═══════════════════════════════════════════════════════════════════════════

  test('kitchen_professional.json: لا Courier', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final json = await rootBundle
        .loadString('assets/invoice_templates/kitchen_professional.json');
    final id = await db.importTemplateFromJson(json);
    final template = (await db.getTemplateWithData(id))!;

    final bytes = await TemplatePdfRenderer.generatePdf(
      templateData: template,
      invoiceData: kFixtureRendererData,
    );
    final s = String.fromCharCodes(bytes);
    expect(s.contains('/Courier') || s.contains('/BaseFont/Courier'), isFalse,
        reason: 'قالبُ المطبخ لا يجب أن يستخدم Courier');
  });
}
