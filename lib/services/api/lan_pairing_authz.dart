// Service-layer authorization of device pairing (plan 2026-10-23 §B.4, G-6).
//
// Issuing a pairing code, revoking a device and listing paired devices need
// `devices_pair_manage`. The check lives here, called by [LanPairingService],
// so a UI that forgets the gate (AUTHZ-010) cannot be the only line of
// defence. Every allowed issue/revoke is written to the activity log with the
// actor, the device kind, the branch and the device id; a denial is logged too.
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../core/permissions/warehouse_permission_codes.dart';
import '../../data/database/database.dart';
import '../activity_logger.dart';
import '../permission_enforcer.dart';

/// Device kinds a pairing code may be issued for.
const Set<String> kPairableDeviceKinds = {'admin', 'pos', 'warehouse'};

class PairingAuthz {
  const PairingAuthz({required this.hasPermission, this.db});

  /// `AppDatabase.userHasPermission` in production.
  final HasPermissionFn hasPermission;
  final AppDatabase? db;

  /// Throws [PermissionDeniedException] unless [actorUserId] is an active user
  /// holding `devices_pair_manage`. [action] is `issue` | `revoke` | `list`.
  Future<void> require(
    int? actorUserId, {
    required String action,
    String? deviceKind,
    int? branchId,
    String? deviceId,
  }) async {
    final allowed = actorUserId != null &&
        actorUserId > 0 &&
        await _isLive(actorUserId) &&
        await hasPermission(
          actorUserId,
          WarehousePermissionCodes.devicesPairManage,
        );
    if (!allowed) {
      await _audit(actorUserId, 'device_pairing_denied', action, deviceKind, branchId, deviceId);
      throw PermissionDeniedException(
        WarehousePermissionCodes.devicesPairManage,
        tr('ليست لديك صلاحية ربط وإقران الأجهزة'),
      );
    }
    if (action != 'list') {
      await _audit(actorUserId, 'device_pairing_$action', action, deviceKind, branchId, deviceId);
    }
  }

  Future<bool> _isLive(int userId) async {
    final database = db;
    if (database == null) return true;
    final row = await (database.select(database.users)
          ..where((u) => u.id.equals(userId))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? true : row.isActive && !row.isLocked;
  }

  Future<void> _audit(
    int? userId,
    String action,
    String what,
    String? deviceKind,
    int? branchId,
    String? deviceId,
  ) async {
    final database = db;
    if (database == null) return;
    try {
      await ActivityLogger(database).log(
        userId: userId,
        userName: userId == null ? '-' : 'user#$userId',
        action: action,
        entityType: 'lan_device',
        description:
            'pairing $what kind=${deviceKind ?? '-'} branch=${branchId ?? '-'} device=${deviceId ?? '-'}',
      );
    } catch (_) {
      // Audit must never turn an authorization decision into a crash.
    }
  }
}