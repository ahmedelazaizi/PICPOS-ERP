// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// Sends the already-filtered rows shown by a PicPos report to the shared
/// Excel service. The export permission is enforced by the caller's action.
Future<void> exportPicPosReport({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required List<String> headers,
  required List<List<dynamic>> rows,
  DateTime? periodFrom,
  DateTime? periodTo,
  int? branchId,
  Set<int>? scopedBranchIds,
}) async {
  final service = ref.read(excelServiceProvider);
  if (service == null) {
    if (context.mounted) {
      AppToast.show(context, tr('التصدير غير متاح على هذا الجهاز'), type: ToastType.error);
    }
    return;
  }
  final path = await service.exportReport(
    title: title,
    headers: headers,
    rows: rows,
    periodFrom: periodFrom,
    periodTo: periodTo,
    branchId: branchId,
    scopedBranchIds: scopedBranchIds,
  );
  if (!context.mounted) return;
  if (path == null) {
    AppToast.show(context, tr('تعذّر تصدير التقرير'), type: ToastType.error);
  } else {
    AppToast.show(
      context,
      tr('تم تصدير التقرير بنجاح: {path}', {'path': path}),
      type: ToastType.success,
    );
  }
}
