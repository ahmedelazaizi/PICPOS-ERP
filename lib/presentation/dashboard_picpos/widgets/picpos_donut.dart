import 'dart:math' as math;

import 'package:flutter/material.dart';

/// شريحة دونات واحدة — قيمة جاهزة تُمرَّر من الشاشة المستدعية، لا تُحسب هنا.
class PicPosDonutSegment {
  final String label;
  final double value;
  final Color color;

  const PicPosDonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  double get _safeValue => (value.isFinite && value > 0) ? value : 0.0;
}

/// دونات تفاعلي بهوية PicPos — عرض فقط (Pure presentation).
///
/// يستقبل [segments] جاهزة (label/value/color) من الشاشة المستدعية ولا
/// يحسب أي رقم أعمال بنفسه؛ النسبة المئوية المعروضة لكل شريحة هي حصتها من
/// إجمالي [segments] فقط (حساب عرض، وليس منطق أعمال). النقر على شريحة
/// يبرزها ويعرض نسبتها بالمنتصف. طبقة عرض PicPos-only لا تُنقل لـ UralCash.
class PicPosDonut extends StatefulWidget {
  final List<PicPosDonutSegment> segments;
  final double size;

  /// تسمية/قيمة المنتصف الافتراضية قبل اختيار أي شريحة.
  final String? centerLabel;
  final String? centerValue;
  final Duration duration;

  const PicPosDonut({
    super.key,
    required this.segments,
    this.size = 150,
    this.centerLabel,
    this.centerValue,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  State<PicPosDonut> createState() => _PicPosDonutState();
}

class _PicPosDonutState extends State<PicPosDonut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int? _selectedIndex;

  double get _total =>
      widget.segments.fold(0.0, (sum, s) => sum + s._safeValue);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant PicPosDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapUp(TapUpDetails details) {
    final total = _total;
    if (widget.segments.isEmpty || total <= 0) return;

    final center = Offset(widget.size / 2, widget.size / 2);
    final local = details.localPosition - center;
    final dist = local.distance;
    final outerRadius = widget.size / 2;
    final strokeWidth = outerRadius * 0.42;
    final innerRadius = outerRadius - strokeWidth;
    if (dist < innerRadius || dist > outerRadius) {
      setState(() => _selectedIndex = null);
      return;
    }

    // زاوية اللمس بنفس مرجع الرسّام: البداية من الأعلى (-90°) بدل ٠° الافتراضية.
    var angle = math.atan2(local.dy, local.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    double cursor = 0;
    for (var i = 0; i < widget.segments.length; i++) {
      final sweep = widget.segments[i]._safeValue / total * 2 * math.pi;
      if (angle >= cursor && angle < cursor + sweep) {
        setState(() => _selectedIndex = i);
        return;
      }
      cursor += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final selected =
        (_selectedIndex != null && _selectedIndex! < widget.segments.length)
            ? widget.segments[_selectedIndex!]
            : null;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return GestureDetector(
          onTapUp: _handleTapUp,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _PicPosDonutPainter(
                segments: widget.segments,
                progress: _controller.value,
                selectedIndex: _selectedIndex,
              ),
              child: Center(
                child: total <= 0
                    ? Text(
                        'لا بيانات',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selected != null
                                ? '${(selected._safeValue / total * 100).toStringAsFixed(0)}%'
                                : (widget.centerValue ?? total.toStringAsFixed(0)),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selected?.label ?? widget.centerLabel ?? 'الإجمالي',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PicPosDonutPainter extends CustomPainter {
  final List<PicPosDonutSegment> segments;
  final double progress;
  final int? selectedIndex;

  _PicPosDonutPainter({
    required this.segments,
    required this.progress,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (sum, s) => sum + s._safeValue);
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final strokeWidth = outerRadius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: outerRadius - strokeWidth / 2);

    if (total <= 0) {
      final emptyPaint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, 0, 2 * math.pi, false, emptyPaint);
      return;
    }

    double cursor = -math.pi / 2; // البداية من الأعلى
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final fraction = seg._safeValue / total;
      final sweep = fraction * 2 * math.pi * progress;
      final isSelected = selectedIndex == i;
      final paint = Paint()
        ..color = isSelected ? seg.color : seg.color.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? strokeWidth * 1.12 : strokeWidth
        ..strokeCap = StrokeCap.butt;
      if (sweep > 0) {
        canvas.drawArc(rect, cursor, sweep, false, paint);
      }
      cursor += fraction * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(covariant _PicPosDonutPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.progress != progress ||
      oldDelegate.selectedIndex != selectedIndex;
}
