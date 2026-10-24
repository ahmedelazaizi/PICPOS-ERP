// Branch-manager console («مدير الفروع», the mirror) permission - plan
// 2026-10-24 §B.12 / M1-M2.
//
// Kept out of permission_codes.dart (at its file-size ceiling), like
// warehouse_permission_codes.dart: registered there by ONE spread in
// `PermissionCodes.masterList`. The category is the existing devices one.
import 'package:picpos_erp/core/i18n/tr.dart';

import 'warehouse_permission_codes.dart' show kWarehouseMobileCategory;

abstract final class MirrorPermissionCodes {
  /// Sign in on a mirror device (the online branch-manager console). Enforced
  /// on the server (`POST /api/auth/session` from a `mirror` device answers
  /// 403 `mirror_console_denied` without it) and, in M2, on the device.
  static const String mirrorConsole = 'mirror_console';
}

/// Rows appended to `PermissionCodes.masterList`.
List<Map<String, String>> get mirrorConsolePermissionEntries => [
  {
    'code': MirrorPermissionCodes.mirrorConsole,
    'name': tr('الدخول على كونسول مدير الفروع (المرآة)'),
    'category': kWarehouseMobileCategory,
  },
];
