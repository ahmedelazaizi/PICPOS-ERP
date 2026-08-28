// مصغَّرةُ القالب — تُرسم من **عمليّات الرسم نفسِها** التي تصل الورق.
//
// ── لماذا لا «رسمٌ تخطيطيّ» ───────────────────────────────────────────────
// ملفُّ التصميم يرسم المصغَّرةَ بأشرطةٍ مكتوبةٍ باليد لكلِّ نوعِ ورق
// (‏`A4_SKETCH` · `THERMAL_SKETCH` · `STMT_SKETCH`). وهي صورةٌ **ثانيةٌ**
// للقالب: تُكتب مرّةً ولا تعرف شيئاً عن العناصر، فقالبٌ يُعدَّل تبقى
// مصغَّرتُه كما كانت — والمستخدمُ يختار بالصورة ويُطبع له غيرُها.
//
// وهذا عينُ فئة العطب التي بُني المحرّكُ كلُّه لمنعها: مصدرٌ ثانٍ للتخطيط
// ينحرف عن الأوّل ولا يشكو. فهنا تُستهلَك [PaintOp] كما هي — نفسُ ما يقرؤه
// راسمُ الـPDF — ولا يُحسب موضعٌ واحدٌ في هذا الملفّ.
//
// ولأنها مصغَّرةٌ لا معاينة: تُرسم كتلاً لا حروفاً. النصُّ عند ٦ بكسل غيرُ
// مقروءٍ أصلاً، ورسمُه يكلّف ولا يفيد — بينما **مواضعُه** هي ما يميّز
// قالباً عن قالب.

import 'package:flutter/material.dart';

import '../../../domain/models/picpos_template_card.dart';
import '../../../services/printing/paint_plan.dart';
import '../../picpos_shell/picpos_surface.dart';

class TemplateThumbnailView extends StatelessWidget {
  const TemplateThumbnailView({super.key, required this.thumbnail});

  final TemplateThumbnail thumbnail;

  @override
  Widget build(BuildContext context) {
    final paper = context.picposIsDark ? const Color(0xFF111C2E) : Colors.white;

    return LayoutBuilder(
      builder: (context, box) {
        // الورقةُ تُحفظ نسبتُها: مصغَّرةٌ ممطوطةٌ تكذب على العين بشأن الورق.
        final ratio = thumbnail.heightMm <= 0
            ? 1.0
            : thumbnail.widthMm / thumbnail.heightMm;
        var w = box.maxWidth;
        var h = w / ratio;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * ratio;
        }

        return Center(
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: context.picposHairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: thumbnail.isEmpty
                ? Center(
                    child: Icon(
                      Icons.hourglass_empty,
                      size: 14,
                      color: context.picposMuted,
                    ),
                  )
                : CustomPaint(
                    painter: _ThumbPainter(
                      thumbnail: thumbnail,
                      ink: context.picposText,
                      muted: context.picposMuted,
                      brand: context.picposBrandInk,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.thumbnail,
    required this.ink,
    required this.muted,
    required this.brand,
  });

  final TemplateThumbnail thumbnail;
  final Color ink;
  final Color muted;
  final Color brand;

  @override
  void paint(Canvas canvas, Size size) {
    if (thumbnail.widthMm <= 0 || thumbnail.heightMm <= 0) return;
    final sx = size.width / thumbnail.widthMm;
    final sy = size.height / thumbnail.heightMm;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final op in thumbnail.ops) {
      final r = Rect.fromLTWH(
        op.leftMm * sx,
        op.topMm * sy,
        op.widthMm * sx,
        // كتلةٌ لا يقلّ سمكُها عن بكسلٍ واحد — وإلّا اختفى نصفُ المستند عند
        // هذا القياس فبدت الورقةُ أفرغَ ممّا هي.
        (op.heightMm * sy).clamp(1.0, size.height),
      );
      if (r.width <= 0) continue;

      paint.color = _toneOf(op);
      canvas.drawRect(r, paint);
    }
  }

  /// لونُ الكتلة من **دورها** لا من نوعها: الرأسُ أغمقُ، والجدولُ أفتح،
  /// والتذييلُ أخفت — فتُقرأ بنيةُ الورقة بلمحةٍ بلا حرفٍ واحد.
  Color _toneOf(PaintOp op) {
    switch (op.kind) {
      case PaintKind.tableHeader:
        return brand.withValues(alpha: 0.55);
      case PaintKind.tableCell:
        return muted.withValues(alpha: 0.45);
      case PaintKind.text:
        if (op.bold) return ink.withValues(alpha: 0.75);
        return muted.withValues(alpha: 0.55);
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.thumbnail != thumbnail || old.ink != ink;
}
