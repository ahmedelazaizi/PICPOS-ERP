import 'dart:math' as math;

import 'package:flutter/material.dart';

/// قوس متحرك (0..1) بهوية PicPos — عرض فقط (Pure presentation).
///
/// **لا يحسب ولا يجلب أي رقم.** يستقبل [value] جاهزة من الشاشة المستدعية
/// (عادة مشتقة من provider حقيقي) ويرسمها كقوس متحرك؛ أي منطق حساب يبقى
/// في الشاشة الأم لا هنا. طبقة عرض PicPos-only لا تُنقل لـ UralCash.
class PicPosGauge extends StatefulWidget {
  /// النسبة المعروضة، بين ٠ و١. القيم خارج المدى تُقصّ (clamp) داخلياً.
  final double value;

  /// تسمية أسفل القيمة (مثال: «هامش الربح»).
  final String label;

  /// نص القيمة المعروض بمنتصف القوس. لو null يُشتق من [value] كنسبة مئوية.
  /// مفيد لعرض القيمة الحقيقية غير المقصوصة (مثال: هامش سالب) بينما القوس
  /// بصرياً يتوقف عند ٠..١٠٠٪.
  final String? valueLabel;

  final Color color;
  final Color trackColor;
  final double size;
  final Duration duration;

  const PicPosGauge({
    super.key,
    required this.value,
    required this.label,
    this.valueLabel,
    this.color = const Color(0xFF2563EB),
    this.trackColor = const Color(0xFFE2E8F0),
    this.size = 132,
    this.duration = const Duration(milliseconds: 900),
  });

  double get _clamped {
    if (value.isNaN || !value.isFinite) return 0.0;
    if (value < 0) return 0.0;
    if (value > 1) return 1.0;
    return value;
  }

  @override
  State<PicPosGauge> createState() => _PicPosGaugeState();
}

class _PicPosGaugeState extends State<PicPosGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: widget._clamped).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant PicPosGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final start = _animation.value;
      _animation = Tween<double>(begin: start, end: widget._clamped).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final displayed =
            widget.valueLabel ?? '${(_animation.value * 100).toStringAsFixed(1)}%';
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _PicPosGaugePainter(
              progress: _animation.value,
              color: widget.color,
              trackColor: widget.trackColor,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayed,
                    style: TextStyle(
                      fontSize: widget.size * 0.16,
                      fontWeight: FontWeight.w800,
                      color: widget.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: widget.size * 0.03),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.size * 0.09,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// يرسم قوساً بزاوية بداية ١٣٥° وامتداد ٢٧٠° (ترك ٩٠° سفلية فارغة) —
/// شكل "speedometer" شائع لمؤشرات النسبة المئوية.
class _PicPosGaugePainter extends CustomPainter {
  final double progress; // 0..1، مُقصّ مسبقاً من الودجت
  final Color color;
  final Color trackColor;

  _PicPosGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  static const double _startAngle = 0.75 * math.pi; // 135°
  static const double _sweepTotal = 1.5 * math.pi; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.11;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);
    final clamped = progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress);
    if (clamped > 0) {
      canvas.drawArc(rect, _startAngle, _sweepTotal * clamped, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PicPosGaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
