// الرأسُ والتذييلُ على كلِّ صفحة، ورؤوسُ الأعمدة تُعاد.
//
// ── العطبُ الذي يمنعه ──────────────────────────────────────────────────────
// فاتورةٌ من صفحتين صفحتُها الثانيةُ بلا ترويسةِ شركةٍ ولا رقمِ ضريبةٍ ولا
// أسماءِ أعمدةٍ هي ورقةٌ لا يُعرف صاحبُها ولا معنى أرقامها. والتكرارُ ليس
// زينةً: التذييلُ يحمل «صفحة ٢ من ٣»، وبدونه تضيع الورقةُ المنفصلة.
//
// ويُقاس العكسُ أيضاً: `repeatHeader = false` يعني رأسَ جدولٍ **واحداً**
// على الشريحة الأولى — وحارسٌ لا يُختبَر على الحالتين يمرّ على ثابتٍ مكتوب.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

const _columns = [
  TableColumn(key: 'name', labelAr: 'الصنف', labelEn: 'Item', flex: 3),
  TableColumn(key: 'qty', labelAr: 'العدد', labelEn: 'Qty'),
  TableColumn(key: 'total', labelAr: 'الإجمالي', labelEn: 'Total'),
];

TemplateDocument _doc({bool repeatHeader = true}) => TemplateDocument(
      paper: _a4,
      table: TableSpec(
        columns: _columns,
        rowHeightMm: 6,
        repeatHeader: repeatHeader,
      ),
      bands: const [
        TemplateBand(
          id: BandId.header,
          heightMm: 20,
          repeatEachPage: true,
          elements: [
            TemplateElement(
              id: 'company_name',
              contentKey: 'company_name',
              xMm: 0,
              yMm: 4,
              wMm: 80,
              hMm: 6,
            ),
          ],
        ),
        TemplateBand(id: BandId.details, heightMm: 20, growsWithData: true),
        TemplateBand(
          id: BandId.footer,
          heightMm: 15,
          repeatEachPage: true,
          elements: [
            TemplateElement(
              id: 'page_no',
              contentKey: 'page_number',
              xMm: 0,
              yMm: 2,
              wMm: 40,
              hMm: 5,
            ),
          ],
        ),
      ],
    );

List<List<String>> _rows(int n) =>
    List.generate(n, (i) => ['صنف ${i + 1}', '1', '10.00']);

/// قيمُ العناصر — بدونها يسقط العنصرُ بقاعدة «لا تسميةَ معلَّقة».
const _values = {'company_name': 'شركة الاختبار', 'page_number': '1'};

void main() {
  test('الرأسُ والتذييلُ يظهران على كلِّ صفحةٍ من الصفحتين', () {
    final pages = LayoutEngine.paginate(
        document: _doc(), rows: _rows(42), values: _values);
    expect(pages.length, greaterThan(1), reason: 'الضابط: بلا صفحتين لا معنى للتكرار');

    for (final p in pages) {
      expect(
        p.elements.where((e) => e.id == 'company_name'),
        hasLength(1),
        reason: 'صفحة ${p.pageNumber} بلا ترويسةِ شركة',
      );
      expect(
        p.elements.where((e) => e.id == 'page_no'),
        hasLength(1),
        reason: 'صفحة ${p.pageNumber} بلا تذييل',
      );
    }
  });

  test('التذييلُ مثبَّتٌ في قاع الصفحة لا يتدفّق مع المحتوى', () {
    final pages = LayoutEngine.paginate(
        document: _doc(), rows: _rows(42), values: _values);

    // قاعُ الورقة ٢٩٧ − هامشٌ ١٠ − ارتفاعُ النطاق ١٥ = ٢٧٢، والعنصرُ عندها +٢.
    for (final p in pages) {
      final footer = p.elements.firstWhere((e) => e.id == 'page_no');
      expect(footer.yMm, 274.0,
          reason: 'صفحة ${p.pageNumber}: التذييلُ المتدفّقُ يرتفع بقلّة '
              'الصفوف، والمثبَّتُ لا يتحرّك');
    }
  });

  test('الرأسُ مثبَّتٌ في قمّة كلِّ صفحة', () {
    final pages = LayoutEngine.paginate(
        document: _doc(), rows: _rows(42), values: _values);
    for (final p in pages) {
      final h = p.elements.firstWhere((e) => e.id == 'company_name');
      expect(h.yMm, 14.0, reason: 'هامشٌ ١٠ + إزاحةٌ ٤');
    }
  });

  test('رؤوسُ الأعمدة تُعاد على كلِّ شريحةٍ حين repeatHeader', () {
    final pages = LayoutEngine.paginate(
        document: _doc(), rows: _rows(42), values: _values);
    for (final p in pages) {
      for (final t in p.tables) {
        expect(t.headerCells, isNotEmpty,
            reason: 'صفحة ${p.pageNumber}: شريحةٌ بلا رؤوسِ أعمدة');
        expect(t.headerCells.map((c) => c.text).toList(),
            ['الصنف', 'العدد', 'الإجمالي']);
      }
    }
  });

  test('وبإطفاء repeatHeader يظهر الرأسُ على الشريحة الأولى وحدَها', () {
    final pages = LayoutEngine.paginate(
      document: _doc(repeatHeader: false),
      rows: _rows(42),
      values: _values,
    );

    final slices = [for (final p in pages) ...p.tables];
    expect(slices.length, greaterThan(1));
    expect(slices.first.headerCells, isNotEmpty);
    for (final t in slices.skip(1)) {
      expect(t.headerCells, isEmpty);
      expect(t.headerHeightMm, 0);
    }
  });
}
