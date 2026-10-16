// جسمُ الشاشة بعد وصول النتيجة: بطاقاتُ المؤشّرات، لوحةُ المخاطر، ثمّ ستُّ
// مجموعاتٍ من النسب. أو حالةٌ فارغةٌ إرشاديّة حين لا قيودَ مرحَّلة.
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/i18n/tr.dart';
import '../../data/providers/financial_analytics_provider.dart';
import '../../domain/analytics/ratio_engine.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_surface.dart';
import 'fin_analytics_state.dart';
import 'fin_kpi_card.dart';
import 'fin_ratio_group_section.dart';
import 'fin_risk_panel.dart';

/// ترتيبُ المجموعات في الشاشة — هو ترتيبُ المحرّك.
const List<RatioGroup> kFinGroupOrder = [
  RatioGroup.liquidity,
  RatioGroup.profitability,
  RatioGroup.efficiency,
  RatioGroup.leverage,
  RatioGroup.cashFlow,
  RatioGroup.growth,
];

class FinancialIndicatorsBody extends StatelessWidget {
  const FinancialIndicatorsBody({
    super.key,
    required this.result,
    required this.onChangePeriod,
  });

  final FinancialAnalyticsResult result;
  final VoidCallback onChangePeriod;

  @override
  Widget build(BuildContext context) {
    if (finSnapshotsEmpty(result.current, result.prior)) {
      return PicPosEmptyState(
        icon: Icons.insights_outlined,
        title: tr('لا توجد بيانات مرحَّلة في هذه الفترة'),
        hint: tr('المؤشرات تُحتسب من القيود المرحَّلة فقط. رحِّل قيوداً أو وسِّع الفترة الزمنية.'),
        action: OutlinedButton.icon(
          onPressed: onChangePeriod,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(tr('تغيير الفترة')),
        ),
      );
    }

    final kpis = buildFinKpis(result);
    final kpiMeta = <(String, IconData)>[
      (tr('الإيرادات'), Icons.point_of_sale),
      (tr('مجمل الربح'), Icons.account_balance_wallet_outlined),
      (tr('صافي الدخل'), Icons.savings_outlined),
      (tr('التدفق النقدي التشغيلي'), Icons.currency_exchange),
    ];
    final priorByKey = finPriorRatios(result);

    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
            const gap = Spacing.md;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < kpis.length; i++)
                  SizedBox(
                    width: w,
                    child: FinancialKpiCard(
                      label: kpiMeta[i].$1,
                      icon: kpiMeta[i].$2,
                      comparison: kpis[i],
                      budgetAvailable: result.budgetAvailable,
                    ),
                  ),
              ],
            );
          },
        ),
        if (!result.budgetAvailable) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            key: const ValueKey('budget-unavailable-note'),
            children: [
              Icon(Icons.info_outline, size: 14, color: context.picposMuted),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(
                  tr('الموازنة غير متاحة عند تقييد العرض على فرع بعينه لأن الموازنات على مستوى الشركة'),
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Spacing.lg),
        FinancialRiskPanel(ratios: result.ratios),
        for (final g in kFinGroupOrder)
          if (result.ratios.any((r) => r.group == g)) ...[
            const SizedBox(height: Spacing.lg),
            FinancialRatioGroupSection(
              group: g,
              ratios: [for (final r in result.ratios) if (r.group == g) r],
              priorByKey: priorByKey,
            ),
          ],
      ],
    );
  }
}
