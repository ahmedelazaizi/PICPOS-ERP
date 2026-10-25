// Warehouse app + device pairing permissions (plan 2026-10-23, §B.4).
//
// Kept out of permission_codes.dart (at its file-size ceiling). Registered
// there by one spread in `PermissionCodes.masterList` and one category
// name. Only codes that have an enforcement point live here.
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

  /// Record goods received against a purchase order (W2). Enforced in
  /// `wh_receipt_handlers.dart`; posting stays `purchases_create`.
  static const String goodsReceiptMobile = 'goods_receipt_mobile';

  /// Submit blind-count entries (W4). Enforced in `wh_count_handlers.dart`.
  static const String stockCountSubmit = 'stock_count_submit';

  /// Approve counts, vouchers, transfer requests (W3/W4); never the approver's
  /// own work (four-eyes, enforced on the server). Enforced in
  /// `wh_count_handlers.dart` and `wh_stock_doc_handlers.dart`.
  static const String stockAdjustApprove = 'stock_adjust_approve';
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
  {
    'code': WarehousePermissionCodes.goodsReceiptMobile,
    'name': tr('استلام البضاعة مقابل أمر شراء من تطبيق المخازن'),
    'category': kWarehouseMobileCategory,
  },
  {
    'code': WarehousePermissionCodes.stockCountSubmit,
    'name': tr('إرسال نتائج الجرد الأعمى من تطبيق المخازن'),
    'category': kWarehouseMobileCategory,
  },
  {
    'code': WarehousePermissionCodes.stockAdjustApprove,
    'name': tr('اعتماد الجرد والسندات وطلبات التحويل من تطبيق المخازن'),
    'category': kWarehouseMobileCategory,
  },
];