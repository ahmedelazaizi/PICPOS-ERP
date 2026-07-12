import 'package:flutter/foundation.dart';

/// Action-scoped manager approval cache.
///
/// Eliminates the double-prompt that appears when a cashier saves a POS
/// invoice with a permission they don't have locally:
///
///   1. `PermissionGuard` on the "حفظ وفتح الدرج" button checks `pos_save`,
///      sees it's missing, and shows the manager-override dialog. The
///      cashier types the admin password → guard accepts → the button's
///      onPressed fires.
///   2. Inside `_processPaymentAndSave` the code calls
///      `_userHasPermissionFresh('pos_save')` as a defence-in-depth gate
///      against keyboard / programmatic save paths. That check re-reads
///      the DB, sees `pos_save` still missing, and prompts AGAIN.
///
/// The contract of the override dialog is "authorise this single action,
/// then forget" — but "this single action" in practice spans multiple
/// guards in the same call chain (button click → save method → server
/// push). Without a short-lived approval, every guard in that chain
/// re-prompts, and the operator sees a cascade of dialogs.
///
/// This cache stores `(permission, approvedAt)` entries with a 60-second
/// TTL. `consume(permission)` returns true iff there's a fresh approval —
/// and removes it so the same approval can't authorise unrelated actions
/// later in the session. That gives us the right balance:
///   • One admin-password entry per high-level operation.
///   • The approval can't leak across distinct user actions (60s window
///     is tight enough that even a fast typist must re-prompt for the
///     next operation).
///   • No global session elevation is left dangling — `AuthState.elevate`
///     still isn't touched.
class ManagerApprovalCache {
  ManagerApprovalCache._();
  static final ManagerApprovalCache instance = ManagerApprovalCache._();

  final Map<String, DateTime> _approvals = {};
  static const _ttl = Duration(seconds: 60);

  /// Record a successful manager approval for [permission]. Subsequent
  /// permission checks for the same code within [_ttl] will pass without
  /// prompting again, until consumed.
  void grant(String permission) {
    if (permission.isEmpty) return;
    _approvals[permission] = DateTime.now();
    debugPrint('[MgrApproval] granted "$permission" for ${_ttl.inSeconds}s');
  }

  /// Returns true if there's a fresh approval for [permission] AND removes
  /// it (single-use). Stale entries (older than [_ttl]) are evicted.
  bool consume(String permission) {
    final stamp = _approvals[permission];
    if (stamp == null) return false;
    final age = DateTime.now().difference(stamp);
    if (age > _ttl) {
      _approvals.remove(permission);
      debugPrint('[MgrApproval] "$permission" expired (age=${age.inSeconds}s)');
      return false;
    }
    _approvals.remove(permission);
    debugPrint('[MgrApproval] consumed "$permission" (age=${age.inSeconds}s)');
    return true;
  }

  /// Non-destructive check — exposed for diagnostics. Prefer [consume] in
  /// the hot path so each approval authorises exactly one action.
  bool isFresh(String permission) {
    final stamp = _approvals[permission];
    if (stamp == null) return false;
    return DateTime.now().difference(stamp) <= _ttl;
  }

  /// Clears all approvals — call on logout to guarantee no carry-over
  /// between sessions on the same device.
  void clear() {
    _approvals.clear();
  }
}
