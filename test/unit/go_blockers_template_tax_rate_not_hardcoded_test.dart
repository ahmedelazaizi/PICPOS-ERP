// ═══════════════════════════════════════════════════════════════════════════
// §٤‑٦ — نسبةُ الضريبة على الورقة: من الإعداد لا من نصٍّ في القالب
// ═══════════════════════════════════════════════════════════════════════════
//
// سبعةُ قوالبَ كانت تكتب النسبةَ نصّاً في **تسمية سطر الإجمالي**
// (‏`ضريبة القيمة المضافة ١٤٪` · `ض.ق.م ١٤٪` · `ضريبة القيمة المضافة (14%)`)،
// والراسمُ يبثّ التسميةَ حرفيّاً (‏`template_pdf_renderer._resolveValue` →
// `withLabel`، ومثلُها `TemplateRenderPipeline._labelOf`).
//
// ── لماذا هذا خطأٌ لا تفصيلُ ذوق ────────────────────────────────────────────
// النسبةُ خاصّيّةُ **صنفٍ** (`Products.taxRate`) من سلّمٍ قابلٍ للضبط
// (‏`TaxRatePolicy`)، وسلّمُه الافتراضيُّ `[0, 1, 2, 4, 5, 10, 16]` — و١٤ ليست
// فيه أصلاً. فمنشأةٌ بنسبةٍ أخرى كانت تُخرج ورقةً تكذب على عميلها.
//
// ── والمقيسُ كان أسوأَ من المكتوب ──────────────────────────────────────────
// الأرقامُ الهنديّةُ تنعكس عند الرسم: `١٤٪` كانت تصل الورقةَ `٤١٪`
// (‏`codeUnits=[1636, 1633, 1642]`) أي «واحدٌ وأربعون بالمئة»، و`(14%)` تصل
// `(%14)`. فالورقةُ لم تكن تكذب بنسبةٍ قديمةٍ فحسب، بل بنسبةٍ لا وجودَ لها.
//
// ── العقدُ اليوم (قرارُ المالك 2026-08-31) ─────────────────────────────────
// النسبةُ **تُطبع**، لكنّها تُقرأ من `pos_default_tax_rate` كي تطابق الورقةُ
// ما تعرضه الشاشة — لا نصّاً في القالب. والإلحاقُ في موضعٍ واحدٍ
// (`TemplatedInvoiceService._withTaxRateLabels`) يكفي المحرّكَين لأنّ كليهما
// يقرأ `labelAr` من العنصر نفسِه.
//
// ⚠️ **ولا يُقاس هذا بـgrep على الـJSON**: العطبُ في ما يصل الورقة. ولذلك
// يُضبط الإعدادُ هنا على قيمةٍ مميّزة، ثمّ يُفكّ الـPDF ويُقرأ ما رُسم.
// والتوكيدُ على **علامة النسبة مجاورةً لرقم** لا على «١٤» وحدَها: النصُّ
// المنعكسُ لا يحوي «١٤» أصلاً، فنمطٌ يبحث عنها كان سيقرأ صفراً ويمرُّ أخضرَ
// على ورقةٍ تطبع `٤١٪`.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';

// ٢٠٠ − ٠ + ١٠ = ٢١٠ — أرقامٌ متمايزةٌ فتكفي المطابقةُ التامّة.
const _subtotal = 200.0;
const _discount = 0.0;
const _tax = 10.0;
const _total = 210.0;

/// نسبةٌ مضبوطةٌ **لا تشبه شيئاً مخبوزاً**: لا ١٤ ولا ١٦ الافتراضيّة ولا ٤١
/// المنعكسة. فظهورُها دليلٌ قاطعٌ على أنّ المصدرَ هو الإعداد.
const _storedRate = '0.07';
const _expectedClaim = '7%';

/// علامةُ نسبةٍ (لاتينيّةٌ أو عربيّة) مجاورةً لرقمٍ (لاتينيٍّ أو هنديّ) — في
/// أيِّ الاتّجاهين، لأنّ الرسمَ كان يقلب ترتيبَ الأرقام الهنديّة.
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

  Future<List<String>> printDefault(String type, String category) async {
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
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
    )).bytes;
    return probePdf(bytes).allTexts.map((t) => t.text.trim()).toList();
  }

  Future<List<String>> importAndPrint(
      String file, String type, String category, String expectedName) async {
    final json = await rootBundle.loadString('assets/invoice_templates/$file');
    final id = await db.importTemplateFromJson(json);
    await db.setDefaultTemplate(id);

    // 🔴 مرساةٌ غيرُ دائريّة: الحاسمُ يختار **هذا** القالبَ بعينه.
    final resolved = await db.getDefaultTemplateByCategory(type, category);
    expect(resolved?.name, expectedName,
        reason: 'الحاسمُ يجب أن يختار $file — وإلّا فالقياسُ على قالبٍ آخر');

    return printDefault(type, category);
  }

  for (final t in _templates) {
    final file = t[0];

    test('$file يطبع نسبةَ الإعداد لا نسبةً مخبوزة', () async {
      await db.setSetting('pos_default_tax_rate', _storedRate);
      final texts = await importAndPrint(file, t[1], t[2], t[3]);

      // مرساة ١: الورقةُ رُسمت — وإلّا مرَّ كلُّ توكيدٍ زوراً.
      expect(texts, isNotEmpty, reason: 'مرساة: الـPDF فيه نصٌّ مرسوم');

      // مرساة ٢: **سطرُ الضريبة نفسُه** وصل الورقة. بدونها يمرُّ قالبٌ أسقط
      // تذييلَه كلَّه — وهو عينُ ما كان يقع قبل §٦‑١.
      expect(texts.contains('10.00'), isTrue,
          reason: 'مرساة: قيمةُ الضريبة ١٠٫٠٠ يجب أن تُطبع. '
              'ما طُبع: ${texts.where((s) => s.isNotEmpty).take(30).toList()}');

      final claims = texts.where((s) => _rateClaim.hasMatch(s)).toSet();

      // ⚠️ وهذه هي المرساةُ الحاسمة: النسبةُ **تُطبع فعلاً**. بدونها كان
      // توكيدُ «لا ١٤٪» يمرُّ على ورقةٍ بلا نسبةٍ إطلاقاً.
      expect(claims, isNotEmpty,
          reason: '$file — النسبةُ يجب أن تُطبع (قرارُ المالك 2026-08-31)');

      expect(claims, {_expectedClaim},
          reason: '$file — النسبةُ المطبوعةُ يجب أن تتبع '
              '`pos_default_tax_rate` = $_storedRate. '
              'وحداتُ ما طُبع: ${claims.map((c) => c.codeUnits).toList()}');
    });
  }

  test('تغييرُ الإعداد يغيّر الورقة — والكسريُّ لا يُبتَر', () async {
    const file = 'a4_sales_tax_invoice.json';
    final json = await rootBundle.loadString('assets/invoice_templates/$file');
    final id = await db.importTemplateFromJson(json);
    await db.setDefaultTemplate(id);

    await db.setSetting('pos_default_tax_rate', '0.05');
    final five = (await printDefault('a4', 'invoice'))
        .where((s) => _rateClaim.hasMatch(s))
        .toSet();
    expect(five, {'5%'}, reason: 'خمسةٌ بالمئة كما ضُبطت');

    // ⚠️ كسريّةٌ عمداً: `toStringAsFixed(0)` كانت ستطبع «12%» على منشأةٍ
    // نسبتُها ١٢٫٥٪ — بخسٌ صامتٌ في ورقةٍ يقرؤها مراجع.
    await db.setSetting('pos_default_tax_rate', '0.125');
    final twelveHalf = (await printDefault('a4', 'invoice'))
        .where((s) => _rateClaim.hasMatch(s))
        .toSet();
    expect(twelveHalf, {'12.5%'},
        reason: 'النسبةُ الكسريّةُ تُطبع كاملةً لا مبتورة');
  });

  // ── المسارُ الثاني: قاعدةٌ استوردت القالبَ **قبل** إصلاح الأصول ──────────
  //
  // إصلاحُ الأصول لا يبلغ صفّاً مخزَّناً: الملفُّ يُقرأ عند الاستيراد لا عند
  // كلِّ إقلاع. فلولا `repairHardcodedTaxRateLabels` لبقيت كلُّ قاعدةٍ قائمةٍ
  // تحمل «١٤٪» المخبوزةَ — وتطبعها الآن **إلى جانب** نسبة الإعداد.
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

    test('صفٌّ مخزَّنٌ بالنسبة القديمة يُصلَح — والورقةُ تنظف', () async {
      await db.setSetting('pos_default_tax_rate', _storedRate);
      final id = await db.importTemplateFromJson(await legacyJson());
      await db.setDefaultTemplate(id);

      // مرساة: التجهيزةُ **أعادت العطبَ فعلاً** على الورقة — النسبةُ
      // المخبوزةُ المنعكسةُ `٤١٪` تظهر إلى جانب نسبة الإعداد.
      final before = (await printDefault('a4', 'invoice'))
          .where((s) => _rateClaim.hasMatch(s))
          .toSet();
      expect(before.length, greaterThan(1),
          reason: 'مرساة: القالبُ القديمُ يطبع نسبتَين — المخبوزةَ والمضبوطة. '
              'ما طُبع: $before');
      expect(before.contains(_expectedClaim), isTrue,
          reason: 'مرساة: نسبةُ الإعداد حاضرةٌ قبل الإصلاح أيضاً');

      final changed = await db.repairHardcodedTaxRateLabels();
      expect(changed, 1, reason: 'عنصرُ ضريبةٍ واحدٌ في هذا القالب');

      final after = await printDefault('a4', 'invoice');
      expect(after.contains('10.00'), isTrue,
          reason: 'مرساة: سطرُ الضريبة ما زال يُطبع بعد الإصلاح');
      expect(after.where((s) => _rateClaim.hasMatch(s)).toSet(),
          {_expectedClaim},
          reason: 'بعد الإصلاح: نسبةُ الإعداد وحدَها — لا أثرَ للمخبوزة');
    });

    test('متعادلٌ — والتسميةُ التي كتبها المالكُ لا تُمَسّ', () async {
      final id = await db.importTemplateFromJson(await legacyJson());
      await db.setDefaultTemplate(id);

      expect(await db.repairHardcodedTaxRateLabels(), 1);
      // تعادل: لا شيءَ يبقى ليُصلَح.
      expect(await db.repairHardcodedTaxRateLabels(), 0,
          reason: 'التشغيلُ الثاني يجب أن يجد القاعدةَ نظيفة');

      // تسميةٌ من عند المالك — نصٌّ لم نشحنه قطّ.
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
