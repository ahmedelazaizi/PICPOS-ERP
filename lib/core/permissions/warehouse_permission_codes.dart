// Warehouse app + device pairing permissions (plan 2026-10-23, §B.4).
//
// Kept out of permission_codes.dart (at its file-size ceiling). Registered
// there by one spread in `PermissionCodes.masterList` and one category
// name. Only codes that have an enforcement point TODAY live here; the
// remaining plan codes (goods_receipt_mobile, stock_count_submit,
// stock_adjust_approve) are added by the phase that enforces them (W2-W4).
import 'package:picpos_erp/core/i18n/tr.dart';

/// Category key of the warehouse-app / device-pairing permissions.
const String kWarehouseMobileCategory = 'warehouse_mobile';

abstract final class WarehousePermissionCodes {
  /// Issue pairing codes for ANY device kind (admin | pos | warehouse),
  /// list paired devices and revoke them. Enforced in the service layer
  /// (LanPairingService), not only in the UI (AUTHZ-010).
  static const String devicesPairManage = 'devices_pair_manage';

  /// Use the warehouse mobile app (/api/m1/wh/*). Pairing a phone does NOT
  /// grant it; the signed-in user's role does.
  static const String warehouseMobileAccess = 'warehouse_mobile_access';
}

/// Rows appended to `PermissionCodes.masterList`.
List<Map<String, String>> get warehouseMobilePermissionEntries => [
  {
    'code': WarehousePermissionCodes.devicesPairManage,
    'name': tr('ربط وإقران الأجهزة وإلغاء ربطها'),
    'category': kWarehouseMobileCategory,
  },
  {
    'code': WarehousePermissionCodes.warehouseMobileAccess,
    'name': tr('استعمال تطبيق المخازن على الهاتف'),
    'category': kWarehouseMobileCategory,
  },
];