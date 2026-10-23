// test/unit/template_layout_writer_test.dart
//
// معاملةُ حفظ القالب — **والدورةُ كاملةً**: يُكتب المستندُ ثمّ يُقرأ بخطّ
// الرسم نفسِه الذي يطبع.
//
// ── لماذا الدورةُ لا الكتابةُ وحدَها ──────────────────────────────────────
// «عدّلت ولم يتغيّر شيء» أشيعُ عطبٍ في المحرّرات، وسببُه غالباً حقلٌ يُكتب
// بمفتاحٍ ويُقرأ بآخر. فاختبارٌ يقيس أنّ الكتابةَ وقعت لا يمسكه إطلاقاً —
// الصفُّ موجودٌ والقارئُ لا يراه. ولذلك يُقاس هنا ما **يصل الورقةَ** بعد
// الحفظ لا ما دخل الجدول.
//
// وأخصُّ ما يُقاس: **عنوانُ العمود**. فحصُ القبول §٢ يقول «غيّر عنوان عمود
// ‹الصنف› إلى ‹البيان›» — وهو ما كان مستحيلاً لأنّ العناوينَ حرفيّاتٌ في
// الراسم.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/template_layout_writer.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

const _margins = MarginsMm(top: 10, right: 10, bottom: 10, left: 10);

TemplateDocument _doc({
  String companyLabel = 'اسم الشركة',
  String itemLabel = 'الصنف',
  double totalX = 120,
  String? totalCondition,
}) =>
    TemplateDocument(
      paper: const PaperSpec(widthMm: 210, heightMm: 297, margins: _margins),
      bands: [
        TemplateBand(id: BandId.header, heightMm: 30, repeatEachPage: true,
            elements: [
          TemplateElement(
            id: 'h1',
            contentKey: 'company_name',
            xMm: 0,
            yMm: 2,
            wMm: 90,
            hMm: 8,
            labelAr: companyLabel,
            fontSize: 14,
            bold: true,
          ),
        ]),
        const TemplateBand(id: BandId.details, heightMm: 80,
            growsWithData: true),
        TemplateBand(id: BandId.totals, heightMm: 20, elements: [
          TemplateElement(
            id: 't1',
            contentKey: 'total',
            xMm: totalX,
            yMm: 4,
            wMm: 60,
            hMm: 8,
            labelAr: 'الإجمالي المستحق',
            condition: totalCondition,
          ),
        ]),
      ],
      table: TableSpec(columns: [
        const TableColumn(key: 'index', labelAr: 'م', flex: 0.8),
        TableColumn(
            key: 'name',
            labelAr: itemLabel,
            labelEn: 'Item',
            flex: 3,
            align: ColumnAlign.start),
        const TableColumn(key: 'total', labelAr: 'الإجمالي', flex: 1.5),
        const TableColumn(key: 'tax', labelAr: 'الضريبة', visible: false),
      ]),
    );

void main() {
  late AppDatabase db;
  late int templateId;

  setUp(() async {
    db = AppDatabase.forTesting();
    templateId = await db.createTemplate(
        name: 'قالب اختبار', type: 'a4', templateCategory: 'invoice');
  });
  tearDown(() => db.close());

  /// يقرأ القالبَ المحفوظَ بخطّ الرسم — نفسِ ما يمشيه `printWithTemplate`.
  Future<List<PaintOp>> paintFirstPage() async {
    final data = await db.getTemplateWithData(templateId);
    final document = TemplateRenderPipeline.buildDocument(
      template: data!.template,
      orderedElements:
          TemplatedInvoiceService.orderElementsForPrint(data.elements),
      tableSettings: data.tableSettings,
    );
    final pages = LayoutEngine.paginate(
      document: document,
      rows: TemplateRenderPipeline.buildRows(
        const [
          {'name': 'صنف', 'quantity': 1.0, 'price': 10.0, 'total': 10.0},
        ],
        document.table,
        2,
      ),
      values: {'company_name': 'شركة الاختبار', 'total': '10.00'},
    );
    return pages.isEmpty ? const [] : planPage(pages.first);
  }

  group('ما كُتب يصل الورقةَ', () {
    test('العناصرُ تُكتب بعددها وترتيبها', () async {
      final r = await saveTemplateLayout(db,
          templateId: templateId, document: _doc());

      expect(r.elementCount, 2, reason: 'رأسٌ ومجاميع');
      expect(r.visibleColumnCount, 3, reason: 'الضريبةُ مخفيّة');

      final rows = await db.getTemplateElements(templateId);
      expect(rows, hasLength(2));
      expect(rows.map((e) => e.bandId).toList(), ['header', 'totals']);
      expect(rows.map((e) => e.sortOrder).toList(), [0, 1],
          reason: 'الترتيبُ متسلسلٌ عبر النطاقات بترتيبها الرأسيّ');
    });

    test('والقالبُ يُرفَع إلى نسخة النطاقات', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());
      final t = await db.getTemplateById(templateId);
      expect(t!.layoutVersion, greaterThanOrEqualTo(kBandLayoutVersion));
    });

    test('وعنوانُ العمود المعدَّلُ يبلغ الورقةَ — فحصُ القبول §٢', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc(itemLabel: 'البيان'));

      final ops = await paintFirstPage();
      final headers = ops
          .where((o) => o.kind == PaintKind.tableHeader)
          .map((o) => o.text)
          .toList();

      expect(headers, contains('البيان'),
          reason: 'العنوانُ لم يصل الورقةَ — عادت الحرفيّاتُ في الراسم');
      expect(headers, isNot(contains('الصنف')));
    });

    test('والعمودُ المخفيُّ لا يُرسم ويبقى محفوظاً', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());

      final ops = await paintFirstPage();
      final headers = ops
          .where((o) => o.kind == PaintKind.tableHeader)
          .map((o) => o.text)
          .toList();
      expect(headers, isNot(contains('الضريبة')));

      // ومحفوظٌ: إعادةُ الفتح تجده لتُعاد إتاحتُه.
      final settings = await db.getTableSettings(templateId);
      expect(settings!.columnsJson, contains('"key":"tax"'));
    });

    test('والموضعُ المعدَّلُ يبلغ الورقةَ — فحصُ القبول §٣', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc(totalX: 120));
      final before = (await paintFirstPage())
          .firstWhere((o) => o.band == BandId.totals);

      await saveTemplateLayout(db,
          templateId: templateId, document: _doc(totalX: 100));
      final after = (await paintFirstPage())
          .firstWhere((o) => o.band == BandId.totals);

      // الفرقُ ٢٠مم في إحداثيِّ النطاق، ويظهر مقلوباً في RTL لأنّ `planPage`
      // تقلب من حافّة البداية إلى اليسار — فالقياسُ على الفرق المطلق.
      expect((after.leftMm - before.leftMm).abs(), closeTo(20, 0.01),
          reason: 'تحريكٌ في المحرّر لم يصل الورقة');
    });

    test('والشرطُ المعدَّلُ يُسقط العنصرَ — فحصُ القبول §٤', () async {
      await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(totalCondition: 'discount > 0'));

      final data = await db.getTemplateWithData(templateId);
      final saved = data!.elements.firstWhere((e) => e.content == 'total');
      expect(saved.condition, 'discount > 0',
          reason: 'الشرطُ لم يُكتب — فالعنصرُ يظهر دائماً');
    });

    test('وشرطٌ فارغٌ يُخزَّن `null` لا نصّاً فارغاً', () async {
      // نصٌّ فارغٌ في العمود يجعل المُقيِّمَ يفحص شرطاً لا معنى له.
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc(totalCondition: '   '));
      final data = await db.getTemplateWithData(templateId);
      expect(data!.elements.firstWhere((e) => e.content == 'total').condition,
          isNull);
    });
  });

  group('الحفظُ يستبدل ولا يراكم', () {
    test('حفظان متتاليان يتركان عناصرَ حفظٍ واحد', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());

      expect(await db.getTemplateElements(templateId), hasLength(2),
          reason: 'الحذفُ قبل الكتابة داخلَ المعاملة — وإلّا تضاعفت العناصر');
    });

    test('وحفظٌ بعناصرَ أقلَّ يحذف الزائدَ فعلاً', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());

      const lean = TemplateDocument(
        paper: PaperSpec(widthMm: 210, heightMm: 297, margins: _margins),
        bands: [
          TemplateBand(id: BandId.header, heightMm: 30, elements: [
            TemplateElement(
                id: 'h1', contentKey: 'company_name',
                xMm: 0, yMm: 2, wMm: 90, hMm: 8),
          ]),
        ],
        table: null,
      );
      await saveTemplateLayout(db,
          templateId: templateId, document: lean);

      expect(await db.getTemplateElements(templateId), hasLength(1));
    });
  });

  group('التفعيلُ داخلَ نفس المعاملة — فحصُ القبول §٥', () {
    test('«حفظ» وحدَه لا يلمس الرابطات', () async {
      final r = await saveTemplateLayout(db,
          templateId: templateId, document: _doc());
      expect(r.activated, isFalse);
      expect(await db.getAllBindings(), isEmpty);
    });

    test('و«حفظ وتفعيل» يكتب رابطةً واحدة', () async {
      final r = await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');

      expect(r.activated, isTrue);
      final bindings = await db.getAllBindings();
      expect(bindings, hasLength(1));
      expect(bindings.single.documentType, 'sales_invoice');
      expect(bindings.single.templateId, templateId);
      expect(bindings.single.locale, 'ar');
      expect(bindings.single.branchId, isNull,
          reason: '`null` تعني «أيُّ فرع» — لا صفراً');
    });

    test('وتفعيلُ قالبٍ ثانٍ يُلغي الأوّلَ **ويقوله**', () async {
      final other = await db.createTemplate(
          name: 'قالبٌ آخر', type: 'a4', templateCategory: 'invoice');

      await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');

      final r = await saveTemplateLayout(db,
          templateId: other,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');

      expect(r.cancelledDocumentTypes, ['sales_invoice'],
          reason: 'الإلغاءُ الصامتُ يجعل المستخدمَ يظنّ قالبين مفعّلَين');

      final bindings = await db.getAllBindings();
      expect(bindings, hasLength(1), reason: 'لا تتعايش رابطتان بنفس المفتاح');
      expect(bindings.single.templateId, other);
    });

    test('وإعادةُ تفعيل نفسِ القالب لا تُبلِغ عن إلغاء', () async {
      await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');
      final r = await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');

      expect(r.cancelledDocumentTypes, isEmpty,
          reason: 'إبلاغٌ عن إلغاءٍ لم يقع يُفزع المستخدمَ بلا سبب');
      expect(await db.getAllBindings(), hasLength(1));
    });

    test('والرابطةُ تصل مسارَ الطباعة فوراً — فحصُ القبول §٦', () async {
      await saveTemplateLayout(db,
          templateId: templateId,
          document: _doc(),
          activateForDocumentType: 'sales_invoice',
          activateLocale: 'ar');

      final resolution = await db.resolveTemplateFor(
        documentType: 'sales_invoice',
        category: 'invoice',
        locale: 'ar',
        paperType: 'a4',
      );
      expect(resolution.templateId, templateId);
      expect(resolution.level, lessThanOrEqualTo(4),
          reason: 'حُسم برابطةٍ لا بافتراضيِّ الفئة');
    });
  });

  group('ضابط: القياسُ يمرّ بالورقة فعلاً', () {
    test('الرسمُ يُنتج عمليّاتٍ — لا قائمةً فارغةً تُبارك كلَّ شيء', () async {
      await saveTemplateLayout(db,
          templateId: templateId, document: _doc());
      final ops = await paintFirstPage();

      expect(ops, isNotEmpty);
      expect(ops.where((o) => o.kind == PaintKind.tableHeader), isNotEmpty,
          reason: 'بلا رؤوسٍ يمرّ فحصُ العنوان على مجموعةٍ فارغة');
      expect(ops.where((o) => o.band == BandId.totals), isNotEmpty);
    });
  });
}
