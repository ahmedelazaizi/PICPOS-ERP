// J4 (الجزء ٢) — «الورديات» (PicPos): تعريفُ الورديّات، وإسنادُها لكلّ
// موظفٍ بتاريخ سريانٍ وسجلٍّ محفوظ، والإسنادُ الجماعيُّ بالقسم أو الفرع.
// محروسةٌ بـ`hr_shifts_manage`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import '../widgets/hr_table.dart';
import '../widgets/shift_dialogs.dart';

class HrShiftsPicPosScreen extends ConsumerStatefulWidget {
  const HrShiftsPicPosScreen({super.key});

  @override
  ConsumerState<HrShiftsPicPosScreen> createState() =>
      _HrShiftsPicPosScreenState();
}

class _HrShiftsPicPosScreenState extends ConsumerState<HrShiftsPicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  int? _departmentId;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _editShift([WorkShift? s]) async {
    if (await showShiftDialog(context, shift: s) && mounted) {
      refreshHrAttendance(ref);
    }
  }

  Future<void> _deleteShift(WorkShift s) async {
    try {
      await ref.read(databaseProvider).deleteWorkShift(s.id!);
      refreshHrAttendance(ref);
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    }
  }

  Future<void> _assign({EmployeeProfile? p}) async {
    if (await showShiftAssignDialog(context,
            employeeId: p?.id, employeeName: p?.name) &&
        mounted) {
      refreshHrAttendance(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        ref.watch(hasPermissionProvider(PermissionCodes.hrShiftsManage)).value ??
            false;
    return PicPosScreenScaffold(
      title: tr('الورديات'),
      subtitle: tr('أوقات العمل والراحة الأسبوعية وإسنادها للموظفين'),
      icon: PhosphorIconsBold.clockClockwise,
      bodyPadding: EdgeInsets.zero,
      headerActions: [
        OutlinedButton.icon(
          key: const Key('shifts_bulk_assign'),
          onPressed: canManage ? () => _assign() : null,
          icon: const Icon(PhosphorIconsBold.usersThree, size: 16),
          label: Text(tr('إسناد جماعي')),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('shifts_new'),
          onPressed: canManage ? () => _editShift() : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('وردية جديدة')),
        ),
      ],
      subHeader: HrTabBar(controller: _tabs, tabs: [
        ('shifts_tab_list', PhosphorIconsBold.clockClockwise, tr('الورديات')),
        ('shifts_tab_assign', PhosphorIconsBold.userSwitch, tr('إسناد الموظفين')),
      ]),
      body: TabBarView(controller: _tabs, children: [
        _shiftsTab(context, canManage),
        _assignTab(context, canManage),
      ]),
    );
  }

  Widget _shiftsTab(BuildContext context, bool canManage) {
    final shifts = ref.watch(hrShiftsProvider).value ?? const <WorkShift>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: HrTable(
        minWidth: 980,
        emptyIcon: PhosphorIconsBold.clockClockwise,
        emptyTitle: tr('لا ورديات بعد'),
        emptyHint: tr('عرّف أول وردية بأوقاتها وأيام راحتها'),
        columns: [
          HrTableColumn(tr('الوردية'), flex: 3),
          HrTableColumn(tr('الأوقات'), flex: 3),
          HrTableColumn(tr('الاستراحة')),
          HrTableColumn(tr('السماح')),
          HrTableColumn(tr('الإضافي بعد')),
          HrTableColumn(tr('أيام الراحة'), flex: 3),
          HrTableColumn(tr('الموظفون')),
          HrTableColumn(tr('الحالة')),
          const HrTableColumn('', flex: 1),
        ],
        rows: [
          for (final s in shifts)
            HrTableRow(
              key: Key('shift_row_${s.id}'),
              onTap: canManage ? () => _editShift(s) : null,
              cells: [
                HrCellText(trData(s.name), sub: s.nameEn),
                HrCellText(shiftTimesLabel(s),
                    number: true,
                    sub: tr('{p0} ساعة عمل',
                        {'p0': hrMinutes(s.scheduledMinutes)})),
                HrCellText(tr('{p0} د', {'p0': s.breakMinutes}), number: true),
                HrCellText(tr('{p0} د', {'p0': s.graceLateMinutes}),
                    number: true),
                HrCellText(tr('{p0} د', {'p0': s.overtimeAfterMinutes}),
                    number: true),
                HrCellText(s.daysOff.isEmpty
                    ? '—'
                    : [
                        for (final d in kHrWeekOrder)
                          if (s.daysOff.contains(d)) hrWeekdayLabel(d),
                      ].join('، ')),
                HrCellText('${s.employeeCount}', number: true),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: HrPill(
                    label: s.isActive ? tr('فعالة') : tr('موقوفة'),
                    color: s.isActive
                        ? AppColors.statusSuccess(context)
                        : context.picposMuted,
                  ),
                ),
                if (canManage)
                  IconButton(
                    tooltip: tr('حذف'),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    iconSize: 16,
                    onPressed: () => _deleteShift(s),
                    icon: Icon(PhosphorIconsBold.trash,
                        color: AppColors.statusError(context)),
                  )
                else
                  const SizedBox(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _assignTab(BuildContext context, bool canManage) {
    final profiles = [
      for (final p in ref.watch(hrProfilesProvider).value ??
          const <EmployeeProfile>[])
        if (p.status != EmployeeStatus.terminated &&
            (_departmentId == null || p.departmentId == _departmentId))
          p,
    ];
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final assignments =
        ref.watch(hrShiftAssignmentsProvider(null)).value ?? const [];
    final today = hrDay(DateTime.now());
    final current = <int, ShiftAssignment>{
      for (final a in assignments)
        if (a.covers(today)) a.employeeId: a,
    };
    final history = <int, int>{};
    for (final a in assignments) {
      history[a.employeeId] = (history[a.employeeId] ?? 0) + 1;
    }
    return Column(children: [
      HrToolbar(children: [
        SizedBox(
          width: 200,
          child: HrDropdown<int>(
            fieldKey: const Key('shifts_filter_department'),
            label: tr('القسم'),
            value: _departmentId,
            emptyLabel: tr('الكل'),
            items: {for (final d in departments) d.id: trData(d.name)},
            onChanged: (v) => setState(() => _departmentId = v),
          ),
        ),
        HrPill(
          label: tr('{p0} بلا وردية',
              {'p0': profiles.where((p) => !current.containsKey(p.id)).length}),
          color: AppColors.statusWarning(context),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 900,
            emptyIcon: PhosphorIconsBold.usersThree,
            emptyTitle: tr('لا موظفين بعد'),
            columns: [
              HrTableColumn(tr('الموظف'), flex: 4),
              HrTableColumn(tr('القسم'), flex: 3),
              HrTableColumn(tr('الوردية الحالية'), flex: 4),
              HrTableColumn(tr('منذ')),
              HrTableColumn(tr('السجل')),
              const HrTableColumn('', flex: 2),
            ],
            rows: [
              for (final p in profiles)
                HrTableRow(
                  key: Key('assign_row_${p.id}'),
                  onTap: () => _showHistory(p),
                  cells: [
                    HrCellText(p.name, sub: p.code),
                    HrCellText(p.departmentName == null
                        ? '—'
                        : trData(p.departmentName!)),
                    HrCellText(
                        current[p.id]?.shiftName == null
                            ? tr('بلا وردية')
                            : trData(current[p.id]!.shiftName!),
                        color: current.containsKey(p.id)
                            ? null
                            : context.picposMuted),
                    HrCellText(hrDate(current[p.id]?.effectiveFrom),
                        number: true),
                    HrCellText(tr('{p0} إسناد', {'p0': history[p.id] ?? 0})),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: Key('assign_btn_${p.id}'),
                        onPressed: canManage ? () => _assign(p: p) : null,
                        icon: const Icon(PhosphorIconsBold.userSwitch, size: 15),
                        label: Text(tr('إسناد')),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _showHistory(EmployeeProfile p) async {
    final rows = await ref
        .read(databaseProvider)
        .listShiftAssignments(employeeId: p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('سجل ورديات {p0}', {'p0': p.name})),
        content: SizedBox(
          width: 460,
          child: rows.isEmpty
              ? Text(tr('لم تُسند له وردية بعد'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in rows)
                      HrInfoLine(
                        icon: PhosphorIconsBold.clockClockwise,
                        label: trData(a.shiftName ?? '—'),
                        value: a.effectiveTo == null
                            ? tr('من {p0} — حتى الآن',
                                {'p0': hrDate(a.effectiveFrom)})
                            : '${hrDate(a.effectiveFrom)} → '
                                '${hrDate(a.effectiveTo)}',
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('إغلاق'))),
        ],
      ),
    );
  }
}
