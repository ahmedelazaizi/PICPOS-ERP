import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// بطاقة مؤشّر أداء (KPI) موحّدة وقابلة للاستخدام في كل الداشبوردات.
///
/// تخطيط أفقي مدمج: أيقونة على اليمين (RTL)، الرقم والـ label في
/// المنتصف، شريط الاتجاه في الأعلى. ارتفاع ثابت ~80px لتناسب
/// عرض شبكة 4×2 لثمانية مؤشرات بدون scroll على شاشة 1080p.
///
/// الأنماط:
/// - `KpiStyle.gradient` — تدرّج بلون المؤشر، نص أبيض (للداشبورد التنفيذي)
/// - `KpiStyle.flat` — خلفية بيضاء، شريط جانبي ملوّن (للملخصات)
enum KpiStyle { gradient, flat }

class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final double? trend;
  final Color color;
  final KpiStyle style;
  final VoidCallback? onTap;

  const AppKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
    this.trend,
    this.style = KpiStyle.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGradient = style == KpiStyle.gradient;
    final fg = isGradient ? Colors.white : AppColors.textPrimary;
    final labelColor = isGradient
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.textSecondary;
    final subtitleColor = isGradient
        ? Colors.white.withValues(alpha: 0.78)
        : AppColors.textMuted;
    final iconBg = isGradient
        ? Colors.white.withValues(alpha: 0.20)
        : color.withValues(alpha: 0.12);
    final iconFg = isGradient ? Colors.white : color;

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: isGradient
            ? LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isGradient ? null : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: isGradient
            ? null
            : Border(
                right: BorderSide(color: color, width: 3),
                top: const BorderSide(color: AppColors.border, width: 0.8),
                bottom: const BorderSide(color: AppColors.border, width: 0.8),
                left: const BorderSide(color: AppColors.border, width: 0.8),
              ),
        boxShadow: [
          BoxShadow(
            color: (isGradient ? color : Colors.black)
                .withValues(alpha: isGradient ? 0.22 : 0.04),
            blurRadius: isGradient ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon (right side in RTL)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconFg, size: 20),
          ),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (trend != null) _TrendChip(trend: trend!, onGradient: isGradient),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtitleColor, fontSize: 9.5, height: 1.15),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: card,
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  final double trend;
  final bool onGradient;
  const _TrendChip({required this.trend, required this.onGradient});

  @override
  Widget build(BuildContext context) {
    final positive = trend >= 0;
    final color = onGradient
        ? Colors.white
        : (positive ? AppColors.success : AppColors.error);
    final bg = onGradient
        ? Colors.white.withValues(alpha: 0.20)
        : (positive ? AppColors.success : AppColors.error)
            .withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${trend.abs().toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// شبكة متجاوبة لبطاقات الـ KPI تتأقلم مع عرض الشاشة تلقائياً.
///
/// تستخدم `LayoutBuilder` لتختار عدد الأعمدة بناءً على العرض المتاح،
/// مع ارتفاع ثابت لكل بطاقة (80px) بدلاً من aspect ratio حتى لا تتمدد
/// رأسياً على الشاشات العريضة.
class AppKpiGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double itemHeight;

  const AppKpiGrid({
    super.key,
    required this.children,
    this.spacing = 10,
    this.itemHeight = 80,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1300
            ? 4
            : w >= 900
                ? 3
                : w >= 600
                    ? 2
                    : 1;
        final colWidth = (w - (cols - 1) * spacing) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((c) => SizedBox(width: colWidth, height: itemHeight, child: c))
              .toList(),
        );
      },
    );
  }
}
