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

  /// صورةٌ — الشعارُ اليوم. بايتاتُها لا تمرّ بالخطّة: الخطّةُ **حسابٌ
  /// خالصٌ** لا يلمس ملفّاً، فتقول «صورةٌ هنا» ويأتي الراسمُ بالبكسل.
  image,

  /// مربّعُ QR — حمولتُه في [PaintOp.text].
  qrCode,

  /// شفرةٌ خطّيّة — حمولتُها في [PaintOp.text].
  barcode,

  /// خطٌّ فاصلٌ أفقيّ.
  line,

  /// مستطيلٌ محدَّد.
  rect,
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

/// نوعُ العنصر ⇒ نوعُ عمليّة الرسم.
PaintKind _kindOf(ElementKind k) {
  switch (k) {
    case ElementKind.image:
      return PaintKind.image;
    case ElementKind.qrCode:
      return PaintKind.qrCode;
    case ElementKind.barcode:
      return PaintKind.barcode;
    case ElementKind.line:
      return PaintKind.line;
    case ElementKind.rect:
      return PaintKind.rect;
    case ElementKind.text:
    case ElementKind.spacer:
      return PaintKind.text;
  }
}

/// يحوّل صفحةً مخطَّطةً إلى عمليّاتِ رسمٍ بإحداثيّاتٍ من اليسار.
///
/// هذه الدالّةُ **هي** العقدُ بين المعاينة والورق. أيُّ راسمٍ يحسب موضعاً
/// بنفسه خارجَها يكسر الضمانَ ويعيد عطبَ «المعاينة ≠ الورق».
/// نصُّ العنصر كما يصل الورقةَ — تسميةً وقيمةً معاً.
///
/// ── لماذا تُركَّب هنا ────────────────────────────────────────────────────
/// عقدُ المحرّر يقول: «حقلُ التسمية عربي — يُكتب مباشرةً **ويظهر على
/// الورقة**». وكان هذا الموضعُ يأخذ القيمةَ ويُهمل التسميةَ إلّا حين تكون
/// القيمةُ فارغة، فيخرج «0100 123 4567» بلا «هاتف:» و«310-…» بلا «السجل
/// الضريبي:».
///
/// ومقيسٌ أثرُه: هجرةُ القوالب التسعةَ عشرَ كانت تُسقط اثنين وثلاثين مقطعاً
/// من ورقة الفاتورة الضريبيّة وحدَها، جُلُّها تسمياتٌ — أي أن القاعدةَ
/// الحاكمةَ للهجرة («يطبع بعدها نفسَ ما كان يطبعه») كانت مكسورةً بهذا
/// السطر.
///
/// والنصُّ الثابتُ يبقى كما هو: قيمتُه فارغةٌ فتُطبع تسميتُه وحدَها، وهي
/// نفسُه.
String elementText(String value, String? label) {
  final l = label?.trim() ?? '';
  if (value.isEmpty) return l;
  if (l.isEmpty) return value;
  return '$l: $value';
}

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
    // الفراغُ لا يُرسم ولا يُنشئ عمليّة — يحجز مكانَه في التخطيط وكفى.
    if (el.kind == ElementKind.spacer) continue;
    ops.add(
      PaintOp(
        id: el.id,
        kind: _kindOf(el.kind),
        leftMm: left(el.xMm, el.wMm),
        topMm: el.yMm,
        widthMm: el.wMm,
        heightMm: el.hMm,
        text: elementText(el.text, el.labelAr),
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
