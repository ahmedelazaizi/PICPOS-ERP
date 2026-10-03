// J4 (الجزء ٢) — حوارا الورديّة: تعريفُها (البداية والنهاية وعبورُ منتصف الليل
// والاستراحةُ والسماحُ وأيّامُ الراحة وحدُّ الإضافيّ)، وإسنادُها لموظفٍ أو
// لقسمٍ/فرعٍ كاملٍ من تاريخ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';

Future<bool> showShiftDialog(BuildContext context, {WorkShift? shift}) async =>
    await showDialog<bool>(
        context: context, builder: (_) => ShiftDialog(shift: shift)) ??
    false;

class ShiftDialog extends ConsumerStatefulWidget {
  const ShiftDialog({super.key, this.shift});
  final WorkShift? shift;

  @override
  ConsumerState<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<ShiftDialog> {
  late final WorkShift? _s = widget.shift;
  late final _name = TextEditingController(text: _s?.name);
  late final _nameEn = TextEditingController(text: _s?.nameEn);
  late final _start = TextEditingController(
      text: WorkShift.formatMinute(_s?.startMinute ?? 9 * 60));
  late final _end = TextEditingController(
      text: WorkShift.formatMinute(_s?.endMinute ?? 17 * 60));
  late final _break =
      TextEditingController(text: '${_s?.breakMinutes ?? 60}');
  late final _grace =
      TextEditingController(text: '${_s?.graceLateMinutes ?? 10}');
  late final _overtime =
      TextEditingController(text: '${_s?.overtimeAfterMinutes ?? 30}');
  late Set<int> _daysOff = {...?_s?.daysOff};
  late bool _active = _s?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_s == null) _daysOff = {DateTime.friday};
  }

  @override
  void dispose() {
    for (final c in [_name, _nameEn, _start, _end, _break, _grace, _overtime]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _crosses {
    final s = WorkShift.parseMinute(_start.text);
    final e = WorkShift.parseMinute(_end.text);
    return s != null && e != null && e <= s;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final start = WorkShift.parseMinute(_start.text);
      final end = WorkShift.parseMinute(_end.text);
      if (start == null || end == null) {
        throw HrException('صيغة الوقت ساعة:دقيقة مثل 09:30');
      }
      int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
      await ref.read(databaseProvider).saveWorkShift(WorkShift(
            id: _s?.id,
            name: _name.text,
            nameEn: _nameEn.text,
            startMinute: start,
            endMinute: end,
            breakMinutes: n(_break),
            graceLateMinutes: n(_grace),
            overtimeAfterMinutes: n(_overtime),
            daysOff: _daysOff,
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
    return PicPosDialog(
      icon: PhosphorIconsBold.clockClockwise,
      title: _s == null ? tr('وردية جديدة') : tr('تعديل الوردية'),
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
          HrTextField(
              fieldKey: const Key('shift_name'),
              label: tr('اسم الوردية'),
              controller: _name,
              required: true),
          HrTextField(
              fieldKey: const Key('shift_name_en'),
              label: tr('الاسم بالإنجليزية'),
              controller: _nameEn,
              textDirection: TextDirection.ltr),
        ]),
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('shift_start'),
              label: tr('البداية'),
              controller: _start,
              required: true,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {})),
          HrTextField(
              fieldKey: const Key('shift_end'),
              label: tr('النهاية'),
              controller: _end,
              required: true,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {})),
        ]),
        if (_crosses)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.moonStars,
            text: tr('الوردية تعبر منتصف الليل — الانصراف في اليوم التالي.'),
            color: AppColors.statusInfo(context),
          ),
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('shift_break'),
              label: tr('الاستراحة (دقيقة)'),
              controller: _break,
              number: true),
          HrTextField(
              fieldKey: const Key('shift_grace'),
              label: tr('سماح التأخير (دقيقة)'),
              controller: _grace,
              number: true),
          HrTextField(
              fieldKey: const Key('shift_overtime'),
              label: tr('الإضافي بعد (دقيقة)'),
              controller: _overtime,
              number: true),
        ]),
        HrLabeled(
          label: tr('أيام الراحة الأسبوعية'),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in kHrWeekOrder)
              FilterChip(
                key: Key('shift_off_$d'),
                label: Text(hrWeekdayLabel(d)),
                selected: _daysOff.contains(d),
                onSelected: (v) => setState(
                    () => v ? _daysOff.add(d) : _daysOff.remove(d)),
              ),
          ]),
        ),
        SwitchListTile(
          key: const Key('shift_active'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          title: Text(tr('وردية فعالة')),
        ),
      ],
    );
  }
}

/// يُسند ورديّةً لموظف ([employeeId]) أو لقسمٍ/فرعٍ كامل (‏[employeeId] null).
Future<bool> showShiftAssignDialog(BuildContext context,
        {int? employeeId, String? employeeName}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          ShiftAssignDialog(employeeId: employeeId, employeeName: employeeName),
    ) ??
    false;

class ShiftAssignDialog extends ConsumerStatefulWidget {
  const ShiftAssignDialog({super.key, this.employeeId, this.employeeName});
  final int? employeeId;
  final String? employeeName;

  @override
  ConsumerState<ShiftAssignDialog> createState() => _ShiftAssignDialogState();
}

class _ShiftAssignDialogState extends ConsumerState<ShiftAssignDialog> {
  int? _shiftId;
  DateTime? _from = hrDay(DateTime.now());
  int? _departmentId;
  int? _branchId;
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _bulk => widget.employeeId == null;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shift = _shiftId;
    final from = _from;
    if (shift == null || from == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = ref.read(databaseProvider);
    final actor = ref.read(authProvider).user?.id;
    try {
      if (_bulk) {
        if (_departmentId == null && _branchId == null) {
          throw HrException('اختر قسماً أو فرعاً للإسناد الجماعي.');
        }
        await db.assignShiftBulk(
            shiftId: shift,
            from: from,
            departmentId: _departmentId,
            branchId: _branchId,
            actorUserId: actor);
      } else {
        await db.assignShift(
            employeeId: widget.employeeId!,
            shiftId: shift,
            from: from,
            notes: _notes.text,
            actorUserId: actor);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shifts = [
      for (final s in ref.watch(hrShiftsProvider).value ?? const <WorkShift>[])
        if (s.isActive) s,
    ];
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final branches = ref.watch(hrBranchesProvider).value ?? const [];
    return PicPosDialog(
      icon: PhosphorIconsBold.userSwitch,
      title: _bulk ? tr('إسناد جماعي للوردية') : tr('إسناد وردية'),
      subtitle: widget.employeeName,
      width: 560,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('إسناد'),
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed:
            _saving || _shiftId == null || _from == null ? null : _save,
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        HrDropdown<int>(
          fieldKey: const Key('assign_shift'),
          label: tr('الوردية'),
          required: true,
          value: _shiftId,
          items: {
            for (final s in shifts)
              s.id!: '${trData(s.name)} · ${shiftTimesLabel(s)}',
          },
          onChanged: (v) => setState(() => _shiftId = v),
        ),
        HrDateField(
          fieldKey: const Key('assign_from'),
          label: tr('اعتباراً من'),
          required: true,
          value: _from,
          onChanged: (v) => setState(() => _from = v),
        ),
        if (_bulk)
          PicPosDialogRow(children: [
            HrDropdown<int>(
              fieldKey: const Key('assign_department'),
              label: tr('القسم'),
              value: _departmentId,
              emptyLabel: tr('الكل'),
              items: {for (final d in departments) d.id: trData(d.name)},
              onChanged: (v) => setState(() => _departmentId = v),
            ),
            HrDropdown<int>(
              fieldKey: const Key('assign_branch'),
              label: tr('الفرع'),
              value: _branchId,
              emptyLabel: tr('الكل'),
              items: {for (final b in branches) b.id: trData(b.name)},
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ])
        else
          HrTextField(
              fieldKey: const Key('assign_notes'),
              label: tr('ملاحظات'),
              controller: _notes),
        Text(
          tr('الإسناد السابق يُغلق في اليوم السابق للتاريخ ويبقى في السجل.'),
          style: TextStyle(fontSize: 11.5, color: picposDialogMuted(context)),
        ),
      ],
    );
  }
}
