// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ توليدِ PDF — A4 و80mm — عربيٌّ وإنجليزيٌّ
// ═══════════════════════════════════════════════════════════════════════════
//
// يُغطِّي هذا الملفُّ:
//   • صحّةَ الترويسة (%PDF) وعددَ الصفحات
//   • مطابقةَ مقاسِ الصفحة: A4 ≈ 595×842pt، 80mm ≈ 227pt عرضاً
//   • الخطُّ المضمَّن في الإيصال الحراريّ يبدأ بـ Noto (خطُّ العربيّة)
//   • رقمُ الفاتورة والإجماليُّ واسمُ العميل يصلون الورقة
//   • locale='ar' وlocaleen يُنتجان نصّاً مختلفاً (المحتوى وليس فقط الشكل)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';
import 'package:ural_erp/services/printing/thermal_receipt_generator.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── مساعداتٌ مشتركة ──────────────────────────────────────────────────────

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  /// يُنشئ إيصالاً حراريّاً مباشرةً عبر ThermalReceiptGenerator.
  Future<PdfProbe> buildThermalProbe({String locale = 'ar'}) async {
    final r = await ThermalReceiptGenerator.printThermalReceipt(
      invoiceNumber: 'PDF-TEST-001',
      date: DateTime(2026, 6, 1),
      items: [
        InvoiceItem(name: 'صنفٌ تجريبيٌّ', quantity: 3, price: 10.0, total: 30.0),
      ],
      total: 30.0,
      paid: 30.0,
      change: 0,
      companyName: 'شركةُ الاختبار',
      companyPhone: '0501112233',
      taxId: '310000000000001',
      locale: locale,
      debugBuildOnly: true,
    );
    return probePdf(r.bytes);
  }

  /// يُنشئ فاتورةً عبر نظام القوالب ويُعيد البايتات.
  Future<PdfProbe> buildTemplatedProbe({
    required String type,
    required String category,
    String locale = 'ar',
    String invoiceNumber = 'TPL-TEST-001',
  }) async {
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: type,
      category: category,
      invoiceNumber: invoiceNumber,
      date: DateTime(2026, 6, 1),
      customerName: 'عميلُ الاختبار',
      customerPhone: '0509998877',
      customerAddress: 'شارعُ التجربة',
      items: const [
        {'name': 'صنف', 'quantity': 2.0, 'price': 50.0, 'total': 100.0}
      ],
      subtotal: 100.0,
      discount: 0.0,
      tax: 15.0,
      deliveryFee: 0.0,
      total: 115.0,
      paid: 115.0,
      companyName: 'شركةُ الاختبار',
      companyAddress: 'الرياض',
      companyPhone: '0501112233',
      companyTaxId: '310000000000001',
      locale: locale,
    )).bytes;
    return probePdf(bytes);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ١. صحّةُ الترويسة
  // ═══════════════════════════════════════════════════════════════════════════

  group('ترويسةُ PDF صحيحة', () {
    test('الإيصالُ الحراريُّ يبدأ بـ %PDF', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'HDR-1',
        date: DateTime(2026, 1, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10.0, total: 10.0)
        ],
        total: 10.0,
        paid: 10.0,
        change: 0,
        debugBuildOnly: true,
      );
      expect(r.bytes, isNotEmpty);
      expect(String.fromCharCodes(r.bytes.take(4)), equals('%PDF'));
    });

    test('فاتورةُ A4 عبر القوالب تبدأ بـ %PDF', () async {
      final probe = await buildTemplatedProbe(type: 'a4', category: 'invoice');
      // المجسُّ يفشل إن لم يكن الملفُّ PDF صحيحاً، فوجودُ النصوص كافٍ
      expect(probe.pages, isNotEmpty,
          reason: 'مرساةٌ: فاتورة A4 يجب أن تكون صفحةً واحدة على الأقل');
    });

    test('الإيصالُ الحراريُّ 80mm عبر القوالب تبدأ بـ %PDF', () async {
      final probe =
          await buildTemplatedProbe(type: 'thermal', category: 'receipt');
      expect(probe.pages, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٢. مقاسُ الصفحة
  // ═══════════════════════════════════════════════════════════════════════════

  group('مقاسُ الصفحة بالنقاط', () {
    test('الإيصالُ الحراريُّ المباشر: العرض ≈ 226.77pt (80mm)', () async {
      final probe = await buildThermalProbe();
      expect(probe.pages, isNotEmpty);
      // 80mm × 72pt/inch ÷ 25.4mm/inch = 226.77pt
      expect(probe.pages.first.widthPts, closeTo(226.77, 3.0),
          reason: '80mm × 72/25.4 ≈ 226.77pt');
    });

    test('فاتورةُ A4 عبر القوالب: العرض ≈ 595pt', () async {
      final probe =
          await buildTemplatedProbe(type: 'a4', category: 'invoice');
      expect(probe.pages, isNotEmpty);
      // A4 width = 210mm × 72/25.4 ≈ 595.28pt
      expect(probe.pages.first.widthPts, closeTo(595.0, 5.0),
          reason: 'A4 = 210mm × 72/25.4 ≈ 595pt');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٣. الخطُّ العربيُّ المضمَّن
  // ═══════════════════════════════════════════════════════════════════════════

  group('الخطُّ العربيُّ المضمَّن (NotoNaskhArabic)', () {
    test('الإيصالُ الحراريُّ يستخدم خطَّ Noto', () async {
      final probe = await buildThermalProbe(locale: 'ar');
      expect(probe.allTexts, isNotEmpty,
          reason: 'مرساةٌ: يجب أن يكون هناك نصٌّ على الورقة');
      // الخطُّ المضمَّن هو NotoNaskhArabic — يبدأ اسمُه بـ Noto
      final fonts = probe.allTexts.map((t) => t.font).toSet();
      expect(
        fonts.any((f) => f.toLowerCase().contains('noto')),
        isTrue,
        reason: 'الخطُّ العربيُّ المضمَّن يجب أن يكون Noto (NotoNaskhArabic)',
      );
    });

    test('إيصالُ القوالب يستخدم خطَّ Noto', () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.allTexts, isNotEmpty);
      final fonts = probe.allTexts.map((t) => t.font).toSet();
      expect(
        fonts.any((f) => f.toLowerCase().contains('noto')),
        isTrue,
        reason: 'TemplatePdfRenderer يضمِّن خطَّ Noto العربيَّ',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٤. رقمُ الفاتورة والإجماليُّ واسمُ العميل
  // ═══════════════════════════════════════════════════════════════════════════

  group('حقولُ الفاتورة تصل الورقة', () {
    test('رقمُ الفاتورة يصل الورقة في الإيصال الحراريّ', () async {
      final r = await ThermalReceiptGenerator.printThermalReceipt(
        invoiceNumber: 'UNIQUE-INV-9977',
        date: DateTime(2026, 6, 1),
        items: [
          InvoiceItem(name: 'صنف', quantity: 1, price: 10.0, total: 10.0)
        ],
        total: 10.0,
        paid: 10.0,
        change: 0,
        debugBuildOnly: true,
      );
      final probe = probePdf(r.bytes);
      final allText = probe.allTexts.map((t) => t.text).join(' ');
      expect(allText, contains('UNIQUE-INV-9977'),
          reason: 'رقمُ الفاتورة يجب أن يظهر على الورقة');
    });

    test('الإجماليُّ يصل الورقة عبر قالب الإيصال الحراريّ', () async {
      final probe =
          await buildTemplatedProbe(type: 'thermal', category: 'receipt');
      final texts = probe.allTexts.map((t) => t.text.trim()).toList();
      // الإجماليُّ = 115.00
      expect(texts.any((t) => t == '115.00'), isTrue,
          reason: 'الإجماليُّ (115.00) يجب أن يُطبع');
    });

    test('رقمُ الفاتورة يصل فاتورةَ A4', () async {
      const uniq = 'A4-UNIQ-5544';
      final probe = await buildTemplatedProbe(
          type: 'a4', category: 'invoice', invoiceNumber: uniq);
      final allText = probe.allTexts.map((t) => t.text).join(' ');
      expect(allText, contains(uniq),
          reason: 'رقمُ الفاتورة يجب أن يظهر في مستند A4');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٥. locale='ar' وlocaleen يُنتجان نصّاً مختلفاً
  // ═══════════════════════════════════════════════════════════════════════════

  group('اللغةُ تؤثّر على محتوى الورقة', () {
    test('الإيصالُ الحراريُّ ar وen يختلفان في نصّ الورقة', () async {
      final arProbe = await buildThermalProbe(locale: 'ar');
      final enProbe = await buildThermalProbe(locale: 'en');

      expect(arProbe.allTexts, isNotEmpty);
      expect(enProbe.allTexts, isNotEmpty);

      final arJoined = arProbe.allTexts.map((t) => t.text).join();
      final enJoined = enProbe.allTexts.map((t) => t.text).join();
      expect(arJoined, isNot(equals(enJoined)),
          reason: 'locale=ar وen يختلفان في فاصل Invoice/فاتورة وما شابه');
    });

    test('locale=ar في TemplateInvoiceData: اسمُ الشركة العربيُّ على الورقة',
        () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;

      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: TemplateInvoiceData(
          invoiceNumber: 'LANG-AR-1',
          date: DateTime(2026, 6, 1),
          items: [
            InvoiceItem(name: 'صنف', quantity: 1, price: 10, total: 10)
          ],
          subtotal: 10,
          total: 10,
          paid: 10,
          companyName: 'شركةُ النورِ العربيّة',
          locale: 'ar',
        ),
      );
      final probe = probePdf(bytes);
      expect(probe.allTexts, isNotEmpty);
      final text =
          deshapeArabic(probe.allTexts.map((t) => t.text).join(' '));
      expect(text, contains('شركة'),
          reason: 'locale=ar يجب أن يُظهر النصَّ العربيَّ');
    });

    test('locale=en في TemplateInvoiceData: المستندُ يُبنى بلا استثناء',
        () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;

      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: TemplateInvoiceData(
          invoiceNumber: 'LANG-EN-1',
          date: DateTime(2026, 6, 1),
          items: [
            InvoiceItem(name: 'Test Item', quantity: 1, price: 10, total: 10)
          ],
          subtotal: 10,
          total: 10,
          paid: 10,
          companyName: 'Test Company LLC',
          locale: 'en',
        ),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'),
          reason: 'locale=en يجب أن يُنتج PDF صحيحاً');
    });
  });
}
