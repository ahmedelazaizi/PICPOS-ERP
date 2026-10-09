import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../admin_session.dart';
import '../l10n/strings.dart';
import '../screens/approvals_page.dart';
import '../screens/dashboard_page.dart';
import '../screens/placeholder_page.dart';
import '../screens/settings_page.dart';

/// M-A screen map (ARCHITECTURE-M §3.1): bottom bar on phones (Notifications
/// and Settings under «المزيد»), navigation rail with all six on tablets.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.session,
    this.initialIndex = 0,
    required this.onOpenPairing,
  });
  final int initialIndex;
  final AdminSession session;
  final VoidCallback onOpenPairing;

  static const destinationCount = 6;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final pages = <Widget>[
      DashboardPage(session: widget.session),
      ApprovalsPage(session: widget.session),
      PlaceholderPage(
        title: t('navReports'),
        subtitle: t('reportsSub'),
        icon: Icons.analytics_outlined,
        message: t('reportsComing'),
      ),
      PlaceholderPage(
        title: t('navOperations'),
        subtitle: t('operationsSub'),
        icon: Icons.receipt_long_outlined,
        message: t('operationsComing'),
      ),
      PlaceholderPage(
        title: t('navNotifications'),
        subtitle: t('notificationsSub'),
        icon: Icons.notifications_outlined,
        message: t('notificationsComing'),
      ),
      SettingsPage(session: widget.session, onOpenPairing: widget.onOpenPairing),
    ];
    return PicPosAdaptiveScaffold(
      selectedIndex: _index,
      onSelected: (i) => setState(() => _index = i),
      railLeading: const _Wordmark(),
      destinations: [
        PicPosDestination(
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard,
          label: t('navDashboard'),
        ),
        PicPosDestination(
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check,
          label: t('navApprovals'),
        ),
        PicPosDestination(
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          label: t('navReports'),
        ),
        PicPosDestination(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: t('navOperations'),
        ),
        PicPosDestination(
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications,
          label: t('navNotifications'),
        ),
        PicPosDestination(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: t('navSettings'),
        ),
      ],
      body: pages[_index],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PicPosSpacing.md),
      child: Text(
        'PicPos',
        textDirection: TextDirection.ltr,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: context.picposBrandInk,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
