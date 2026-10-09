import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../admin_session.dart';
import '../l10n/strings.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.session});
  final AdminSession session;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _error;

  Widget _previewDashboard(BuildContext context) {
    final t = S.of(context);
    final kpis = [
      (t('kpiNetSales'), Icons.payments_outlined, PicPosTone.brand),
      (t('kpiInvoices'), Icons.receipt_outlined, PicPosTone.brand),
      (t('kpiGrossProfit'), Icons.trending_up, PicPosTone.success),
      (t('kpiReturns'), Icons.assignment_return_outlined, PicPosTone.warning),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PicPosPageHeader(
          title: t('navDashboard'),
          subtitle: t('dashboardSub'),
          icon: Icons.space_dashboard_outlined,
          actions: const [ConnectionChip(connection: PicPosConnection.offline)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= PicPosBreakpoints.expanded
                      ? 4
                      : 2;
                  final width =
                      (constraints.maxWidth -
                          PicPosSpacing.cardGap * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: PicPosSpacing.cardGap,
                    runSpacing: PicPosSpacing.cardGap,
                    children: [
                      for (final (label, icon, tone) in kpis)
                        SizedBox(
                          width: width,
                          child: KpiCard(
                            label: label,
                            value: '—',
                            icon: icon,
                            tone: tone,
                            footnote: t('kpiAfterPairing'),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: PicPosSpacing.lg),
              PicPosBlock(
                title: t('cashBanks'),
                subtitle: t('cashBanksSub'),
                child: SizedBox(
                  height: 220,
                  child: EmptyState(
                    icon: Icons.link_off,
                    title: t('notPaired'),
                    message: t('notPairedMsg'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    try {
      await widget.session.refresh();
      if (mounted) setState(() => _error = null);
    } on ApiError catch (error) {
      if (mounted) setState(() => _error = error.code);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final snapshots = widget.session.snapshots;
    if (snapshots == null && !widget.session.loggedIn) {
      return _previewDashboard(context);
    }
    final today = snapshots?.find(SnapshotKinds.kpiToday);
    final figures = today?.payload is Map ? today!.payload as Map : const {};
    final cash = snapshots?.find(SnapshotKinds.cash);
    final accounts = cash?.payload is Map
        ? (cash!.payload as Map)['accounts'] as List?
        : null;
    final stale =
        today != null && DateTime.now().difference(today.asOf).inMinutes > 15;
    final kpis = [
      (
        t('kpiNetSales'),
        figures['netSales'],
        Icons.payments_outlined,
        PicPosTone.brand,
      ),
      (
        t('kpiInvoices'),
        figures['invoiceCount'],
        Icons.receipt_outlined,
        PicPosTone.brand,
      ),
      (
        t('kpiGrossProfit'),
        figures['grossProfit'],
        Icons.trending_up,
        PicPosTone.success,
      ),
      (
        t('kpiReturns'),
        figures['returns'],
        Icons.assignment_return_outlined,
        PicPosTone.warning,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PicPosPageHeader(
          title: t('navDashboard'),
          subtitle: t('dashboardSub'),
          icon: Icons.space_dashboard_outlined,
          actions: [
            IconButton(
              onPressed: widget.session.loggedIn ? _refresh : null,
              icon: const Icon(Icons.refresh),
              tooltip: t('refresh'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            children: [
              if (today != null) ...[
                Text('${t('asOf')}: ${today.asOf.toLocal()}'),
                if (stale)
                  StatusPill(
                    label: t('staleSnapshot'),
                    tone: PicPosTone.warning,
                  ),
              ],
              if (snapshots != null && snapshots.rejected > 0)
                Text(
                  t('unverifiedSnapshots'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (widget.session.loggedIn && (snapshots?.items.isEmpty ?? true))
                Text(t('noVerifiedData')),
              if (_error != null) Text('${t('requestFailed')}: $_error'),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= PicPosBreakpoints.expanded
                      ? 4
                      : 2;
                  final width =
                      (constraints.maxWidth -
                          PicPosSpacing.cardGap * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: PicPosSpacing.cardGap,
                    runSpacing: PicPosSpacing.cardGap,
                    children: [
                      for (final (label, figure, icon, tone) in kpis)
                        SizedBox(
                          width: width,
                          child: KpiCard(
                            label: label,
                            value: figure?.toString() ?? '—',
                            icon: icon,
                            tone: tone,
                            footnote: !widget.session.paired
                                ? t('kpiAfterPairing')
                                : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: PicPosSpacing.lg),
              PicPosBlock(
                title: t('cashBanks'),
                subtitle: t('cashBanksSub'),
                child: accounts == null
                    ? SizedBox(
                        height: 160,
                        child: EmptyState(
                          icon: widget.session.paired ? Icons.sync : Icons.link_off,
                          title: widget.session.paired
                              ? t('noVerifiedData')
                              : t('notPaired'),
                          message: widget.session.paired ? null : t('notPairedMsg'),
                        ),
                      )
                    : Column(
                        children: [
                          for (final account in accounts)
                            ListTile(
                              title: Text('${account['name']}'),
                              trailing: Text('${account['balance']}'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
