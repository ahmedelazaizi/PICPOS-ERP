// J4 (الجزء ٣) — خططُ العمولة: الافتراضيّةُ لكلّ مندوبٍ بلا خطّةٍ خاصّة،
// والخاصّةُ لمندوبٍ بعينه. نسبةُ صافي المبيعات والتحصيلات، وشرائحُ بنسبة
// تحقيق الهدف الشهريّ تستبدل نسبةَ المبيعات، ونسبٌ اختياريّةٌ لفئات المنتجات.
// الإدارةُ لـ`hr_commissions_manage`.
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
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

String _pct(double v) =>
    '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}%';

class CommissionPlansView extends ConsumerWidget {
  const CommissionPlansView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans =
        ref.watch(commissionPlansProvider).value ?? const <CommissionPlan>[];
    final canManage = ref
            .watch(hasPermissionProvider(PermissionCodes.hrCommissionsManage))
            .value ??
        false;
    Future<void> edit([CommissionPlan? p]) async {
      final ok = await showDialog<bool>(
          context: context, builder: (_) => _PlanDialog(plan: p));
      if (ok == true) refreshPayroll(ref);
    }

    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('commission_plan_new'),
          onPressed: canManage ? () => edit() : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('خطة جديدة')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 900,
            emptyIcon: PhosphorIconsBold.percent,
            emptyTitle: tr('لا خطط عمولة بعد'),
            emptyHint: tr('أنشئ خطة افتراضية تسري على كل مندوب بلا خطة خاصة'),
            columns: [
              HrTableColumn(tr('الخطة'), flex: 3),
              HrTableColumn(tr('المندوب'), flex: 3),
              HrTableColumn(tr('المبيعات')),
              HrTableColumn(tr('التحصيلات')),
              HrTableColumn(tr('الشرائح'), flex: 3),
              HrTableColumn(tr('الحالة')),
              const HrTableColumn('', flex: 1),
            ],
            rows: [
              for (final p in plans)
                HrTableRow(
                  key: Key('commission_plan_row_${p.id}'),
                  onTap: canManage ? () => edit(p) : null,
                  cells: [
                    HrCellText(trData(p.name),
                        sub: p.categoryRates.isEmpty
                            ? null
                            : tr('{p0} فئة بنسبة خاصة',
                                {'p0': '${p.categoryRates.length}'})),
                    HrCellText(p.employeeId == null
                        ? tr('افتراضية لكل المندوبين')
                        : (p.employeeName ?? '')),
                    HrCellText(_pct(p.salesRatePct), number: true),
                    HrCellText(_pct(p.collectionsRatePct), number: true),
                    HrCellText(
                        p.tiers.isEmpty
                            ? '—'
                            : p.tiers
                                .map((t) =>
                                    '≥${_pct(t.minAchievementPct)} → ${_pct(t.salesRatePct)}')
                                .join('  '),
                        number: true),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: p.isActive ? tr('فعال') : tr('موقوف'),
                        color: p.isActive
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
                        onPressed: () async {
                          await ref.read(databaseProvider).deleteCommissionPlan(
                              p.id!,
                              userId: ref.read(authProvider).user?.id);
                          refreshPayroll(ref);
                        },
                        icon: Icon(PhosphorIconsBold.trash,
                            color: AppColors.statusError(context)),
                      )
                    else
                      const SizedBox(),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({this.plan});
  final CommissionPlan? plan;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  late final CommissionPlan? _p = widget.plan;
  late final _name = TextEditingController(text: _p?.name);
  late final _sales = TextEditingController(text: '${_p?.salesRatePct ?? 0}');
  late final _collections =
      TextEditingController(text: '${_p?.collectionsRatePct ?? 0}');
  late int? _employee = _p?.employeeId;
  late bool _active = _p?.isActive ?? true;
  late final List<(TextEditingController, TextEditingController)> _tiers = [
    for (final t in _p?.tiers ?? const <CommissionTier>[])
      (
        TextEditingController(text: '${t.minAchievementPct}'),
        TextEditingController(text: '${t.salesRatePct}'),
      ),
  ];
  late final List<(int?, TextEditingController)> _categories = [
    for (final e in (_p?.categoryRates ?? const <int, double>{}).entries)
      (e.key, TextEditingController(text: '${e.value}')),
  ];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name, _sales, _collections,
      for (final t in _tiers) ...[t.$1, t.$2],
      for (final c in _categories) c.$2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).saveCommissionPlan(
            CommissionPlan(
              id: _p?.id,
              name: _name.text,
              employeeId: _employee,
              salesRatePct: _d(_sales),
              collectionsRatePct: _d(_collections),
              tiers: [
                for (final t in _tiers)
                  CommissionTier(
                      minAchievementPct: _d(t.$1), salesRatePct: _d(t.$2)),
              ],
              categoryRates: {
                for (final c in _categories)
                  if (c.$1 != null) c.$1!: _d(c.$2),
              },
              isActive: _active,
            ),
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(hrProfilesProvider).value ?? const <EmployeeProfile>[];
    final categories = ref.watch(commissionCategoriesProvider).value ?? const [];
    final reps = {
      for (final p in people)
        if (p.roleTags.contains(HrRoleTag.rep) || p.id == _employee)
          p.id!: p.name,
    };
    Widget remove(VoidCallback onTap) => IconButton(
          tooltip: tr('حذف'),
          onPressed: onTap,
          icon: Icon(PhosphorIconsBold.trash,
              size: 16, color: AppColors.statusError(context)),
        );
    return PicPosDialog(
      icon: PhosphorIconsBold.percent,
      title: _p == null ? tr('خطة عمولة جديدة') : tr('تعديل خطة العمولة'),
      width: 700,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.floppyDisk,
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
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('commission_plan_name'),
              label: tr('اسم الخطة'),
              controller: _name,
              required: true),
          HrDropdown<int>(
            fieldKey: const Key('commission_plan_employee'),
            label: tr('المندوب'),
            value: _employee,
            emptyLabel: tr('افتراضية لكل المندوبين'),
            items: reps,
            onChanged: (v) => setState(() => _employee = v),
          ),
        ]),
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('commission_plan_sales'),
              label: tr('نسبة صافي المبيعات %'),
              controller: _sales,
              number: true),
          HrTextField(
              fieldKey: const Key('commission_plan_collections'),
              label: tr('نسبة التحصيلات %'),
              controller: _collections,
              number: true),
        ]),
        Text(tr('شرائح تحقيق الهدف (تستبدل نسبة المبيعات)'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        for (var i = 0; i < _tiers.length; i++)
          Row(children: [
            Expanded(
              child: HrTextField(
                  fieldKey: Key('commission_tier_${i}_min'),
                  label: tr('تحقيق الهدف من %'),
                  controller: _tiers[i].$1,
                  number: true),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HrTextField(
                  fieldKey: Key('commission_tier_${i}_rate'),
                  label: tr('نسبة المبيعات %'),
                  controller: _tiers[i].$2,
                  number: true),
            ),
            remove(() => setState(() => _tiers.removeAt(i))),
          ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('commission_tier_add'),
            onPressed: () => setState(() => _tiers
                .add((TextEditingController(), TextEditingController()))),
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label: Text(tr('إضافة شريحة')),
          ),
        ),
        Text(tr('نسب خاصة لفئات المنتجات (اختياري)'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        for (var i = 0; i < _categories.length; i++)
          Row(children: [
            Expanded(
              child: HrDropdown<int>(
                fieldKey: Key('commission_category_$i'),
                label: tr('الفئة'),
                value: _categories[i].$1,
                items: {for (final c in categories) c.$1: trData(c.$2)},
                onChanged: (v) => setState(
                    () => _categories[i] = (v, _categories[i].$2)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HrTextField(
                  fieldKey: Key('commission_category_${i}_rate'),
                  label: tr('نسبة المبيعات %'),
                  controller: _categories[i].$2,
                  number: true),
            ),
            remove(() => setState(() => _categories.removeAt(i))),
          ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('commission_category_add'),
            onPressed: () => setState(
                () => _categories.add((null, TextEditingController()))),
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label: Text(tr('إضافة فئة')),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(
            key: const Key('commission_plan_active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v ?? false),
          ),
          Text(tr('فعال')),
        ]),
      ],
    );
  }
}
