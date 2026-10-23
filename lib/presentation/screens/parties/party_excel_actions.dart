// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import 'party_data_gate.dart';

/// Excel export/import of parties — extracted from party_dialogs.dart. Both
/// entry points are gated by [ensurePartyDataAccess] (AUTHZ-003).
Future<void> exportPartiesTemplateAction(BuildContext context, WidgetRef ref, {bool isSupplier = false}) async {
  if (!await ensurePartyDataAccess(ref, context, PartyDataAction.export,
      isSupplier: isSupplier)) {
    return;
  }
  final service = ref.read(excelServiceProvider);
  final path = await service.exportPartiesTemplate(isSupplier);
  if (path != null && context.mounted) {
    AppToast.show(
      context,
      tr('تم تصدير النموذج بنجاح: {path}', {'path': path}),
      type: ToastType.success,
    );
    try {
      final auth = ref.read(authProvider);
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: auth.user?.id,
        userName: auth.user?.displayName ?? tr('مستخدم'),
        action: 'export_template',
        entityType: 'party',
        description: tr('تصدير قالب {p0}', {'p0': isSupplier ? tr('موردين') : tr('عملاء')}),
      );
    } catch (_) {}
  }
}

Future<void> importPartiesAction(BuildContext context, WidgetRef ref, {bool isSupplier = false}) async {
  if (!await ensurePartyDataAccess(ref, context, PartyDataAction.import,
      isSupplier: isSupplier)) {
    return;
  }
  final service = ref.read(excelServiceProvider);
  final result = await service.importParties(isSupplier);
  if (context.mounted) {
    AppToast.show(
      context,
      result.message,
      type: result.success == true ? ToastType.success : ToastType.error,
    );
    if (result.success) {
      ref.invalidate(allPartiesProvider);
      try {
        final auth = ref.read(authProvider);
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: auth.user?.id,
          userName: auth.user?.displayName ?? tr('مستخدم'),
          action: 'import_data',
          entityType: 'party',
          description:
              tr('استيراد بيانات {p0} من Excel', {'p0': isSupplier ? tr('موردين') : tr('عملاء')}),
        );
      } catch (_) {}
    }
  }
}
