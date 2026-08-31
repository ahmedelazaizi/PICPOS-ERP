// ═══════════════════════════════════════════════════════════════════════════
// §٤‑٦ — نسبةُ الضريبة مخبوزةٌ في تسمية القالب: قياسٌ على الورقة لا على الملفّ
// ═══════════════════════════════════════════════════════════════════════════
//
// سبعةُ قوالبَ كانت تكتب النسبةَ نصّاً في **تسمية سطر الإجمالي**
// (‏`ضريبة القيمة المضافة ١٤٪` · `ض.ق.م ١٤٪` · `ضريبة القيمة المضافة (14%)`)،
// والراسمُ يبثّ التسميةَ حرفيّاً (‏`template_pdf_renderer._resolveValue` →
// `withLabel`، ومثلُها في `TemplateRenderPipeline._labelOf`).
//
// ── لماذا هذا خطأٌ لا تفصيلُ ذوق ────────────────────────────────────────────
// النسبةُ خاصّيّةُ **صنفٍ** (`Products.taxRate`) تُؤخذ من سلّمٍ قابلٍ للضبط
// (‏`TaxRatePolicy`)، وسلّمُه الافتراضيُّ `[0, 1, 2, 4, 5, 10, 16]` — و١٤ ليست
// فيه أصلاً. وفاتورةٌ واحدةٌ قد تخلط نسباً (صنفٌ معفيٌّ وآخرُ ١٦٪)، فلا نسبةَ
// مفردةً تصدُق على سطر الإجمالي. فالتسميةُ تسمّي الضريبةَ ولا تدّعي نسبتَها،
// وهو ما تفعله اثنا عشرَ قالباً من التسعةَ عشرَ المشحونة أصلاً
// (‏`a4_professional` · `a4_purchase` · `thermal_classic` وأخواتُها).
//
// ── والمقيسُ أسوأُ من المكتوب ───────────────────────────────────────────────
// الأرقامُ الهنديّةُ تنعكس عند الرسم: `١٤٪` تصل الورقةَ `٤١٪`
// (‏`codeUnits=[1636, 1633, 1642]`)، أي «واحدٌ وأربعون بالمئة». و`(14%)`
// تصل `(%14)`. فالورقةُ لم تكن تكذب بنسبةٍ قديمةٍ فحسب، بل بنسبةٍ لا وجودَ لها.
//
// ⚠️ **ولا يُقاس هذا بـgrep على الـJSON**: العطبُ في ما يصل الورقة. ولذلك
// يُطبع هنا مستندٌ نسبتُه الحقيقيّةُ ٥٪ ثمّ يُفكّ الـPDF ويُقرأ ما رُسم.
// والتوكيدُ على **علامة النسبة مجاورةً لرقم** لا على «١٤» وحدَها: النصُّ
// المنعكسُ لا يحوي «١٤» أصلاً، فنمطٌ يبحث عنها كان سيقرأ صفراً ويمرُّ أخضرَ
// على ورقةٍ تطبع `٤١٪`.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';

// ٢٠٠ − ٠ + ١٠ = ٢١٠ — والضريبةُ ١٠ على وعاءٍ ٢٠٠ نسبتُها **٥٪** لا ١٤٪.
// وكلُّ مكوّنٍ رقمٌ فريدٌ فتكفي المطابقةُ التامّة.
const _subtotal = 200.0;
const _discount = 0.0;
const _tax = 10.0;
const _total = 210.0;

/// علامةُ نسبةٍ (لاتينيّةٌ أو عربيّة) مجاورةً لرقمٍ (لاتينيٍّ أو هنديّ) — في
/// أيِّ الاتّجاهين، لأنّ الرسمَ يقلب ترتيبَ الأرقام الهنديّة.
final _rateClaim = RegExp(r'[0-9٠-٩][%٪]|[%٪][0-9٠-٩]');

/// (اسمُ الملفّ، النوع، الفئة، الاسمُ المتوقَّع في القاعدة)
///
/// ⚠️ **`a4_commercial` فئتُه `receipt`**: الملفُّ بلا `templateCategory`
/// فيسقط الاستيرادُ إلى `receipt`. وطلبُ `invoice` كان يجعل الحاسمَ يختار
/// قالباً مبذوراً آخرَ فيُقاس ما لم يُختبَر (وقع فعلاً 2026-09-01).
const _templates = <List<String>>[
  ['a4_commercial.json', 'a4', 'receipt', 'فاتورة A4 تجارية'],
  ['a4_sales_tax_invoice.json', 'a4', 'invoice', 'فاتورة مبيعات ضريبية — A4'],
  ['a5_sales_tax_invoice.json', 'a4', 'invoice', 'فاتورة مبيعات ضريبية — A5'],
  ['a4_sales_return.json', 'a4', 'invoice', 'مرتجع مبيعات — A4'],
  ['a4_purchase_invoice.json', 'a4', 'purchase', 'فاتورة مشتريات — A4'],
  ['a4_purchase_return.json', 'a4', 'purchase', 'مرتجع مشتريات — A4'],
  ['thermal80_quick_sale.json', 'thermal', 'receipt', 'بيع سريع حراري — 80mm'],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  Future<List<String>> printWith(
      String file, String type, String category, String expectedName) async {
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
      subtotal: _subtotal,
      discount: _discount,
      tax: _tax,
      deliveryFee: 0.0,
      total: _total,
      paid: _total,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: '',
      companyTaxId: null,
    );
    return probePdf(bytes).allTexts.map((t) => t.text.trim()).toList();
  }

  for (final t in _templates) {
    final file = t[0];

    test('$file لا يطبع نسبةَ ضريبةٍ مخبوزة', () async {
      final texts = await printWith(file, t[1], t[2], t[3]);

      // مرساة ١: الورقةُ رُسمت — وإلّا مرَّ كلُّ توكيدٍ سلبيٍّ زوراً.
      expect(texts, isNotEmpty, reason: 'مرساة: الـPDF فيه نصٌّ مرسوم');

      // مرساة ٢: **سطرُ الضريبة نفسُه** وصل الورقة. بدونها يمرُّ قالبٌ
      // أسقط تذييلَه كلَّه — وهو عينُ ما كان يقع قبل §٦‑١.
      expect(texts.contains('10.00'), isTrue,
          reason: 'مرساة: قيمةُ الضريبة ١٠٫٠٠ يجب أن تُطبع، وإلّا '
              'فالتوكيدُ التالي يقيس غياباً لا إصلاحاً. '
              'ما طُبع: ${texts.where((s) => s.isNotEmpty).take(30).toList()}');

      final claims = texts.where((s) => _rateClaim.hasMatch(s)).toList();
      expect(claims, isEmpty,
          reason: '$file — الورقةُ تدّعي نسبةَ ضريبةٍ بينما نسبةُ المستند '
              'الحقيقيّةُ ٥٪ (‏${_tax.toInt()} على وعاءٍ ${_subtotal.toInt()}). '
              'النصُّ المدّعي: $claims — '
              'وحداتُه: ${claims.map((c) => c.codeUnits).toList()}');
    });
  }

  // ── المسارُ الثاني: قاعدةٌ استوردت القالبَ **قبل** إصلاح الأصول ──────────
  //
  // إصلاحُ الأصول لا يبلغ صفّاً مخزَّناً: الملفُّ يُقرأ عند الاستيراد لا عند
  // كلِّ إقلاع. فلولا `repairHardcodedTaxRateLabels` لبقيت كلُّ قاعدةٍ قائمةٍ
  // تطبع `٤١٪` بينما الأصولُ نظيفة.
  group('الإصلاحُ يبلغ القوالبَ المستوردةَ سلفاً', () {
    /// يعيد بناءَ الأصل **المعطوب** كما كان قبل الإصلاح.
    Future<String> legacyJson() async {
      final clean = await rootBundle
          .loadString('assets/invoice_templates/a4_sales_tax_invoice.json');
      final broken = clean
          .replaceAll('"ضريبة القيمة المضافة"', '"ضريبة القيمة المضافة ١٤٪"')
          .replaceAll('"VAT"', '"VAT 14%"');
      // مرساة: التجهيزةُ غيّرت النصَّ فعلاً — وإلّا اختبرنا القالبَ النظيف
      // وحدَه ومرَّ الإصلاحُ أخضرَ بلا أن يُصلح شيئاً.
      expect(broken, isNot(clean),
          reason: 'مرساة: نصُّ القالب القديم يجب أن يختلف عن المُصلَح');
      return broken;
    }

    Future<List<String>> printCurrentDefault() async {
      final bytes = await TemplatedInvoiceService.printWithTemplate(
        db: db,
        debugBuildOnly: true,
        type: 'a4',
        category: 'invoice',
        invoiceNumber: 'TPL-1',
        date: DateTime(2026, 9, 1),
        customerName: 'عميل',
        customerPhone: null,
        customerAddress: null,
        items: const [
          {'name': 'صنف', 'quantity': 2.0, 'price': 100.0, 'total': 200.0}
        ],
        subtotal: _subtotal,
        discount: _discount,
        tax: _tax,
        deliveryFee: 0.0,
        total: _total,
        paid: _total,
        companyName: 'شركة',
        companyAddress: '',
        companyPhone: '',
        companyTaxId: null,
      );
      return probePdf(bytes).allTexts.map((t) => t.text.trim()).toList();
    }

    test('صفٌّ مخزَّنٌ بالنسبة القديمة يُصلَح — والورقةُ تنظف', () async {
      final id = await db.importTemplateFromJson(await legacyJson());
      await db.setDefaultTemplate(id);

      // مرساة: التجهيزةُ **أعادت العطبَ فعلاً** على الورقة. بدونها قد يمرُّ
      // التوكيدُ النهائيُّ لأنّ العطبَ لم يُعَد أصلاً.
      final before = await printCurrentDefault();
      expect(before.where(_rateClaim.hasMatch).toList(), isNotEmpty,
          reason: 'مرساة: القالبُ القديمُ يجب أن يطبع نسبةً قبل الإصلاح');

      final changed = await db.repairHardcodedTaxRateLabels();
      expect(changed, 1, reason: 'عنصرُ ضريبةٍ واحدٌ في هذا القالب');

      final after = await printCurrentDefault();
      expect(after.contains('10.00'), isTrue,
          reason: 'مرساة: سطرُ الضريبة ما زال يُطبع بعد الإصلاح');
      expect(after.where(_rateClaim.hasMatch).toList(), isEmpty,
          reason: 'الورقةُ ما زالت تدّعي نسبةً بعد الإصلاح');
    });

    test('متعادلٌ — والتسميةُ التي كتبها المالكُ لا تُمَسّ', () async {
      final id = await db.importTemplateFromJson(await legacyJson());
      await db.setDefaultTemplate(id);

      expect(await db.repairHardcodedTaxRateLabels(), 1);
      // تعادل: لا شيءَ يبقى ليُصلَح.
      expect(await db.repairHardcodedTaxRateLabels(), 0,
          reason: 'التشغيلُ الثاني يجب أن يجد القاعدةَ نظيفة');

      // تسميةٌ من عند المالك — نسبةٌ مكتوبةٌ عن قصدٍ بنصٍّ لم نشحنه قطّ.
      final custom = await db.importTemplateFromJson(
        (await rootBundle
                .loadString('assets/invoice_templates/a4_sales_tax_invoice.json'))
            .replaceAll('"ضريبة القيمة المضافة"', '"ضريبة مبيعاتي 7%"'),
      );
      expect(await db.repairHardcodedTaxRateLabels(), 0,
          reason: 'المطابقةُ حرفيّةٌ تامّة — لا تقصّ ما كتبه المالك');
      final els = await db.getTemplateElements(custom);
      expect(els.any((e) => e.labelAr == 'ضريبة مبيعاتي 7%'), isTrue,
          reason: 'تسميةُ المالك باقيةٌ بحرفها');
    });
  });
}
