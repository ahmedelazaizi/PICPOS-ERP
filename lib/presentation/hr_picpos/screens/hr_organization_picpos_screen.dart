// J4 — «الأقسام والمسميات الوظيفية» (PicPos): إدارةُ الأقسام (‏بقسمٍ أبٍ
// ومدير) والمسمّيات (‏بقسمها)، والهيكلُ التنظيميّ شجرةً بالمدير المباشر.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import 'hr_employee_file_screen.dart';

class HrOrganizationPicPosScreen extends ConsumerStatefulWidget {
  const HrOrganizationPicPosScreen({super.key});

  @override
  ConsumerState<HrOrganizationPicPosScreen> createState() =>
      _HrOrganizationPicPosScreenState();
}

class _HrOrganizationPicPosScreenState
    extends ConsumerState<HrOrganizationPicPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('الأقسام والمسميات الوظيفية'),
      subtitle: tr('هيكل المنشأة: الأقسام والمسميات والمدير المباشر'),
      icon: PhosphorIconsBold.treeStructure,
      subHeader: Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: context.picposMuted,
          tabs: [
            Tab(
                key: const Key('hr_org_tab_departments'),
                icon: const Icon(PhosphorIconsBold.buildings, size: 18),
                text: tr('الأقسام')),
            Tab(
                key: const Key('hr_org_tab_titles'),
                icon: const Icon(PhosphorIconsBold.briefcase, size: 18),
                text: tr('المسميات الوظيفية')),
            Tab(
                key: const Key('hr_org_tab_chart'),
                icon: const Icon(PhosphorIconsBold.treeStructure, size: 18),
                text: tr('الهيكل التنظيمي')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_DepartmentsTab(), _TitlesTab(), _OrgChartTab()],
      ),
    );
  }
}

bool _canManage(WidgetRef ref) =>
    ref.watch(hasPermissionProvider(PermissionCodes.hrManage)).value ?? false;

Future<bool> _guard(BuildContext context, WidgetRef ref,
    Future<void> Function() action) async {
  try {
    await action();
    refreshHr(ref);
    return true;
  } catch (e, st) {
    if (!context.mounted) return false;
    if (e is HrException) {
      AppToast.show(context, e.message, type: ToastType.error);
    } else {
      AppErrorHandler.handle(context, e, st);
    }
    return false;
  }
}

/// صفٌّ من قائمة: عنوانٌ وسطرٌ خافتٌ وعدّادُ موظفين وتعديلٌ وحذف.
class _OrgRow extends StatelessWidget {
  const _OrgRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.active,
    this.onEdit,
    this.onDelete,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final bool active;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: context.picposBrandInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted)),
          ]),
        ),
        if (!active) ...[
          HrPill(label: tr('غير نشط'), color: context.picposMuted),
          const SizedBox(width: 8),
        ],
        HrPill(
            label: tr('{p0} موظف', {'p0': count}),
            color: context.picposBrandInk,
            icon: PhosphorIconsBold.users),
        IconButton(
            tooltip: tr('تعديل'),
            onPressed: onEdit,
            icon: const Icon(PhosphorIconsBold.pencilSimple, size: 18)),
        IconButton(
            tooltip: tr('حذف'),
            onPressed: onDelete,
            icon: Icon(PhosphorIconsBold.trash,
                size: 18,
                color: onDelete == null
                    ? null
                    : Theme.of(context).colorScheme.error)),
      ]),
    );
  }
}

class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final people = ref.watch(hrProfilesProvider).value ?? const [];
    final names = {for (final p in people) p.id: p.name};
    final deptNames = {for (final d in departments) d.id: trData(d.name)};
    final canManage = _canManage(ref);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('الأقسام'),
          icon: PhosphorIconsBold.buildings,
          actions: [
            FilledButton.icon(
              key: const Key('hr_department_new'),
              onPressed: canManage
                  ? () => _departmentDialog(context, ref, departments, people)
                  : null,
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('قسم جديد')),
            ),
          ],
          child: departments.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.buildings,
                  title: tr('لا أقسام بعد'),
                  hint: tr('أضف أقسام المنشأة: المبيعات، المخازن، الحسابات…'),
                )
              : Column(children: [
                  for (final d in departments)
                    _OrgRow(
                      key: Key('hr_department_${d.id}'),
                      icon: PhosphorIconsBold.buildings,
                      title: [trData(d.name), if (d.code != null) d.code!]
                          .join(' · '),
                      subtitle: [
                        if (d.parentId != null)
                          tr('تابع لـ {p0}', {'p0': deptNames[d.parentId] ?? '—'}),
                        if (d.managerEmployeeId != null)
                          tr('المدير: {p0}',
                              {'p0': names[d.managerEmployeeId] ?? '—'}),
                      ].join('   '),
                      count: d.employeeCount,
                      active: d.isActive,
                      onEdit: canManage
                          ? () => _departmentDialog(
                              context, ref, departments, people,
                              department: d)
                          : null,
                      onDelete: canManage
                          ? () => _guard(context, ref,
                              () => ref.read(databaseProvider).deleteHrDepartment(d.id))
                          : null,
                    ),
                ]),
        ),
      ],
    );
  }
}

Future<void> _departmentDialog(BuildContext context, WidgetRef ref,
    List<HrDepartment> departments, List<EmployeeProfile> people,
    {HrDepartment? department}) async {
  final name = TextEditingController(text: department?.name ?? '');
  final nameEn = TextEditingController(text: department?.nameEn ?? '');
  final code = TextEditingController(text: department?.code ?? '');
  int? parentId = department?.parentId;
  int? managerId = department?.managerEmployeeId;
  var active = department?.isActive ?? true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => PicPosDialog(
        icon: PhosphorIconsBold.buildings,
        title: department == null ? tr('قسم جديد') : tr('تعديل القسم'),
        width: 620,
        onCancel: () => Navigator.pop(ctx),
        primaryAction: PicPosDialogAction(
          label: tr('حفظ'),
          icon: PhosphorIconsBold.check,
          onPressed: () async {
            final ok = await _guard(
                ctx,
                ref,
                () => ref.read(databaseProvider).saveHrDepartment(
                      id: department?.id,
                      name: name.text,
                      nameEn: nameEn.text,
                      code: code.text,
                      parentId: parentId,
                      managerEmployeeId: managerId,
                      isActive: active,
                    ));
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
        ),
        body: [
          HrFieldGrid(children: [
            HrTextField(
                fieldKey: const Key('hr_department_name'),
                label: tr('اسم القسم'),
                controller: name,
                required: true),
            HrTextField(
                label: tr('الاسم بالإنجليزية'),
                controller: nameEn,
                textDirection: TextDirection.ltr),
            HrTextField(label: tr('الكود'), controller: code),
            HrDropdown<int>(
              label: tr('القسم الأب'),
              value: parentId,
              emptyLabel: tr('بدون'),
              items: {
                for (final d in departments)
                  if (d.id != department?.id) d.id: trData(d.name),
              },
              onChanged: (v) => setState(() => parentId = v),
            ),
            HrDropdown<int>(
              label: tr('مدير القسم'),
              value: managerId,
              emptyLabel: tr('بدون'),
              items: {
                for (final p in people)
                  if (p.status != EmployeeStatus.terminated) p.id!: p.name,
              },
              onChanged: (v) => setState(() => managerId = v),
            ),
          ]),
          SwitchListTile(
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: Text(tr('نشط')),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
  );
}

class _TitlesTab extends ConsumerWidget {
  const _TitlesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(hrJobTitlesProvider).value ?? const [];
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final deptNames = {for (final d in departments) d.id: trData(d.name)};
    final canManage = _canManage(ref);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('المسميات الوظيفية'),
          icon: PhosphorIconsBold.briefcase,
          actions: [
            FilledButton.icon(
              key: const Key('hr_title_new'),
              onPressed: canManage
                  ? () => _titleDialog(context, ref, departments)
                  : null,
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('مسمى جديد')),
            ),
          ],
          child: titles.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.briefcase,
                  title: tr('لا مسميات بعد'),
                  hint: tr('مندوب مبيعات، كاشير، محاسب، أمين مخزن…'),
                )
              : Column(children: [
                  for (final t in titles)
                    _OrgRow(
                      key: Key('hr_title_${t.id}'),
                      icon: PhosphorIconsBold.briefcase,
                      title: trData(t.name),
                      subtitle: t.departmentId == null
                          ? tr('كل الأقسام')
                          : deptNames[t.departmentId] ?? '—',
                      count: t.employeeCount,
                      active: t.isActive,
                      onEdit: canManage
                          ? () => _titleDialog(context, ref, departments,
                              title: t)
                          : null,
                      onDelete: canManage
                          ? () => _guard(context, ref,
                              () => ref.read(databaseProvider).deleteHrJobTitle(t.id))
                          : null,
                    ),
                ]),
        ),
      ],
    );
  }
}

Future<void> _titleDialog(
    BuildContext context, WidgetRef ref, List<HrDepartment> departments,
    {HrJobTitle? title}) async {
  final name = TextEditingController(text: title?.name ?? '');
  final nameEn = TextEditingController(text: title?.nameEn ?? '');
  int? departmentId = title?.departmentId;
  var active = title?.isActive ?? true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => PicPosDialog(
        icon: PhosphorIconsBold.briefcase,
        title: title == null ? tr('مسمى جديد') : tr('تعديل المسمى'),
        width: 560,
        onCancel: () => Navigator.pop(ctx),
        primaryAction: PicPosDialogAction(
          label: tr('حفظ'),
          icon: PhosphorIconsBold.check,
          onPressed: () async {
            final ok = await _guard(
                ctx,
                ref,
                () => ref.read(databaseProvider).saveHrJobTitle(
                      id: title?.id,
                      name: name.text,
                      nameEn: nameEn.text,
                      departmentId: departmentId,
                      isActive: active,
                    ));
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
        ),
        body: [
          HrFieldGrid(children: [
            HrTextField(
                fieldKey: const Key('hr_title_name'),
                label: tr('المسمى'),
                controller: name,
                required: true),
            HrTextField(
                label: tr('الاسم بالإنجليزية'),
                controller: nameEn,
                textDirection: TextDirection.ltr),
            HrDropdown<int>(
              label: tr('القسم'),
              value: departmentId,
              emptyLabel: tr('كل الأقسام'),
              items: {for (final d in departments) d.id: trData(d.name)},
              onChanged: (v) => setState(() => departmentId = v),
            ),
          ]),
          SwitchListTile(
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: Text(tr('نشط')),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
  );
}

class _OrgChartTab extends ConsumerWidget {
  const _OrgChartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = [
      for (final p in ref.watch(hrProfilesProvider).value ?? const <EmployeeProfile>[])
        if (p.status != EmployeeStatus.terminated) p,
    ];
    final roots = buildOrgChart(people);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('الهيكل التنظيمي'),
          icon: PhosphorIconsBold.treeStructure,
          child: roots.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.treeStructure,
                  title: tr('لا موظفين بعد'),
                  hint: tr('حدّد المدير المباشر في ملف كل موظف ليظهر الهيكل'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in roots) _OrgNode(node: r, depth: 0),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OrgNode extends StatelessWidget {
  const _OrgNode({required this.node, required this.depth});
  final OrgChartNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final p = node.employee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: depth * 28.0, bottom: 6),
          child: InkWell(
            key: Key('hr_org_node_${p.id}'),
            borderRadius: BorderRadius.circular(11),
            onTap: () => openEmployeeFile(context, employeeId: p.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: depth == 0 ? context.picposField : context.picposCard,
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(children: [
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                    node.reports.isEmpty
                        ? PhosphorIconsBold.user
                        : PhosphorIconsBold.usersThree,
                    size: 16,
                    color: context.picposBrandInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      p.name,
                      if (p.jobTitleName != null) trData(p.jobTitleName!),
                      if (p.departmentName != null) trData(p.departmentName!),
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.picposText),
                  ),
                ),
                if (node.reports.isNotEmpty)
                  HrPill(
                      label: tr('{p0} تابع', {'p0': node.reports.length}),
                      color: context.picposBrandInk),
                const SizedBox(width: 6),
                HrPill(
                    label: hrStatusLabel(p.status),
                    color: hrStatusColor(context, p.status)),
              ]),
            ),
          ),
        ),
        for (final r in node.reports) _OrgNode(node: r, depth: depth + 1),
      ],
    );
  }
}
