// J4 (الجزء ٣) — ربطُ حسابات الرواتب بدليل الحسابات (تفصيليّةٌ وحدَها)،
// ومركزُ تكلفةٍ لكلّ قسمٍ تحمله سطورُ المصروف في قيد المسيّر. الافتراضيُّ
// من الدليل القائم وربطِ الحسابات القديم. الحفظُ لـ`hr_payroll_edit`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';

class PayrollAccountsView extends ConsumerStatefulWidget {
  const PayrollAccountsView({super.key});

  @override
  ConsumerState<PayrollAccountsView> createState() =>
      _PayrollAccountsViewState();
}

class _PayrollAccountsViewState extends ConsumerState<PayrollAccountsView> {
  Map<String, String>? _codes;
  Map<int, int>? _centers;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final user = ref.read(authProvider).user?.id;
    try {
      if (_codes != null) await db.savePayrollAccounts(_codes!, userId: user);
      if (_centers != null) {
        await db.saveDepartmentCostCenters(_centers!, userId: user);
      }
      refreshPayroll(ref);
      if (mounted) AppToast.show(context, tr('تم حفظ ربط الحسابات'));
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        ref.watch(hasPermissionProvider(PermissionCodes.hrPayrollEdit)).value ??
            false;
    final accounts = ref.watch(payrollAccountsProvider).value;
    final options =
        ref.watch(payrollAccountOptionsProvider).value ?? const <PayrollAccountOption>[];
    final centers = ref.watch(payrollCostCentersProvider).value ?? const [];
    final deptCenters = ref.watch(payrollDeptCostCentersProvider).value;
    final departments =
        ref.watch(hrDepartmentsProvider).value ?? const <HrDepartment>[];
    if (accounts == null || deptCenters == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final codes = _codes ?? accounts.codes;
    final map = _centers ?? deptCenters;
    final items = {
      for (final o in options) o.code: '${o.code} — ${trData(o.name)}',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        HrSection(
          title: tr('حسابات الرواتب'),
          icon: PhosphorIconsBold.treeStructure,
          actions: [
            FilledButton.icon(
              key: const Key('payroll_accounts_save'),
              onPressed: canEdit && !_saving ? _save : null,
              icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
              label: Text(tr('حفظ')),
            ),
          ],
          child: HrFieldGrid(children: [
            for (final key in PayAccountKey.values)
              HrDropdown<String>(
                fieldKey: Key('payroll_account_$key'),
                label: payAccountKeyLabel(key),
                value: items.containsKey(codes[key]) ? codes[key] : null,
                emptyLabel: codes[key] ?? '—',
                items: items,
                onChanged: canEdit
                    ? (v) => setState(() => _codes = {
                          ...codes,
                          key: ?v,
                        })
                    : null,
              ),
          ]),
        ),
        const SizedBox(height: 12),
        HrSection(
          title: tr('مراكز التكلفة للأقسام'),
          icon: PhosphorIconsBold.chartPieSlice,
          child: departments.isEmpty
              ? Text(tr('لا أقسام بعد'),
                  style: TextStyle(color: context.picposMuted))
              : HrFieldGrid(children: [
                  for (final d in departments)
                    HrDropdown<int>(
                      fieldKey: Key('payroll_dept_cc_${d.id}'),
                      label: trData(d.name),
                      value: map[d.id],
                      emptyLabel: tr('بلا مركز تكلفة'),
                      items: {for (final c in centers) c.$1: trData(c.$2)},
                      onChanged: canEdit
                          ? (v) => setState(() {
                                final next = {...map};
                                if (v == null) {
                                  next.remove(d.id);
                                } else {
                                  next[d.id] = v;
                                }
                                _centers = next;
                              })
                          : null,
                    ),
                ]),
        ),
        const SizedBox(height: 8),
        Text(
          tr('القيد: من حـ/ المصروفات إلى حـ/ الرواتب والتأمينات والضريبة المستحقة وسلف الموظفين.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}
