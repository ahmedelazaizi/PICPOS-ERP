// ٤٢ صنفاً ⇒ صفحتان، والمجاميعُ **بعدَ** آخر صفٍّ لا فوقَه.
//
// ── العطبُ الذي يمنعه ──────────────────────────────────────────────────────
// هذا هو السببُ المعلَن لاختيار «النطاقات» بدل الإحداثيّات المطلقة على
// الورقة كلِّها: جدولٌ بثلاثين صنفاً بدل خمسةٍ **يدهس المجاميع** لأنّ موضعَ
// المجاميع كان ثابتاً على الورقة. النطاقُ يتمدّد فيدفع ما بعده.
//
// والاختبارُ يقيس الرقمَ لا الحالة: «المجاميعُ تحرّكت» يمرّ على مقدارٍ خاطئ،
// فالمقيسُ هنا أنّ قمّةَ نطاق المجاميع **لا تقلّ** عن قاع آخر صفّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';

/// A4 بهوامشَ ١٠مم: صندوقُ المحتوى من ١٠ إلى ٢٨٧.
const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

const _table = TableSpec(
  columns: [
    TableColumn(key: 'name', labelAr: 'الصنف', flex: 3),
    TableColumn(key: 'qty', labelAr: 'العدد'),
    TableColumn(key: 'total', labelAr: 'الإجمالي'),
  ],
  rowHeightMm: 6,
  headerFontSize: 9,
  repeatHeader: true,
);

TemplateDocument _doc() => const TemplateDocument(
      paper: _a4,
      table: _table,
      bands: [
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
        TemplateBand(id: BandId.info, heightMm: 15),
        TemplateBand(id: BandId.party, heightMm: 10),
        TemplateBand(id: BandId.details, heightMm: 20, growsWithData: true),
        TemplateBand(
          id: BandId.totals,
          heightMm: 20,
          elements: [
            TemplateElement(
              id: 'grand_total',
              contentKey: 'total_amount',
              xMm: 0,
              yMm: 0,
              wMm: 60,
              hMm: 6,
            ),
          ],
        ),
        TemplateBand(id: BandId.footer, heightMm: 15, repeatEachPage: true),
      ],
    );

List<List<String>> _rows(int n) => List.generate(
      n,
      (i) => ['صنف ${i + 1}', '1', '10.00'],
    );

void main() {
  test('٤٢ صنفاً تنقسم على صفحتين', () {
    final pages = LayoutEngine.paginate(document: _doc(), rows: _rows(42));
    expect(pages, hasLength(2));
    expect(pages.first.pageCount, 2, reason: 'كلُّ صفحةٍ تعرف العدَّ الكلّيّ');
    expect(pages.last.pageNumber, 2);
  });

  test('كلُّ صفٍّ يظهر مرّةً واحدةً وبترتيبه الأصليّ', () {
    final pages = LayoutEngine.paginate(document: _doc(), rows: _rows(42));

    final indices = <int>[
      for (final p in pages)
        for (final t in p.tables)
          for (final r in t.rows) r.sourceIndex,
    ];

    expect(indices, List.generate(42, (i) => i),
        reason: 'لا صفَّ مكرَّرٌ ولا ساقطٌ ولا مُعادُ الترقيم في الصفحة الثانية');
  });

  test('المجاميعُ تقع بعدَ قاع آخر صفٍّ لا فوقَه', () {
    final pages = LayoutEngine.paginate(document: _doc(), rows: _rows(42));
    final last = pages.last;

    final lastRow = last.tables.expand((t) => t.rows).last;
    final rowBottom = lastRow.yMm + lastRow.heightMm;

    final totals =
        last.elements.firstWhere((e) => e.band == BandId.totals);

    expect(
      totals.yMm,
      greaterThanOrEqualTo(rowBottom),
      reason: 'قمّةُ المجاميع (${totals.yMm}) دهست آخرَ صفٍّ ينتهي عند '
          '$rowBottom — وهذا عينُ العطب الذي جاء نموذجُ النطاقات ليمنعه',
    );
  });

  test('خمسةُ أصنافٍ تبقى في صفحةٍ واحدةٍ والمجاميعُ ترتفع معها', () {
    // الضابط: لو كان موضعُ المجاميع ثابتاً لما تحرّك بتغيّر عدد الصفوف.
    final few = LayoutEngine.paginate(document: _doc(), rows: _rows(5));
    final many = LayoutEngine.paginate(document: _doc(), rows: _rows(20));

    expect(few, hasLength(1));

    double totalsY(List<PositionedPage> p) =>
        p.last.elements.firstWhere((e) => e.band == BandId.totals).yMm;

    expect(
      totalsY(many) - totalsY(few),
      15 * 6.0,
      reason: 'خمسةَ عشرَ صفّاً إضافيّاً بارتفاع ٦مم تدفع المجاميعَ ٩٠مم '
          'بالضبط — لا «تحرّكت» فقط',
    );
  });
}
