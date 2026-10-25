// ═══════════════════════════════════════════════════════════════════════════
// Branch-manager console (mirror) guard on the MAIN (plan 2026-10-24, M2 / B.12).
//
// A request from a paired `mirror` device is authorised here, per request, by
//   1. the signed-in user's OWN `mirror_console` permission (a revoked grant
//      stops the console at once, not at session expiry),
//   2. the BRANCH CONTEXT the console works in: `X-Branch-Id` and any
//      `branchId` / `branch_id` in a write body must be inside the user's branch
//      scope (`403 branch_access_denied`),
//   3. the ACTING USER: a write is attributed to the session user ONLY. The body
//      can never name somebody else (`403 actor_mismatch`); the server stamps
//      `actorUserId` and `userId` from the session (the console no longer
//      stamps "the admin who paired the device").
// Writes need a session (`401 session_required`); the mirror has no outbox, so
// nothing is ever queued under another identity.
//
// Contract: docs/plans/2026-10-24-users-login-sync-logic-plan.md, "M2 -
// implemented contract". Other device kinds are never touched by this guard.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../core/permissions/mirror_permission_codes.dart';
import '../../data/database/database.dart';
import 'api_user_context.dart';

/// Machine-readable codes this guard adds to a refusal.
abstract final class MirrorGuardCode {
  static const String sessionRequired = 'session_required';
  static const String consoleDenied = 'mirror_console_denied';
  static const String branchDenied = 'branch_access_denied';
  static const String invalidBranch = 'invalid_branch';
  static const String actorMismatch = 'actor_mismatch';
}

class MirrorConsole {
  MirrorConsole._();

  static AppDatabase? _db;

  /// Called by `ApiHandler`'s constructor (like `WebSessionGuard.configure`).
  static void configure(AppDatabase db) => _db = db;

  /// Paths whose body `userId` names the TARGET of an administrative action,
  /// not the actor: they are never rewritten and never actor-checked.
  static const List<String> targetUserPaths = [
    '/api/users',
    '/api/user-',
    '/api/roles',
    '/api/role_permissions',
    '/api/permissions',
  ];

  /// Reachable without a session (handshake, pairing, credential calls).
  static const List<String> sessionlessPaths = [
    '/api/auth/',
    '/api/pair',
    '/api/sync/heartbeat',
  ];

  /// `p` ending in `/` or `-` is a plain string prefix; otherwise `p` itself or
  /// anything below `p/` (so `/api/users` does not match `/api/users2`).
  static bool _under(String path, List<String> prefixes) => prefixes.any((p) {
        if (p.endsWith('/') || p.endsWith('-')) return path.startsWith(p);
        return path == p || path.startsWith('$p/');
      });

  /// The branches [userId] may work in: `null` = every branch, `[]` = none.
  static Future<List<int>?> scopeOf(AppDatabase db, int userId) async {
    final allowed = await db.getUserAccessibleBranchIds(userId);
    if (allowed.isNotEmpty) return allowed;
    return await db.isFullBranchAccessUser(userId) ? null : const <int>[];
  }

  static bool _inScope(List<int>? scope, int branchId) =>
      scope == null || scope.contains(branchId);

  static Response _deny(int status, String code, String error) => Response(
        status,
        body: jsonEncode({'error': error, 'code': code}),
        headers: const {'content-type': 'application/json'},
      );

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// Wraps [inner]: authorises a mirror request, or passes any other through.
  static Future<Response> guard(Request request, Handler inner) async {
    final db = _db;
    if (db == null || request.context['lanDeviceKind'] != 'mirror') {
      return inner(request);
    }
    final path = '/${request.url.path}';
    final write = !const {'GET', 'HEAD', 'OPTIONS'}.contains(request.method);
    final uid = ApiUserCtx.userIdOf(request);
    if (uid == null) {
      if (write && !_under(path, sessionlessPaths)) {
        return _deny(401, MirrorGuardCode.sessionRequired,
            'A mirror write needs a signed-in user');
      }
      return inner(request);
    }
    if (_under(path, const ['/api/auth/'])) return inner(request);

    if (!await db.userHasPermission(uid, MirrorPermissionCodes.mirrorConsole)) {
      return _deny(403, MirrorGuardCode.consoleDenied,
          'This account may not use the branch-manager console');
    }
    final scope = await scopeOf(db, uid);

    final header = request.headers['x-branch-id'];
    if (header != null && header.trim().isNotEmpty) {
      final id = int.tryParse(header.trim());
      if (id == null || id <= 0) {
        return _deny(400, MirrorGuardCode.invalidBranch, 'Invalid X-Branch-Id');
      }
      if (!_inScope(scope, id)) {
        return _deny(403, MirrorGuardCode.branchDenied,
            'The branch is outside your scope');
      }
    }
    if (!write) return inner(request);

    final text = await request.readAsString();
    Object? decoded;
    try {
      decoded = text.trim().isEmpty ? null : jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      return inner(request.change(body: text));
    }
    for (final key in const ['branchId', 'branch_id']) {
      final b = _asInt(decoded[key]);
      if (b != null && !_inScope(scope, b)) {
        return _deny(403, MirrorGuardCode.branchDenied,
            'The branch is outside your scope');
      }
    }
    final target = _under(path, targetUserPaths);
    final claimedActor = _asInt(decoded['actorUserId']);
    final claimedUser = target ? null : _asInt(decoded['userId']);
    if ((claimedActor != null && claimedActor != uid) ||
        (claimedUser != null && claimedUser != uid)) {
      // A device-local user id may differ from the main's for the SAME person
      // (the handlers resolve it by username / global id), so a differing id is
      // tolerated only when the body's own identity stamp names the signed-in
      // user - and it is rewritten to the session id below either way.
      if (!await _namesSessionUser(db, uid, decoded)) {
        return _deny(403, MirrorGuardCode.actorMismatch,
            'The body names another user than the signed-in one');
      }
    }
    decoded['actorUserId'] = uid;
    if (!target) decoded['userId'] = uid;
    final rewritten = jsonEncode(decoded);
    return inner(request.change(
      body: rewritten,
      headers: {'content-length': '${utf8.encode(rewritten).length}'},
    ));
  }

  /// Does the body's identity stamp (`createdByUsername` / `userGlobalId`) name
  /// the signed-in user?
  static Future<bool> _namesSessionUser(
    AppDatabase db,
    int uid,
    Map<String, dynamic> body,
  ) async {
    final name = (body['createdByUsername'] as String?)?.trim();
    final gid = (body['userGlobalId'] as String?)?.trim();
    if ((name == null || name.isEmpty) && (gid == null || gid.isEmpty)) {
      return false;
    }
    final me = await (db.select(db.users)..where((u) => u.id.equals(uid)))
        .getSingleOrNull();
    if (me == null) return false;
    return (name != null && name.isNotEmpty && name == me.username) ||
        (gid != null && gid.isNotEmpty && gid == me.globalId);
  }

  // ── GET /api/mirror/context ──────────────────────────────────────────────
  /// The console's working context for the signed-in user:
  /// `{userId, fullAccess, branches:[{id,name,code}], defaultBranchId,
  ///   canConsole, serverTime}`. Branches are exactly the user's scope.
  static Future<Response> context(Request request) async {
    final db = _db;
    final uid = ApiUserCtx.userIdOf(request);
    if (db == null || uid == null || !await ApiUserCtx.isUserLive(db, uid)) {
      return _deny(401, MirrorGuardCode.sessionRequired,
          'Missing or invalid X-Session-Token');
    }
    final scope = await scopeOf(db, uid);
    final q = db.select(db.branches)
      ..where((b) => b.isActive.equals(true) & b.deletedAt.isNull());
    final rows = (await q.get())
        .where((b) => _inScope(scope, b.id))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final home = await db.getUserBranchId(uid);
    final ids = rows.map((b) => b.id).toList();
    final defaultId = ids.contains(home) ? home : (ids.isEmpty ? null : ids.first);
    return Response.ok(
      jsonEncode({
        'userId': uid,
        'fullAccess': scope == null,
        'canConsole': await db.userHasPermission(
            uid, MirrorPermissionCodes.mirrorConsole),
        'branches': [
          for (final b in rows) {'id': b.id, 'name': b.name, 'code': b.code}
        ],
        'defaultBranchId': defaultId,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      }),
      headers: const {'content-type': 'application/json'},
    );
  }
}
