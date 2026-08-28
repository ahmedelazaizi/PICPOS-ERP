/// خطّةُ الرسم — **آخرُ حسابٍ قبل القماش**.
///
/// ── لماذا طبقةٌ ثالثة ────────────────────────────────────────────────────
/// [PositionedPage] يعطي مواضعَ من **حافّة البداية** (اليمينُ في RTL). وقلبُ
/// ذلك إلى إحداثيٍّ من اليسار عمليّةٌ صغيرةٌ — ولو تُركت لكلِّ راسمٍ لقلبها
/// أحدُهما ونسيها الآخر، وهو بالضبط شكلُ العطب الذي بُني هذا كلُّه لمنعه:
/// «المعاينة ≠ الورق».
///
/// فتُقلب هنا مرّةً واحدة، ويأخذ الراسمان [PaintOp] بإحداثيّاتٍ نهائيّةٍ من
/// اليسار ولا يحسبان شيئاً.
///
/// نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

import '../../domain/printing/template_document.dart';
import 'layout_engine.dart';

/// اتّجاهُ النصّ — يقرّر أيَّ حافّةٍ هي «البداية».
enum PaintDirection { rtl, ltr }

/// نوعُ العمليّة — يقرّر الأسلوبَ لا الموضع.
enum PaintKind {
  /// نصُّ عنصرٍ عاديّ.
  text,

  /// خليّةُ رأسِ جدول — تُرسم بأسلوبٍ مختلف (عريضٌ وخلفيّة).
  tableHeader,

  /// خليّةُ بياناتٍ في الجدول.
  tableCell,
}

/// عمليّةُ رسمٍ واحدة — بإحداثيٍّ **نهائيٍّ من حافّة اليسار** بالمليمتر.
class PaintOp {
  final String id;
  final PaintKind kind;

  final double leftMm;
  final double topMm;
  final double widthMm;
  final double heightMm;

  final String text;

  /// السطرُ الثاني في رأسٍ ثنائيِّ اللغة — فارغٌ فيما عداه.
  final String subText;

  final double fontSize;
  final bool bold;
  final TextAlignSpec align;
  final String? colorHex;

  /// النطاقُ الذي جاء منه — يستعمله المحرّرُ للتحديد، ويتجاهله الورق.
  final BandId? band;

  const PaintOp({
    required this.id,
    required this.kind,
    required this.leftMm,
    required this.topMm,
    required this.widthMm,
    required this.heightMm,
    required this.text,
    this.subText = '',
    this.fontSize = 10,
    this.bold = false,
    this.align = TextAlignSpec.start,
    this.colorHex,
    this.band,
  });
}

/// يحوّل صفحةً مخطَّطةً إلى عمليّاتِ رسمٍ بإحداثيّاتٍ من اليسار.
///
/// هذه الدالّةُ **هي** العقدُ بين المعاينة والورق. أيُّ راسمٍ يحسب موضعاً
/// بنفسه خارجَها يكسر الضمانَ ويعيد عطبَ «المعاينة ≠ الورق».
List<PaintOp> planPage(
  PositionedPage page, {
  PaintDirection direction = PaintDirection.rtl,
}) {
  final ops = <PaintOp>[];

  /// في RTL تُقاس السيناتُ من اليمين، فالإحداثيُّ من اليسار هو ما تبقّى.
  double left(double startMm, double widthMm) =>
      direction == PaintDirection.rtl
          ? page.widthMm - startMm - widthMm
          : startMm;

  for (final el in page.elements) {
    ops.add(
      PaintOp(
        id: el.id,
        kind: PaintKind.text,
        leftMm: left(el.xMm, el.wMm),
        topMm: el.yMm,
        widthMm: el.wMm,
        heightMm: el.hMm,
        text: el.text.isNotEmpty ? el.text : (el.labelAr ?? ''),
        fontSize: el.fontSize,
        bold: el.bold,
        align: el.align,
        colorHex: el.colorHex,
        band: el.band,
      ),
    );
  }

  for (var t = 0; t < page.tables.length; t++) {
    final table = page.tables[t];

    for (var i = 0; i < table.headerCells.length; i++) {
      final c = table.headerCells[i];
      ops.add(
        PaintOp(
          id: 'table${t}_h$i',
          kind: PaintKind.tableHeader,
          leftMm: left(c.xMm, c.wMm),
          topMm: table.yMm,
          widthMm: c.wMm,
          heightMm: table.headerHeightMm,
          text: c.text,
          subText: table.bilingualHeaders ? c.subText : '',
          bold: true,
          align: _align(c.align),
          band: BandId.details,
        ),
      );
    }

    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      for (var i = 0; i < row.cells.length; i++) {
        final c = row.cells[i];
        ops.add(
          PaintOp(
            id: 'table${t}_r${row.sourceIndex}_c$i',
            kind: PaintKind.tableCell,
            leftMm: left(c.xMm, c.wMm),
            topMm: row.yMm,
            widthMm: c.wMm,
            heightMm: row.heightMm,
            text: c.text,
            align: _align(c.align),
            band: BandId.details,
          ),
        );
      }
    }
  }

  return List.unmodifiable(ops);
}

TextAlignSpec _align(ColumnAlign a) {
  switch (a) {
    case ColumnAlign.start:
      return TextAlignSpec.start;
    case ColumnAlign.center:
      return TextAlignSpec.center;
    case ColumnAlign.end:
      return TextAlignSpec.end;
  }
}
