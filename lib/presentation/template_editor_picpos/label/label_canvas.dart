// قماشُ الملصق — حرٌّ بإحداثيّاتٍ مليمتريّةٍ من **يسار** الملصق.
//
// ── لماذا `Positioned` لا `PositionedDirectional` ─────────────────────────
// كانفاسُ النطاقات يقيس من حافّة البداية لأنّ `planPage` يفعل ذلك. أمّا راسمُ
// الملصقات فيضع العنصرَ بـ`pw.Positioned(left: x)` — من اليسار في كلِّ
// اتّجاه. فالقياسُ هنا من اليسار كذلك، وإلّا قفز كلُّ عنصرٍ عند الطبع.
//
// ── والسحبُ تراكميٌّ من نقطة البدء ────────────────────────────────────────
// المحاذاةُ للشبكة (٠٫٥مم) تقع على كلِّ تحديث؛ وجمعُ الإزاحة على الموضع
// الحاليِّ كان يُرجع كلَّ حركةٍ أصغرَ من ربع مليمترٍ إلى مكانها، فيعلق
// العنصرُ تحت الإصبع البطيء. فيُحسب الموضعُ من نقطة البدء + الإزاحة الكلّيّة.

import 'package:flutter/material.dart';

import '../../../domain/printing/label_design.dart';
import '../../../services/printing/label_paint_plan.dart';
import '../../picpos_shell/picpos_surface.dart';

/// بكسلاتٌ لكلِّ مليمترٍ عند ١٠٠٪ — الملصقُ صغيرٌ فيُكبَّر أكثرَ من الفاتورة.
const double labelPixelsPerMm = 8;

// الورقُ أبيضُ والحبرُ أسودُ في الوضعين: هو **محاكاةُ ملصق**، وتلوينُه بالثيم
// يكذب على العين بشأن ما يخرج من الطابعة.
const _paper = Color(0xFFFFFFFF);
const _ink = Color(0xFF0B1220);
const _guide = Color(0xFFC9D2E0);

class LabelCanvas extends StatelessWidget {
  const LabelCanvas({
    super.key,
    required this.design,
    required this.zoom,
    required this.showGrid,
    required this.selectedKey,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
  });

  final LabelDesign design;
  final double zoom;
  final bool showGrid;
  final String? selectedKey;
  final ValueChanged<String?> onSelect;

  /// (المفتاح، x، y) بالمليمتر من يسار الملصق وأعلاه.
  final void Function(String, double, double) onMove;
  final void Function(String, double, double) onResize;

  @override
  Widget build(BuildContext context) {
    final k = labelPixelsPerMm * zoom;
    return Container(
      color: context.picposIsDark
          ? const Color(0xFF060C16)
          : const Color(0xFFE2E8F2),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
          // الملصقُ في وسط القماش ما دام يسعه، ويُمرَّر حين يكبر عنه.
          constraints: BoxConstraints(
              minWidth: (box.maxWidth - 64).clamp(0, double.infinity)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => onSelect(null),
                child: Container(
                  key: const Key('label-canvas'),
                  width: design.widthMm * k,
                  height: design.heightMm * k,
                  decoration: const BoxDecoration(
                    // dark-ok: محاكاةُ ورق الملصق — بيضاءُ في الوضعين عمداً.
                    color: _paper,
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x3D0B1220),
                          blurRadius: 30,
                          offset: Offset(0, 10)),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (showGrid)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _GridPainter(k)),
                          ),
                        ),
                      for (final el in design.elements)
                        Positioned(
                          left: el.xMm * k,
                          top: el.yMm * k,
                          width: el.wMm * k,
                          // الخطُّ رقيقٌ لا يُمسك — يُعطى ارتفاعَ لمسٍ أدنى.
                          height: el.hMm * k < 6 ? 6 : el.hMm * k,
                          child: _LabelElementBox(
                            key: Key('label-el-${el.key}'),
                            element: el,
                            k: k,
                            selected: el.key == selectedKey,
                            onSelect: () => onSelect(el.key),
                            onMove: (x, y) => onMove(el.key, x, y),
                            onResize: (w, h) => onResize(el.key, w, h),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
      ),
    );
  }
}

class _LabelElementBox extends StatefulWidget {
  const _LabelElementBox({
    super.key,
    required this.element,
    required this.k,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
  });

  final LabelElement element;
  final double k;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double, double) onMove;
  final void Function(double, double) onResize;

  @override
  State<_LabelElementBox> createState() => _LabelElementBoxState();
}

class _LabelElementBoxState extends State<_LabelElementBox> {
  Offset _origin = Offset.zero;
  Offset _total = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final el = widget.element;
    final k = widget.k;
    final brand = context.picposBrandInk;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelect,
      onPanStart: (_) {
        widget.onSelect();
        _origin = Offset(el.xMm, el.yMm);
        _total = Offset.zero;
      },
      onPanUpdate: (d) {
        _total += d.delta;
        widget.onMove(_origin.dx + _total.dx / k, _origin.dy + _total.dy / k);
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.selected ? brand.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: widget.selected ? brand : _ink.withValues(alpha: 0.14),
            width: widget.selected ? 1.4 : 0.6,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _content(el, k)),
            if (widget.selected)
              Positioned(
                right: -5,
                bottom: -5,
                child: GestureDetector(
                  key: const Key('label-resize-handle'),
                  onPanStart: (_) {
                    _origin = Offset(el.wMm, el.hMm);
                    _total = Offset.zero;
                  },
                  onPanUpdate: (d) {
                    _total += d.delta;
                    widget.onResize(
                        _origin.dx + _total.dx / k, _origin.dy + _total.dy / k);
                  },
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: brand,
                      border: Border.all(color: _paper, width: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(LabelElement el, double k) {
    if (el.isLine) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Divider(height: 1, thickness: 1, color: _ink),
      );
    }
    if (el.isRect) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: _ink,
            width: (el.borderWidth > 0 ? el.borderWidth : 0.5) * 0.3528 * k,
          ),
        ),
      );
    }
    if (el.isBarcode) {
      return CustomPaint(
        painter: _SymbolPainter(qr: el.isQr),
        child: const SizedBox.expand(),
      );
    }
    final text = labelElementText(el, LabelSample.demo);
    return Align(
      alignment: switch (el.align) {
        'left' => Alignment.topLeft,
        'center' => Alignment.topCenter,
        _ => Alignment.topRight,
      },
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: switch (el.align) {
          'left' => TextAlign.left,
          'center' => TextAlign.center,
          _ => TextAlign.right,
        },
        style: TextStyle(
          // ‏١pt = ٠٫٣٥٢٨مم — نفسُ تحويل ورقة المعاينة.
          fontSize: el.fontSize * 0.3528 * k,
          fontWeight: el.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: el.italic ? FontStyle.italic : FontStyle.normal,
          color: _colorOf(el.color),
          height: 1.1,
        ),
      ),
    );
  }

  Color _colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? _ink : Color(0xFF000000 | v);
  }
}

/// رسمٌ تخطيطيٌّ للرمز — الموضعُ والمقاسُ هما ما يُراجَع، والبياناتُ عند الطبع.
class _SymbolPainter extends CustomPainter {
  _SymbolPainter({required this.qr});

  final bool qr;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = _ink;
    if (qr) {
      final side = size.shortestSide;
      final cell = side / 7;
      for (var i = 0; i < 7; i++) {
        for (var j = 0; j < 7; j++) {
          if ((i * 3 + j * 5) % 4 == 0 || i == 0 || j == 0) {
            canvas.drawRect(Rect.fromLTWH(i * cell, j * cell, cell, cell), p);
          }
        }
      }
      return;
    }
    // ثمانون بالمئة أعمدةٌ كما يرسمها الراسم، والباقي للأرقام تحتها.
    final barsH = size.height * 0.8;
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final w = (i % 3 + 1) * size.width / 120;
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w, barsH * 0.82), p);
      x += w;
      i++;
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.qr != qr;
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.k);

  /// بكسلاتٌ لكلِّ مليمتر — نقطةٌ كلَّ مليمتر.
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    if (k < 4) return;
    final paint = Paint()..color = _guide;
    for (var x = 0.0; x <= size.width; x += k) {
      for (var y = 0.0; y <= size.height; y += k) {
        canvas.drawCircle(Offset(x, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.k != k;
}
