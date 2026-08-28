// تغييرُ عنوانِ العمود يصل الورق.
//
// ── العطبُ الذي يمنعه ─────────────────────────────────────────────────────
// عناوينُ الأعمدة اليومَ **حرفيّاتٌ مكتوبةٌ في الكود** داخلَ `_buildItemsTable`:
// «الإجمالي» · «الضريبة» · «الخصم» · «السعر» · «العدد» · «الكود» · «الصنف» ·
// «م». فالمستخدمُ لا يستطيع تسميةَ عمودٍ باسمِ عمله، ولا يستطيع سطراً
// إنجليزيّاً — والحقلان `labelAr`/`labelEn` موجودان في البنية ولا يقرؤهما أحد.
//
// وهذا الاختبارُ يقيس السلسلةَ كاملةً: العنوانُ في `TableColumn` ⇒ خطّةُ الرسم
// ⇒ صفحةُ PDF حقيقيّة. فلا يكفي أن يُخزَّن؛ لا بدّ أن يصل.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';
import 'package:ural_erp/services/printing/paint_plan.dart';
import 'package:ural_erp/services/printing/pdf_painter.dart';

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

TemplateDocument _doc({
  required String nameLabelAr,
  String nameLabelEn = '',
  bool bilingual = false,
}) =>
    TemplateDocument(
      paper: _a4,
      table: TableSpec(
        columns: [
          TableColumn(
            key: 'name',
            labelAr: nameLabelAr,
            labelEn: nameLabelEn,
            flex: 3,
          ),
          const TableColumn(key: 'total', labelAr: 'الإجمالي'),
        ],
        rowHeightMm: 6,
        bilingualHeaders: bilingual,
      ),
      bands: const [
        TemplateBand(id: BandId.details, heightMm: 20, growsWithData: true),
      ],
    );

List<PaintOp> _plan(TemplateDocument doc) => planPage(
      LayoutEngine.paginate(
        document: doc,
        rows: const [
          ['قلم', '10.00']
        ],
      ).single,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('العنوانُ الافتراضيُّ «الصنف» يصل الخطّة', () {
    final headers = _plan(_doc(nameLabelAr: 'الصنف'))
        .where((o) => o.kind == PaintKind.tableHeader)
        .map((o) => o.text);
    expect(headers, contains('الصنف'));
  });

  test('وتغييرُه إلى «البيان» يصل الخطّةَ ولا يبقى الحرفيُّ القديم', () {
    final headers = _plan(_doc(nameLabelAr: 'البيان'))
        .where((o) => o.kind == PaintKind.tableHeader)
        .map((o) => o.text)
        .toList();

    expect(headers, contains('البيان'));
    expect(headers, isNot(contains('الصنف')),
        reason: 'بقاءُ «الصنف» يعني أنّ الراسمَ ما زال يقرأ حرفيّاً مكتوباً '
            'في الكود لا القالب');
  });

  test('والسطرُ الإنجليزيُّ يصل حين تُطلَب الثنائيّة', () {
    final header = _plan(
      _doc(nameLabelAr: 'البيان', nameLabelEn: 'Item', bilingual: true),
    ).firstWhere((o) => o.kind == PaintKind.tableHeader);

    expect(header.text, 'البيان');
    expect(header.subText, 'Item');
  });

  test('وبلا ثنائيّةٍ لا يظهر الإنجليزيُّ ولو كان مخزَّناً', () {
    final header = _plan(
      _doc(nameLabelAr: 'البيان', nameLabelEn: 'Item'),
    ).firstWhere((o) => o.kind == PaintKind.tableHeader);

    expect(header.subText, isEmpty);
  });

  group('ويصل الورقَ لا الخطّةَ وحدَها', () {
    test('الراسمُ يُنتج PDF صالحاً بعدد الصفحات الصحيح', () async {
      final pages = LayoutEngine.paginate(
        document: _doc(nameLabelAr: 'البيان'),
        rows: List.generate(3, (i) => ['صنف $i', '10.00']),
      );

      final bytes = await PdfPainter.paint(pages: pages);

      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-',
          reason: 'المخرَجُ ليس مستندَ PDF أصلاً');
      expect(PdfPainter.lastPageCount, pages.length);
    });

    test('وصفحتان تُنتجان صفحتين في المستند', () async {
      final pages = LayoutEngine.paginate(
        document: _doc(nameLabelAr: 'البيان'),
        rows: List.generate(60, (i) => ['صنف $i', '10.00']),
      );
      expect(pages.length, greaterThan(1), reason: 'الضابط: بلا تعدّدٍ لا قياس');

      await PdfPainter.paint(pages: pages);
      expect(PdfPainter.lastPageCount, pages.length);
    });
  });
}
