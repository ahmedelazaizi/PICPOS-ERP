// 060 (D1-001) — Per-user authentication for the embedded HTTP server.
//
// Today the only auth is a shared Bearer token; once a client holds the
// token it can call any mutation endpoint with no per-user check. This
// helper adds an X-User-Id header layer that identifies WHICH user
// behind the token is making the request, plus a helper to gate
// individual handlers on a permission code.
//
// **Scope (Phase 1)**: middleware extracts header, validates the userId
// against the DB, stores it in request.context['userId']. Handlers that
// opt in call `requirePermission(...)` to gate. Phase 1 wires ~6
// highest-risk endpoints; phase 2 sweeps the remaining ~85.
//
// **Backward compatibility**: the entire layer is gated by the setting
// `server_per_user_perms_enabled` (default `false` = off, behavior
// identical to pre-060). Admin flips the flag once all clients have
// shipped with X-User-Id support.

import 'package:shelf/shelf.dart';

import '../../core/auth/bootstrap_admin.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';

/// Shelf request-context keys.
class ApiUserCtx {
  ApiUserCtx._();

  // Spec 088 USR-1 — emit the bootstrap-admin bypass PERMS-WARN line at
  // most once per server boot so field operators can grep for it after
  // rollout without log spam.
  static bool _bootstrapBypassLogged = false;

  /// Stored in `request.context[userIdKey]` after the middleware
  /// validates `X-User-Id`. Null when the per-user mode is OFF.
  static const String userIdKey = 'urs.userId';

  /// Read the validated userId from the request context. Returns null
  /// when the middleware didn't populate it (per-user mode off, or
  /// header missing on a legacy client).
  static int? userIdOf(Request request) {
    final v = request.context[userIdKey];
    if (v is int) return v;
    return null;
  }

  /// Whether server-side per-user permission enforcement is currently
  /// enabled for this installation. Cheap settings lookup — handlers
  /// can short-circuit when off.
  static Future<bool> isPerUserPermsEnabled(AppDatabase db) async {
    final v = await db.getSettingValue('server_per_user_perms_enabled');
    return v == 'true';
  }

  /// Permission gate. Reads the userId from request.context, looks up
  /// `userHasPermission(userId, code)`, returns null when allowed and
  /// a Response(403) when denied.
  ///
  /// When per-user perms are disabled (setting off OR no userId stored),
  /// auto-passes — preserves pre-060 behavior.
  static Future<Response?> requirePermission(
    Request request,
    AppDatabase db,
    String code,
  ) async {
    if (!await isPerUserPermsEnabled(db)) return null;
    final userId = userIdOf(request);
    if (userId == null) {
      return Response(
        401,
        body: '{"error":"Missing X-User-Id (per-user perms enabled)"}',
        headers: const {'content-type': 'application/json'},
      );
    }
    // Spec 088 USR-1 — bootstrap admin (userId=1, by Spec 061 invariant)
    // ALWAYS short-circuits to allowed. The matrix-fill path from Spec
    // 084b and the safety net from Spec 086 remain authoritative for
    // every other user; this bypass is durable so future permission
    // codes don't have to be added to admin's grants explicitly. See
    // specs/088-mirror-hotfix-pack/contracts/permission-bypass.md.
    if (isBootstrapAdmin(userId)) {
      if (!_bootstrapBypassLogged) {
        _bootstrapBypassLogged = true;
        // ignore: discarded_futures — fire-and-forget log; we don't await
        // here to avoid adding latency to every admin request, and the
        // logger swallows its own I/O failures.
        DiagnosticLogger.log(
          'PERMS-WARN',
          'bootstrap admin bypass engaged (userId=$userId) — '
              'request path=${request.url.path} code=$code',
        );
      }
      return null;
    }
    final ok = await db.userHasPermission(userId, code);
    if (!ok) {
      return Response(
        403,
        body: '{"error":"User #$userId lacks permission: $code"}',
        headers: const {'content-type': 'application/json'},
      );
    }
    return null;
  }
}
