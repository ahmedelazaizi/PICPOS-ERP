// ═══════════════════════════════════════════════════════════════════════════
// §٤ — الشعار: وحدةٌ خاطئةٌ وصندوقٌ مكتوبٌ فيه «LOGO»
// ═══════════════════════════════════════════════════════════════════════════
//
// بندُ التسليم كان «فواتيرُ A4 عدّةٌ صارت صفحتَين بعد §٦‑١». والقياسُ ردَّه
// إلى جذرٍ واحدٍ يفسّر عَرَضَين معاً — وثالثٍ لم يكن مبلَّغاً عنه أصلاً.
//
// ── الجذر: التباسُ وحدة ──────────────────────────────────────────────────
// `buildFlowWidget` كان يعترض عنصرَ الشعار قبل `_buildElementContent` ويقرأ
// `element.width` **نسبةً مئويّة** (‏`width / 100` من عرض الورقة)، ويحسب
// الارتفاعَ `0.65 × العرض` متجاهلاً `element.height`. و`width` نقاطٌ كما في
// كلِّ عنصرٍ آخر — والتنفيذُ الصحيحُ كان **موجوداً وميّتاً** في
// `_buildElementContent` لا يُبلَغ أبداً.
//
// ── الأثرُ المقيس ────────────────────────────────────────────────────────
//   · شعارٌ **مضبوط**: `a4_professional` مكتوبٌ ١٣٠×٨٠ ⇒ كان يُطبع ٥٩٥×٣٨٧،
//     أي عرضُ A4 كاملاً و٤٦٪ من ارتفاعها. وكلُّ قالبٍ في المستودع مكبَّرٌ
//     نحوَ ستّةِ أضعاف — لا الأربعةَ الفائضةَ وحدَها.
//   · **بلا شعار**: يُملأ ذلك الصندوقُ بكلمة `LOGO` الإنجليزيّةِ الحرفيّة —
//     وصلت ورقةَ العميل في **١٧ من ٢٧** بصمةً ذهبيّة.
//   · وارتفاعُ ٣٨٧ نقطةً يدفع المجاميعَ إلى **صفحةٍ ثانية** — وهو البند
//     المبلَّغُ عنه.
//
// ⚠️ **ولا يُقاس هذا بقراءة الكود**: البلوكان متجاوران في ملفٍّ واحد،
// وقراءةُ الثاني وحدَه تُري تنفيذاً سليماً لا يعمل.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

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
  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  Future<PdfProbe> printWith(String file, String type, String category,
      String expectedName, {Uint8List? logo}) async {
    final json = await rootBundle.loadString('assets/invoice_templates/$file');
    final id = await db.importTemplateFromJson(json);
    await db.setDefaultTemplate(id);

    // 🔴 مرساةٌ غيرُ دائريّة: الحاسمُ يختار **هذا** القالبَ بعينه.
    final resolved = await db.getDefaultTemplateByCategory(type, category);
    expect(resolved?.name, expectedName,
        reason: 'الحاسمُ يجب أن يختار $file — وإلّا فالقياسُ على قالبٍ آخر');

    final bytes = await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: type,
      category: category,
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
      logoBytes: logo,
    );
    return probePdf(bytes);
  }

  group('بلا شعارٍ مضبوط', () {
    // القوالبُ الأربعةُ التي كانت تفيض إلى صفحةٍ ثانية — وكلُّها من المخطَّط
    // القديم الذي يكتب عرضَ الشعار ١٠٠..١٣٠ نقطة.
    const overflowing = <List<String>>[
      ['a4_commercial.json', 'a4', 'receipt', 'فاتورة A4 تجارية'],
      ['a4_professional.json', 'a4', 'receipt', 'فاتورة A4 احترافية'],
      ['a4_purchase.json', 'a4', 'purchase', 'فاتورة مشتريات A4'],
      ['a4_receipt_voucher.json', 'a4', 'receipt', 'سند قبض / صرف'],
    ];

    for (final t in overflowing) {
      test('${t[0]} — صفحةٌ واحدةٌ ولا كلمةَ «LOGO»', () async {
        final pdf = await printWith(t[0], t[1], t[2], t[3]);
        final texts = pdf.allTexts.map((x) => x.text.trim()).toList();

        // مرساة: الورقةُ رُسمت — وإلّا مرَّ التوكيدُ السلبيُّ زوراً.
        expect(texts, isNotEmpty, reason: 'مرساة: الـPDF فيه نصٌّ مرسوم');

        expect(texts.contains('LOGO'), isFalse,
            reason: '${t[0]} — كلمةٌ إنجليزيّةٌ حرفيّةٌ في مستندٍ ماليّ');
        expect(pdf.pageCount, 1,
            reason: '${t[0]} — صندوقُ الشعار الفارغُ كان يدفع المجاميعَ '
                'إلى صفحةٍ ثانية');
      });
    }

    test('ولا قالبَ في الأصول يطبع «LOGO» بعد الآن', () async {
      // القالبُ الحديثُ كذلك: لم يكن يفيض، لكنّه كان يطبع الكلمة.
      final pdf = await printWith('a4_sales_tax_invoice.json', 'a4', 'invoice',
          'فاتورة مبيعات ضريبية — A4');
      expect(pdf.allTexts.map((x) => x.text.trim()).contains('LOGO'), isFalse);
    });
  });

  group('وشعارٌ مضبوطٌ يُرسم بقياسه المكتوب', () {
    test('a4_professional — ١٣٠×٨٠ لا عرضُ الورقة', () async {
      final pdf = await printWith('a4_professional.json', 'a4', 'receipt',
          'فاتورة A4 احترافية', logo: _png);

      // مرساة: الصورةُ رُسمت فعلاً — وإلّا قِسنا غياباً لا قياساً.
      expect(pdf.allImages, isNotEmpty,
          reason: 'مرساة: شعارٌ مُرِّر فيجب أن تُرسَم صورة');

      final logo = pdf.allImages.first;

      // ⚠️ **الصندوقُ ١٣٠×٨٠ والصورةُ مربّعة**، والرسمُ بـ`BoxFit.contain` —
      // فالمربّعُ يُحتوى ٨٠×٨٠ داخلَ الصندوق. فالمقيسُ **الاحتواءُ في القياس
      // المكتوب**، لا مطابقةُ العرض. وأوّلُ صياغةٍ لهذا التوكيد توقّعت ١٣٠
      // فسقطت — والقياسُ هو الذي صحّحها.
      //
      // والقيمُ مأخوذةٌ من `a4_professional.json` نفسِه لا أرقاماً مختارة.
      expect(logo.w, lessThanOrEqualTo(132),
          reason: 'كان يُرسم بعرض الورقة (٥٩٥) — أربعةَ أضعافٍ ونصفاً');
      expect(logo.h, lessThanOrEqualTo(82),
          reason: 'والارتفاعُ كان `0.65 × العرض` = ٣٨٧، متجاهلاً المكتوب');
      expect(logo.h, closeTo(80, 2),
          reason: 'ومربّعٌ في صندوقٍ ١٣٠×٨٠ يملأ ارتفاعَه — فلا انكماشَ زائد');
    });

    test('وثيقةٌ بشعارٍ تبقى صفحةً واحدةً', () async {
      final pdf = await printWith('a4_commercial.json', 'a4', 'receipt',
          'فاتورة A4 تجارية', logo: _png);
      expect(pdf.allImages, isNotEmpty, reason: 'مرساة: الشعارُ رُسم');
      expect(pdf.pageCount, 1);
    });
  });
}
