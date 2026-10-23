import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../core/permissions/financial_figures_access.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';

/// RPT-006: the products template exports cost and sale prices, so the
/// exporter must be allowed to see both ([canExportProductFigures]). Called by
/// every export entry point after its own `products_export` gate.
Future<bool> ensureProductExportFigures(
  WidgetRef ref,
  BuildContext context,
) async {
  final perms = await ref.read(currentUserPermissionsProvider.future);
  final ok = canExportProductFigures(perms,
      bypass: ref.read(authProvider).hasSystemAdminBypass);
  if (!ok && context.mounted) {
    AppToast.show(context, tr('ليس لديك صلاحية لهذا الإجراء.'),
        type: ToastType.error);
  }
  return ok;
}
