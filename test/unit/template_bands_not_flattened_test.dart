// النطاقاتُ الستّةُ تمتلئ — ولا ينهار القالبُ في نطاقٍ واحد.
//
// ── العطبُ الذي يمنعه ──────────────────────────────────────────────────────
// `_seedDefaultElements` كانت تكتب عناصرَها **بلا `section`**، فتأخذ الافتراضَ
// `'body'` من عمود الجدول. و`TemplateMapper._bandFor` كان فرعُه الافتراضيُّ
// يعرف نطاقين لا غير — `party` لمفاتيح الطرف و`info` لكلِّ ما عداها. فكانت
// النتيجةُ المقيسةُ على «فاتورة A4»:
//
//   الرأس ٠مم · **البيانات ١٦٢مم** · الطرف ١٩٫٨مم · التفاصيل والمجاميع
//   والتذييل أصفار.
//
// وأثرُه على الشاشة عطبان لا واحد:
//   ١ · الترتيبُ مسطَّح — ٢٢ حقلاً في عمودٍ واحدٍ تحت «البيانات».
//   ٢ · **الورقةُ مقصوصة** — نطاقُ `details` صفريُّ الارتفاع، والجدولُ يُرسم
//       فيه بـ`Clip.none` فيخرج كلُّه خارجَ حدود الورقة.
//
// ⚠️ ولا يُكتفى هنا بـ«النطاقُ غيرُ فارغ»: الرقمُ ١٦٢ هو عينُ ما كان يُنتجه
// العطبُ، فتثبيتُه نفياً هو ما يمنع عودتَه. راجع «مصالحةٌ قد تتّفق عند رقمٍ
// خاطئ» — شرطٌ فضفاضٌ يبارك رقماً معطوباً.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/printing/print_values.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/domain/printing/template_mapper.dart';
import 'package:ural_erp/services/printing/template_migration.dart';
import 'package:ural_erp/services/printing/template_render_pipeline.dart';

/// عنصرٌ قديمٌ بقسمٍ عامٍّ — عينُ ما كان يبذره الباذر.
LegacyElement _body(String key, {double fontSize = 12}) => LegacyElement(
      elementType: 'variable',
      content: key,
      section: 'body',
      fontSize: fontSize,
    );

const _paper = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(5),
);

TableSpec _table() => const TableSpec(
      columns: [
        TableColumn(key: 'product', labelAr: 'الصنف', labelEn: 'Item'),
        TableColumn(key: 'quantity', labelAr: 'الكمية', labelEn: 'Qty'),
        TableColumn(key: 'total', labelAr: 'الإجمالي', labelEn: 'Amount'),
      ],
    );

TemplateBand _band(TemplateDocument d, BandId id) =>
    d.bands.firstWhere((b) => b.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('المُخطِّطُ يشتقّ النطاقَ من المفتاح حين لا يقول القسمُ شيئاً', () {
    test('جدولُ الأصناف يقع في «التفاصيل» لا في «البيانات»', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _paper,
        elements: [
          _body('company_name'),
          _body('invoice_number'),
          _body('customer_name'),
          _body('items_table'),
          _body('total_amount'),
          _body('notes'),
        ],
        table: _table(),
      );

      expect(_band(doc, BandId.details).elements.map((e) => e.contentKey),
          ['items_table']);
      expect(_band(doc, BandId.info).elements.map((e) => e.contentKey),
          ['invoice_number']);
    });

    test('كلُّ نطاقٍ من الستّة يأخذ عنصرَه — ولا ينهار الستّةُ في واحد', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _paper,
        elements: [
          _body('company_name'),
          _body('invoice_number'),
          _body('customer_name'),
          _body('items_table'),
          _body('total_amount'),
          _body('notes'),
        ],
        table: _table(),
      );

      for (final id in BandId.values) {
        expect(_band(doc, id).elements, hasLength(1),
            reason: 'النطاق ${id.name} يجب أن يحمل عنصراً واحداً');
      }
    });

    test('مفاتيحُ ملفّات الأصول الخامُ تُوزَّع صحيحةً', () {
      // ⚠️ مقيسةٌ من `assets/invoice_templates/*.json` نفسِها: تلك الملفّاتُ
      //    تكتب المفتاحَ في `type` بلا `content`، وبأسماءٍ لا يولّدها
      //    المحرّرُ — `customer` و`adhoc_customer_name` منها.
      const cases = <String, BandId>{
        'company_name': BandId.header,
        'logo': BandId.header,
        'cashier_name': BandId.info,
        'time': BandId.info,
        'customer': BandId.party,
        'adhoc_customer_name': BandId.party,
        'supplier_name': BandId.party,
        'payment_method': BandId.party,
        'table_number': BandId.party,
        'items_table': BandId.details,
        'total': BandId.totals,
        'tax': BandId.totals,
        'remaining': BandId.totals,
        'notes': BandId.footer,
        'qr_code': BandId.footer,
      };
      cases.forEach((key, band) {
        expect(bandForKey(key), band, reason: 'المفتاح $key');
      });
    });

    test('سطرُ التذييل الحرُّ يبقى في التذييل — ومفتاحُه فارغ', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _paper,
        elements: [
          const LegacyElement(
            elementType: 'footer',
            content: 'شكراً لتعاملكم معنا',
          ),
        ],
      );

      // `bandForKey('')` تُرجع `info` — فالنوعُ هو ما ينقذ هذا السطر.
      expect(bandForKey(''), BandId.info);
      expect(_band(doc, BandId.footer).elements, hasLength(1));
      expect(_band(doc, BandId.info).elements, isEmpty);
    });

    test('القسمُ الصريحُ يسبق المفتاحَ — ولا يقفز عنصرٌ وضعه المستخدم', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _paper,
        elements: [
          const LegacyElement(
            elementType: 'variable',
            content: 'company_name',
            section: 'footer',
          ),
        ],
      );

      expect(_band(doc, BandId.footer).elements, hasLength(1));
      expect(_band(doc, BandId.header).elements, isEmpty);
    });

    test('«التفاصيل» يحجز كتلةَ جدوله فلا يُرسم الجدولُ خارجَ الورقة', () {
      final table = _table();
      final doc = TemplateMapper.fromLegacy(
        paper: _paper,
        elements: [_body('items_table')],
        table: table,
      );

      // بلا الحجز كان الارتفاعُ ارتفاعَ سطرٍ واحد (‏١٢ × ٠٫٤٩٣٩ ≈ ٥٫٩مم)،
      // والجدولُ يفيض منه. والقيمةُ المرساةُ محسوبةٌ لا مقرَّبة:
      // رأسٌ بسطرٍ (٦) + أربعةُ صفوفٍ (٦ × ٤) = ٣٠مم.
      expect(table.designHeightMm, 30.0);
      expect(_band(doc, BandId.details).heightMm, 30.0);

      // والرأسُ الثنائيُّ سطران — فيرتفع الحجزُ إلى ٣٣مم، وهو ما يقع فعلاً
      // على A4 لأنّ `buildTable` تُشعل الثنائيّةَ فوق الورق الضيّق.
      final bilingual = table.copyWith(bilingualHeaders: true);
      expect(bilingual.designHeightMm, 33.0);
      expect(
        TemplateMapper.fromLegacy(
          paper: _paper,
          elements: [_body('items_table')],
          table: bilingual,
        ).bands.firstWhere((b) => b.id == BandId.details).heightMm,
        33.0,
      );
    });
  });

  group('البذرُ الافتراضيُّ يخرج بنطاقاتٍ صحيحة', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('«فاتورة A4» تملأ الستّةَ — و«البيانات» ليست ١٦٢مم', () async {
      await db.seedDefaultTemplates();

      final template = await db.getDefaultTemplateByCategory('a4', 'invoice');
      expect(template, isNotNull, reason: 'قالبُ الفاتورة الافتراضيُّ مبذور');

      final doc = TemplateRenderPipeline.buildDocument(
        template: template!,
        orderedElements: await db.getTemplateElements(template.id),
        tableSettings: await db.getTableSettings(template.id),
      );

      // ⚠️ الأعدادُ من ملفِّ التصميم `PicPos Template Editor.dc.html`.
      expect(_band(doc, BandId.header).elements, hasLength(6));
      expect(_band(doc, BandId.info).elements, hasLength(4));
      expect(_band(doc, BandId.party).elements, hasLength(4));
      expect(_band(doc, BandId.details).elements, hasLength(1));
      expect(_band(doc, BandId.totals).elements, hasLength(5));
      expect(_band(doc, BandId.footer).elements, hasLength(4));

      // نفيُ الرقم المعطوب صراحةً — لا «أكبر من صفر».
      expect(_band(doc, BandId.info).heightMm, lessThan(30));
      expect(_band(doc, BandId.details).heightMm, 96.0);
    });

    test('ارتفاعاتُ النطاقات تُحفَظ — لا تُشتقّ', () async {
      await db.seedDefaultTemplates();
      final template = await db.getDefaultTemplateByCategory('a4', 'invoice');

      final doc = TemplateRenderPipeline.buildDocument(
        template: template!,
        orderedElements: await db.getTemplateElements(template.id),
        tableSettings: await db.getTableSettings(template.id),
      );

      // ⚠️ أرقامُ التصميم لا أرقامُ الاشتقاق. أبعدُ قاعِ عنصرٍ يعطي
      //    ٣١/١٩/١٨/٩٦/٣٣/٣٣ — أي بلا الحشوة السفليّة تحت كلِّ نطاق،
      //    فتضيق الورقةُ ٢٨مم عن المقصود. تثبيتُ القيم المحسوبة هو ما
      //    يمنع عودةَ الاشتقاق صامتاً.
      expect(_band(doc, BandId.header).heightMm, 34.0);
      expect(_band(doc, BandId.info).heightMm, 24.0);
      expect(_band(doc, BandId.party).heightMm, 26.0);
      expect(_band(doc, BandId.details).heightMm, 96.0);
      expect(_band(doc, BandId.totals).heightMm, 42.0);
      expect(_band(doc, BandId.footer).heightMm, 36.0);
    });

    test('عمودٌ فارغٌ أو تالفٌ يعني «اشتقّ» — لا ارتفاعاً صفريّاً', () {
      expect(TemplateRenderPipeline.parseBandHeights(null), isEmpty);
      expect(TemplateRenderPipeline.parseBandHeights(''), isEmpty);
      // JSON تالفٌ لا يُسقط الشاشةَ ومعها عملُ المستخدم.
      expect(TemplateRenderPipeline.parseBandHeights('{ليس'), isEmpty);
      // وقيمةٌ غيرُ موجبةٍ تُهمَل: نطاقٌ بصفرٍ يخفي عناصرَه.
      expect(
        TemplateRenderPipeline.parseBandHeights('{"header":0,"info":24}'),
        {BandId.info: 24.0},
      );
    });

    test('العناوينُ الثنائيّةُ صارت ممكنةً على A4', () async {
      await db.seedDefaultTemplates();
      final template = await db.getDefaultTemplateByCategory('a4', 'invoice');
      final table = TemplateRenderPipeline.buildTable(
        await db.getTableSettings(template!.id),
        TemplateRenderPipeline.buildPaper(template),
      );

      // ⚠️ كانت أعمدةُ الفاتورة كلُّها بلا `labelEn`، وشرطُ الإشعال
      //    `columns.any((c) => c.labelEn.isNotEmpty)` — فالرأسُ الثنائيُّ
      //    مطفأٌ **دائماً** على A4 مهما فعل المستخدم.
      expect(table, isNotNull);
      expect(table!.columns.every((c) => c.labelEn.isNotEmpty), isTrue);
      expect(table.bilingualHeaders, isTrue);

      // ⚠️ **وحدودُ هذا الحارس**: يثبّت أنّ **المواصفةَ** صارت ثنائيّةً — لا
      //    أنّ الورقةَ تطبعها. مقيسٌ 2026-08-29 أنّ **لا بصمةً ذهبيّةً واحدةً**
      //    من السبعٍ وعشرين تحمل عنواناً إنجليزيّاً، فالانقطاعُ أعمقُ من هذه
      //    الطبقة ولم يُشخَّص بعد. لا تقرأ هذا الاختبارَ دليلاً على المطبوع.
    });

    test('القالبُ المبذورُ مختومٌ عند ٢ فلا تدهسه الهجرةُ عند أوّل فتح',
        () async {
      await db.seedDefaultTemplates();
      final template = await db.getDefaultTemplateByCategory('a4', 'invoice');

      expect(TemplateMigration.isMigrated(template!), isTrue);
      // مُعادٌ آمن: لا شيءَ لتهاجره.
      expect(await TemplateMigration.migrate(db, template.id), isFalse);
    });

    test('ملفُّ أصولٍ بلا `section` يُوزَّع على نطاقاته — لا في واحد',
        () async {
      // ⚠️ ثمانيةٌ من التسعةَ عشرَ لا تحمل `section` إطلاقاً، فتأخذ الافتراضَ
      //    `'body'` عند الاستيراد (`invoice_template_dao.dart:343`). وهذا
      //    الاختبارُ يمسك أكبرَها — لأنّ البصمةَ الذهبيّةَ تقيس **الورق**،
      //    والعطبُ المبلَّغ عنه كان في **المحرّر**.
      final id = await db.importTemplateFromJson(
          await File('assets/invoice_templates/a4_commercial.json')
              .readAsString());

      final template = (await db.getTemplateById(id))!;
      final doc = TemplateRenderPipeline.buildDocument(
        template: template,
        orderedElements: await db.getTemplateElements(id),
        tableSettings: await db.getTableSettings(id),
      );

      final filled = BandId.values
          .where((b) => _band(doc, b).elements.isNotEmpty)
          .toList();

      expect(filled.length, greaterThanOrEqualTo(4),
          reason: 'كان الكلُّ ينهار في `info` و`party` — نطاقان لا غير');

      String bandOf(String key) => BandId.values
          .firstWhere((b) =>
              _band(doc, b).elements.any((e) => e.contentKey == key))
          .name;

      expect(bandOf('company_name'), 'header');
      expect(bandOf('logo'), 'header');
      expect(bandOf('invoice_number'), 'info');
      expect(bandOf('customer'), 'party');
      expect(bandOf('total'), 'totals');
      expect(bandOf('qr_code'), 'footer');

      // ⚠️ ولا يُتوقَّع جدولٌ هنا: **الثمانيةُ كلُّها بلا عنصر `items_table`**
      //    في ملفّاتها — يزرعه `_seedMissingElements` عند الإقلاع بقسم
      //    `details`. وهذا هو تفسيرُ بقاء بصماتها الذهبيّة بلا تغيّرٍ بعد
      //    إصلاح التوزيع: نطاقُ تفاصيلها فارغٌ لغياب الجدول لا لخللٍ في
      //    التوزيع.
      expect(_band(doc, BandId.details).elements, isEmpty);
    });

    test('كلُّ عنصرٍ مبذورٍ يحمل قسماً غيرَ `body`', () async {
      await db.seedDefaultTemplates();
      final template = await db.getDefaultTemplateByCategory('a4', 'invoice');
      final elements = await db.getTemplateElements(template!.id);

      expect(elements, isNotEmpty);
      expect(elements.map((e) => e.section), isNot(contains('body')));
      expect(elements.map((e) => e.bandId), isNot(contains(null)));
    });
  });

  group('الحقولُ التي لا بيانَ لها تُرجع فراغاً لا رقمَ جارها', () {
    // ⚠️ ستّةُ مفاتيحَ كانت موسومةً «تُرجع `''` عن قصد» **بلا `return`**،
    //    فتسقط إلى `cash_amount` التي تليها في نفس `switch`. فطبعت «الفرع»
    //    و«المخزن» المبلغَ النقديَّ رقماً — رُصد على البصمة الذهبيّة:
    //    «ﺍﻟﻔﺮﻉ: 300.00». وكان نائماً لأنّ أيَّ قالبٍ لم يستعمل المفاتيحَ قطّ.
    final payload = PrintPayload(
      invoiceNumber: 'INV-1',
      date: DateTime(2026, 8, 29),
      companyName: 'ش',
      companyAddress: 'ع',
      companyPhone: '0',
      subtotal: 100,
      discount: 0,
      tax: 0,
      deliveryFee: 0,
      total: 100,
      paid: 100,
      remaining: 0,
      cashAmount: 300,
    );

    test('الفرعُ والمخزنُ وأخواتُهما لا يطبعون المبلغَ النقديّ', () {
      // النقديُّ موجودٌ فعلاً — فلو تسرّب لظهر.
      expect(resolveContentValue('cash_amount', payload), '300.00');

      for (final key in const [
        'warehouse_name',
        'branch_name',
        'delivery_type',
        'delivery_address',
        'courier_name',
        'waiter_name',
      ]) {
        expect(resolveContentValue(key, payload), '',
            reason: 'المفتاح $key');
      }
    });
  });

  group('إصلاحُ القوالب التي هاجرت بالمُخطِّط المعطوب', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    Future<int> newTemplate() => db.createTemplate(
          name: 'قالبُ فحص',
          type: 'a4',
          templateCategory: 'invoice',
          paperSize: 'A4',
          paperWidth: 210,
          paperHeight: 297,
        );

    Future<void> element(int templateId, String key, String band) =>
        db.into(db.invoiceTemplateElements).insert(
              InvoiceTemplateElementsCompanion.insert(
                templateId: templateId,
                elementType: 'variable',
                content: Value(key),
                bandId: Value(band),
              ),
            );

    test('بصمةُ العطب: جدولُ الأصناف خارجَ «التفاصيل»', () async {
      final id = await newTemplate();
      await element(id, 'items_table', 'info');

      expect(
        TemplateMigration.needsBandRepair(await db.getTemplateElements(id)),
        isTrue,
      );
    });

    test('قالبٌ سليمٌ لا يُلمس — والبصمةُ لا تتّسع لعنصرٍ حرّكه المستخدم',
        () async {
      final id = await newTemplate();
      await element(id, 'items_table', 'details');
      // اسمُ الشركة في التذييل — اختيارُ المستخدم، لا عطب.
      await element(id, 'company_name', 'footer');

      expect(
        TemplateMigration.needsBandRepair(await db.getTemplateElements(id)),
        isFalse,
      );
    });
  });
}
