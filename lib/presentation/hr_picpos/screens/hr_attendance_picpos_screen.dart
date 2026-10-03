// J4 (الجزء ٢) — «الحضور والانصراف» (PicPos): اللوحةُ اليوميّة بمرشّحَي
// الفرع والقسم والتصحيحِ اليدويّ و«تحضير الكلّ» واستيرادِ البصمة، والكشفُ
// الشهريُّ لكلّ موظفٍ بمجاميعه، وتقويمُ العطلات الرسميّة.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/attendance_board_view.dart';
import '../widgets/attendance_month_view.dart';
import '../widgets/hr_holidays_view.dart';
import '../widgets/hr_table.dart';

class HrAttendancePicPosScreen extends StatefulWidget {
  const HrAttendancePicPosScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HrAttendancePicPosScreen> createState() =>
      _HrAttendancePicPosScreenState();
}

class _HrAttendancePicPosScreenState extends State<HrAttendancePicPosScreen>
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
      title: tr('الحضور والانصراف'),
      subtitle: tr('اللوحة اليومية والكشف الشهري والعطلات الرسمية'),
      icon: PhosphorIconsBold.fingerprint,
      bodyPadding: EdgeInsets.zero,
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('att_tab_board', PhosphorIconsBold.listChecks, tr('اللوحة اليومية')),
        ('att_tab_month', PhosphorIconsBold.calendarDots, tr('الكشف الشهري')),
        ('att_tab_holidays', PhosphorIconsBold.confetti, tr('العطلات الرسمية')),
      ]),
      body: TabBarView(
        controller: _tabs,
        children: const [
          AttendanceBoardView(),
          AttendanceMonthView(),
          HrHolidaysView(),
        ],
      ),
    );
  }
}
