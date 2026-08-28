/// راسمُ الـPDF — يستهلك [PaintOp] ولا يحسب موضعاً.
///
/// ── حدُّ المسؤوليّة ──────────────────────────────────────────────────────
/// هذا الملفُّ **لا منطقَ تخطيطٍ فيه**. لا ترقيمَ صفحاتٍ ولا قياسَ ارتفاعٍ ولا
/// توزيعَ أعمدة — كلُّ ذلك حُسب في `layout_engine` ثمّ `paint_plan`، ووصل هنا
/// بإحداثيّاتٍ نهائيّةٍ بالمليمتر من حافّة اليسار.
///
/// والسببُ أنّ راسمَ المعاينة يستهلك **نفسَ** [PaintOp]. أيُّ حسابٍ يُكتب هنا
/// يجب أن يُكرَّر هناك، وأوّلُ اختلافٍ بينهما يعيد عطبَ «المعاينة ≠ الورق» —
/// وهو ما بُنيت هذه السلسلةُ كلُّها لمنعه.
///
/// وحارسٌ بنيويٌّ يمنع تسلّلَ الحساب:
/// `test/structural/painters_do_no_layout_test.dart`.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/printing/template_document.dart';
import '../generators/base_generator.dart';
import 'layout_engine.dart';
import 'paint_plan.dart';

/// المليمترُ الواحدُ بالنقاط — ٧٢ نقطةً في البوصة، والبوصةُ ٢٥.٤مم.
const double _mmToPt = 72.0 / 25.4;

class PdfPainter {
  const PdfPainter._();

  /// عددُ الصفحات في آخر مستندٍ رُسم — مِقبضُ قياسٍ للاختبار.
  ///
  /// يُعلَن ولا يُخفى: `pw.Document` لا يكشف عددَ صفحاته بعد الحفظ، وفتحُ
  /// الـPDF وتحليلُه في اختبارٍ أثقلُ من الفائدة.
  static int lastPageCount = 0;

  /// يرسم الصفحاتِ المخطَّطةَ ويُرجع بايتاتِ الـPDF.
  /// يرسم الصفحاتِ المخطَّطةَ ويُرجع بايتاتِ الـPDF.
  ///
  /// [logoBytes] بكسلُ الشعار. **لا تمرّ بالخطّة**: الخطّةُ حسابٌ خالصٌ لا
  /// يلمس ملفّاً، فتقول «صورةٌ هنا» ويأتي الراسمُ بالبكسل. وغيابُها ليس
  /// خطأً — يُرسم إطارُ الشعار كما يفعل المسارُ القديمُ بالضبط، فيرى المصمّمُ
  /// مكانَه على الورق قبل أن يرفع صورته.
  static Future<Uint8List> paint({
    required List<PositionedPage> pages,
    PaintDirection direction = PaintDirection.rtl,
    Uint8List? logoBytes,
  }) async {
    // المستندُ من المصنع لا عارياً — العاري بلا ثيمٍ يعني خطاً واحداً لكلِّ
    // النصّ، وأيُّ رسمٍ ينقصه ذلك الخطُّ يُحذف بلا أثر.
    final doc = await BaseGenerator.newDocument();

    for (final page in pages) {
      final ops = planPage(page, direction: direction);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            page.widthMm * _mmToPt,
            page.heightMm * _mmToPt,
          ),
          // صفحةٌ بلا اتّجاهٍ صريحٍ تُرسم LTR، فلا تُشكَّل العربيةُ ولا يُعاد
          // ترتيبُها: «صبري» ⇒ «يربص».
          //
          // والمواضعُ لا تنقلب بهذا: `pw.Positioned` تأخذ `left` مطلقاً من
          // حافّة اليسار، فلا ازدواجَ مع القلب الذي وقع في `planPage`.
          textDirection: direction == PaintDirection.rtl
              ? pw.TextDirection.rtl
              : pw.TextDirection.ltr,
          build: (_) => pw.Stack(
            children: [
              for (final op in ops) _positioned(op, direction, logoBytes),
            ],
          ),
        ),
      );
    }

    lastPageCount = pages.length;
    return doc.save();
  }

  static pw.Widget _positioned(
    PaintOp op,
    PaintDirection dir,
    Uint8List? logoBytes,
  ) =>
      pw.Positioned(
        left: op.leftMm * _mmToPt,
        top: op.topMm * _mmToPt,
        child: pw.SizedBox(
          width: op.widthMm * _mmToPt,
          height: op.heightMm * _mmToPt,
          child: _content(op, dir, logoBytes),
        ),
      );

  static pw.Widget _content(
    PaintOp op,
    PaintDirection dir,
    Uint8List? logoBytes,
  ) {
    // ── الأشكالُ قبل النصّ ────────────────────────────────────────────
    //
    // وهي تُرسم **كما يرسمها المسارُ القديم** لا كما نراه أجمل: الفاصلُ
    // بنصف نقطة، ومربّعُ QR من رقم الفاتورة، وإطارُ الشعار حين لا صورة.
    // فقاعدةُ الهجرة أن يخرج الورقُ كما كان، والاختلافُ التجميليُّ هنا
    // اختلافٌ في الورق.
    switch (op.kind) {
      case PaintKind.image:
        return _image(op, logoBytes);
      case PaintKind.qrCode:
        return _barcode(op, pw.Barcode.qrCode());
      case PaintKind.barcode:
        return _barcode(op, pw.Barcode.code128());
      case PaintKind.line:
        return pw.Center(
          child: pw.Container(
            height: 0.5,
            color: _color(op.colorHex) ?? PdfColors.black,
          ),
        );
      case PaintKind.rect:
        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              width: 0.5,
              color: _color(op.colorHex) ?? PdfColors.black,
            ),
          ),
        );
      case PaintKind.text:
      case PaintKind.tableHeader:
      case PaintKind.tableCell:
        break;
    }

    final style = pw.TextStyle(
      fontSize: op.fontSize,
      fontWeight: op.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: _color(op.colorHex),
    );

    // الرأسُ الثنائيُّ سطران — العربيُّ فوق والإنجليزيُّ تحته أصغر.
    if (op.subText.isNotEmpty) {
      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: _crossAlign(op.align, dir),
        children: [
          pw.Text(op.text, style: style, textAlign: _textAlign(op.align, dir)),
          pw.Text(
            op.subText,
            style: style.copyWith(fontSize: op.fontSize * 0.8),
            textAlign: _textAlign(op.align, dir),
          ),
        ],
      );
    }

    return pw.Align(
      alignment: _alignment(op.align, dir),
      child:
          pw.Text(op.text, style: style, textAlign: _textAlign(op.align, dir)),
    );
  }

  /// الشعارُ — صورةً إن وُجدت، وإطاراً باسمه إن لم توجد.
  ///
  /// والإطارُ ليس حشواً: المسارُ القديمُ يرسمه، فحذفُه يعني أنّ كلَّ قالبٍ
  /// بلا شعارٍ مرفوعٍ يفقد كتلةً كانت على ورقه. ومقيسٌ أنّ `LOGO` كان آخرَ
  /// ما يضيع في قياس الهجرة.
  static pw.Widget _image(PaintOp op, Uint8List? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    }
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Center(
        child: pw.Text('LOGO', style: pw.TextStyle(fontSize: op.fontSize)),
      ),
    );
  }

  /// رمزٌ من حمولته النصّيّة. وبلا حمولةٍ لا يُرسم شيءٌ: رمزٌ فارغٌ يُطبع
  /// مربّعاً أسودَ لا يقرؤه ماسحٌ، وهو أسوأُ من فراغ.
  static pw.Widget _barcode(PaintOp op, pw.Barcode barcode) {
    if (op.text.trim().isEmpty) return pw.SizedBox();
    return pw.Center(
      child: pw.BarcodeWidget(barcode: barcode, data: op.text),
    );
  }

  static PdfColor? _color(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : PdfColor.fromInt(0xFF000000 | v);
  }

  // ── «البداية» و«النهاية» تُحسمان بالاتّجاه لا بافتراضٍ مكتوب ─────────────
  // تثبيتُهما على RTL يجعل قالباً إنجليزيّاً يحاذي من الجهة الخطأ بلا شكوى —
  // والراسمُ يستقبل الاتّجاهَ أصلاً، فتثبيتُه إهدارٌ لمعلومةٍ في اليد.
  static bool _startIsRight(PaintDirection d) => d == PaintDirection.rtl;

  static pw.Alignment _alignment(TextAlignSpec a, PaintDirection d) {
    switch (a) {
      case TextAlignSpec.start:
        return _startIsRight(d)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft;
      case TextAlignSpec.center:
        return pw.Alignment.center;
      case TextAlignSpec.end:
        return _startIsRight(d)
            ? pw.Alignment.centerLeft
            : pw.Alignment.centerRight;
    }
  }

  static pw.CrossAxisAlignment _crossAlign(TextAlignSpec a, PaintDirection d) {
    switch (a) {
      case TextAlignSpec.start:
        return _startIsRight(d)
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start;
      case TextAlignSpec.center:
        return pw.CrossAxisAlignment.center;
      case TextAlignSpec.end:
        return _startIsRight(d)
            ? pw.CrossAxisAlignment.start
            : pw.CrossAxisAlignment.end;
    }
  }

  static pw.TextAlign _textAlign(TextAlignSpec a, PaintDirection d) {
    switch (a) {
      case TextAlignSpec.start:
        return _startIsRight(d) ? pw.TextAlign.right : pw.TextAlign.left;
      case TextAlignSpec.center:
        return pw.TextAlign.center;
      case TextAlignSpec.end:
        return _startIsRight(d) ? pw.TextAlign.left : pw.TextAlign.right;
    }
  }
}
