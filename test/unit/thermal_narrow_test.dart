// ٥٨مم بثلاثة أعمدةٍ — بلا قصٍّ للإجمالي وبلا سطرٍ إنجليزيٍّ لا يسعه الورق.
//
// ── العطبان اللذان يمنعهما ────────────────────────────────────────────────
// ١ · **القصّ الصامت.** عمودُ الإجمالي هو آخرُ الأعمدة، فأيُّ خطأِ توزيعٍ
//     يتراكم عليه وحدَه: الرقمُ يُقصّ عند حافّة الورق ولا يشكو أحد. والمقيسُ
//     هنا حافّةُ العمود الأخير لا مجرَّدُ «الأعمدةُ موجودة».
//
// ٢ · **العناوينُ الثنائيّةُ على الحراريّ.** ٥٢مم لا تسع سطرين لكلِّ عمود،
//     فالثنائيّةُ تُطفأ تلقائيّاً. وهذا سلوكٌ لا زينة: تركُها يدهس الصفَّ
//     الأوّل من البيانات.
//
// والورقُ المتّصلُ بلا ارتفاعٍ لا يُقسَّم مهما طال — مئةُ صنفٍ ورقةٌ واحدة.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';

const _thermal58 = PaperSpec.continuous(
  widthMm: 58,
  margins: MarginsMm.all(3),
);

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

const _columns = [
  TableColumn(key: 'name', labelAr: 'الصنف', labelEn: 'Item', flex: 3),
  TableColumn(key: 'qty', labelAr: 'العدد', labelEn: 'Qty'),
  TableColumn(key: 'total', labelAr: 'الإجمالي', labelEn: 'Total', flex: 2),
];

TemplateDocument _doc(PaperSpec paper, {bool bilingual = true}) =>
    TemplateDocument(
      paper: paper,
      table: TableSpec(
        columns: _columns,
        rowHeightMm: 5,
        bilingualHeaders: bilingual,
      ),
      bands: const [
        TemplateBand(id: BandId.details, heightMm: 10, growsWithData: true),
        TemplateBand(id: BandId.footer, heightMm: 8, repeatEachPage: true),
      ],
    );

List<List<String>> _rows(int n) =>
    List.generate(n, (i) => ['صنف ${i + 1}', '2', '150.00']);

void main() {
  test('الورقُ المتّصلُ لا يُقسَّم — مئةُ صنفٍ ورقةٌ واحدة', () {
    final pages =
        LayoutEngine.paginate(document: _doc(_thermal58), rows: _rows(100));
    expect(pages, hasLength(1));
    expect(pages.single.tables.expand((t) => t.rows), hasLength(100));
  });

  test('عمودُ الإجمالي ينتهي عند حافّة المحتوى بالضبط — لا قصَّ ولا فائض', () {
    final pages =
        LayoutEngine.paginate(document: _doc(_thermal58), rows: _rows(3));
    final table = pages.single.tables.single;

    // ٥٨ − (٣ + ٣) = ٥٢مم متاحة، تبدأ عند ٣.
    expect(table.wMm, 52.0);

    final lastCell = table.rows.first.cells.last;
    expect(lastCell.columnKey, 'total');
    expect(
      lastCell.xMm + lastCell.wMm,
      closeTo(3.0 + 52.0, 0.0001),
      reason: 'حافّةُ الإجمالي تجاوزت المحتوى أو قصُرت عنه — وهذا هو القصُّ '
          'الصامتُ الذي يأكل آخرَ رقمٍ في الإيصال',
    );
  });

  test('لا عمودَ بعرضٍ صفريٍّ أو سالب', () {
    final pages =
        LayoutEngine.paginate(document: _doc(_thermal58), rows: _rows(3));
    for (final c in pages.single.tables.single.rows.first.cells) {
      expect(c.wMm, greaterThan(0), reason: 'العمود ${c.columnKey} انطوى');
    }
  });

  test('العناوينُ الثنائيّةُ تُطفأ تلقائيّاً على الورق الضيّق', () {
    final table = LayoutEngine.paginate(
      document: _doc(_thermal58, bilingual: true),
      rows: _rows(3),
    ).single.tables.single;

    expect(table.bilingualHeaders, isFalse,
        reason: '٥٢مم لا تسع سطرين لكلِّ عمود — والسطرُ الثاني يدهس البيانات');
    expect(table.headerCells.first.subText, isEmpty);
  });

  test('وتبقى مشتعلةً على A4 حين تُطلَب', () {
    // الضابط: لولاه لمرّ الاختبارُ السابقُ على ثنائيّةٍ معطَّلةٍ دائماً.
    final table = LayoutEngine.paginate(
      document: _doc(_a4, bilingual: true),
      rows: _rows(3),
    ).single.tables.single;

    expect(table.bilingualHeaders, isTrue);
    expect(table.headerCells.first.subText, 'Item');
  });
}
