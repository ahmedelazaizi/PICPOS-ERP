// J4 — تبويبُ «المستندات»: بياناتُ مرفقات الموظف (النوع والرقم والإصدار
// والانتهاء ومسارُ الملف) مع تنبيهٍ بالانتهاء قبل ٣٠ يوماً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';

class EfDocumentsTab extends ConsumerWidget {
  const EfDocumentsTab({super.key, required this.employeeId});
  final int? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId;
    if (id == null) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.files,
        title: tr('احفظ الموظف أولاً'),
        hint: tr('تُضاف المستندات بعد حفظ ملف الموظف لأول مرة'),
      );
    }
    final docs = ref.watch(hrDocumentsProvider(id)).value ?? const [];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('مستندات الموظف'),
          icon: PhosphorIconsBold.files,
          actions: [
            FilledButton.icon(
              key: const Key('ef_doc_add'),
              onPressed: () => showEmployeeDocumentDialog(context, ref, id),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('إضافة مستند')),
            ),
          ],
          child: docs.isEmpty
              ? PicPosEmptyState(
                  icon: PhosphorIconsBold.fileDashed,
                  title: tr('لا مستندات بعد'),
                  hint: tr('الهوية وجواز السفر وعقد العمل والشهادات…'),
                )
              : Column(children: [
                  for (final d in docs) _DocTile(employeeId: id, doc: d),
                ]),
        ),
      ],
    );
  }
}

class _DocTile extends ConsumerWidget {
  const _DocTile({required this.employeeId, required this.doc});
  final int employeeId;
  final EmployeeDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = doc.expiryState(DateTime.now());
    final (label, color) = switch (state) {
      DocumentExpiryState.expired => (
          tr('منتهي'),
          AppColors.statusError(context)
        ),
      DocumentExpiryState.expiringSoon => (
          tr('ينتهي قريباً'),
          AppColors.statusWarning(context)
        ),
      DocumentExpiryState.valid => (
          tr('ساري'),
          AppColors.statusSuccess(context)
        ),
      DocumentExpiryState.none => (tr('بلا انتهاء'), context.picposMuted),
    };
    return Container(
      key: Key('ef_doc_${doc.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: [
        Icon(PhosphorIconsBold.fileText, size: 20, color: context.picposBrandInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [doc.docType, if (doc.docNumber != null) doc.docNumber!]
                    .join(' — '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText),
              ),
              Text(
                '${tr('الإصدار')}: ${hrDate(doc.issueDate)}   '
                '${tr('الانتهاء')}: ${hrDate(doc.expiryDate)}'
                '${doc.filePath == null ? '' : '   ${doc.filePath}'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: context.picposMuted),
              ),
            ],
          ),
        ),
        HrPill(label: label, color: color),
        IconButton(
          tooltip: tr('تعديل'),
          onPressed: () =>
              showEmployeeDocumentDialog(context, ref, employeeId, doc: doc),
          icon: const Icon(PhosphorIconsBold.pencilSimple, size: 18),
        ),
        IconButton(
          tooltip: tr('حذف'),
          onPressed: () async {
            final ok = await showPicPosConfirm(context,
                icon: PhosphorIconsBold.trash,
                title: tr('حذف المستند'),
                message: tr('سيُحذف المستند «{p0}» من ملف الموظف.',
                    {'p0': doc.docType}),
                danger: true);
            if (!ok) return;
            await ref.read(databaseProvider).deleteEmployeeDocument(doc.id!);
            ref.invalidate(hrDocumentsProvider(employeeId));
            ref.invalidate(hrExpiringDocsProvider);
          },
          icon: Icon(PhosphorIconsBold.trash,
              size: 18, color: Theme.of(context).colorScheme.error),
        ),
      ]),
    );
  }
}

Future<void> showEmployeeDocumentDialog(
    BuildContext context, WidgetRef ref, int employeeId,
    {EmployeeDocument? doc}) async {
  final type = TextEditingController(text: doc?.docType ?? '');
  final number = TextEditingController(text: doc?.docNumber ?? '');
  final path = TextEditingController(text: doc?.filePath ?? '');
  final notes = TextEditingController(text: doc?.notes ?? '');
  var issue = doc?.issueDate;
  var expiry = doc?.expiryDate;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => PicPosDialog(
        icon: PhosphorIconsBold.fileText,
        title: doc == null ? tr('إضافة مستند') : tr('تعديل مستند'),
        width: 620,
        onCancel: () => Navigator.pop(ctx),
        primaryAction: PicPosDialogAction(
          label: tr('حفظ'),
          icon: PhosphorIconsBold.check,
          onPressed: () async {
            try {
              await ref.read(databaseProvider).saveEmployeeDocument(
                    employeeId,
                    EmployeeDocument(
                      id: doc?.id,
                      docType: type.text,
                      docNumber: number.text,
                      issueDate: issue,
                      expiryDate: expiry,
                      filePath: path.text,
                      notes: notes.text,
                    ),
                  );
              ref.invalidate(hrDocumentsProvider(employeeId));
              ref.invalidate(hrExpiringDocsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } on HrException catch (e) {
              setState(() => error = e.message);
            }
          },
        ),
        body: [
          HrFieldGrid(children: [
            HrTextField(
              fieldKey: const Key('ef_doc_type'),
              label: tr('نوع المستند'),
              controller: type,
              required: true,
              hint: tr('هوية، جواز سفر، رخصة…'),
            ),
            HrTextField(
              fieldKey: const Key('ef_doc_number'),
              label: tr('رقم المستند'),
              controller: number,
              textDirection: TextDirection.ltr,
            ),
            HrDateField(
              label: tr('تاريخ الإصدار'),
              value: issue,
              onChanged: (v) => setState(() => issue = v),
            ),
            HrDateField(
              fieldKey: const Key('ef_doc_expiry'),
              label: tr('تاريخ الانتهاء'),
              value: expiry,
              onChanged: (v) => setState(() => expiry = v),
            ),
          ]),
          HrTextField(
            label: tr('مسار الملف'),
            controller: path,
            textDirection: TextDirection.ltr,
          ),
          HrTextField(label: tr('ملاحظات'), controller: notes),
          if (error != null)
            Text(error!,
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
  // المتحكّماتُ لا تُتلَف هنا: الحوارُ ما زال يرسمها أثناء حركة الإغلاق.
}
