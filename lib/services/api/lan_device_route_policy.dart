// ADR-W3 (plan 2026-10-23) + M1 (plan 2026-10-24): a paired device is limited
// by its KIND.
//
// * `warehouse` (the PicPos Warehouse phone app) may only reach the public
//   probe, the credential-for-session call and its own `/api/m1/wh/*` routes.
//   Everything else is `403 device_scope`, so a lost or hostile phone with a
//   valid device token cannot read the ERP.
// * `mirror` (branch-manager console) is a deny-list: it keeps the console
//   surface (reads, sync, admin writes under the signed-in user's identity) but
//   has NO point-of-sale: terminal registration, held sales and the warehouse
//   phone API are `403 device_scope`.
// * `pos` (the PicPos Cashier tablet) is a deny-list too: no warehouse phone
//   API and no branch-manager console, so a stolen cashier token cannot reach
//   them (`403 device_scope`). Its sales surface stays open and is gated per
//   request by the signed-in user (`pos_access` is required at sign-in).
//   Residual: other desktop routes are not narrowed for `pos` (plan E-9).
// * Other kinds keep today's behaviour.
class LanDeviceRoutePolicy {
  LanDeviceRoutePolicy._();

  static const String warehouseKind = 'warehouse';
  static const String mirrorKind = 'mirror';
  static const String posKind = 'pos';

  /// Exact paths or `<prefix>/...` a Cashier tablet may NOT call.
  static const List<String> posDeniedPaths = ['/api/m1/wh', '/api/mirror'];

  /// Carve-outs inside [posDeniedPaths]: the desktop receipts desk.
  static const List<String> posAllowedPaths = ['/api/m1/wh/desk'];

  /// Exact paths or `<prefix>/...` a warehouse device may call.
  static const List<String> warehousePaths = [
    '/api/m1/info',
    '/api/auth/session',
    '/api/m1/wh',
  ];

  /// Exact paths or `<prefix>/...` a mirror device may NOT call (no POS).
  static const List<String> mirrorDeniedPaths = [
    '/api/pos',
    '/api/pos-terminals',
    '/api/sales/held',
    '/api/sales/held-items',
    '/api/table-requests',
    '/api/m1/wh',
  ];

  /// Owner decision 2026-10-26: the accountant's receipts desk
  /// (`/api/m1/wh/desk/*`) is a DESKTOP console route, so a mirror manager
  /// reaches it although the phone API below is denied. `MirrorConsole.guard`
  /// still demands `mirror_console` + the branch scope, and `runDesk` the
  /// receipts permission.
  static const List<String> mirrorAllowedPaths = ['/api/m1/wh/desk'];

  static bool _matches(String path, List<String> prefixes) =>
      prefixes.any((p) => path == p || path.startsWith('$p/'));

  /// Exact paths a mirror may READ (GET) although they are in
  /// [mirrorDeniedPaths]: the shared sync engine pulls the terminal registry
  /// (FLEET-1); only registering a terminal is POS.
  static const List<String> mirrorReadablePaths = ['/api/pos-terminals'];

  /// Whether a device of [kind] may call [path] (`/api/...`, no query).
  /// [method] is the HTTP method; only the mirror's read exception uses it.
  static bool allows(String? kind, String path, {String method = 'POST'}) {
    if (kind == mirrorKind) {
      if (method.toUpperCase() == 'GET' && mirrorReadablePaths.contains(path)) {
        return true;
      }
      if (_matches(path, mirrorAllowedPaths)) return true;
      return !_matches(path, mirrorDeniedPaths);
    }
    if (kind == posKind) {
      // The accountant's receipts desk is a DESKTOP surface (a desktop session
      // is paired as `pos`): it stays open, the phone API around it does not.
      if (_matches(path, posAllowedPaths)) return true;
      return !_matches(path, posDeniedPaths);
    }
    if (kind != warehouseKind) return true;
    return _matches(path, warehousePaths);
  }
}
