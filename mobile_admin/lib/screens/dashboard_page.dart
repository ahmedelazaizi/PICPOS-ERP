import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// KPI dashboard layout (M-1 fills it from signed desktop snapshots); M-0
/// shows the structure with empty figures.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final kpis = [
      (t('kpiNetSales'), Icons.payments_outlined, PicPosTone.brand),
      (t('kpiInvoices'), Icons.receipt_outlined, PicPosTone.brand),
      (t('kpiGrossProfit'), Icons.trending_up, PicPosTone.success),
      (t('kpiReturns'), Icons.assignment_return_outlined, PicPosTone.warning),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: t('navDashboard'),
        subtitle: t('dashboardSub'),
        icon: Icons.space_dashboard_outlined,
        actions: const [ConnectionChip(connection: PicPosConnection.offline)],
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth >= PicPosBreakpoints.expanded ? 4 : 2;
            final w = (c.maxWidth - PicPosSpacing.cardGap * (columns - 1)) / columns;
            return Wrap(spacing: PicPosSpacing.cardGap, runSpacing: PicPosSpacing.cardGap, children: [
              for (final (label, icon, tone) in kpis)
                SizedBox(
                  width: w,
                  child: KpiCard(label: label, value: '—', icon: icon, tone: tone, footnote: t('kpiAfterPairing')),
                ),
            ]);
          }),
          const SizedBox(height: PicPosSpacing.lg),
          PicPosBlock(
            title: t('cashBanks'),
            subtitle: t('cashBanksSub'),
            child: SizedBox(
              height: 220,
              child: EmptyState(icon: Icons.link_off, title: t('notPaired'), message: t('notPairedMsg')),
            ),
          ),
        ]),
      ),
    ]);
  }
}
