// J4 (الجزء ٣) — «عمولات المندوبين» (PicPos): خططُ العمولة (افتراضيّةٌ أو
// لمندوب: نسبةُ صافي المبيعات بعد المرتجعات ونسبةُ التحصيلات وشرائحُ تحقيق
// الهدف ونسبُ الفئات)، وكشفُ عمولة الشهر بمستنداته المختومة.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/commission_plans_view.dart';
import '../widgets/commission_statement_view.dart';
import '../widgets/hr_table.dart';

class HrCommissionsPicPosScreen extends StatefulWidget {
  const HrCommissionsPicPosScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HrCommissionsPicPosScreen> createState() =>
      _HrCommissionsPicPosScreenState();
}

class _HrCommissionsPicPosScreenState extends State<HrCommissionsPicPosScreen>
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
      title: tr('عمولات المندوبين'),
      subtitle: tr('خطط العمولة وكشف عمولة كل مندوب من مستنداته'),
      icon: PhosphorIconsBold.percent,
      bodyPadding: EdgeInsets.zero,
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('commission_tab_plans', PhosphorIconsBold.listBullets,
            tr('خطط العمولة')),
        ('commission_tab_statement', PhosphorIconsBold.fileText,
            tr('كشف العمولة')),
      ]),
      body: TabBarView(controller: _tabs, children: const [
        CommissionPlansView(),
        CommissionStatementView(),
      ]),
    );
  }
}
