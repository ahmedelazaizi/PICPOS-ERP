// J4 (الجزء ٢) — «الإجازات» (PicPos): الطلباتُ بدورتها (مسودة → مقدَّم →
// معتمد/مرفوض، والإلغاء)، والأرصدةُ السنويّة لكلّ موظف، وأنواعُ الإجازات.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/hr_table.dart';
import '../widgets/leave_balances_view.dart';
import '../widgets/leave_requests_view.dart';
import '../widgets/leave_types_view.dart';

class HrLeavePicPosScreen extends StatefulWidget {
  const HrLeavePicPosScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HrLeavePicPosScreen> createState() => _HrLeavePicPosScreenState();
}

class _HrLeavePicPosScreenState extends State<HrLeavePicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('الإجازات'),
      subtitle: tr('طلبات الإجازة واعتمادها والأرصدة السنوية'),
      icon: PhosphorIconsBold.airplaneTilt,
      bodyPadding: EdgeInsets.zero,
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('leave_tab_requests', PhosphorIconsBold.listChecks, tr('الطلبات')),
        ('leave_tab_balances', PhosphorIconsBold.scales, tr('الأرصدة')),
        ('leave_tab_types', PhosphorIconsBold.listBullets, tr('أنواع الإجازات')),
      ]),
      body: TabBarView(controller: _tabs, children: const [
        LeaveRequestsView(),
        LeaveBalancesView(),
        LeaveTypesView(),
      ]),
    );
  }
}
