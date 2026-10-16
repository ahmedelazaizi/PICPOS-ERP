// بطاقةُ مؤشّرٍ رئيسيّ: القيمةُ، والتغيّرُ عن الفترة السابقة، والفرقُ عن
// الموازنة. ودجتٌ عرضٍ خالصة — تستقبل [KpiComparison] جاهزاً.
//
// ⚠️ الموازنةُ المجهولة (العرضُ مقيَّدٌ بفرع، أو لا سطرَ موازنةٍ يطابق المؤشّر)
//    تُكتب «غير متاح» ولا تُكتب صفراً. وأخضرُ/أحمرُ يتبع [Favourability]
//    الذي حسبه المحرّك — لا يُعاد اشتقاقُه هنا.
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/i18n/tr.dart';
import '../../domain/analytics/kpi_comparison.dart';
import '../picpos_shell/picpos_surface.dart';
import 'fin_format.dart';

class FinancialKpiCard extends StatelessWidget {
  const FinancialKpiCard({
    super.key,
    required this.label,
    required this.icon,
    required this.comparison,
    required this.budgetAvailable,
  });

  final String label;
  final IconData icon;
  final KpiComparison comparison;

  /// False ⇒ لا تُعرض أيُّ مقارنةٍ بالموازنة (موازناتٌ على مستوى الشركة).
  final bool budgetAvailable;

  @override
  Widget build(BuildContext context) {
    final k = comparison.key;
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
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
              Icon(icon, size: 16, color: context.picposBrandInk),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.picposMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            finMoney(comparison.actual),
            key: ValueKey('kpi-$k-value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.picposText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          FinVarianceLine(
            valueKey: ValueKey('kpi-$k-prior'),
            caption: tr('مقارنة بالفترة السابقة'),
            variance: comparison.vsPrior,
          ),
          const SizedBox(height: Spacing.xs),
          FinVarianceLine(
            valueKey: ValueKey('kpi-$k-budget'),
            caption: tr('مقارنة بالموازنة'),
            variance: comparison.vsBudget,
            available: budgetAvailable,
          ),
        ],
      ),
    );
  }
}

/// سطرُ مقارنةٍ واحد: «التسمية … التغيّر%». المجهولُ ⇒ «غير متاح».
class FinVarianceLine extends StatelessWidget {
  const FinVarianceLine({
    super.key,
    required this.valueKey,
    required this.caption,
    required this.variance,
    this.available = true,
  });

  final Key valueKey;
  final String caption;
  final Variance variance;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final known = available && variance.baseline != null;
    final Widget value;
    if (!known) {
      value = Tooltip(
        message: available
            ? tr('لا توجد موازنة لهذا المؤشر في الفترة')
            : tr('الموازنة غير متاحة عند تقييد العرض على فرع بعينه'),
        child: Text(
          tr('غير متاح'),
          key: valueKey,
          style: TextStyle(fontSize: 11.5, color: context.picposMuted),
        ),
      );
    } else {
      final color = finFavourColor(context, variance.favourability);
      final pct = variance.percent;
      final text = pct != null
          ? finPercent(pct, signed: true)
          : finSignedMoney(variance.amount);
      final arrow = finFavourIcon(variance);
      value = Row(
        key: valueKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (arrow != null) Icon(arrow, size: 12, color: color),
          if (arrow != null) const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: context.picposMuted),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        value,
      ],
    );
  }
}
