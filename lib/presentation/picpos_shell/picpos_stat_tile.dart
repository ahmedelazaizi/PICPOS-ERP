import 'picpos_surface.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/theme/app_colors.dart';

/// بطاقة رقم واحد — العنوان فوق، القيمة تحت، ودلالة اتجاه اختيارية.
///
/// التقارير كلها بتعرض صفوف أرقام زي دي وكل واحدة بتبنيها بإيدها بمقاسات
/// مختلفة، فالشاشة الواحدة بتبان متسقة والشاشتين جنب بعض لأ. `ReportKpiCard`
/// المشتركة موجودة بس بهوية UralCash المرفوعة (ظلال + elevation) — دي نسخة
/// PicPos المسطّحة بحد شعري.
class PicPosStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  /// لون التمييز. الافتراضي لون العلامة؛ استخدم `success`/`error` للأرقام
  /// اللي ليها اتجاه (ربح/خسارة، فائض/عجز).
  final Color? accent;

  /// سطر مساعد تحت القيمة — مقارنة بفترة سابقة مثلاً.
  final String? caption;

  /// نسبة التغير عن الفترة السابقة. موجب = أخضر لأعلى، سالب = أحمر لأسفل.
  /// `null` يعني مفيش بيانات مقارنة، والسهم مبيظهرش أصلاً بدل ما نرسم صفر
  /// كأنه «مفيش تغيير».
  final double? changePercent;

  const PicPosStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
    this.caption,
    this.changePercent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    final change = changePercent;
    // خافتٌ يتبع الوضع — `AppColors.textMuted` الثابتُ يذوب في البطاقة الداكنة.
    final muted = context.picposMuted;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: color,
              // أرقام جدولية عشان الأعمدة تفضل متراصة والقيمة ما ترقصش وهي
              // بتتحدث.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (change != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Icon(
                  change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 11,
                  color: change >= 0 ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 3),
                Text(
                  '${change.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: change >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (caption != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
