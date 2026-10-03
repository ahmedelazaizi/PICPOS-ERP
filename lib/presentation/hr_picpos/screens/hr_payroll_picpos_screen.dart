// J4 (الجزء ٣) — «الرواتب» (PicPos): المسيّراتُ الشهريّة بدورتها (مسودة →
// مراجَع → معتمد → مرحَّل → مدفوع، أو معكوس)، وبنودُ الراتب، وقواعدُ
// الاحتساب (الغياب والتأخير والإضافيّ والتأمينات والضريبة)، وربطُ الحسابات.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/hr_table.dart';
import '../widgets/payroll_accounts_view.dart';
import '../widgets/payroll_components_view.dart';
import '../widgets/payroll_rules_view.dart';
import '../widgets/payroll_runs_view.dart';

class HrPayrollPicPosScreen extends StatefulWidget {
  const HrPayrollPicPosScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HrPayrollPicPosScreen> createState() => _HrPayrollPicPosScreenState();
}

class _HrPayrollPicPosScreenState extends State<HrPayrollPicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('الرواتب'),
      subtitle: tr('مسيرات الرواتب الشهرية وقسائم الموظفين وإعدادات الاحتساب'),
      icon: PhosphorIconsBold.money,
      bodyPadding: EdgeInsets.zero,
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('payroll_tab_runs', PhosphorIconsBold.listChecks, tr('المسيرات')),
        ('payroll_tab_components', PhosphorIconsBold.stack, tr('بنود الراتب')),
        ('payroll_tab_rules', PhosphorIconsBold.sliders, tr('قواعد الاحتساب')),
        ('payroll_tab_accounts', PhosphorIconsBold.treeStructure,
            tr('ربط الحسابات')),
      ]),
      body: TabBarView(controller: _tabs, children: const [
        PayrollRunsView(),
        PayrollComponentsView(),
        PayrollRulesView(),
        PayrollAccountsView(),
      ]),
    );
  }
}
