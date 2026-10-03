// J4 (الجزء ٣) — «السلف والجزاءات» (PicPos): السلفُ والقروضُ بأقساطها
// ورصيدها (تُصرف بسند صرفٍ وتُسدَّد مبكّراً بسند قبض)، والمكافآتُ والجزاءاتُ
// لمرّةٍ واحدةٍ بسببٍ واعتماد.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/advances_view.dart';
import '../widgets/hr_table.dart';
import '../widgets/payroll_adjustments_view.dart';

class HrAdvancesPicPosScreen extends StatefulWidget {
  const HrAdvancesPicPosScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HrAdvancesPicPosScreen> createState() => _HrAdvancesPicPosScreenState();
}

class _HrAdvancesPicPosScreenState extends State<HrAdvancesPicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('السلف والجزاءات'),
      subtitle: tr('سلف الموظفين وقروضهم وأقساطها، والمكافآت والجزاءات'),
      icon: PhosphorIconsBold.handCoins,
      bodyPadding: EdgeInsets.zero,
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('advances_tab_list', PhosphorIconsBold.handCoins, tr('السلف والقروض')),
        ('advances_tab_adjustments', PhosphorIconsBold.scales,
            tr('المكافآت والجزاءات')),
      ]),
      body: TabBarView(controller: _tabs, children: const [
        AdvancesView(),
        PayrollAdjustmentsView(),
      ]),
    );
  }
}
