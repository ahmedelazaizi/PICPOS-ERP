import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/permissions/party_data_access.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// ما يُحرَس من بيانات الأطراف (AUTHZ-003).
enum PartyDataAction { statement, export, import }

/// بوّابةٌ واحدةٌ لكشف الحساب والتصدير والاستيراد، تُستدعى من **القِمع**
/// (الدالّة التي ينفّذها الزرّ) لا من الزرّ وحده. ترفض بإشعارٍ بلا حوار موافقة:
/// هذه مداخلُ بياناتٍ لا إجراءاتٌ مشروطة.
Future<bool> ensurePartyDataAccess(
  WidgetRef ref,
  BuildContext context,
  PartyDataAction action, {
  required bool isSupplier,
}) async {
  final perms = await ref.read(currentUserPermissionsProvider.future);
  final bypass = ref.read(authProvider).hasSystemAdminBypass;
  final ok = switch (action) {
    PartyDataAction.statement => PartyDataAccess.canViewStatement(perms,
        supplier: isSupplier, bypass: bypass),
    PartyDataAction.export =>
      PartyDataAccess.canExport(perms, supplier: isSupplier, bypass: bypass),
    PartyDataAction.import =>
      PartyDataAccess.canImport(perms, supplier: isSupplier, bypass: bypass),
  };
  if (!ok && context.mounted) {
    AppToast.show(context, tr('ليس لديك صلاحية لهذا الإجراء.'),
        type: ToastType.error);
  }
  return ok;
}
