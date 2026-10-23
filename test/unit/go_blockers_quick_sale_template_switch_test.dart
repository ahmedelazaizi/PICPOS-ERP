// ═══════════════════════════════════════════════════════════════════════════
// §٤‑٥ — مِزلاجُ «القالب المستخدم»: كان يُحفَظ ولا يُقرأ
// ═══════════════════════════════════════════════════════════════════════════
//
// `pos_receipt_template` كان معلَناً في سياسة البيع السريع بثلاثةِ خيارات
// (‏٨٠mm · ٥٨mm · فاتورةٌ ضريبيّة A4)، ويُحفَظ في القاعدة، **ولا يُقرأ في
// أيِّ مسارِ طباعة**. فمن ضبطه على ٥٨mm ظلّ يطبع على ٨٠mm.
//
// ⚠️ ولم يكن خداعاً: الشاشةُ تعرض وسمَ «يُحفَظ ولا يُنفَّذ بعد» بسببه —
// و`notEnforcedReason` نصُّه أنّ تثبيتَه «يحتاج قراراً». والقرارُ جاء
// 2026-08-31: **مُرجِّحٌ عند غياب ربطٍ صريح**.
//
// ── العقدُ المقيسُ هنا ────────────────────────────────────────────────────
//   ١ · مِزلاجٌ **لم يُلمَس** لا يغيّر شيئاً.       ← أخطرُ بندٍ في الملفّ
//   ٢ · مِزلاجٌ مضبوطٌ يفوز على القالب الافتراضيِّ للفئة.
//   ٣ · ويخسر أمام أيِّ ربطٍ صريح.
//   ٤ · ولا يمسّ نوعَ مستندٍ آخرَ (مشترياتٍ ولا كشفَ حساب).
//   ٥ · وقالبٌ لا يُوجد ⇒ سقوطٌ **صامتٌ** للمستوى التالي.
//
// ⚠️ **والبندُ الأوّلُ ليس تفصيلاً**: التخزينُ فهرسٌ نصّيّ، و`defaultIndex`
// صفرٌ. فقراءةٌ ساقطةٌ إلى الافتراض كانت ستعني «اختار المديرُ
// thermal80_quick_sale» في **كلِّ** تركيبٍ لم يفتح الشاشةَ قطّ — فيتقدّم على
// قالبه الافتراضيّ وينقلب مطبوعُه صامتاً. وهذا ما وقع في أوّل صياغةٍ لهذا
// الإصلاح قبل القياس.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/services/printing/template_resolver.dart';

/// الخيارُ رقم ١ في صفّ `tpl` — القالبُ الحراريُّ ٥٨mm.
const _idx58 = '1';

/// والخيارُ رقم ٠ — ٨٠mm.
const _idx80 = '0';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  /// يستورد قالباً من الأصول ويعيد معرِّفَه.
  Future<int> importAsset(String file) async =>
      db.importTemplateFromJson(
          await rootBundle.loadString('assets/invoice_templates/$file'));

  Future<TemplateResolution> resolveReceipt() => db.resolveTemplateFor(
        documentType: 'sales_receipt',
        category: 'receipt',
        paperType: 'thermal',
      );

  group('المِزلاجُ يُقرأ الآن', () {
    test('مضبوطٌ على ٥٨mm ⇒ يفوز على القالب الافتراضيِّ للفئة', () async {
      final id58 = await importAsset('thermal58_quick_sale.json');

      // مرساةٌ غيرُ دائريّة: **قبل** ضبط المِزلاج يحسم بمستوى الفئة (٦) على
      // قالبٍ آخر. بدونها قد يمرُّ التوكيدُ التالي لأنّ ٥٨mm كان الفائزَ
      // أصلاً، فلا يُثبت أنّ المِزلاجَ فعل شيئاً.
      final before = await resolveReceipt();
      expect(before.level, 6,
          reason: 'مرساة: بلا مِزلاجٍ يحسم بمستوى الفئة');
      expect(before.templateId, isNot(id58),
          reason: 'مرساة: الفائزُ قبل الضبط ليس ٥٨mm');

      await db.setSetting(kQuickSaleReceiptTemplateKey, _idx58);

      final after = await resolveReceipt();
      expect(after.level, 5, reason: 'المِزلاجُ هو المستوى الخامس');
      expect(after.templateId, id58,
          reason: 'القالبُ المطبوعُ يجب أن يتبع المِزلاج');
    });

    test('ويخسر أمام ربطٍ صريح — الربطُ نيّةٌ أخصّ', () async {
      final id58 = await importAsset('thermal58_quick_sale.json');
      final id80 = await importAsset('thermal80_quick_sale.json');

      await db.setSetting(kQuickSaleReceiptTemplateKey, _idx58);
      // مرساة: المِزلاجُ فاعلٌ فعلاً قبل أن نُدخل الرابطة.
      expect((await resolveReceipt()).templateId, id58,
          reason: 'مرساة: المِزلاجُ يفوز حين لا رابطة');

      await db.activateBinding(
        documentType: 'sales_receipt',
        templateId: id80,
      );

      final r = await resolveReceipt();
      expect(r.level, 4, reason: 'الرابطةُ العامّةُ هي المستوى الرابع');
      expect(r.templateId, id80,
          reason: 'ربطٌ صريحٌ يتقدّم على مِزلاجٍ عامّ — وإلّا أُبطل صامتاً');
    });
  });

  group('ومِزلاجٌ لم يُلمَس لا يقرّر شيئاً', () {
    test('غيابُ المفتاح لا يفرض الخيارَ الأوّل', () async {
      await importAsset('thermal80_quick_sale.json');

      final r = await resolveReceipt();
      expect(r.level, isNot(5),
          reason: 'الفهرسُ الافتراضيُّ صفرٌ (٨٠mm)، فقراءةٌ ساقطةٌ إليه كانت '
              'ستفرضه على كلِّ تركيبٍ لم يفتح الشاشة');
      expect(r.level, 6, reason: 'يبقى السلوكُ القائم — الحسمُ بالفئة');
    });

    test('وفهرسٌ فاسدٌ أو خارجُ المدى مثلُه', () async {
      await importAsset('thermal58_quick_sale.json');

      for (final bad in const ['', '  ', 'abc', '-1', '3', '99']) {
        await db.setSetting(kQuickSaleReceiptTemplateKey, bad);
        expect((await resolveReceipt()).level, 6,
            reason: 'قيمةٌ شاذّةٌ "$bad" تسقط للمستوى التالي لا تُحزَر');
      }
    });

    test('والمساعدُ نفسُه يفرّق بين الغائب والمضبوط', () {
      expect(quickSaleReceiptTemplateFile(null), isNull);
      expect(quickSaleReceiptTemplateFile(_idx80), 'thermal80_quick_sale');
      expect(quickSaleReceiptTemplateFile(_idx58), 'thermal58_quick_sale');
      expect(quickSaleReceiptTemplateFile('2'), 'a4_sales_tax_invoice');
    });
  });

  group('نطاقُه إيصالُ نقطةِ البيع وحدَه', () {
    test('لا يمسّ فاتورةَ المشتريات', () async {
      await importAsset('thermal58_quick_sale.json');
      await db.setSetting(kQuickSaleReceiptTemplateKey, _idx58);

      // مرساة: المِزلاجُ فاعلٌ على الإيصال في نفس القاعدة.
      expect((await resolveReceipt()).level, 5,
          reason: 'مرساة: المِزلاجُ يعمل على `sales_receipt`');

      final purchase = await db.resolveTemplateFor(
        documentType: 'purchase_invoice',
        category: 'purchase',
        paperType: 'a4',
      );
      expect(purchase.level, isNot(5),
          reason: 'مِزلاجُ إيصالِ البيع لا يحكم فاتورةَ مشترياتٍ');
    });
  });

  group('السقوطُ الصامتُ حين لا قالب', () {
    test('قالبٌ غيرُ مستورَدٍ ⇒ المستوى التالي بلا انهيار', () async {
      // ٥٨mm **لم يُستورَد** — والمِزلاجُ يشير إليه.
      await db.setSetting(kQuickSaleReceiptTemplateKey, _idx58);

      final r = await resolveReceipt();
      expect(r.level, 6,
          reason: 'مِزلاجٌ لا يجد قالبَه يسقط للمستوى التالي — ولا يمنع '
              'فاتورةً من الطباعة');
      expect(r.templateId, isNotNull,
          reason: 'والقالبُ الافتراضيُّ للفئة ما زال يخرج');
    });

    test('وقالبٌ حُذف بعد الضبط مثلُه', () async {
      final id58 = await importAsset('thermal58_quick_sale.json');
      await db.setSetting(kQuickSaleReceiptTemplateKey, _idx58);
      expect((await resolveReceipt()).level, 5, reason: 'مرساة: يعمل أوّلاً');

      await db.deleteTemplate(id58);

      final r = await resolveReceipt();
      expect(r.level, 6, reason: 'الحذفُ يُسقط مستوىً لا يُسقط الطباعة');
    });
  });
}
