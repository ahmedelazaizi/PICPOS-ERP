// ═══════════════════════════════════════════════════════════════════════════
// E-08: Performance Analytics (BI Lite) Service
// Trend analysis, comparison metrics, and forecast models
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/theme/app_colors.dart';

final _currFmt = NumberFormat('#,##0.00');
final _pctFmt = NumberFormat('#,##0.0');

// ─── Data Models ────────────────────────────────────────────────────────

/// Time series data point
class TimeSeriesPoint {
  final DateTime date;
  final double value;

  const TimeSeriesPoint({required this.date, required this.value});
}

/// Trend direction
enum TrendDirection { up, down, flat }

/// Trend analysis result
class TrendAnalysis {
  final double slope;
  final double startValue;
  final double endValue;
  final double changePercent;
  final TrendDirection direction;
  final double? forecastNext;

  const TrendAnalysis({
    required this.slope,
    required this.startValue,
    required this.endValue,
    required this.changePercent,
    required this.direction,
    this.forecastNext,
  });
}

/// Period comparison result (e.g. this month vs last month)
class PeriodComparison {
  final String metricName;
  final double currentValue;
  final double previousValue;
  final double change;
  final double changePercent;

  const PeriodComparison({
    required this.metricName,
    required this.currentValue,
    required this.previousValue,
    required this.change,
    required this.changePercent,
  });

  bool get isImprovement => change > 0;
  bool get isDecline => change < 0;
}

/// Complete analytics snapshot
class AnalyticsSnapshot {
  final DateTime generatedAt;
  final List<PeriodComparison> periodComparisons;
  final Map<String, TrendAnalysis> trends;
  final Map<String, double> currentKPIs;

  const AnalyticsSnapshot({
    required this.generatedAt,
    required this.periodComparisons,
    required this.trends,
    required this.currentKPIs,
  });
}

// ─── Analytics Engine ───────────────────────────────────────────────────

class PerformanceAnalyticsService {
  /// Calculate simple linear regression trend
  static TrendAnalysis analyzeTrend(List<TimeSeriesPoint> data) {
    if (data.isEmpty) {
      return const TrendAnalysis(
        slope: 0, startValue: 0, endValue: 0,
        changePercent: 0, direction: TrendDirection.flat,
      );
    }

    if (data.length == 1) {
      return TrendAnalysis(
        slope: 0,
        startValue: data.first.value,
        endValue: data.first.value,
        changePercent: 0,
        direction: TrendDirection.flat,
      );
    }

    // Linear regression
    final n = data.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += data[i].value;
      sumXY += i * data[i].value;
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final firstVal = data.first.value;
    final lastVal = data.last.value;
    final changePct = firstVal != 0 ? ((lastVal - firstVal) / firstVal * 100) : 0.0;
    final forecast = lastVal + slope;

    return TrendAnalysis(
      slope: slope,
      startValue: firstVal,
      endValue: lastVal,
      changePercent: changePct,
      direction: slope > 0.01 ? TrendDirection.up
          : slope < -0.01 ? TrendDirection.down
          : TrendDirection.flat,
      forecastNext: forecast,
    );
  }

  /// Compare two periods
  static PeriodComparison comparePeriods({
    required String metricName,
    required double current,
    required double previous,
  }) {
    final change = current - previous;
    final pct = previous != 0 ? (change / previous * 100) : 0.0;

    return PeriodComparison(
      metricName: metricName,
      currentValue: current,
      previousValue: previous,
      change: change,
      changePercent: pct,
    );
  }

  /// Calculate moving average for smoothing noisy data
  static List<TimeSeriesPoint> movingAverage(List<TimeSeriesPoint> data, int window) {
    if (data.length < window) return data;

    final result = <TimeSeriesPoint>[];
    for (int i = window - 1; i < data.length; i++) {
      double sum = 0;
      for (int j = i - window + 1; j <= i; j++) {
        sum += data[j].value;
      }
      result.add(TimeSeriesPoint(date: data[i].date, value: sum / window));
    }
    return result;
  }

  /// Detect seasonality (simplified: compare same period across years)
  static double? seasonalityIndex(List<TimeSeriesPoint> data, int currentMonth) {
    final sameMonth = data.where((d) => d.date.month == currentMonth).toList();
    final allAvg = data.fold(0.0, (s, p) => s + p.value) / data.length;
    if (sameMonth.isEmpty || allAvg == 0) return null;
    final monthAvg = sameMonth.fold(0.0, (s, p) => s + p.value) / sameMonth.length;
    return monthAvg / allAvg;
  }

  /// Simple forecast: project next N periods based on trend
  static List<TimeSeriesPoint> forecast(List<TimeSeriesPoint> data, int periods) {
    final trend = analyzeTrend(data);
    final results = <TimeSeriesPoint>[];
    final lastDate = data.last.date;

    for (int i = 1; i <= periods; i++) {
      results.add(TimeSeriesPoint(
        date: DateTime(lastDate.year, lastDate.month + i, lastDate.day),
        value: math.max(0, trend.endValue + trend.slope * i),
      ));
    }

    return results;
  }
}

// ─── Sparkline Widget ───────────────────────────────────────────────────

/// Compact inline trend sparkline for dashboard cards
class TrendSparkline extends StatelessWidget {
  final List<double> data;
  final double height;
  final double width;
  final Color? color;

  const TrendSparkline({
    super.key,
    required this.data,
    this.height = 30,
    this.width = 80,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return SizedBox(height: height, width: width);

    final maxVal = data.reduce(math.max);
    final minVal = data.reduce(math.min);
    final range = maxVal - minVal;
    final isUp = data.last >= data.first;
    final lineColor = color ?? (isUp ? AppColors.success : AppColors.error);

    return CustomPaint(
      size: Size(width, height),
      painter: _SparklinePainter(data: data, min: minVal, range: range, color: lineColor),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final double min;
  final double range;
  final Color color;

  _SparklinePainter({required this.data, required this.min, required this.range, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final y = range > 0
          ? size.height - ((data[i] - min) / range * size.height)
          : size.height / 2;
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(i * stepX, y);
      }
    }

    canvas.drawPath(path, paint);

    // Fill gradient under line
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.data != data;
}

// ─── Period Comparison Widget ───────────────────────────────────────────

class PeriodComparisonCard extends StatelessWidget {
  final PeriodComparison comparison;
  final String currencySymbol;

  const PeriodComparisonCard({
    super.key,
    required this.comparison,
    this.currencySymbol = '',
  });

  @override
  Widget build(BuildContext context) {
    final isUp = comparison.isImprovement;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(comparison.metricName,
              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('$currencySymbol ${_currFmt.format(comparison.currentValue)}',
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isUp ? PhosphorIconsBold.trendUp : PhosphorIconsBold.trendDown,
                size: 14,
                color: isUp ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 4),
              Text(
                '${isUp ? "+" : ""}${_pctFmt.format(comparison.changePercent)}%',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUp ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'عن الفترة السابقة',
                style: GoogleFonts.cairo(fontSize: 9, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
