// 062 (D1-004) — PermissionEnforcer: thin throw-on-deny façade for the
// 6 criticalFinancialOps codes.
//
// Why a separate service rather than calling userHasPermission inline:
//  - Self-documenting at the call site: `enforcer.requireCriticalOp(...)`
//    signals "this throws if denied, no defensive null-check needed".
//  - Centralizes the Arabic-message + diagnostic-log pattern so future
//    additions stay consistent.
//  - Trivial to mock in tests.
//
// Design note: this file deliberately does NOT import `database.dart`,
// to avoid creating a circular import (database.dart → DAO part files
// → PermissionEnforcer → database.dart). Instead, the constructor takes
// a function reference matching the database's `userHasPermission`
// signature. Production callers pass `db.userHasPermission`; tests can
// pass a stub.
//
// See specs/062-wire-critical-financial-ops/contracts/critical-financial-gates.md C-1.

/// Signature of `AppDatabase.userHasPermission(userId, code)`.
typedef HasPermissionFn = Future<bool> Function(int userId, String code);

/// Thrown by [PermissionEnforcer.requireCriticalOp] when the calling user
/// does not hold the required permission. Carries both the code (for
/// programmatic handling) and an Arabic user-facing message.
class PermissionDeniedException implements Exception {
  PermissionDeniedException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class PermissionEnforcer {
  PermissionEnforcer(this._hasPermission);
  final HasPermissionFn _hasPermission;

  /// True iff the user holds the permission. `userId == null` (or 0) is
  /// treated as "no permission" — sync-replay paths and system-init
  /// callers MUST pass null. The downstream userHasPermission already
  /// exempts criticalFinancialOps from the system-admin auto-bypass
  /// (lib/data/database/daos/permissions_dao.dart:209-216).
  Future<bool> hasCriticalOp(int? userId, String code) async {
    if (userId == null || userId == 0) return false;
    return _hasPermission(userId, code);
  }

  /// Throws [PermissionDeniedException] iff the user does NOT hold the
  /// permission. The Arabic message names the missing permission so the
  /// dialog / snackbar that surfaces the throw can guide the operator.
  Future<void> requireCriticalOp({
    required int? userId,
    required String code,
    required String arabicReason,
  }) async {
    final ok = await hasCriticalOp(userId, code);
    if (!ok) {
      throw PermissionDeniedException(code, arabicReason);
    }
  }
}
