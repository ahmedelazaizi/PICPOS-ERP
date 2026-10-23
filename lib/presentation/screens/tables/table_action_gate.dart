import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';

// بوّابةُ أفعال الطاولات — تعرف «المشروط» (cond:<code>) فتطلب موافقة مدير
// بدل أن تمرّ لمجرّد أنّ الكود في القائمة (B-3 في مراجعة الجودة).

/// قرارُ بوّابةِ فعلِ طاولة.
enum TableActionGate {
  /// ممنوحٌ بلا شرط (أو مدير نظام) — يمضي بلا سؤال.
  allowed,

  /// ممنوحٌ **مشروطاً** — يمضي بعد موافقة مدير فقط.
  needsApproval,

  /// غيرُ ممنوح — يُرفض.
  denied,
}

/// دالّةٌ خالصة: قرارُ [permission] لحاملِ [permissions].
///
/// الترتيبُ كما في `ensurePermission`: المشروطُ قبل المِلك، فالكودُ المشروط
/// يكون في القائمة ومع ذلك لا يمرّ بلا موافقة.
TableActionGate tableActionGate(List<String> permissions, String permission) {
  if (!hasPermissionWithAdminBypass(permissions, permission)) {
    return TableActionGate.denied;
  }
  if (PermissionCodes.isConditionalIn(permissions, permission)) {
    return TableActionGate.needsApproval;
  }
  return TableActionGate.allowed;
}

/// ينفّذ بوّابةَ فعلِ الطاولة: يمضي، أو يطلب موافقةَ مدير، أو يرفض بتوست.
Future<bool> ensureTableAction(
  WidgetRef ref,
  BuildContext context,
  String permission,
  String actionName,
) async {
  final perms =
      ref.read(currentUserPermissionsProvider).value ?? const <String>[];
  switch (tableActionGate(perms, permission)) {
    case TableActionGate.allowed:
      return true;
    case TableActionGate.needsApproval:
      if (!context.mounted) return false;
      return ensurePermission(ref, context, permission,
          actionName: actionName);
    case TableActionGate.denied:
      if (context.mounted) {
        AppToast.show(
          context,
          tr('ليس لديك صلاحية {actionName}', {'actionName': actionName}),
          type: ToastType.error,
        );
      }
      return false;
  }
}