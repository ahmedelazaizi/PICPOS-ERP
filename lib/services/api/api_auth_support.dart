// Shared helpers of the credential endpoints (`/api/auth/session`,
// `/api/auth/change-password`) - plan 2026-10-24, P1 / M1.
//
//  * [deviceSessionDenial]: what the PAIRED DEVICE itself forbids a user
//    (a branch device only admits users assigned to its branch; a `mirror`
//    device only admits users holding `mirror_console`).
//  * [AuthAudit]: audit lines for session issuance / password changes
//    (`activity_logs`), never containing a secret.
import 'package:shelf/shelf.dart';

import '../../core/auth/bootstrap_admin.dart';
import '../../core/permissions/mirror_permission_codes.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../activity_logger.dart';
import 'client_address.dart';

/// Machine-readable codes returned in the `code` field of a 403.
abstract final class AuthDenialCode {
  static const String branchAccessDenied = 'branch_access_denied';
  static const String mirrorConsoleDenied = 'mirror_console_denied';
  static const String posAccessDenied = 'pos_access_denied';
}

/// Returns an [AuthDenialCode] when the device that carries [request] does not
/// admit [user], else `null`. Unpaired / legacy callers and `admin`-kind or
/// branch-less devices are never denied by this check.
Future<String?> deviceSessionDenial(
  AppDatabase db,
  Request request,
  User user,
) async {
  if (request.context['lanDeviceKind'] == 'mirror') {
    final allowed = await db.userHasPermission(
      user.id,
      MirrorPermissionCodes.mirrorConsole,
    );
    return allowed ? null : AuthDenialCode.mirrorConsoleDenied;
  }
  // A Cashier tablet only admits users who may use the point of sale.
  if (request.context['lanDeviceKind'] == 'pos' &&
      !isBootstrapAdmin(user.id, username: user.username) &&
      !await db.userHasPermission(user.id, PermissionCodes.posAccess)) {
    return AuthDenialCode.posAccessDenied;
  }
  final deviceBranch = request.context['lanDeviceBranchId'];
  if (deviceBranch is! int) return null;
  if (isBootstrapAdmin(user.id, username: user.username)) return null;
  final assigned = await db.getRawUserBranchAssignments(user.id);
  return assigned.contains(deviceBranch) ? null : AuthDenialCode.branchAccessDenied;
}

class AuthAudit {
  AuthAudit._();

  /// A session is audited at most once per user + device per this interval.
  static const Duration sessionInterval = Duration(minutes: 10);
  static final Map<String, DateTime> _sessionSeen = {};

  /// True when a `session_issued` line should be written now (throttled).
  static bool shouldLogSession(int userId, String? deviceId, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final key = '$userId@${deviceId ?? '-'}';
    final last = _sessionSeen[key];
    if (last != null && at.difference(last) < sessionInterval) return false;
    _sessionSeen[key] = at;
    return true;
  }

  static void resetForTesting() => _sessionSeen.clear();

  /// Writes one audit line. Failure to audit never fails the request.
  static Future<void> log(
    AppDatabase db,
    Request request, {
    required String action,
    required User user,
    String? detail,
  }) async {
    try {
      final device = request.context['lanDeviceId'];
      final kind = request.context['lanDeviceKind'];
      await ActivityLogger(db).log(
        userId: user.id,
        userName: user.username,
        action: action,
        entityType: 'user',
        entityId: user.id,
        description: 'device=${device ?? '-'} kind=${kind ?? '-'}'
            '${detail == null ? '' : ' $detail'}',
        ipAddress: ClientAddress.of(request),
      );
    } catch (_) {
      // Audit must never turn an authentication decision into a crash.
    }
  }
}
