// J4 (الجزء ٣) — قائمةُ المسيّرات: شهرٌ ونطاقٌ (فرعٌ أو قسمٌ أو الكلّ)
// ومجاميعُ وحالة، ومسيّرٌ جديدٌ يُحتسب فوراً (‏`hr_payroll_edit`). المسيّراتُ
// المنقولةُ من الشاشة القديمة للقراءة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import '../screens/payroll_run_screen.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class PayrollRunsView extends ConsumerWidget {
  const PayrollRunsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(payrollRunsProvider).value ?? const <PayrollRun>[];
    final canEdit =
        ref.watch(hasPermissionProvider(PermissionCodes.hrPayrollEdit)).value ??
            false;
    final branchList = ref.watch(hrBranchesProvider).value;
    final branches = {
      if (branchList != null)
        for (final b in branchList) b.id: b.name,
    };
    final departments = {
      for (final d in ref.watch(hrDepartmentsProvider).value ??
          const <HrDepartment>[])
        d.id: d.name,
    };
    String scope(PayrollRun r) => [
          if (r.branchId != null) trData(branches[r.branchId] ?? ''),
          if (r.departmentId != null) trData(departments[r.departmentId] ?? ''),
        ].where((s) => s.isNotEmpty).join(' · ');

    Future<void> create() async {
      final id = await showDialog<int>(
          context: context, builder: (_) => const _NewRunDialog());
      if (id == null) return;
      refreshPayroll(ref);
      if (context.mounted) await openPayrollRun(context, id);
      refreshPayroll(ref);
    }

    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('payroll_run_new'),
          onPressed: canEdit ? create : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('مسير جديد')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 1000,
            emptyIcon: PhosphorIconsBold.money,
            emptyTitle: tr('لا مسيرات رواتب بعد'),
            emptyHint: tr('أنشئ مسير الشهر ليُحتسب من الحضور والبدلات والعمولات'),
            columns: [
              HrTableColumn(tr('الشهر')),
              HrTableColumn(tr('النطاق'), flex: 3),
              HrTableColumn(tr('الموظفون')),
              HrTableColumn(tr('الإجمالي')),
              HrTableColumn(tr('الخصومات')),
              HrTableColumn(tr('الصافي')),
              HrTableColumn(tr('المصروف')),
              HrTableColumn(tr('الحالة')),
            ],
            rows: [
              for (final r in runs)
                HrTableRow(
                  key: Key('payroll_run_row_${r.id}'),
                  onTap: () async {
                    await openPayrollRun(context, r.id);
                    refreshPayroll(ref);
                  },
                  cells: [
                    HrCellText(r.period,
                        number: true, sub: r.legacy ? tr('مرحَّل من النظام القديم') : null),
                    HrCellText(scope(r).isEmpty ? tr('كل الموظفين') : scope(r)),
                    HrCellText('${r.employeeCount}', number: true),
                    HrCellText(hrMoney(r.gross), number: true),
                    HrCellText(hrMoney(r.deductions), number: true),
                    HrCellText(hrMoney(r.net), number: true),
                    HrCellText(hrMoney(r.paid), number: true),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: payrollStatusLabel(r.status),
                        color: payrollStatusColor(context, r.status),
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
}

class _NewRunDialog extends ConsumerStatefulWidget {
  const _NewRunDialog();

  @override
  ConsumerState<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends ConsumerState<_NewRunDialog> {
  late DateTime _month = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();
  int? _branch;
  int? _department;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(databaseProvider).createPayrollRun(
            year: _month.year,
            month: _month.month,
            branchId: _branch,
            departmentId: _department,
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(id);
    } on HrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(hrBranchesProvider).value ?? const [];
    final departments =
        ref.watch(hrDepartmentsProvider).value ?? const <HrDepartment>[];
    return PicPosDialog(
      icon: PhosphorIconsBold.money,
      title: tr('مسير رواتب جديد'),
      width: 620,
      onCancel: () => Navigator.of(context).pop(),
      primaryAction: PicPosDialogAction(
        label: tr('إنشاء واحتساب'),
        icon: PhosphorIconsBold.calculator,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        HrLabeled(
          label: tr('الشهر'),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: HrStepper(
              keyPrefix: 'payroll_new_month',
              label: hrPeriod(_month.year, _month.month),
              onPrev: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ),
        ),
        PicPosDialogRow(children: [
          HrDropdown<int>(
            fieldKey: const Key('payroll_new_branch'),
            label: tr('الفرع'),
            value: _branch,
            emptyLabel: tr('كل الفروع'),
            items: {for (final b in branches) b.id: trData(b.name)},
            onChanged: (v) => setState(() => _branch = v),
          ),
          HrDropdown<int>(
            fieldKey: const Key('payroll_new_department'),
            label: tr('القسم'),
            value: _department,
            emptyLabel: tr('كل الأقسام'),
            items: {for (final d in departments) d.id: trData(d.name)},
            onChanged: (v) => setState(() => _department = v),
          ),
        ]),
        Text(
          tr('يُحتسب كل موظف من حضوره وبدلاته وعمولته ومكافآته وجزاءاته وأقساط سلفه.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}
