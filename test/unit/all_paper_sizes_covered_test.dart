// الإصلاحاتُ تشمل المقاساتِ الأربعة — A4 · A5 · 80mm · 58mm.
//
// ── لماذا حارسٌ للمقاسات أصلاً ────────────────────────────────────────────
// إصلاحاتُ النطاقات والأعمدة والرأس الثنائيّ كلُّها في المحرّك المشترك،
// فيسهل الظنُّ أنّها تعمّ. لكنّ في المحرّك **عتبةً** صريحةً (`narrowPaperMm`)
// تُغيّر السلوكَ تحت ١٠٠مم، وحسابَ عرضٍ خاصّاً بالحراريّ (‏`paperWidth - 8`
// لرأس الطباعة). فالتعميمُ دعوى، وهذا الملفُّ يقيسها.
//
// ⚠️ **والمقصودُ من الحارس أن يُظهر الفرقَ لا أن يخفيه**: الرأسُ الثنائيُّ
// **يُطفأ عمداً** على ٥٨ و٨٠ — لا مكانَ لسطرين في ٥٢مم، والسطرُ الثاني يدهس
// الصفَّ الأوّل. فتثبيتُ إطفائه هناك جزءٌ من العقد لا نقصٌ فيه.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/domain/printing/template_mapper.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';

/// المقاساتُ الأربعةُ بعرض الورق المخزَّن — لا بعرض الطباعة.
const _papers = <String, ({double widthMm, double? heightMm})>{
  'A4': (widthMm: 210, heightMm: 297),
  'A5': (widthMm: 148, heightMm: 210),
  '80mm': (widthMm: 80, heightMm: null),
  '58mm': (widthMm: 58, heightMm: null),
};

/// الورقُ الضيّق — تحت عتبة `narrowPaperMm` بعد حسم رأس الطباعة.
const _narrow = {'80mm', '58mm'};

LegacyElement _body(String key) =>
    LegacyElement(elementType: 'variable', content: key, fontSize: 10);

TemplateBand _band(TemplateDocument d, BandId id) =>
    d.bands.firstWhere((b) => b.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('توزيعُ النطاقات لا يعتمد على المقاس', () {
    _papers.forEach((name, p) {
      test('$name — الستّةُ تمتلئ وجدولُ الأصناف في «التفاصيل»', () {
        final paper = PaperSpec(
          widthMm: p.widthMm,
          heightMm: p.heightMm,
          margins: const MarginsMm.all(5),
        );
        final doc = TemplateMapper.fromLegacy(
          paper: paper,
          elements: [
            _body('company_name'),
            _body('invoice_number'),
            _body('customer_name'),
            _body('items_table'),
            _body('total_amount'),
            _body('notes'),
          ],
          table: const TableSpec(columns: [
            TableColumn(key: 'name', labelAr: 'الصنف', labelEn: 'Item'),
            TableColumn(key: 'total', labelAr: 'الإجمالي', labelEn: 'Amount'),
          ]),
        );

        for (final id in BandId.values) {
          expect(_band(doc, id).elements, hasLength(1),
              reason: '$name — النطاق ${id.name}');
        }
        expect(_band(doc, BandId.details).elements.single.contentKey,
            'items_table');
      });
    });
  });

  group('الورقُ الضيّقُ يُطفئ الثنائيّةَ — والعريضُ يُشعلها', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    _papers.forEach((name, p) {
      test('$name — الثنائيّةُ ${_narrow.contains(name) ? "مطفأة" : "مشتعلة"}',
          () async {
        final id = await db.createTemplate(
          name: 'قالبُ $name',
          type: p.widthMm <= 80 ? 'thermal' : 'a4',
          templateCategory: 'invoice',
          paperSize: name,
          paperWidth: p.widthMm,
          paperHeight: p.heightMm,
        );
        final t = (await db.getTemplateById(id))!;
        final paper = TemplateRenderPipeline.buildPaper(t);
        final table = TemplateRenderPipeline.buildTable(
            await db.getTableSettings(id), paper);

        expect(table, isNotNull, reason: '$name بلا أعمدة');
        // الأعمدةُ تحمل `labelEn` في المقاسات كلِّها — الفرقُ في العتبة لا
        // في التعريف. وهذا ما يجعل الإطفاءَ قراراً لا نقصَ بيانات.
        expect(table!.columns.every((c) => c.labelEn.isNotEmpty), isTrue,
            reason: '$name — عمودٌ بلا إنجليزيّ');
        expect(table.bilingualHeaders, !_narrow.contains(name),
            reason: '$name — عرضُ الطباعة ${paper.widthMm}مم '
                'والعتبةُ $narrowPaperMm');
      });
    });

    test('العتبةُ مقيسةٌ لا مفترَضة — ٨٠mm تُطبع بـ٧٢ و٥٨ بـ٥٠', () async {
      for (final e in {'80mm': 80.0, '58mm': 58.0}.entries) {
        final id = await db.createTemplate(
          name: e.key, type: 'thermal', templateCategory: 'invoice',
          paperSize: e.key, paperWidth: e.value,
        );
        final paper =
            TemplateRenderPipeline.buildPaper((await db.getTemplateById(id))!);
        // رأسُ الطباعة يبتلع ٨مم — فالعرضُ الصالحُ أقلُّ من عرض الورق.
        expect(paper.widthMm, e.value - 8);
        expect(paper.widthMm, lessThan(narrowPaperMm));
      }
    });
  });

  group('ارتفاعاتُ النطاقات وحجمُ الخطّ يعمّان المقاسات', () {
    test('العمودُ المخزَّنُ يُقرأ أيّاً كان الورق', () {
      final parsed = TemplateRenderPipeline.parseBandHeights(
          '{"header":20,"details":40,"footer":15}');
      expect(parsed[BandId.header], 20.0);
      expect(parsed[BandId.details], 40.0);
      expect(parsed[BandId.footer], 15.0);
    });

    test('ارتفاعُ الرأس الثنائيِّ يتبع الخطَّ لا الورق', () {
      // الدالّةُ لا تسأل عن المقاس أصلاً — فالمقاسُ يقرّر **هل** ثنائيٌّ،
      // والخطُّ يقرّر **كم** يحتاج. فصلٌ مقصودٌ يمنع رأساً مقصوصاً على A5.
      expect(bilingualHeaderHeightMm(9, 6), closeTo(10.0, 0.1));
      expect(bilingualHeaderHeightMm(12, 6), closeTo(13.3, 0.1));
      expect(bilingualHeaderHeightMm(12, 6),
          greaterThan(bilingualHeaderHeightMm(9, 6)));
    });
  });

  group('حقولُ الصنف الجديدةُ تصل الجدولَ في المقاسات كلِّها', () {
    test('الكودُ والوحدةُ والخصمُ والضريبةُ تُقرأ من خريطة البند', () {
      const table = TableSpec(columns: [
        TableColumn(key: 'code', labelAr: 'الكود', labelEn: 'Code'),
        TableColumn(key: 'unit', labelAr: 'الوحدة', labelEn: 'Unit'),
        TableColumn(key: 'discount', labelAr: 'الخصم', labelEn: 'Disc.'),
        TableColumn(key: 'tax', labelAr: 'الضريبة', labelEn: 'VAT'),
        TableColumn(key: 'barcode', labelAr: 'الباركود', labelEn: 'Barcode'),
      ]);

      final rows = TemplateRenderPipeline.buildRows([
        {
          'name': 'صنف',
          'quantity': 2.0,
          'price': 10.0,
          'total': 20.0,
          'code': 'SKU-1',
          'unit': 'كرتونة',
          'barcode': '6221031',
          'discount': 1.5,
          'tax': 2.8,
        },
      ], table, 2);

      // ⚠️ والباركودُ **غيرُ** الكود: كانا يقرآن نفسَ الحقل، فعمودُ الباركود
      //    يطبع كودَ الصنف. لم يظهر لأنّهما لم يُشعلا معاً قطُّ.
      expect(rows.single, ['SKU-1', 'كرتونة', '1.50', '2.80', '6221031']);
    });

    test('بندٌ قديمٌ بلا الحقول الجديدة لا ينهار', () {
      const table = TableSpec(columns: [
        TableColumn(key: 'code', labelAr: 'الكود'),
        TableColumn(key: 'discount', labelAr: 'الخصم'),
      ]);
      final rows = TemplateRenderPipeline.buildRows(
          [{'name': 'صنف', 'quantity': 1.0, 'price': 5.0, 'total': 5.0}],
          table, 2);
      expect(rows.single, ['', '0.00']);
    });
  });
}
