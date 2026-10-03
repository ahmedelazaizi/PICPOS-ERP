// J4 — «سجل الموظفين» (PicPos): جدولُ الموظفين بمرشّحات القسم والمسمّى
// والفرع والحالة والدور وبحثٍ بالاسم والكود والهاتف، وتنبيهُ المستندات
// المنتهية، ومنه يُفتح «ملف الموظف» أو يُنشأ موظفٌ جديد.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import 'hr_employee_file_screen.dart';

class HrEmployeesPicPosScreen extends ConsumerStatefulWidget {
  const HrEmployeesPicPosScreen({super.key});

  @override
  ConsumerState<HrEmployeesPicPosScreen> createState() =>
      _HrEmployeesPicPosScreenState();
}

class _HrEmployeesPicPosScreenState
    extends ConsumerState<HrEmployeesPicPosScreen> {
  EmployeeListFilter _filter = const EmployeeListFilter();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(int? id) async {
    await openEmployeeFile(context, employeeId: id);
    if (mounted) refreshHr(ref, id);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(hrProfilesProvider).value ?? const [];
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final titles = ref.watch(hrJobTitlesProvider).value ?? const [];
    final branches = ref.watch(hrBranchesProvider).value ?? const [];
    final expiring = ref.watch(hrExpiringDocsProvider).value ?? const {};
    final canManage =
        ref.watch(hasPermissionProvider(PermissionCodes.hrManage)).value ??
            false;
    final rows = [for (final p in all) if (_filter.matches(p)) p];
    int count(String s) => all.where((p) => p.status == s).length;

    Widget filter<T>(String key, String label, T? value, Map<T, String> items,
            void Function(T?) set) =>
        SizedBox(
          width: 190,
          child: HrDropdown<T>(
            fieldKey: Key('hr_filter_$key'),
            label: label,
            value: value,
            emptyLabel: tr('الكل'),
            items: items,
            onChanged: (v) => setState(() => set(v)),
          ),
        );

    return PicPosScreenScaffold(
      title: tr('سجل الموظفين'),
      subtitle: tr('ملفات الموظفين ووظائفهم وأدوارهم في النظام'),
      icon: PhosphorIconsBold.identificationCard,
      headerSearch: TextField(
        key: const Key('hr_search'),
        controller: _search,
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('بحث بالاسم أو الكود أو الهاتف'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
        ),
        onChanged: (v) =>
            setState(() => _filter = _filter.copyWith(query: v)),
      ),
      headerActions: [
        FilledButton.icon(
          key: const Key('hr_new_employee'),
          onPressed: canManage ? () => _open(null) : null,
          icon: const Icon(PhosphorIconsBold.userPlus, size: 16),
          label: Text(tr('موظف جديد')),
        ),
      ],
      subHeader: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            filter<int>(
              'department',
              tr('القسم'),
              _filter.departmentId,
              {for (final d in departments) d.id: trData(d.name)},
              (v) => _filter = _filter.copyWith(departmentId: () => v),
            ),
            filter<int>(
              'title',
              tr('المسمى الوظيفي'),
              _filter.jobTitleId,
              {for (final t in titles) t.id: trData(t.name)},
              (v) => _filter = _filter.copyWith(jobTitleId: () => v),
            ),
            filter<int>(
              'branch',
              tr('الفرع'),
              _filter.branchId,
              {for (final b in branches) b.id: trData(b.name)},
              (v) => _filter = _filter.copyWith(branchId: () => v),
            ),
            filter<String>(
              'status',
              tr('الحالة'),
              _filter.status,
              {for (final s in EmployeeStatus.values) s: hrStatusLabel(s)},
              (v) => _filter = _filter.copyWith(status: () => v),
            ),
            filter<String>(
              'role',
              tr('الدور'),
              _filter.roleTag,
              {for (final t in HrRoleTag.values) t: hrRoleTagLabel(t)},
              (v) => _filter = _filter.copyWith(roleTag: () => v),
            ),
            if (!_filter.isEmpty)
              TextButton.icon(
                key: const Key('hr_filter_clear'),
                onPressed: () => setState(() {
                  _search.clear();
                  _filter = const EmployeeListFilter();
                }),
                icon: const Icon(PhosphorIconsBold.x, size: 14),
                label: Text(tr('مسح المرشحات')),
              ),
            Wrap(spacing: 6, children: [
              HrPill(
                  label: tr('{p0} نشط', {'p0': count(EmployeeStatus.active)}),
                  color: AppColors.statusSuccess(context)),
              HrPill(
                  label:
                      tr('{p0} موقوف', {'p0': count(EmployeeStatus.suspended)}),
                  color: AppColors.statusWarning(context)),
              HrPill(
                  label: tr('{p0} منتهي الخدمة',
                      {'p0': count(EmployeeStatus.terminated)}),
                  color: AppColors.statusError(context)),
            ]),
          ],
        ),
      ),
      body: all.isEmpty
          ? PicPosEmptyState(
              icon: PhosphorIconsBold.usersThree,
              title: tr('لا موظفين بعد'),
              hint: tr('أضف أول موظف بملفه الكامل وأدواره في النظام'),
            )
          : rows.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.funnel,
                  title: tr('لا نتائج لهذه المرشحات'),
                  hint: tr('غيّر المرشحات أو امسحها'),
                )
              : _EmployeesTable(
                  rows: rows, expiring: expiring, onOpen: (id) => _open(id)),
    );
  }
}

/// جدولُ الموظفين: كتلةٌ واحدةٌ (حدُّ ١٧) بعرضٍ أدنى ٩٠٠ وتمريرٍ أفقيّ.
class _EmployeesTable extends StatelessWidget {
  const _EmployeesTable({
    required this.rows,
    required this.expiring,
    required this.onOpen,
  });
  final List<EmployeeProfile> rows;
  final Map<int, int> expiring;
  final ValueChanged<int> onOpen;

  static const _flex = [2, 4, 4, 3, 3, 3, 2];

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w800, color: context.picposMuted);
    Widget cell(int i, Widget child) => Expanded(flex: _flex[i], child: child);
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth < 900 ? 900.0 : c.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.picposCard,
              border: Border.all(color: context.picposHairline),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Column(children: [
              Container(
                color: context.picposField,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(children: [
                  cell(0, Text(tr('الكود'), style: head)),
                  cell(1, Text(tr('الموظف'), style: head)),
                  cell(2, Text(tr('الوظيفة'), style: head)),
                  cell(3, Text(tr('الفرع'), style: head)),
                  cell(4, Text(tr('الأدوار'), style: head)),
                  cell(5, Text(tr('مستخدم النظام'), style: head)),
                  cell(6, Text(tr('الحالة'), style: head)),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.picposHairline),
                  itemBuilder: (context, i) => _row(context, rows[i], cell),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _row(BuildContext context, EmployeeProfile p,
      Widget Function(int, Widget) cell) {
    final strong = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: context.picposText);
    final sub = TextStyle(fontSize: 11.5, color: context.picposMuted);
    final docs = expiring[p.id] ?? 0;
    return InkWell(
      key: Key('hr_row_${p.id}'),
      onTap: () => onOpen(p.id!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(children: [
          cell(
              0,
              Text(p.code ?? '—',
                  style: strong.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]))),
          cell(
            1,
            Row(children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .12),
                child: Icon(PhosphorIconsBold.user,
                    size: 15, color: context.picposBrandInk),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, overflow: TextOverflow.ellipsis, style: strong),
                    Text(p.phone ?? p.nameEn ?? '',
                        overflow: TextOverflow.ellipsis, style: sub),
                  ],
                ),
              ),
              if (docs > 0)
                Tooltip(
                  message: tr('{p0} مستند منتهٍ أو قارب الانتهاء', {'p0': docs}),
                  child: Icon(PhosphorIconsBold.warning,
                      key: Key('hr_docs_warning_${p.id}'),
                      size: 16,
                      color: AppColors.statusWarning(context)),
                ),
            ]),
          ),
          cell(
            2,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.jobTitleName == null ? '—' : trData(p.jobTitleName!),
                  overflow: TextOverflow.ellipsis, style: strong),
              Text(p.departmentName == null ? '' : trData(p.departmentName!),
                  overflow: TextOverflow.ellipsis, style: sub),
            ]),
          ),
          cell(
              3,
              Text(p.branchName == null ? '—' : trData(p.branchName!),
                  overflow: TextOverflow.ellipsis, style: strong)),
          cell(
            4,
            Wrap(spacing: 4, children: [
              for (final t in HrRoleTag.values)
                if (p.roleTags.contains(t))
                  Tooltip(
                    message: hrRoleTagLabel(t),
                    child: Icon(hrRoleTagIcon(t),
                        size: 16, color: context.picposBrandInk),
                  ),
              if (p.roleTags.isEmpty) Text('—', style: sub),
            ]),
          ),
          cell(
              5,
              Text(p.username ?? '—',
                  overflow: TextOverflow.ellipsis, style: strong)),
          cell(
            6,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: HrPill(
                  label: hrStatusLabel(p.status),
                  color: hrStatusColor(context, p.status)),
            ),
          ),
        ]),
      ),
    );
  }
}
