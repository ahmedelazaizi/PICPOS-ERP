// معاينةُ ملصقٍ بقالبٍ محفوظ — من **خطّة الرسم نفسِها** (‏`labelPaintOps`).
//
// ── لماذا لا `LabelPagePreview` ──────────────────────────────────────────
// تلك ترسم خلايا المقاس وتكتب في كلٍّ منها اسمَ الصنف وحده، ولا تعرف أنّ
// للقالب عناصر. فاختيارُ قالبٍ فيه سعرٌ وباركود كان يعرض الاسمَ فقط بينما
// الورقةُ تحملها كلَّها (‏التحقّق الحيّ 2026-11-03). هنا كلُّ موضعٍ وكلُّ
// نصٍّ يأتي من [PaintOp] كما يصل راسمَ الـPDF، مضروباً في مقياسٍ واحد.

import 'package:flutter/material.dart';

import '../../../../domain/printing/label_design.dart';
import '../../../../domain/printing/template_document.dart' show TextAlignSpec;
import '../../../../services/printing/label_paint_plan.dart';
import '../../../../services/printing/paint_plan.dart';

class LabelTemplatePreview extends StatelessWidget {
  const LabelTemplatePreview({
    super.key,
    required this.design,
    required this.sample,
  });

  final LabelDesign design;
  final LabelSample sample;

  static const double _maxHeight = 180;
  static const double _maxWidth = 360;

  // dark-ok: ورقةُ الملصق محاكاةُ ورقٍ مطبوع — حبرٌ أسود على أبيض في الوضعين.
  static const _ink = Color(0xFF0B1220);

  @override
  Widget build(BuildContext context) {
    final w = design.widthMm, h = design.heightMm;
    if (w <= 0 || h <= 0) return const SizedBox(height: 40);
    final k = (_maxWidth / w) < (_maxHeight / h)
        ? _maxWidth / w
        : _maxHeight / h;
    final ops = labelPaintOps(design, sample: sample);
    return Container(
      key: const Key('label_template_preview'),
      width: w * k,
      height: h * k,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        // dark-ok: label preview paper is intentionally white.
        color: Colors.white,
        border: Border.all(color: Colors.black54),
      ),
      child: Stack(
        children: [
          for (final op in ops)
            Positioned(
              key: Key('label_template_op_${op.id}'),
              left: op.leftMm * k,
              top: op.topMm * k,
              width: op.widthMm * k,
              height: op.heightMm * k < 1 ? 1 : op.heightMm * k,
              child: _opWidget(op, k),
            ),
        ],
      ),
    );
  }

  Widget _opWidget(PaintOp op, double k) {
    switch (op.kind) {
      case PaintKind.line:
        return const ColoredBox(color: _ink);
      case PaintKind.rect:
        return DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: _ink)),
        );
      case PaintKind.barcode:
      case PaintKind.qrCode:
        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _BarsPainter(op.text),
                size: Size.infinite,
              ),
            ),
            Text(
              op.text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: (op.fontSize * 0.3528 * k).clamp(6, 40),
                color: _ink,
                height: 1.0,
              ),
            ),
          ],
        );
      case PaintKind.text:
      case PaintKind.image:
      case PaintKind.tableHeader:
      case PaintKind.tableCell:
        return Text(
          op.text,
          maxLines: 2,
          overflow: TextOverflow.clip,
          textDirection: TextDirection.rtl,
          // المحاذاةُ مطلقةٌ كما في الراسم: `start` = الحافّةُ اليسرى.
          textAlign: switch (op.align) {
            TextAlignSpec.start => TextAlign.left,
            TextAlignSpec.center => TextAlign.center,
            TextAlignSpec.end => TextAlign.right,
          },
          style: TextStyle(
            // ‏`fontSize` بالنقاط والمقياسُ بالمليمتر: ١pt = ٠٫٣٥٢٨مم.
            fontSize: (op.fontSize * 0.3528 * k).clamp(6, 60),
            fontWeight: op.bold ? FontWeight.w700 : FontWeight.w400,
            color: _ink,
            height: 1.1,
          ),
        );
    }
  }
}

/// خطوطُ باركودٍ تقريبيّةٌ من القيمة — المعاينةُ تُثبت **الموضعَ والحجمَ
/// والقيمة**؛ ورمزُ الطابعة الفعليّ يرسمه `pw.BarcodeWidget` على الورق.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.value);

  final String value;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()..color = LabelTemplatePreview._ink;
    final units = <int>[];
    for (final c in value.codeUnits) {
      units
        ..add(1 + c % 3)
        ..add(1 + (c ~/ 3) % 2);
    }
    if (units.isEmpty) units.addAll(const [1, 1]);
    final total = units.fold<int>(0, (a, b) => a + b);
    final unit = size.width / total;
    var x = 0.0;
    for (var i = 0; i < units.length; i++) {
      final w = units[i] * unit;
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.value != value;
}
