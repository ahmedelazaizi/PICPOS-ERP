// ═══════════════════════════════════════════════════════════════════════════
// PASSWORD COLLISION SCANNER — Feature 004 (Multi-Branch Governance, US2)
// ═══════════════════════════════════════════════════════════════════════════
//
// Asynchronously scans every user in branches OTHER THAN the affected user's
// branches and detects whether the new plaintext password verifies against
// another user's stored hash. Cross-branch matches surface as:
//   1. an ActivityLog row (action='password_collision_detected') — one row
//      per detection event for auditability (FR-011);
//   2. a Notification row per System Admin (deduped per unordered user-pair —
//      FR-014). The Notification surface uses three rendering paths in the
//      app: a transient banner on the admin's next session, a persistent
//      "Security Alerts" panel on the user-management screen, and the
//      activity log itself.
//
// Boundaries (research.md Decision 4):
//   • Server / standalone mode  — scanner runs locally; the local DB has
//     every user across every branch.
//   • Paired client mode        — scanner short-circuits to a no-op. The
//     client only has its own branch's users; running the scan locally
//     would miss cross-branch collisions. The server runs its own scan
//     when the user write arrives via sync.
//
// Boundaries (per spec):
//   • FR-016 — same-branch collisions are out of scope. Two users with
//     overlapping branch sets do not trigger a warning.
//   • FR-017 — self-update with the same password (no real change) does
//     not trigger a warning.
//   • FR-013 — the warning is informational only; it never blocks the save.
//
// Performance (revised SC-005): the scan never blocks the user save (the
// caller fires `unawaited(...)`). For up to ~500 users, the background
// scan completes within ~30 seconds at p95 on desktop hardware (Argon2id
// at the project's tuning takes ~30-50ms per verify).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import 'network_service.dart';
import 'security_service.dart';

/// Scans for cross-branch password collisions and emits notifications.
///
/// Construct one instance per app boot and inject it where user write paths
/// need to fire scans. The DAO's responsibilities are the durable insert/
/// update; this service handles the side-effect of detection and alerting.
class PasswordCollisionScanner {
  PasswordCollisionScanner(this._db);

  final AppDatabase _db;

  /// New ActivityLog action constant adopted by US2. Public so other code
  /// (security-alerts panel, audit-log filters) can reference it without
  /// hard-coding the string.
  static const String activityLogAction = 'password_collision_detected';

  /// Notification's `relatedEntityType` constant — used by the UI panel
  /// stream provider to filter for these alerts. Public for the same
  /// reason as [activityLogAction].
  static const String notificationEntityType = 'password_collision';

  /// Run a cross-branch collision scan for the given user against every
  /// other user, asynchronously. Caller should invoke this with `unawaited`
  /// so the user-facing save never blocks. Safe to call multiple times for
  /// the same user — Notification dedup ensures at most one unresolved
  /// alert per user pair (FR-014).
  ///
  /// [skipIfMatchesHash] / [skipIfMatchesSalt]: when supplied (typically by
  /// the `updateUserPassword` caller), the scanner first verifies [plaintext]
  /// against this hash. If it matches, the user's password didn't actually
  /// change → scan is a no-op (FR-017). For [createUser], pass null.
  Future<void> scanAndNotify({
    required int affectedUserId,
    required String plaintext,
    String? skipIfMatchesHash,
    String? skipIfMatchesSalt,
  }) async {
    // ── Boundary: paired clients never run the scan locally ─────────────
    // Research.md Decision 4: the server (or standalone deployment) is the
    // only node with the union of all users. Running on a paired client
    // gives false negatives because the client lacks other-branch users.
    if (NetworkService.instance.isClient) return;

    // ── FR-017 — self-equality: caller pre-update → caller hash matched ─
    if (skipIfMatchesHash != null && skipIfMatchesHash.isNotEmpty) {
      final selfMatch = await SecurityService.verifyPasswordFull(
        plaintext,
        skipIfMatchesSalt ?? '',
        skipIfMatchesHash,
      );
      if (selfMatch.verified) return;
    }

    // ── Look up the affected user's branch set ──────────────────────────
    final myBranches = await _branchesOf(affectedUserId);
    // A user with no branches yet (e.g., createUser fired before
    // setUserBranchAccess) cannot be classified as cross-branch. No-op.
    if (myBranches.isEmpty) return;

    // ── Iterate candidate users in OTHER branches ───────────────────────
    final candidates = await _candidateUsersOutside(
      affectedUserId,
      myBranches,
    );

    for (final candidate in candidates) {
      try {
        final result = await SecurityService.verifyPasswordFull(
          plaintext,
          candidate.passwordSalt,
          candidate.passwordHash,
        );
        if (!result.verified) continue;

        // We have a cross-branch collision. Resolve branches for both users
        // (best-effort; scanner falls back to first known branch for each).
        final affectedBranch =
            myBranches.isNotEmpty ? myBranches.first : null;
        final candidateBranches = await _branchesOf(candidate.id);
        final candidateBranch = candidateBranches.isNotEmpty
            ? candidateBranches.first
            : null;

        await _emitActivityLog(
          affectedUserId: affectedUserId,
          affectedBranchId: affectedBranch,
          matchedUserId: candidate.id,
          matchedUserName: candidate.username,
          matchedBranchId: candidateBranch,
        );

        await _emitNotificationsToAdmins(
          userIdA: affectedUserId,
          userIdB: candidate.id,
          branchA: affectedBranch,
          branchB: candidateBranch,
        );
      } catch (_) {
        // Argon2 verify can throw on malformed legacy hashes; skip and
        // continue scanning the remaining candidates. Soft-failing here
        // matches the spirit of FR-013 (warning is informational).
      }
    }
  }

  /// Mark every unresolved password-collision notification involving [userId]
  /// as read. Caller invokes this on a successful password change so old
  /// warnings disappear from the admin's panel automatically. Same-pair
  /// dedup (FR-014) treats unresolved notifications as ones whose `isRead`
  /// is false; setting it true unblocks future warnings.
  Future<void> resolveCollisionsInvolving(int userId) async {
    if (NetworkService.instance.isClient) return;

    // Unfortunately the body is JSON — we filter in Dart after a coarse query
    // by relatedEntityType. The volume of password_collision notifications
    // is bounded (one per pair) so the in-Dart pass is acceptable.
    final allCollisions = await (_db.select(_db.notifications)
          ..where((n) =>
              n.relatedEntityType.equals(notificationEntityType) &
              n.isRead.equals(false)))
        .get();

    for (final n in allCollisions) {
      try {
        final body = jsonDecode(n.body) as Map<String, dynamic>;
        final pair = (body['pair'] as List?)?.cast<int>() ?? const <int>[];
        if (pair.contains(userId)) {
          await (_db.update(_db.notifications)
                ..where((row) => row.id.equals(n.id)))
              .write(const NotificationsCompanion(isRead: Value(true)));
        }
      } catch (_) {
        // Malformed body — leave it untouched.
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Return the set of branchIds the given user has access to via
  /// `user_branch_access`. Empty when no rows exist.
  Future<Set<int>> _branchesOf(int userId) async {
    final rows = await (_db.select(_db.userBranchAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    return rows.map((r) => r.branchId).toSet();
  }

  /// Return all users whose branch set is DISJOINT from [myBranches] — that
  /// is, users who don't share a single branch with the affected user. Same-
  /// branch pairs are filtered out per FR-016. Excludes the affected user.
  Future<List<User>> _candidateUsersOutside(
    int affectedUserId,
    Set<int> myBranches,
  ) async {
    if (myBranches.isEmpty) return const [];

    // Pull the user-branch matrix once. Shape: userId → Set<branchId>.
    final allAccess = await _db.select(_db.userBranchAccess).get();
    final byUser = <int, Set<int>>{};
    for (final row in allAccess) {
      byUser.putIfAbsent(row.userId, () => <int>{}).add(row.branchId);
    }

    // Pull active users (excluding the affected one). Soft-deleted users
    // (isActive=false AND isLocked=true) are skipped — they can't log in,
    // so their password collision is irrelevant.
    final allUsers = await (_db.select(_db.users)
          ..where((u) =>
              u.id.equals(affectedUserId).not() &
              (u.isActive.equals(true) | u.isLocked.equals(false))))
        .get();

    final out = <User>[];
    for (final u in allUsers) {
      final theirBranches = byUser[u.id] ?? const <int>{};
      if (theirBranches.isEmpty) continue; // unassigned — skip
      // Cross-branch iff the two sets do not share any branch (FR-016).
      final shared = theirBranches.intersection(myBranches);
      if (shared.isEmpty) {
        out.add(u);
      }
    }
    return out;
  }

  /// Insert one ActivityLog row per detection event. ActivityLogs are
  /// append-only and intentionally NOT deduped (FR-014 distinguishes
  /// notifications from the audit trail).
  Future<void> _emitActivityLog({
    required int affectedUserId,
    required int? affectedBranchId,
    required int matchedUserId,
    required String matchedUserName,
    required int? matchedBranchId,
  }) async {
    await _db.logActivity(
      userId: null, // system-driven detection (no operator on this thread)
      userName: 'system',
      action: activityLogAction,
      entityType: 'user',
      entityId: affectedUserId,
      description:
          'تم اكتشاف تطابق كلمة مرور بين المستخدم رقم $affectedUserId '
          'فى الفرع ${affectedBranchId ?? '—'} '
          'والمستخدم $matchedUserName (#$matchedUserId) '
          'فى الفرع ${matchedBranchId ?? '—'}',
      newValue: jsonEncode({
        'affectedUserId': affectedUserId,
        'affectedBranchId': affectedBranchId,
        'matchedUserId': matchedUserId,
        'matchedBranchId': matchedBranchId,
        'detectedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      branchId: affectedBranchId,
    );
  }

  /// Emit one Notification per System Admin user, deduped by the canonical
  /// unordered user-pair key. If an unresolved notification (`isRead=false`)
  /// already exists for the same pair on a given admin, no new row is
  /// created (FR-014).
  Future<void> _emitNotificationsToAdmins({
    required int userIdA,
    required int userIdB,
    required int? branchA,
    required int? branchB,
  }) async {
    final smaller = userIdA < userIdB ? userIdA : userIdB;
    final larger = userIdA < userIdB ? userIdB : userIdA;

    // Find every admin role row (مدير النظام + isSystemRole = true) and the
    // users that hold those roles.
    final adminRoleIds = await (_db.select(_db.roles)
          ..where((r) =>
              r.name.equals('مدير النظام') & r.isSystemRole.equals(true)))
        .get();
    if (adminRoleIds.isEmpty) return;

    final adminUsers = await (_db.select(_db.users)
          ..where((u) =>
              u.roleId.isIn(adminRoleIds.map((r) => r.id)) &
              u.isActive.equals(true)))
        .get();

    final body = jsonEncode({
      'kind': 'password_collision',
      'pair': [smaller, larger],
      'branchA': branchA,
      'branchB': branchB,
      'detectedAt': DateTime.now().toUtc().toIso8601String(),
    });

    for (final admin in adminUsers) {
      // Dedup: skip if there's already an unresolved notification for this
      // admin + this pair.
      final existing = await (_db.select(_db.notifications)
            ..where((n) =>
                n.userId.equals(admin.id) &
                n.relatedEntityType.equals(notificationEntityType) &
                n.relatedEntityId.equals(smaller) &
                n.isRead.equals(false)))
          .get();
      final alreadyHasPair = existing.any((n) {
        try {
          final decoded = jsonDecode(n.body) as Map<String, dynamic>;
          final pair =
              (decoded['pair'] as List?)?.cast<int>() ?? const <int>[];
          return pair.length == 2 &&
              pair.contains(smaller) &&
              pair.contains(larger);
        } catch (_) {
          return false;
        }
      });
      if (alreadyHasPair) continue;

      await _db.createNotification(
        userId: admin.id,
        title: 'تنبيه أمنى: تطابق كلمة مرور بين فروع',
        body: body,
        type: 'warning',
        relatedEntityId: smaller,
        relatedEntityType: notificationEntityType,
      );
    }
  }
}
