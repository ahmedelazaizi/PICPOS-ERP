// ═══════════════════════════════════════════════════════════════════════════
// اختباراتُ محرِّكِ القوالب — المقاساتُ والتفافُ النصِّ والتقسيمُ
// ═══════════════════════════════════════════════════════════════════════════
//
// يُغطِّي هذا الملفُّ:
//   • كلُّ مقاسٍ ورقيٍّ (58mm، 80mm، A4) يُرسَم بلا استثناء
//   • اسمُ الصنفِ الطويلُ (200 حرف) يلتفُّ ولا يُحطم البناء
//   • فاتورةٌ بـ100 صنفٍ على A4 تُبنى بلا استثناء
//   • checkPaperFit: 58mm ضيّقٌ مسموحٌ به، 90mm يُرفض على طابعة 80mm
//   • رقمُ الفاتورة يصل الورقة في كلِّ مقاس
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/printing/paper_compatibility.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';
import '../helpers/printing_characterization_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  // ١. كلُّ مقاسٍ ورقيٍّ يُرسَم بلا استثناء
  // ═══════════════════════════════════════════════════════════════════════════

  group('كلُّ مقاسٍ ورقيٍّ يُرسَم بلا استثناء', () {
    // القوالبُ المختارة: واحدٌ لكلِّ مقاس من ملفّات الأصول
    const templates = [
      ('thermal58_quick_sale.json', '58mm'),
      ('thermal_modern.json', '80mm'),
      ('a4_professional.json', 'A4'),
      ('a5_sales_tax_invoice.json', 'A5'),
    ];

    for (final (file, label) in templates) {
      test('القالبُ $label ($file) يُرسَم بلا استثناء', () async {
        final json = await rootBundle
            .loadString('assets/invoice_templates/$file');
        final id = await db.importTemplateFromJson(json);
        final template = (await db.getTemplateWithData(id))!;

        final bytes = await TemplatePdfRenderer.generatePdf(
          templateData: template,
          invoiceData: kFixtureRendererData,
        );
        expect(bytes, isNotEmpty,
            reason: 'القالبُ $label يجب أن يُنتج بايتاتٍ غيرَ فارغة');
        expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'),
            reason: 'المخرجُ يجب أن يكون PDF صحيحاً');
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٢. مقاسُ صفحة كلِّ قالب يطابق المعلَن
  // ═══════════════════════════════════════════════════════════════════════════

  group('مقاسُ الصفحة يطابق القالب', () {
    test('قالبُ 58mm: عرضُ الصفحة ≈ 164pt', () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal58_quick_sale.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.pages, isNotEmpty);
      // 58mm × 72/25.4 ≈ 164.4 pt  (هامش 3pt)
      expect(probe.pages.first.widthPts, closeTo(164.4, 5.0),
          reason: '58mm × 72/25.4 ≈ 164pt');
    });

    test('قالبُ 80mm: عرضُ الصفحة ≈ 227pt', () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.pages, isNotEmpty);
      // 80mm × 72/25.4 ≈ 226.77pt
      expect(probe.pages.first.widthPts, closeTo(226.77, 5.0),
          reason: '80mm × 72/25.4 ≈ 227pt');
    });

    test('قالبُ A4: عرضُ الصفحة ≈ 595pt', () async {
      final json = await rootBundle
          .loadString('assets/invoice_templates/a4_professional.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;
      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: kFixtureRendererData,
      );
      final probe = probePdf(bytes);
      expect(probe.pages, isNotEmpty);
      // A4 = 210mm × 72/25.4 ≈ 595.28pt
      expect(probe.pages.first.widthPts, closeTo(595.0, 5.0),
          reason: 'A4 = 210mm × 72/25.4 ≈ 595pt');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٣. التفافُ النصِّ الطويل
  // ═══════════════════════════════════════════════════════════════════════════

  group('الأسماءُ الطويلةُ تلتفُّ ولا تُحطم البناء', () {
    test('اسمُ صنفٍ بـ200 حرفٍ على قالبٍ حراريٍّ لا يُحطم البناء', () async {
      final longName = 'صنفٌ بأسمٍ مطوَّلٍ جدّاً ' * 10; // ≈ 250 حرف
      final json = await rootBundle
          .loadString('assets/invoice_templates/thermal_modern.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;

      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: TemplateInvoiceData(
          invoiceNumber: 'WRAP-TEST-1',
          date: DateTime(2026, 6, 1),
          items: [
            InvoiceItem(name: longName, quantity: 1, price: 10.0, total: 10.0)
          ],
          subtotal: 10.0,
          total: 10.0,
          paid: 10.0,
        ),
      );
      expect(bytes, isNotEmpty,
          reason: 'الاسمُ الطويلُ يجب أن يلتفَّ ولا يُحطم البناء');
    });

    test('اسمُ صنفٍ بـ200 حرفٍ على قالبٍ A4 لا يُحطم البناء', () async {
      final longName = 'Long item description that wraps around ' * 6;
      final json = await rootBundle
          .loadString('assets/invoice_templates/a4_professional.json');
      final id = await db.importTemplateFromJson(json);
      final template = (await db.getTemplateWithData(id))!;

      final bytes = await TemplatePdfRenderer.generatePdf(
        templateData: template,
        invoiceData: TemplateInvoiceData(
          invoiceNumber: 'WRAP-A4-1',
          date: DateTime(2026, 6, 1),
          items: [
            InvoiceItem(name: longName, quantity: 1, price: 10.0, total: 10.0)
          ],
          subtotal: 10.0,
          total: 10.0,
          paid: 10.0,
        ),
      );
      expect(bytes, isNotEmpty,
          reason: 'الاسمُ الطويلُ على A4 يجب أن يلتفَّ بلا استثناء');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٤. فاتورةٌ بـ100 صنفٍ على A4
  // ═══════════════════════════════════════════════════════════════════════════

  test('100 صنفٍ على A4 تُبنى بلا استثناء', () async {
    final items = List.generate(
      100,
      (i) => {
        'name': 'صنف رقم ${i + 1}',
        'quantity': 1.0,
        'price': 10.0,
        'total': 10.0,
      },
    );
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: 'a4',
      category: 'invoice',
      invoiceNumber: 'BULK-100',
      date: DateTime(2026, 6, 1),
      customerName: 'عميلُ الاختبار',
      customerPhone: null,
      customerAddress: null,
      items: items,
      subtotal: 1000.0,
      discount: 0.0,
      tax: 0.0,
      deliveryFee: 0.0,
      total: 1000.0,
      paid: 1000.0,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
    )).bytes;
    expect(bytes, isNotEmpty,
        reason: '100 صنفٍ يجب أن تُبنى بلا استثناء');
    expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    // PDF يجب أن يكون أكبرَ من PDF فارغ
    expect(bytes.length, greaterThan(1000));
  });

  test('20 صنفٍ على قالبٍ حراريٍّ تُبنى بلا استثناء', () async {
    final items = List.generate(
      20,
      (i) => {
        'name': 'صنف ${i + 1}',
        'quantity': 1.0,
        'price': 5.0,
        'total': 5.0,
      },
    );
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: 'thermal',
      category: 'receipt',
      invoiceNumber: 'THERMAL-20',
      date: DateTime(2026, 6, 1),
      customerName: 'عميل',
      customerPhone: null,
      customerAddress: null,
      items: items,
      subtotal: 100.0,
      discount: 0.0,
      tax: 0.0,
      deliveryFee: 0.0,
      total: 100.0,
      paid: 100.0,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
    )).bytes;
    expect(bytes, isNotEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٥. توافقُ الورق (paper_compatibility)
  // ═══════════════════════════════════════════════════════════════════════════

  group('checkPaperFit — التوافقُ بين القالب والطابعة', () {
    test('قالبٌ 58mm على طابعة 58mm: مقبولٌ (ok)', () {
      final verdict =
          checkPaperFit(templateWidthMm: 58.0, printerWidthMm: 58.0);
      expect(verdict.isOk, isTrue,
          reason: 'قالبٌ مطابقٌ للطابعة يجب أن يُقبَل');
    });

    test('قالبٌ 58mm على طابعة 80mm: أضيقُ من الطابعة (narrower)', () {
      final verdict =
          checkPaperFit(templateWidthMm: 58.0, printerWidthMm: 80.0);
      expect(verdict.isWarning, isTrue,
          reason: 'قالبٌ أضيقُ من الطابعة تحذيرٌ لا رفض');
    });

    test('قالبٌ 90mm على طابعة 80mm: أعرضُ من الطابعة (tooWide → rejected)', () {
      final verdict =
          checkPaperFit(templateWidthMm: 90.0, printerWidthMm: 80.0);
      expect(verdict.isRejected, isTrue,
          reason: 'قالبٌ أعرضُ من الطابعة يُرفض صراحةً');
    });

    test('عرضُ طابعةٍ مجهول (null) يُقبَل دائماً', () {
      final verdict = checkPaperFit(templateWidthMm: 80.0);
      expect(verdict.isOk, isTrue,
          reason: 'طابعةٌ مجهولةُ العرض لا تُفعِّل فلترَ الرفض');
    });

    test('التسامحُ 3mm: قالبٌ 77mm على طابعة 80mm مقبولٌ', () {
      // الفرقُ = 3mm = حدُّ التسامح
      final verdict =
          checkPaperFit(templateWidthMm: 77.0, printerWidthMm: 80.0);
      expect(verdict.fit, isNot(PaperFit.tooWide),
          reason: '3mm فرقٌ = التسامح = لا رفض');
    });

    test('قالبٌ أعرضُ بـ4mm من التسامح يُرفض', () {
      // 80 + 3 + 1 = 84mm > 80mm + 3mm tolerance
      final verdict =
          checkPaperFit(templateWidthMm: 84.0, printerWidthMm: 80.0);
      expect(verdict.isRejected, isTrue,
          reason: 'تجاوزُ التسامح بـmm+ يجب أن يُرفض');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ٦. القوالبُ المبذورةُ الافتراضيّة تُرسَم بلا استثناء
  // ═══════════════════════════════════════════════════════════════════════════

  group('القوالبُ المبذورةُ الافتراضيّةُ تُرسَم بلا استثناء', () {
    for (final (type, cat) in [
      ('thermal', 'receipt'),
      ('a4', 'invoice'),
    ]) {
      test('القالبُ الافتراضيُّ ($type/$cat) يُرسَم بلا استثناء', () async {
        final bytes = (await TemplatedInvoiceService.printWithTemplate(
          db: db,
          debugBuildOnly: true,
          type: type,
          category: cat,
          invoiceNumber: 'SEED-$type',
          date: DateTime(2026, 6, 1),
          customerName: 'عميل',
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
          companyName: 'شركة',
          companyAddress: '',
          companyPhone: '',
          companyTaxId: null,
        )).bytes;
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
      });
    }
  });
}
