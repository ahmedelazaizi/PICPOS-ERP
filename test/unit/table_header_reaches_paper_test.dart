// رأسُ الجدول يصل الورقةَ — بسطرَيه وبمقاسِ خطّه.
//
// ── عطبان توأمان لم يصل أثرُهما ورقةً قطّ ─────────────────────────────────
//
// ١ · **السطرُ الإنجليزيُّ يُسقَط صامتاً.** `LayoutEngine` كان يحجز للرأس
//     الثنائيِّ `rowHeightMm * 1.6` — ‏٩٫٦مم عند الافتراض ٦. وذلك أقصرُ من
//     سطرين، وحزمةُ `pdf` **تُسقط الطفلَ الفائض بلا رسالةٍ ولا استثناء**.
//     فلم تحمل أيُّ بصمةٍ ذهبيّةٍ من السبعٍ وعشرين عنواناً إنجليزيّاً قطُّ.
//
// ٢ · **مقاسُ خطِّ الجدول لا يصل الورقة.** `paint_plan` لم تكن تمرّر
//     `fontSize` لعمليّات الرأس والخلايا، فتأخذ افتراضَ `PaintOp` وهو ١٠
//     أيّاً كان المخزَّنُ في `invoice_table_settings`.
//
// وكانا متلازمين: إصلاحُ الارتفاع وحدَه يحجز لخطٍّ ويُرسم بغيره.
//
// ⚠️ **والقياسُ على الراسم نفسِه** لا على حسابٍ بجانبه: العتبةُ معايَرةٌ
// تجريبيّاً (‏١٠٫٥مم تُسقط · ١١٫٠مم تُظهر عند خطّ ١٠)، فالثابتُ في
// `_bilingualHeaderHeightMm` ليس تقديراً.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/pdf_painter.dart';

import '../helpers/pdf_probe.dart';

PositionedPage _page({
  required double headerFontSize,
  required double headerHeightMm,
  double cellFontSize = 9,
}) =>
    PositionedPage(
      pageNumber: 1,
      pageCount: 1,
      widthMm: 210,
      heightMm: 297,
      elements: const [],
      tables: [
        PositionedTable(
          xMm: 10,
          yMm: 20,
          wMm: 190,
          headerCells: const [
            PositionedCell(
              columnKey: 'name',
              xMm: 10,
              wMm: 60,
              text: 'الصنف',
              subText: 'Description',
              align: ColumnAlign.start,
            ),
          ],
          headerHeightMm: headerHeightMm,
          bilingualHeaders: true,
          headerFontSize: headerFontSize,
          cellFontSize: cellFontSize,
          rows: const [],
        ),
      ],
    );

Future<String> _render(PositionedPage page) async =>
    probePdf(await PdfPainter.paint(pages: [page])).fingerprint(header: '#');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('العنوانُ الإنجليزيُّ يصل الورقةَ بالارتفاع المشتَقّ', () async {
    const fs = 10.0;
    final out = await _render(
      _page(
        headerFontSize: fs,
        headerHeightMm: bilingualHeaderHeightMm(fs, 6),
      ),
    );

    expect(out, contains('«Description»'));
    expect(out, contains('«ﺍﻟﺼﻨﻒ»'));
  });

  test('العتبةُ محفوظة — الارتفاعُ القديم كان يُسقطه', () async {
    // ٩٫٦مم = `rowHeightMm * 1.6` القديمة. تثبيتُها **ساقطةً** هو ما يمنع
    // عودةَ الصيغة: لولا هذا التوكيدُ لمرّ أيُّ ارتفاعٍ يبدو معقولاً.
    expect(await _render(_page(headerFontSize: 10, headerHeightMm: 9.6)),
        isNot(contains('«Description»')));
    expect(await _render(_page(headerFontSize: 10, headerHeightMm: 10.5)),
        isNot(contains('«Description»')));
    expect(await _render(_page(headerFontSize: 10, headerHeightMm: 11.0)),
        contains('«Description»'));
  });

  test('المشتَقُّ يتجاوز العتبةَ لكلِّ مقاسِ خطٍّ معقول', () async {
    for (final fs in [8.0, 9.0, 10.0, 12.0, 14.0]) {
      final h = bilingualHeaderHeightMm(fs, 6);
      expect(await _render(_page(headerFontSize: fs, headerHeightMm: h)),
          contains('«Description»'),
          reason: 'خطّ $fs بارتفاع ${h.toStringAsFixed(2)}مم');
    }
  });

  test('ارتفاعُ الصفِّ حدٌّ أدنى — خطٌّ صغيرٌ لا يضيق رأسَه', () {
    // خطُّ ٦ يحتاج ٦٫٦٧مم، وصفٌّ عريضٌ ١٢ يبقى هو الحاكم.
    expect(bilingualHeaderHeightMm(6, 12), 12.0);
    expect(bilingualHeaderHeightMm(14, 6), greaterThan(6.0));
  });

  test('مقاسُ خطِّ الرأس والخليّة يصل الورقةَ — لا افتراضُ ١٠', () async {
    final out = await _render(
      _page(headerFontSize: 14, headerHeightMm: bilingualHeaderHeightMm(14, 6)),
    );

    // البصمةُ تكتب المقاسَ بمنزلتين — فالتوكيدُ على الرقم لا على الوجود.
    expect(out, contains('14.00 «ﺍﻟﺼﻨﻒ»'));
    expect(out, isNot(contains('10.00 «ﺍﻟﺼﻨﻒ»')));
  });
}
