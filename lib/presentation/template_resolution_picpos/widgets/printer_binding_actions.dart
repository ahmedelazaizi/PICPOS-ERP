import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/providers/print_resolution_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/data/providers/template_library_providers.dart';
import 'package:picpos_erp/domain/models/print_resolution_row.dart';

import 'printer_template_binding_dialog.dart';

Future<void> openPrinterBinding({
  required BuildContext context,
  required WidgetRef ref,
  required PrintResolutionRow row,
  required int? branchId,
  required String locale,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => PrinterTemplateBindingDialog(
      documentType: row.documentType,
      branchId: branchId,
      locale: locale,
    ),
  );
  if (saved == true) {
    ref.read(templateLibraryRefreshProvider.notifier).bump();
    ref.invalidate(printResolutionRowsProvider);
  }
}

Future<void> removePrinterBinding({
  required BuildContext context,
  required WidgetRef ref,
  required PrintResolutionRow row,
}) async {
  final printerId = row.printerId;
  if (printerId == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('إزالة ربط الطابعة')),
      content: Text(tr('هل تريد إزالة ربط الطابعة لهذا النوع؟')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(tr('إزالة الربط')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref
      .read(invoiceTemplatesRepositoryProvider)
      .deactivateBinding(
        documentType: row.documentType,
        branchId: row.branchId,
        printerId: printerId,
        locale: row.locale,
      );
  ref.read(templateLibraryRefreshProvider.notifier).bump();
  ref.invalidate(printResolutionRowsProvider);
}
