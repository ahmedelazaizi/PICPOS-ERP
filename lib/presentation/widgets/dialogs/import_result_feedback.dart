import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:picpos_erp/data/services/excel_import_result.dart';

/// How many row errors the result dialog lists (the copy button has all).
const int kImportErrorsShown = 50;

/// Toast style for an import result. A run with ANY row error is never
/// success-styled (green): QA saw «0 جديد، 1 تحديث، 353 أخطاء» in green.
ToastType importToastType(ImportResult r) {
  if (r.errors > 0) return r.success ? ToastType.warning : ToastType.error;
  return r.success ? ToastType.success : ToastType.error;
}

/// Shows the import outcome: a toast, plus — when rows failed — a dialog
/// listing the first [kImportErrorsShown] row errors with a copy button.
Future<void> showImportResultFeedback(
  BuildContext context,
  ImportResult result,
) async {
  AppToast.show(context, result.message, type: importToastType(result));
  if (result.errors <= 0 || result.rowErrors.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (_) => ImportErrorsDialog(result: result),
  );
}

class ImportErrorsDialog extends StatelessWidget {
  const ImportErrorsDialog({super.key, required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final all = result.rowErrors;
    final shown = all.take(kImportErrorsShown).toList();
    return Directionality(
      textDirection: Directionality.of(context),
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('أخطاء استيراد الأصناف'))),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: math.min(420, 90.0 + shown.length * 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message),
              const SizedBox(height: 4),
              Text(
                tr('عرض أول {p0} من {p1} خطأ', {
                  'p0': shown.length,
                  'p1': all.length,
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    key: ValueKey('import_error_$i'),
                    title: Text(
                      tr('الصف {p0} · {p1}', {
                        'p0': shown[i].row,
                        'p1': [shown[i].code, shown[i].name]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      }),
                    ),
                    subtitle: Text(shown[i].reason),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('import_errors_copy'),
            icon: const Icon(PhosphorIconsBold.copy, size: 18),
            label: Text(tr('نسخ الأخطاء')),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: all.map((e) => e.toLine()).join('\n')),
              );
              if (context.mounted) {
                AppToast.show(context, tr('تم نسخ الأخطاء'),
                    type: ToastType.info);
              }
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }
}
