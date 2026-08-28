// ورقةُ المعاينة — **حروفاً هذه المرّة، لا كتلاً**.
//
// ── الفرقُ عن مصغَّرة المكتبة ─────────────────────────────────────────────
// [TemplateThumbnailView] ترسم كتلاً عن قصد: النصُّ عند ستّةِ بكسلاتٍ غيرُ
// مقروءٍ أصلاً، ورسمُه يكلّف ولا يفيد. أمّا هنا فالغرضُ أن يُقرأ المطبوعُ
// قبل أن يخرج — «هل صار عنوانُ العمود ‹البيان›؟» سؤالٌ لا تجيبه كتلةٌ رماديّة.
//
// ── ولا يُحسب موضعٌ واحدٌ في هذا الملفّ ──────────────────────────────────
// كلُّ إحداثيٍّ يأتي من [PaintOp] كما هو، مضروباً في مقياسٍ واحدٍ لا أكثر.
// أيُّ حسابٍ هنا يفتح البابَ لأن تنحرف المعاينةُ عن الورق، وهو العطبُ الذي
// بُني المحرّكُ كلُّه لمنعه.

import 'package:flutter/material.dart';

import '../../../services/printing/paint_plan.dart';
import '../../../domain/printing/template_document.dart';
import '../../picpos_shell/picpos_surface.dart';

/// بكسلاتٌ لكلِّ مليمترٍ عند التكبير ١٠٠٪.
///
/// ٣٫٥ تجعل A4 (٢١٠مم) ٧٣٥ بكسلاً — تسع شاشةَ ١٩٢٠ بجوار اللوحتَين، ويبقى
/// نصُّ ٧pt عند ٩ بكسلاتٍ وهو أصغرُ ما يُقرأ.
const double previewPixelsPerMm = 3.5;

class SheetPreviewView extends StatelessWidget {
  const SheetPreviewView({
    super.key,
    required this.widthMm,
    required this.heightMm,
    required this.ops,
    required this.caption,
    this.zoom = 1.0,
  });

  final double widthMm;

  /// صفرٌ أو أقلُّ = ورقٌ متّصل، فيُشتقّ الارتفاعُ من أبعدِ عمليّةِ رسم.
  final double heightMm;

  final List<PaintOp> ops;
  final String caption;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final scale = previewPixelsPerMm * zoom;

    // الورقُ المتّصلُ بلا ارتفاعٍ معلَن: تنتهي الورقةُ حيث ينتهي الحبر،
    // وهامشٌ صغيرٌ أسفلَه كي لا يُقصّ آخرُ سطر.
    var sheetHeightMm = heightMm;
    if (sheetHeightMm <= 0) {
      var bottom = 0.0;
      for (final op in ops) {
        final b = op.topMm + op.heightMm;
        if (b > bottom) bottom = b;
      }
      sheetHeightMm = bottom + 6;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widthMm * scale,
          height: sheetHeightMm * scale,
          decoration: const BoxDecoration(
            // الورقةُ بيضاءُ في الوضعين: هي **محاكاةُ ورق**، وتلوينُها بالثيم
            // يكذب على العين بشأن التباين الذي سيخرج من الطابعة.
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x380B1220),
                blurRadius: 32,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: CustomPaint(
            painter: _SheetPainter(ops: ops, scale: scale),
            size: Size(widthMm * scale, sheetHeightMm * scale),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          caption,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.picposMuted,
          ),
        ),
      ],
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({required this.ops, required this.scale});

  final List<PaintOp> ops;
  final double scale;

  static const _ink = Color(0xFF0B1220);
  static const _sub = Color(0xFF6B7280);
  static const _rule = Color(0xFFC9D2E0);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;

    for (final op in ops) {
      final rect = Rect.fromLTWH(
        op.leftMm * scale,
        op.topMm * scale,
        op.widthMm * scale,
        op.heightMm * scale,
      );

      switch (op.kind) {
        case PaintKind.line:
          fill.color = _ink;
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top, rect.width,
                rect.height < 1 ? 1 : rect.height),
            fill,
          );

        case PaintKind.rect:
          canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = _rule,
          );

        case PaintKind.image:
        case PaintKind.qrCode:
        case PaintKind.barcode:
          // البايتاتُ لا تمرّ بالخطّة — تقول «صورةٌ هنا» ويأتي الراسمُ
          // بالبكسل. فالمعاينةُ تعرض **الموضعَ والحجمَ** وهما ما يُراجَع.
          canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = _ink,
          );
          _label(canvas, rect, _shortKindLabel(op.kind));

        case PaintKind.text:
        case PaintKind.tableHeader:
        case PaintKind.tableCell:
          _text(canvas, rect, op);
      }
    }
  }

  void _text(Canvas canvas, Rect rect, PaintOp op) {
    final bold = op.bold || op.kind == PaintKind.tableHeader;
    final painter = TextPainter(
      text: TextSpan(
        text: op.text,
        style: TextStyle(
          // ‏`fontSize` بالنقاط والمقياسُ بالمليمتر: ١pt = ٠٫٣٥٢٨مم.
          fontSize: op.fontSize * 0.3528 * scale,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: _colorOf(op),
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: _alignOf(op.align),
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);

    var dx = rect.left;
    if (op.align == TextAlignSpec.center) {
      dx = rect.left + (rect.width - painter.width) / 2;
    } else if (op.align == TextAlignSpec.end) {
      dx = rect.left + rect.width - painter.width;
    }
    painter.paint(canvas, Offset(dx, rect.top));

    if (op.subText.isEmpty) return;
    final sub = TextPainter(
      text: TextSpan(
        text: op.subText,
        style: TextStyle(
          fontSize: op.fontSize * 0.3528 * scale * 0.72,
          fontWeight: FontWeight.w600,
          color: _sub,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    sub.paint(canvas, Offset(dx, rect.top + painter.height));
  }

  void _label(Canvas canvas, Rect rect, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            fontSize: 8, fontWeight: FontWeight.w700, color: _sub),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (painter.width > rect.width || painter.height > rect.height) return;
    painter.paint(
      canvas,
      Offset(rect.left + (rect.width - painter.width) / 2,
          rect.top + (rect.height - painter.height) / 2),
    );
  }

  Color _colorOf(PaintOp op) {
    final hex = op.colorHex;
    if (hex != null && hex.length >= 6) {
      final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return op.kind == PaintKind.tableCell ? const Color(0xFF243247) : _ink;
  }

  TextAlign _alignOf(TextAlignSpec a) => switch (a) {
        TextAlignSpec.start => TextAlign.start,
        TextAlignSpec.center => TextAlign.center,
        TextAlignSpec.end => TextAlign.end,
      };

  String _shortKindLabel(PaintKind k) => switch (k) {
        PaintKind.image => 'LOGO',
        PaintKind.qrCode => 'QR',
        PaintKind.barcode => 'BARCODE',
        _ => '',
      };

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.ops != ops || old.scale != scale;
}
