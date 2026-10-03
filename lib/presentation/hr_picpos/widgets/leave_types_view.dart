// J4 (الجزء ٢) — أنواعُ الإجازات: مدفوعةٌ أو لا، والاستحقاقُ السنويّ وطريقتُه
// (سنويٌّ أو شهريّ)، وحدُّ الترحيل، واشتراطُ المرفق. الأربعةُ الأساسيّة لا
// تُحذف. الإدارةُ لصاحب `hr_leave_approve`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_leave.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class LeaveTypesView extends ConsumerWidget {
  const LeaveTypesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types =
        ref.watch(hrLeaveTypesProvider).value ?? const <LeaveType>[];
    final canManage = ref
            .watch(hasPermissionProvider(PermissionCodes.hrLeaveApprove))
            .value ??
        false;
    Future<void> edit([LeaveType? t]) async {
      final saved = await showDialog<bool>(
          context: context, builder: (_) => _LeaveTypeDialog(type: t));
      if (saved == true) refreshHrAttendance(ref);
    }

    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('leave_type_new'),
          onPressed: canManage ? () => edit() : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('نوع جديد')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 900,
            emptyIcon: PhosphorIconsBold.listBullets,
            emptyTitle: tr('لا أنواع إجازات بعد'),
            columns: [
              HrTableColumn(tr('النوع'), flex: 4),
              HrTableColumn(tr('الأجر')),
              HrTableColumn(tr('الاستحقاق السنوي')),
              HrTableColumn(tr('الاستحقاق')),
              HrTableColumn(tr('أقصى ترحيل')),
              HrTableColumn(tr('مرفق')),
              HrTableColumn(tr('الحالة')),
              const HrTableColumn('', flex: 1),
            ],
            rows: [
              for (final t in types)
                HrTableRow(
                  key: Key('leave_type_row_${t.id}'),
                  onTap: canManage ? () => edit(t) : null,
                  cells: [
                    HrCellText(leaveTypeLabel(t),
                        sub: t.isSystem ? tr('أساسي') : tr('مخصص')),
                    HrCellText(t.isPaid ? tr('مدفوعة') : tr('غير مدفوعة')),
                    HrCellText(tr('{p0} يوم', {'p0': hrDays(t.yearlyDays)}),
                        number: true),
                    HrCellText(leaveAccrualLabel(t.accrual)),
                    HrCellText(hrDays(t.carryOverMax), number: true),
                    HrCellText(t.requiresAttachment ? tr('مطلوب') : '—'),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: t.isActive ? tr('فعال') : tr('موقوف'),
                        color: t.isActive
                            ? AppColors.statusSuccess(context)
                            : context.picposMuted,
                      ),
                    ),
                    if (canManage && !t.isSystem)
                      IconButton(
                        tooltip: tr('حذف'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        iconSize: 16,
                        onPressed: () async {
                          try {
                            await ref
                                .read(databaseProvider)
                                .deleteLeaveType(t.id!);
                            refreshHrAttendance(ref);
                          } on HrException catch (e) {
                            if (context.mounted) {
                              AppToast.show(context, e.message,
                                  type: ToastType.error);
                            }
                          }
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

class _LeaveTypeDialog extends ConsumerStatefulWidget {
  const _LeaveTypeDialog({this.type});
  final LeaveType? type;

  @override
  ConsumerState<_LeaveTypeDialog> createState() => _LeaveTypeDialogState();
}

class _LeaveTypeDialogState extends ConsumerState<_LeaveTypeDialog> {
  late final LeaveType? _t = widget.type;
  late final _name = TextEditingController(
      text: _t == null ? '' : (_t.isSystem ? leaveTypeLabel(_t) : _t.name));
  late final _nameEn = TextEditingController(text: _t?.nameEn);
  late final _days = TextEditingController(text: hrDays(_t?.yearlyDays ?? 0));
  late final _carry = TextEditingController(text: hrDays(_t?.carryOverMax ?? 0));
  late bool _paid = _t?.isPaid ?? true;
  late bool _attachment = _t?.requiresAttachment ?? false;
  late bool _active = _t?.isActive ?? true;
  late String _accrual = _t?.accrual ?? LeaveAccrual.yearly;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _nameEn, _days, _carry]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final t = _t;
      // A system type keeps its stored (Arabic) name — the label shown in the
      // field is its translation.
      final name = t != null && t.isSystem ? t.name : _name.text;
      await ref.read(databaseProvider).saveLeaveType(LeaveType(
            id: t?.id,
            code: t?.code ?? LeaveTypeCode.custom,
            name: name,
            nameEn: _nameEn.text,
            isPaid: _paid,
            yearlyDays: double.tryParse(_days.text.trim()) ?? 0,
            carryOverMax: double.tryParse(_carry.text.trim()) ?? 0,
            requiresAttachment: _attachment,
            accrual: _accrual,
            isActive: _active,
          ));
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final system = _t?.isSystem ?? false;
    return PicPosDialog(
      icon: PhosphorIconsBold.airplaneTilt,
      title: _t == null ? tr('نوع إجازة جديد') : tr('تعديل نوع الإجازة'),
      width: 620,
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
          system
              ? HrInfoLine(
                  icon: PhosphorIconsBold.lock,
                  label: tr('الاسم'),
                  value: _name.text)
              : HrTextField(
                  fieldKey: const Key('leave_type_name'),
                  label: tr('الاسم'),
                  controller: _name,
                  required: true),
          HrTextField(
              fieldKey: const Key('leave_type_name_en'),
              label: tr('الاسم بالإنجليزية'),
              controller: _nameEn,
              textDirection: TextDirection.ltr),
        ]),
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('leave_type_days'),
              label: tr('الاستحقاق السنوي (يوم)'),
              controller: _days,
              number: true),
          HrTextField(
              fieldKey: const Key('leave_type_carry'),
              label: tr('أقصى ترحيل (يوم)'),
              controller: _carry,
              number: true),
          HrDropdown<String>(
            fieldKey: const Key('leave_type_accrual'),
            label: tr('الاستحقاق'),
            value: _accrual,
            items: {
              for (final a in LeaveAccrual.values) a: leaveAccrualLabel(a),
            },
            onChanged: (v) => setState(() => _accrual = v ?? _accrual),
          ),
        ]),
        Wrap(spacing: 16, children: [
          for (final (key, label, value, set) in [
            ('paid', tr('مدفوعة الأجر'), _paid, (bool v) => _paid = v),
            ('attachment', tr('تتطلب مرفقاً'), _attachment,
                (bool v) => _attachment = v),
            ('active', tr('فعال'), _active, (bool v) => _active = v),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                key: Key('leave_type_$key'),
                value: value,
                onChanged: (v) => setState(() => set(v ?? false)),
              ),
              Text(label),
            ]),
        ]),
      ],
    );
  }
}
