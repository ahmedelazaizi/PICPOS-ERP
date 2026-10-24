// ADR-W3 (plan 2026-10-23): a paired device is limited by its KIND.
//
// A `warehouse` device (the PicPos Warehouse phone app) may only reach the
// public probe, the credential-for-session call and its own `/api/m1/wh/*`
// routes. Everything else - sales, parties, accounts, `/api/sync/pull`,
// settings - is `403 device_scope`, so a lost or hostile phone with a valid
// device token cannot read the ERP. Other kinds keep today's behaviour (the
// open `pos` scoping problem is reported separately, plan E-9).
class LanDeviceRoutePolicy {
  LanDeviceRoutePolicy._();

  static const String warehouseKind = 'warehouse';

  /// Exact paths or `<prefix>/...` a warehouse device may call.
  static const List<String> warehousePaths = [
    '/api/m1/info',
    '/api/auth/session',
    '/api/m1/wh',
  ];

  /// Whether a device of [kind] may call [path] (`/api/...`, no query).
  static bool allows(String? kind, String path) {
    if (kind != warehouseKind) return true;
    return warehousePaths.any((p) => path == p || path.startsWith('$p/'));
  }
}