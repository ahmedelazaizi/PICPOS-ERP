// النطاقاتُ تتراصّ رأسيّاً، والعنصرُ داخلَها بإحداثيٍّ نسبيٍّ يصير مطلقاً.
//
// ── العطبُ الذي يمنعه ──────────────────────────────────────────────────────
// النظامُ اليومَ فيه نموذجا تخطيطٍ متناقضان: الكانفاسُ يحفظ
// `xPosition`/`yPosition` والراسمُ يبني تدفّقاً من `sortOrder` ويتجاهلهما.
// فالمستخدمُ يضبط موضعاً ويطبع فيجده في مكانٍ آخر.
//
// هذا الاختبارُ يثبّت العقدَ الجديد: موضعُ العنصر داخلَ نطاقِه **يُحترَم**،
// وموضعُه النهائيُّ على الورقة = هامشُ الورق + مقدّماتُ النطاقات + إزاحتُه.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';

TemplateElement _el(String id, {required double yMm, double xMm = 0}) =>
    TemplateElement(
      id: id,
      contentKey: id,
      xMm: xMm,
      yMm: yMm,
      wMm: 40,
      hMm: 6,
    );

void main() {
  test('العنصرُ يرث هامشَ الورق ومقدّماتِ النطاقات في موضعه النهائيّ', () {
    const paper = PaperSpec(
      widthMm: 210,
      heightMm: 297,
      margins: MarginsMm.all(10),
    );

    final doc = TemplateDocument(
      paper: paper,
      bands: [
        TemplateBand(
          id: BandId.header,
          heightMm: 20,
          elements: [_el('company_name', yMm: 5)],
        ),
        TemplateBand(
          id: BandId.info,
          heightMm: 15,
          elements: [_el('invoice_number', yMm: 2)],
        ),
      ],
    );

    final pages = LayoutEngine.paginate(document: doc, rows: const []);

    expect(pages, hasLength(1), reason: 'نطاقان صغيران على ورقة A4 = صفحةٌ واحدة');

    final byId = {for (final e in pages.single.elements) e.id: e};

    // الهامشُ العلويُّ ١٠ + إزاحةُ العنصر ٥ داخلَ نطاقٍ يبدأ عند الصفر.
    expect(byId['company_name']!.yMm, 15.0);

    // الهامشُ ١٠ + ارتفاعُ الرأس ٢٠ + إزاحةُ العنصر ٢.
    expect(byId['invoice_number']!.yMm, 32.0);
  });
}
