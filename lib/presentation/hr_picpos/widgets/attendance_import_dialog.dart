// J4 (الجزء ٢) — استيرادُ بصمات جهاز الحضور من CSV: اختيارُ الملفّ، وربطُ
// أعمدته (الكود · التاريخ والوقت · الوقت منفصلاً · الاتجاه)، ومعاينةٌ تعرض
// الأيّامَ التي ستُكتَب وأسطرَ الخطأ برقمها، ثمّ الاستيراد.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance_import.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_labels.dart';
import 'hr_form_kit.dart';

Future<bool> showAttendanceImportDialog(BuildContext context,
        {String? initialText}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AttendanceImportDialog(initialText: initialText),
    ) ??
    false;

class AttendanceImportDialog extends ConsumerStatefulWidget {
  const AttendanceImportDialog({super.key, this.initialText});

  /// نصُّ الملفّ جاهزاً (للاختبار، أو للّصق) — يتخطّى منتقيَ الملفّات.
  final String? initialText;

  @override
  ConsumerState<AttendanceImportDialog> createState() =>
      _AttendanceImportDialogState();
}

class _AttendanceImportDialogState
    extends ConsumerState<AttendanceImportDialog> {
  late String? _text = widget.initialText;
  String? _fileName;
  AttendanceCsvMapping _mapping = const AttendanceCsvMapping();
  AttendanceImportPreview? _preview;
  bool _busy = false;

  List<String> get _headers {
    final text = _text;
    if (text == null) return const [];
    final rows = csvRows(text);
    return rows.isEmpty ? const [] : rows.first;
  }

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      dialogTitle: tr('اختر ملف البصمة (CSV)'),
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    if (!mounted) return;
    setState(() {
      _text = text;
      _fileName = path.split(Platform.pathSeparator).last;
      _preview = null;
    });
  }

  Future<void> _runPreview() async {
    final text = _text;
    if (text == null) return;
    setState(() => _busy = true);
    try {
      final p =
          await ref.read(databaseProvider).previewAttendanceImport(text, _mapping);
      if (mounted) setState(() => _preview = p);
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final p = _preview;
    if (p == null || p.days.isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(databaseProvider).applyAttendanceImport(p,
          actorUserId: ref.read(authProvider).user?.id);
      if (!mounted) return;
      AppToast.show(context, tr('تم استيراد {p0} يوم حضور', {'p0': n}));
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMapping(AttendanceCsvMapping m) => setState(() {
        _mapping = m;
        _preview = null;
      });

  @override
  Widget build(BuildContext context) {
    final headers = _headers;
    final columns = {
      for (var i = 0; i < headers.length; i++)
        i: _mapping.hasHeader && headers[i].isNotEmpty
            ? tr('عمود {p0}: {p1}', {'p0': i + 1, 'p1': headers[i]})
            : tr('عمود {p0}', {'p0': i + 1}),
    };
    final preview = _preview;
    return PicPosDialog(
      icon: PhosphorIconsBold.fileCsv,
      title: tr('استيراد بصمات الحضور'),
      subtitle: _fileName ?? tr('ملف CSV مصدَّر من جهاز البصمة'),
      width: 760,
      onCancel: () => Navigator.of(context).pop(false),
      secondaryActions: [
        PicPosDialogAction(
          label: tr('اختيار ملف'),
          icon: PhosphorIconsBold.folderOpen,
          onPressed: _busy ? null : _pick,
        ),
        PicPosDialogAction(
          label: tr('معاينة'),
          icon: PhosphorIconsBold.eye,
          onPressed: _busy || _text == null ? null : _runPreview,
        ),
      ],
      primaryAction: PicPosDialogAction(
        label: tr('استيراد'),
        icon: PhosphorIconsBold.downloadSimple,
        busy: _busy,
        onPressed:
            _busy || preview == null || preview.days.isEmpty ? null : _apply,
      ),
      body: [
        if (_text == null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.info,
            text: tr('اختر ملف CSV فيه كود الموظف وتاريخ ووقت البصمة، واتجاهها إن وُجد.'),
            color: AppColors.statusInfo(context),
          )
        else ...[
          CheckboxListTile(
            key: const Key('att_import_header'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _mapping.hasHeader,
            onChanged: (v) => _setMapping(_mapping.copyWith(hasHeader: v)),
            title: Text(tr('السطر الأول عناوين أعمدة')),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          PicPosDialogRow(children: [
            HrDropdown<int>(
              fieldKey: const Key('att_import_code'),
              label: tr('كود الموظف'),
              value: _mapping.codeColumn,
              items: columns,
              onChanged: (v) =>
                  _setMapping(_mapping.copyWith(codeColumn: v ?? 0)),
            ),
            HrDropdown<int>(
              fieldKey: const Key('att_import_datetime'),
              label: tr('التاريخ والوقت'),
              value: _mapping.dateTimeColumn,
              items: columns,
              onChanged: (v) =>
                  _setMapping(_mapping.copyWith(dateTimeColumn: v ?? 1)),
            ),
          ]),
          PicPosDialogRow(children: [
            HrDropdown<int>(
              fieldKey: const Key('att_import_time'),
              label: tr('الوقت (عمود منفصل)'),
              value: _mapping.timeColumn,
              emptyLabel: tr('لا يوجد'),
              items: columns,
              onChanged: (v) => _setMapping(_mapping.copyWith(timeColumn: () => v)),
            ),
            HrDropdown<int>(
              fieldKey: const Key('att_import_direction'),
              label: tr('الاتجاه (دخول / خروج)'),
              value: _mapping.directionColumn,
              emptyLabel: tr('أول بصمة حضور وآخرها انصراف'),
              items: columns,
              onChanged: (v) =>
                  _setMapping(_mapping.copyWith(directionColumn: () => v)),
            ),
          ]),
          if (preview != null) _PreviewPanel(preview: preview),
        ],
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.preview});
  final AttendanceImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final errors = preview.errors;
    final muted = TextStyle(fontSize: 12, color: context.picposMuted);
    final strong = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: context.picposText,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          HrPill(
            key: const Key('att_import_days'),
            label: tr('{p0} يوم سيُكتب', {'p0': preview.days.length}),
            color: AppColors.statusSuccess(context),
          ),
          HrPill(
            key: const Key('att_import_errors'),
            label: tr('{p0} سطر فيه خطأ', {'p0': errors.length}),
            color: errors.isEmpty
                ? context.picposMuted
                : AppColors.statusError(context),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: context.picposField,
            borderRadius: BorderRadius.circular(11),
          ),
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              for (final e in errors.take(200))
                Padding(
                  key: Key('att_import_error_${e.line}'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(PhosphorIconsBold.warningCircle,
                        size: 14, color: AppColors.statusError(context)),
                    const SizedBox(width: 6),
                    Text(tr('سطر {p0}', {'p0': e.line}), style: strong),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${e.code.isEmpty ? '—' : e.code} · ${tr(e.error!)}',
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    ),
                  ]),
                ),
              for (final d in preview.days.take(300))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(PhosphorIconsBold.checkCircle,
                        size: 14, color: AppColors.statusSuccess(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: Text(d.employeeName,
                          overflow: TextOverflow.ellipsis, style: strong),
                    ),
                    Expanded(flex: 2, child: Text(hrDate(d.workDate), style: muted)),
                    Expanded(
                      flex: 3,
                      child: Text('${hrTime(d.checkIn)} → ${hrTime(d.checkOut)}',
                          style: strong),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
