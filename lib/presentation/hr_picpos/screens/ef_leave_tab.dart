// J4 (الجزء ٢) — تبويبُ «الإجازات» في ملفّ الموظف: أرصدتُه السنويّة وطلباتُه
// بدورتها، وطلبٌ جديدٌ باسمه.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../widgets/leave_balances_view.dart';
import '../widgets/leave_requests_view.dart';

class EfLeaveTab extends StatelessWidget {
  const EfLeaveTab({super.key, required this.employeeId});
  final int? employeeId;

  @override
  Widget build(BuildContext context) {
    final id = employeeId;
    if (id == null) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.airplaneTilt,
        title: tr('احفظ الموظف أولاً'),
        hint: tr('تظهر الإجازات بعد حفظ ملف الموظف'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Expanded(
          flex: 2,
          child: LeaveBalancesView(employeeId: id, compact: true),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 3,
          child: LeaveRequestsView(employeeId: id, compact: true),
        ),
      ]),
    );
  }
}
