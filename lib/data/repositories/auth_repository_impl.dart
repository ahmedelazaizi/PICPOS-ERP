import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/client_write_interceptor.dart';
import '../../services/delta_pull_service.dart';
import '../../services/login_rate_limiter.dart';
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';
import '../../services/sync_service.dart';
import '../database/database.dart';
import '../database/sync_interceptor.dart';
/// Signature for the lazy server-side `user_branch_access` fetch invoked by
/// [AuthRepositoryImpl._verifyBranchAccess] when the local assignments table
/// is empty. Returning `false` (or throwing) is treated as "no rows came
/// back" — the verifier then falls through to its empty-result path.
///
/// Feature 051 — injected so unit tests can stub the network call without
/// spinning up a real [SyncService] / HTTP client.
typedef UserBranchAccessFetcher = Future<bool> Function(AppDatabase db);

Future<bool> _defaultFetchUserBranchAccess(AppDatabase db) async {
  final serverUrl = NetworkService.instance.buildServerUrl();
  if (serverUrl.isEmpty) return false;
  final syncService = SyncService(serverUrl: serverUrl, localDb: db);
  await syncService.initialize();
  // Field-report 2026-05-14: a "مدير كل الفروع" who logged into branch A's
  // device then moved to branch B's device hit "ليس لديك صلاحية الدخول
  // لهذا الفرع" because branch B's local DB hadn't synced his
  // `user_branch_access` rows yet AND his `users` row could be stale (the
  // server-side id-to-local-id mapping needs a fresh user pull). Sync
  // `users` first so any new server rows materialise locally with the
  // correct id, then pull `user_branch_access` against that id space.
  // Timeouts bumped from 4s → 8s each — operators report Device-B is often
  // on a slower link than Device-A and 4s was racing the WAN handshake.
  try {
    await syncService
        .syncTable('users')
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[Auth] lazy users sync failed (continuing): $e');
  }
  await syncService
      .syncTable('user_branch_access')
      .timeout(const Duration(seconds: 8));
  return true;
}

class AuthRepositoryImpl implements IAuthRepository {
  final AppDatabase db;

  /// Injectable for tests — production callers omit it and get the real
  /// network-backed fetch.
  final UserBranchAccessFetcher _fetchUserBranchAccess;

  AuthRepositoryImpl(
    this.db, {
    UserBranchAccessFetcher? fetchUserBranchAccess,
  }) : _fetchUserBranchAccess =
            fetchUserBranchAccess ?? _defaultFetchUserBranchAccess;

  @override
  Stream<List<UserWithRole>> watchAllUsers() => db.watchAllUsers();

  @override
  Future<UserWithRole?> getUserById(int id) => db.getUserById(id);

  @override
  Future<UserWithRole?> getUserByUsername(String username) =>
      db.getUserByUsername(username);

  @override
  Future<int> createUser({
    int? id,
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent = true,
    String? cardCode,
    String? defaultScreen,
    bool forcePasswordChange = false,
    String? globalId,
  }) => db.createUser(
    id: id,
    username: username,
    password: password,
    displayName: displayName,
    roleId: roleId,
    maxDiscountPercent: maxDiscountPercent,
    discountLimitIsPercent: discountLimitIsPercent,
    cardCode: cardCode,
    defaultScreen: defaultScreen,
    forcePasswordChange: forcePasswordChange,
    globalId: globalId,
  );

  @override
  Future<void> updateUserInfo({
    required int userId,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent = true,
    String? cardCode,
    String? defaultScreen,
    bool? forcePasswordChange,
    String? username,
  }) => db.updateUserInfo(
    userId: userId,
    displayName: displayName,
    roleId: roleId,
    maxDiscountPercent: maxDiscountPercent,
    discountLimitIsPercent: discountLimitIsPercent,
    cardCode: cardCode,
    defaultScreen: defaultScreen,
    forcePasswordChange: forcePasswordChange,
    username: username,
  );

  @override
  Future<void> updateUserPassword({
    required int userId,
    required String newPassword,
  }) => db.updateUserPassword(userId: userId, newPassword: newPassword);

  @override
  Future<void> toggleUserActive({
    required int userId,
    required bool isActive,
  }) => db.toggleUserActive(userId: userId, isActive: isActive);

  @override
  Future<void> assignRoleToUser(int userId, int? roleId) =>
      db.assignRoleToUser(userId, roleId);

  @override
  Future<bool> setUserLocked(int userId, bool isLocked) =>
      db.setUserLocked(userId, isLocked);

  @override
  Future<List<int>> getUserAccessibleBranchIds(int userId) =>
      db.getUserAccessibleBranchIds(userId);

  @override
  Future<void> setUserBranchAccess(int userId, List<int> branchIds) async {
    // F3 (MM.E): in interceptor mode (client/mirror), route the access
    // change through PUT /api/users/{id} with `branchIds` so HQ is the
    // source of truth. Without this, the local write was overwritten by
    // the next DeltaPull from HQ — manager dialogs visibly "lost" the
    // selection on the next reload.
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateUser(userId, {
        'branchIds': branchIds,
      });
      return;
    }
    await db.setUserBranchAccess(userId, branchIds);
  }

  /// Phase 6 (T4) — fail-closed branch gate.
  ///
  /// On a paired client device, only let the user in if either:
  ///   • they are the program owner (userId == 1, "صاحب البرنامج" — the
  ///     install-wide superuser, exempt from per-branch checks), or
  ///   • their `user_branch_access` (raw, ignoring the "admin = empty list
  ///     = full access" semantics) explicitly contains the device's
  ///     branch.
  ///
  /// Previously this used [AppDatabase.getUserAccessibleBranchIds] which
  /// returns `[]` for the program owner *and* for any user whose role is
  /// "مدير النظام" / "مدير مالي". The empty list was treated as "no
  /// restrictions" → admit. That fail-open path let a branch-restricted
  /// system manager (or a user whose access rows hadn't synced yet) into
  /// the wrong device. The user's directive: a system manager is a
  /// manager *of one branch*, not of the whole install. Only the program
  /// owner gets the cross-branch escape valve.
  ///
  /// Reads `user_branch_access` via [getRawUserBranchAssignments] to avoid
  /// re-introducing the role-based bypass. `branchScopeProvider` and other
  /// view-time scope helpers continue to use [getUserAccessibleBranchIds]
  /// because there the "admin sees everything" semantic is still correct.
  Future<void> _verifyBranchAccess(UserWithRole result) async {
    if (!SyncInterceptor.isClientMode) return;
    final prefs = await SharedPreferences.getInstance();
    final localBranchId = prefs.getInt('client_branch_id');
    if (localBranchId == null) return;

    var userId = result.user.id;
    if (userId == 1) return; // program owner — never restricted

    var assignments = await db.getRawUserBranchAssignments(userId);

    // Feature 051 (v132): If local rows are empty in client mode, this may
    // be a freshly-created server-side user whose `user_branch_access` rows
    // haven't pulled to this mirror yet. The post-auth refresh in
    // LoginScreen runs *after* this guard, so it can't fix the first login
    // on its own. Trigger a targeted pull of the table here and re-read.
    // If the server confirms emptiness, fall through and throw — empty is
    // then authoritative.
    // Spec 136 ISS-10 — re-pull when the assignments are empty OR don't
    // contain this device's local branch id. The latter covers local↔server
    // branch-id DRIFT: a client whose `user_branch_access` rows still hold raw
    // SERVER branch ids (pre-remap) would be wrongly denied even though the
    // user IS assigned here. The refreshed pull now remaps server branchId →
    // local branch id via globalId (UserBranchAccessSyncStrategy / ISS-10), so
    // the re-read below matches `localBranchId`.
    if (assignments.isEmpty || !assignments.contains(localBranchId)) {
      try {
        await _fetchUserBranchAccess(db);

        // Field-report 2026-05-14: the lazy fetch now also pulls `users`
        // (see _defaultFetchUserBranchAccess), which can rename the
        // just-authenticated local row when a server row with a different
        // id but same username arrives (UserSyncStrategy's dedup path
        // suffixes the local id with __dup_X_username and deactivates it,
        // then inserts the server-id row as the active one). After that
        // pass, `result.user.id` points at the deactivated duplicate and
        // its assignments are empty. Re-resolve by username so the check
        // queries the active server-id row.
        final username = result.user.username;
        final refreshed = await db.getUserByUsername(username);
        if (refreshed != null && refreshed.user.id != userId) {
          debugPrint('[Auth] post-sync user id changed for "$username": '
              '${refreshed.user.id} (was $userId) — re-querying assignments');
          userId = refreshed.user.id;
        }
        assignments = await db.getRawUserBranchAssignments(userId);
      } catch (e) {
        debugPrint('[Auth] lazy user_branch_access fetch failed: $e');
      }
    }

    if (assignments.isEmpty || !assignments.contains(localBranchId)) {
      throw StateError('ليس لديك صلاحية الدخول لهذا الفرع');
    }
  }

  @override
  Future<UserWithRole?> authenticateUser(String username, String password) async {
    // Rate limiting: check if user is locked out
    final lockout = LoginRateLimiter.getLockoutRemaining(username);
    if (lockout != null) {
      final minutes = lockout.inMinutes + 1;
      throw StateError(
        'تم قفل الحساب مؤقتاً. يرجى المحاولة بعد $minutes دقيقة',
      );
    }

    final result = await db.authenticateUser(username, password);

    if (result != null) {
      await _verifyBranchAccess(result);
      LoginRateLimiter.recordSuccess(username);
      // Spec 151 (P1-8) — mint a signed server session token while the
      // plaintext credential is still in scope (client/mirror mode only).
      await _acquireServerSession(result, username: username, password: password);
    } else {
      final remaining = LoginRateLimiter.recordFailure(username);
      if (remaining == 0) {
        throw StateError(
          'تم قفل الحساب مؤقتاً بعد ${LoginRateLimiter.maxAttempts} محاولات فاشلة',
        );
      }
    }

    return result;
  }

  @override
  Future<UserWithRole?> authenticateByCardCode(String cardCode) async {
    final result = await db.authenticateByCardCode(cardCode);
    if (result != null) {
      await _verifyBranchAccess(result);
      // Spec 151 (P1-8) — POS card-swipe → session token via cardCode.
      await _acquireServerSession(result, cardCode: cardCode);
    }
    return result;
  }

  @override
  Future<UserWithRole?> authenticateByPasswordOrCard(String input) async {
    final result = await db.authenticateByPasswordOrCard(input);
    if (result != null) {
      await _verifyBranchAccess(result);
      // Spec 151 (P1-8) — this is the primary login-screen path (password-only,
      // username blank) AND the manager-elevation path (app_shell). The DAO
      // tries `input` as a password first, then as a card code, so disambiguate
      // by the resolved user: if `input` is the user's card code, mint via
      // cardCode; otherwise it matched as a password → mint via
      // username(resolved)+password(input).
      if (result.user.cardCode != null && result.user.cardCode == input) {
        await _acquireServerSession(result, cardCode: input);
      } else {
        await _acquireServerSession(
          result,
          username: result.user.username,
          password: input,
        );
      }
    }
    return result;
  }

  /// Spec 151 (P1-8) — single choke point that hands the just-verified
  /// credential to [ServerProxy.acquireSession] so a client/mirror device
  /// obtains a signed `X-Session-Token`. Gated on [SyncInterceptor.isClientMode]
  /// inside [ServerProxy.acquireSession] (client OR mirror). It swallows all
  /// errors and fast-fails, so awaiting it never blocks or breaks login.
  Future<void> _acquireServerSession(
    UserWithRole result, {
    String? username,
    String? password,
    String? cardCode,
  }) async {
    if (!SyncInterceptor.isClientMode) return;
    await ServerProxy.instance.acquireSession(
      userId: result.user.id,
      username: username,
      password: password,
      cardCode: cardCode,
    );
    // Spec 151 P1-8b — the moment a session token exists, backfill the
    // branch-scoped transactional tables that first-sync / boot skipped while
    // tokenless. Without this a fresh client shows EMPTY sales/purchase/GL/
    // stock/shift history until the first write (or the next app boot), because
    // nothing else re-triggers a pull post-login. Fire-and-forget — DeltaPull
    // no-ops if already pulling; the transactional watermarks are unseeded so
    // this is a full, branch-scoped dump.
    if (ServerProxy.instance.hasSessionToken(result.user.id)) {
      unawaited(DeltaPullService.instance.pullAll());
      // Spec 151 residual #1 — product_batches is NOT a DeltaPull table (absent
      // from `pullTables`), so `pullAll()` above won't backfill it. Its GET now
      // fail-closes tokenless, so a fresh client provisions with EMPTY batches
      // (breaking FEFO/expiry) until the next periodic fullSync. Heal it now
      // with the token present via its own Tier-2 strategy (branch-scoped).
      unawaited(SyncService.instance?.syncTable('product_batches') ??
          Future<void>.value());
    }
  }

  @override
  Future<List<Role>> getAllRoles() => db.getAllRoles();

  @override
  Stream<List<Role>> watchRoles() => db.watchRoles();

  @override
  Future<Role?> getRoleById(int id) => db.getRoleById(id);

  @override
  Future<int> insertRole({
    required String name,
    String? description,
    bool isSystemRole = false,
  }) => db.insertRole(
    name: name,
    description: description,
    isSystemRole: isSystemRole,
  );

  @override
  Future<bool> updateRole({
    required int id,
    required String name,
    String? description,
  }) => db.updateRole(id: id, name: name, description: description);

  @override
  Future<bool> deleteRole(int id) => db.deleteRole(id);

  @override
  Future<List<Permission>> getAllPermissions() => db.getAllPermissions();

  @override
  Future<List<Permission>> getPermissionsForRole(int roleId) =>
      db.getPermissionsForRole(roleId);

  @override
  Future<bool> userHasPermission(int userId, String permissionCode) =>
      db.userHasPermission(userId, permissionCode);

  @override
  Future<List<String>> getUserPermissionCodes(int userId) =>
      db.getUserPermissionCodes(userId);

  @override
  Future<Map<int, String>> getRolePermissionModes(int roleId) =>
      db.getRolePermissionModes(roleId);

  @override
  Future<void> setRolePermissions(
    int roleId,
    List<int> permissionIds, {
    Map<int, String>? modes,
  }) async {
    // Client mode: server is the source of truth. Push to the server BEFORE
    // touching the local DB. Reasoning:
    //   • If we wrote locally first and the network failed, the local DB
    //     would diverge from the server. The next inbound role_permissions
    //     broadcast (or scheduled sync) would reach the client with the
    //     server's stale data and silently overwrite the admin's change —
    //     the operator perceives this as "I clicked save but nothing
    //     happened on the cashier's session". The cwi_sync layer now
    //     queues offline writes in sync_outbox, so a network blip is
    //     recoverable without local-write desync.
    //   • Once the server confirms (or queues), we mirror the change to the
    //     local DB so the admin's own UI reflects it immediately. The
    //     subsequent broadcast-driven sync is then a no-op (same data).
    if (SyncInterceptor.isClientMode && SyncInterceptor.instance != null) {
      // Resolve local IDs → canonical permission codes. Codes are the
      // contract between client and server (IDs may differ across nodes
      // because the permissions table is seeded independently).
      final allPerms = await db.getAllPermissions();
      final idToCode = <int, String>{
        for (final p in allPerms) p.id: p.code,
      };
      final codes = <String>[
        for (final id in permissionIds)
          if (idToCode.containsKey(id)) idToCode[id]!,
      ];
      // Sanity-check: every selected permission must resolve to a code. If
      // we silently dropped any, the server would persist an INCOMPLETE
      // set — the admin would lose permissions they thought they were
      // saving. Refuse rather than partially save.
      if (codes.length != permissionIds.length) {
        throw StateError(
            'Permission ID→code mapping incomplete: expected '
            '${permissionIds.length} codes, resolved ${codes.length}. '
            'Local permissions table may be out of sync with the server.');
      }
      // Spec 136 ISS-15: include the role's globalId + name so the server can
      // resolve (or placeholder-create) a role that was created on this node
      // only — without it, role_permissions FK fails (Postgres 23503).
      final localRole = await db.getRoleById(roleId);
      final ok = await SyncInterceptor.instance!.setRolePermissions(
        roleId,
        codes,
        roleGlobalId: localRole?.globalId,
        roleName: localRole?.name,
      );
      if (!ok) {
        // _tryOrQueueVoid returns true when queued offline, so a `false`
        // here means a non-recoverable error (e.g. interceptor not in
        // client mode, or _db not initialised). Surface it instead of
        // silently writing to the local DB.
        throw StateError(
            'فشل توجيه طلب الصلاحيات إلى السيرفر — الطلب لم يُحفظ');
      }
      // Mirror to local DB for instant UI feedback. The server's broadcast
      // will reach this client too and re-sync (no-op when data matches).
      // ⚠️ **الأنماطُ تُكتَب في المرآة المحلّيّة رغم أنّها لا تعبر السلك**:
      //    رسالةُ الخادم تحمل `permissionCodes` وحدَها، فالنمطُ لا ينتشر
      //    إلى الخادم ولا إلى جهازٍ آخر (‏بندٌ مفتوح). لكنّ سحبَ المزامنة
      //    **لا يُسقطه**: `role_permission_sync_strategy` يبني الـcompanion
      //    بلا `grantMode`، و`insertOnConflictUpdate` لا يحدّث إلّا الأعمدةَ
      //    المعطاة. فالنمطُ يبقى صادقاً على هذا الجهاز بدل أن يُمحى.
      await db.setRolePermissions(roleId, permissionIds, modes: modes);
      return;
    }
    // Standalone / server mode: write directly, then explicitly broadcast.
    //
    // CRITICAL: The previous comment claimed "the server's own broadcast(...)
    // will fan the change out" — but the broadcast was only wired into the
    // HTTP handler (api_data_handler.setRolePermissions, line 1284). When
    // the admin opens the permissions screen *on the server itself*, the
    // change goes straight through this DAO call and never touches the
    // HTTP layer, so connected POS clients (e.g. the cashier's station)
    // never received the data_changed event. The cashier's stale
    // role_permissions cache made it look like nothing was saved, even
    // though the server DB was correct — the operator's exact symptom.
    //
    // We trigger broadcastChange() unconditionally here. It's a no-op when
    // no clients are connected (standalone mode) and idempotent when the
    // change came in via HTTP (clients pull a no-op delta).
    await db.setRolePermissions(roleId, permissionIds, modes: modes);
    try {
      NetworkService.instance.broadcastChange('role_permissions');
    } catch (e) {
      debugPrint('[AuthRepo] role_permissions broadcast failed: $e');
    }
  }

  @override
  Future<bool> updateUserPin(int userId, String? pin) =>
      db.updateUserPin(userId, pin);

  @override
  Future<bool> verifyUserPin(int userId, String pin) =>
      db.verifyUserPin(userId, pin);
}
