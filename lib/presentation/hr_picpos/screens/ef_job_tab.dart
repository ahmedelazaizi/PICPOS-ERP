// J4 — تبويبُ «البيانات الوظيفية»: الكود والقسم والمسمّى والفرع والمدير
// المباشر وتاريخ التعيين ونوع التوظيف والحالة (وإنهاءُ الخدمة بتاريخٍ وسبب).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import 'employee_file_form.dart';

class EfJobTab extends ConsumerWidget {
  const EfJobTab({super.key, required this.form});
  final EmployeeFileForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final titles = ref.watch(hrJobTitlesProvider).value ?? const [];
    final branches = ref.watch(hrBranchesProvider).value ?? const [];
    final people = ref.watch(hrProfilesProvider).value ?? const [];
    return ListenableBuilder(
      listenable: form,
      builder: (context, _) {
        final selfId = form.source?.id;
        final titlesForDept = [
          for (final t in titles)
            if (t.isActive || t.id == form.jobTitleId)
              if (form.departmentId == null ||
                  t.departmentId == null ||
                  t.departmentId == form.departmentId)
                t,
        ];
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            HrSection(
              title: tr('الوظيفة'),
              icon: PhosphorIconsBold.briefcase,
              child: HrFieldGrid(children: [
                HrTextField(
                  fieldKey: const Key('ef_code'),
                  label: tr('كود الموظف'),
                  controller: form.code,
                  hint: tr('يُولَّد تلقائياً'),
                  textDirection: TextDirection.ltr,
                ),
                HrDropdown<int>(
                  fieldKey: const Key('ef_department'),
                  label: tr('القسم'),
                  value: form.departmentId,
                  emptyLabel: tr('بدون قسم'),
                  items: {
                    for (final d in departments)
                      if (d.isActive || d.id == form.departmentId)
                        d.id: trData(d.name),
                  },
                  onChanged: (v) => form.set(() {
                    form.departmentId = v;
                    // مسمّى قسمٍ آخرَ يسقط مع تغيير القسم.
                    final title = titles
                        .where((t) => t.id == form.jobTitleId)
                        .firstOrNull;
                    if (v != null &&
                        title?.departmentId != null &&
                        title!.departmentId != v) {
                      form.jobTitleId = null;
                    }
                  }),
                ),
                HrDropdown<int>(
                  fieldKey: const Key('ef_job_title'),
                  label: tr('المسمى الوظيفي'),
                  value: form.jobTitleId,
                  emptyLabel: tr('بدون مسمى'),
                  items: {for (final t in titlesForDept) t.id: trData(t.name)},
                  onChanged: (v) => form.set(() => form.jobTitleId = v),
                ),
                HrDropdown<int>(
                  fieldKey: const Key('ef_branch'),
                  label: tr('الفرع'),
                  value: form.branchId,
                  emptyLabel: tr('بدون فرع'),
                  items: {for (final b in branches) b.id: trData(b.name)},
                  onChanged: (v) => form.set(() => form.branchId = v),
                ),
                HrDropdown<int>(
                  fieldKey: const Key('ef_manager'),
                  label: tr('المدير المباشر'),
                  value: form.managerId,
                  emptyLabel: tr('بدون مدير'),
                  items: {
                    for (final p in people)
                      if (p.id != selfId &&
                          p.status != EmployeeStatus.terminated)
                        p.id!: p.name,
                  },
                  onChanged: (v) => form.set(() => form.managerId = v),
                ),
                HrDateField(
                  label: tr('تاريخ التعيين'),
                  value: form.hireDate,
                  required: true,
                  onChanged: (v) => form.set(() => form.hireDate = v),
                ),
                HrDropdown<String>(
                  fieldKey: const Key('ef_employment_type'),
                  label: tr('نوع التوظيف'),
                  value: form.employmentType,
                  items: {
                    for (final t in EmploymentType.values)
                      t: hrEmploymentTypeLabel(t),
                  },
                  onChanged: (v) => form.set(
                      () => form.employmentType = v ?? EmploymentType.fullTime),
                ),
              ]),
            ),
            HrSection(
              title: tr('حالة الموظف'),
              icon: PhosphorIconsBold.userSwitch,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in EmployeeStatus.values)
                      ChoiceChip(
                        key: Key('ef_status_$s'),
                        label: Text(hrStatusLabel(s)),
                        selected: form.status == s,
                        onSelected: (_) => form.set(() {
                          form.status = s;
                          if (s == EmployeeStatus.terminated) {
                            form.terminationDate ??= DateTime.now();
                          }
                        }),
                      ),
                  ]),
                  if (form.status == EmployeeStatus.terminated) ...[
                    const SizedBox(height: 12),
                    HrFieldGrid(wide: const {1}, children: [
                      HrDateField(
                        fieldKey: const Key('ef_termination_date'),
                        label: tr('تاريخ إنهاء الخدمة'),
                        value: form.terminationDate,
                        required: true,
                        onChanged: (v) =>
                            form.set(() => form.terminationDate = v),
                      ),
                      HrTextField(
                        fieldKey: const Key('ef_termination_reason'),
                        label: tr('سبب إنهاء الخدمة'),
                        controller: form.terminationReason,
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
