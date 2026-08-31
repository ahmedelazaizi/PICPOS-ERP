// ═══════════════════════════════════════════════════════════════════════════
// الفجوةُ المُعلَنةُ في `006ae81d` — شعارُ المنشأة لا يُطبع في مسارٍ حيٍّ كامل.
// ═══════════════════════════════════════════════════════════════════════════
//
// ذلك الكوميت أسكت كلمةَ `LOGO` النائبةَ في ثلاثة راسمين، وصحّح وحدةَ القياس
// في اثنين — وأعلن أنّ الثالثَ `TemplatePdfRenderer` **لا يستقبل `logoBytes`
// إطلاقاً**: لا في `generatePdf` ولا في `TemplateInvoiceData` ولا من مناديه
// `InvoiceGenerator.printThermalReceipt`.
//
// وهو مسارٌ حيٌّ مستقلّ: كلُّ إيصالٍ حراريٍّ يسقط من `TemplatedInvoiceService`
// (‏`printing_service.dart` عند إخفاق القالب) وكلُّ فاتورةٍ مبدئيّةٍ من شاشة
// الطاولات تمرّ به. فمن ضبط شعارَه كان يطبع بلا شعارٍ ولا يعرف لماذا: العنصرُ
// موجودٌ في القالب، والحقلُ ممتلئٌ في الإعدادات، والورقةُ خالية.
//
// ── ووحدةُ القياس هي الفخُّ نفسُه ─────────────────────────────────────────
// العطبُ الذي عولج في المسار الآخر كان قراءةَ `width` **نسبةً مئويّة** بدل
// نقاط، فطُبع الشعارُ بعرض A4 كاملاً. فالاختبارُ يقيس القياسَ لا الوجودَ
// وحدَه: صندوقُ `thermal_modern` ‏٨٠×٥٠ نقطةً، والصورةُ مربّعةٌ بـ`contain`
// ⇒ ٥٠×٥٠. ولو قُرئ العرضُ نسبةً لخرج ٨٠٪ من عرض الورقة.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/template_pdf_renderer.dart';

import '../helpers/pdf_probe.dart';

/// PNG صالحةٌ ١×١ — أصغرُ شعارٍ ممكن. المقيسُ **قياسُ الرسم** لا محتواه.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late InvoiceTemplateWithData template;

  setUp(() async {
    db = AppDatabase.forTesting();
    final json =
        await rootBundle.loadString('assets/invoice_templates/thermal_modern.json');
    final id = await db.importTemplateFromJson(json);
    template = (await db.getTemplateWithData(id))!;

    // 🔴 مرساةٌ غيرُ دائريّة: القالبُ يحمل عنصرَ شعارٍ فعلاً — وإلّا كان
    //    «لا صورة» نتيجةَ قالبٍ بلا عنصرٍ لا نتيجةَ عطب.
    expect(
      template.elements.where((e) => e.elementType == 'logo'),
      isNotEmpty,
      reason: 'thermal_modern يجب أن يحمل عنصرَ `logo`',
    );
  });

  tearDown(() => db.close());

  Future<PdfProbe> render({Uint8List? logo}) async {
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
        logoBytes: logo,
      ),
    );
    return probePdf(bytes);
  }

  test('مرساة: الورقةُ تُرسَم أصلاً', () async {
    final pdf = await render();
    expect(pdf.allTexts, isNotEmpty,
        reason: 'بلا نصٍّ مرسومٍ تمرُّ التوكيداتُ السلبيّةُ أدناه زوراً');
  });

  test('بلا شعارٍ مضبوطٍ ⇒ صمتٌ لا كلمةُ «LOGO»', () async {
    final pdf = await render();

    expect(pdf.allTexts.map((t) => t.text.trim()).contains('LOGO'), isFalse,
        reason: 'كلمةٌ إنجليزيّةٌ حرفيّةٌ على إيصالِ عميل');
    expect(pdf.allImages, isEmpty,
        reason: 'بلا بكسلٍ لا تُرسَم صورةٌ فارغة');
  });

  test('🔴 شعارٌ مضبوطٌ يصل الورقةَ فعلاً', () async {
    final pdf = await render(logo: _png);

    expect(pdf.allImages, isNotEmpty,
        reason: 'المسارُ كان لا يستقبل `logoBytes` إطلاقاً — فالورقةُ تخرج '
            'بلا شعارٍ مهما ضبطه المستخدم');
  });

  test('🔴 ويُرسَم بقياسه المكتوب — نقاطاً لا نسبةً مئويّة', () async {
    final pdf = await render(logo: _png);
    final logo = pdf.allImages.first;

    // صندوقُ `thermal_modern` ‏٨٠×٥٠ نقطةً، والصورةُ مربّعةٌ بـ`contain`
    // ⇒ ٥٠×٥٠. والقيمُ من ملفّ القالب نفسِه لا أرقاماً مختارة.
    expect(logo.h, closeTo(50, 2),
        reason: 'ارتفاعُ الصندوق المكتوب ٥٠ — والمربّعُ يملؤه');
    expect(logo.w, closeTo(50, 2),
        reason: 'ومربّعٌ في صندوقٍ ٨٠×٥٠ عرضُه ارتفاعُه لا ٨٠');

    // وحدةُ القياس: عرضُ ورقةِ ٨٠mm ≈ ٢٢٧ نقطة. فقراءةُ `width` نسبةً
    // (‏٨٠٪) كانت ستعطي ~١٨١ — وهو الفخُّ الذي طبع الشعارَ بعرض A4 في
    // المسار الآخر.
    expect(logo.w, lessThan(100),
        reason: 'قراءةُ العرض نسبةً مئويّةً تعطي ~١٨١ نقطةً على ورقةِ ٨٠mm');
  });
}
