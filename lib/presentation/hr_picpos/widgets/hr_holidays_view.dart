// J4 (الجزء ٢) — تقويمُ العطلات الرسميّة (على مستوى الشركة، بالتاريخ): يومُ
// العطلة لا يُحسَب غياباً، والعملُ فيه كلُّه إضافيّ.
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
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_labels.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class HrHolidaysView extends ConsumerStatefulWidget {
  const HrHolidaysView({super.key});

  @override
  ConsumerState<HrHolidaysView> createState() => _HrHolidaysViewState();
}

class _HrHolidaysViewState extends ConsumerState<HrHolidaysView> {
  int _year = DateTime.now().year;

  Future<void> _edit([PublicHoliday? h]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HolidayDialog(holiday: h, year: _year),
    );
    if (saved == true && mounted) refreshHrAttendance(ref);
  }

  Future<void> _delete(PublicHoliday h) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.trash,
      title: tr('حذف العطلة'),
      message: tr('حذف «{p0}» بتاريخ {p1}؟', {'p0': h.name, 'p1': hrDate(h.date)}),
      danger: true,
      confirmLabel: tr('حذف'),
    );
    if (!ok || !mounted) return;
    await ref.read(databaseProvider).deletePublicHoliday(h.id!);
    refreshHrAttendance(ref);
  }

  @override
  Widget build(BuildContext context) {
    final holidays = ref.watch(hrHolidaysProvider(_year)).value ??
        const <PublicHoliday>[];
    final canEdit = ref
            .watch(hasPermissionProvider(PermissionCodes.hrAttendanceEdit))
            .value ??
        false;
    return Column(children: [
      HrToolbar(children: [
        HrStepper(
          keyPrefix: 'hol_year',
          label: '$_year',
          onPrev: () => setState(() => _year--),
          onNext: () => setState(() => _year++),
        ),
        HrPill(
            label: tr('{p0} عطلة', {'p0': holidays.length}),
            color: context.picposBrandInk),
        FilledButton.icon(
          key: const Key('hol_add'),
          onPressed: canEdit ? () => _edit() : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('عطلة جديدة')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 640,
            emptyIcon: PhosphorIconsBold.confetti,
            emptyTitle: tr('لا عطلات رسمية في هذه السنة'),
            emptyHint: tr('أضف العطلات الرسمية ليُحسب يومها عطلة لا غياباً'),
            columns: [
              HrTableColumn(tr('التاريخ')),
              HrTableColumn(tr('اليوم')),
              HrTableColumn(tr('العطلة'), flex: 4),
              const HrTableColumn('', flex: 1),
            ],
            rows: [
              for (final h in holidays)
                HrTableRow(
                  key: Key('hol_row_${h.id}'),
                  onTap: canEdit ? () => _edit(h) : null,
                  cells: [
                    HrCellText(hrDate(h.date), number: true),
                    HrCellText(hrWeekdayLabel(h.date.weekday)),
                    HrCellText(
                        uiLocaleCode == 'en' && (h.nameEn ?? '').isNotEmpty
                            ? h.nameEn!
                            : trData(h.name)),
                    if (canEdit)
                      IconButton(
                        tooltip: tr('حذف'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        iconSize: 16,
                        onPressed: () => _delete(h),
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

class _HolidayDialog extends ConsumerStatefulWidget {
  const _HolidayDialog({this.holiday, required this.year});
  final PublicHoliday? holiday;
  final int year;

  @override
  ConsumerState<_HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends ConsumerState<_HolidayDialog> {
  late DateTime? _date = widget.holiday?.date ??
      (DateTime.now().year == widget.year
          ? hrDay(DateTime.now())
          : DateTime(widget.year));
  late final _name = TextEditingController(text: widget.holiday?.name);
  late final _nameEn = TextEditingController(text: widget.holiday?.nameEn);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final date = _date;
    if (date == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).savePublicHoliday(PublicHoliday(
            id: widget.holiday?.id,
            date: date,
            name: _name.text,
            nameEn: _nameEn.text,
          ));
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PicPosDialog(
      icon: PhosphorIconsBold.confetti,
      title: widget.holiday == null ? tr('عطلة جديدة') : tr('تعديل العطلة'),
      width: 520,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.floppyDisk,
        busy: _saving,
        onPressed: _saving || _date == null ? null : _save,
      ),
      body: [
        HrDateField(
          fieldKey: const Key('hol_date'),
          label: tr('التاريخ'),
          required: true,
          value: _date,
          onChanged: (v) => setState(() => _date = v),
        ),
        HrTextField(
          fieldKey: const Key('hol_name'),
          label: tr('اسم العطلة'),
          controller: _name,
          required: true,
        ),
        HrTextField(
          fieldKey: const Key('hol_name_en'),
          label: tr('الاسم بالإنجليزية'),
          controller: _nameEn,
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }
}
