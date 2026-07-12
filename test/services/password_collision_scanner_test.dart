// ═══════════════════════════════════════════════════════════════════════════
// Feature 004 (Multi-Branch Governance, US2) — Cross-branch password
// collision scanner tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers spec.md FRs:
//   FR-009/010 — cross-branch collision creates ActivityLog + Notification
//   FR-011    — every detection event writes a row to activity_logs (audit)
//   FR-013    — scan never blocks the save (already async via unawaited;
//                  here we verify structure rather than timing)
//   FR-014    — duplicate Notification for the same pair is deduped
//   FR-016    — same-branch pairs are skipped
//   FR-017    — self-update with the same password is a no-op
//   U1        — paired client mode short-circuits to no-op
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/password_collision_scanner.dart';
import 'package:ural_erp/services/security_service.dart';

void main() {
  late AppDatabase db;
  late PasswordCollisionScanner scanner;
  late int adminRoleId;
  late int branchA;
  late int branchB;
  late int adminUserId;

  Future<int> insertUserWithHash({
    required String username,
    required String password,
    int? roleId,
  }) async {
    final hash = await SecurityService.hashPasswordArgon2(password);
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hash,
            displayName: username,
          ).copyWith(
            passwordSalt: const Value(''),
            roleId: Value(roleId),
            globalId: Value('gid-$username'),
          ),
        );
  }

  Future<void> assignBranches(int userId, List<int> branchIds) async {
    for (final b in branchIds) {
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: b),
          );
    }
  }

  Future<List<NotificationData>> readCollisionNotifications() async {
    return (db.select(db.notifications)
          ..where((n) => n.relatedEntityType
              .equals(PasswordCollisionScanner.notificationEntityType)))
        .get();
  }

  Future<List<ActivityLog>> readCollisionActivityLogs() async {
    return (db.select(db.activityLogs)
          ..where((a) => a.action
              .equals(PasswordCollisionScanner.activityLogAction)))
        .get();
  }

  setUp(() async {
    // Reset NetworkService to standalone before every test so the scanner
    // does not short-circuit unless the test explicitly opts into client
    // mode (the U1 case).
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);

    db = AppDatabase.forTesting();
    scanner = PasswordCollisionScanner(db);

    // Seed the System Admin role and two branches.
    adminRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير النظام',
            isSystemRole: const Value(true),
            globalId: const Value('gid-role-admin'),
          ),
        );
    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع A',
            globalId: const Value('gid-branch-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع B',
            globalId: const Value('gid-branch-b'),
          ),
        );

    // Seed an admin so notifications have a recipient.
    adminUserId = await insertUserWithHash(
      username: 'admin1',
      password: 'admin-password-distinct',
      roleId: adminRoleId,
    );
    await assignBranches(adminUserId, [branchA]);
  });

  tearDown(() async {
    await db.close();
  });

  group('scanAndNotify', () {
    test('(a) cross-branch collision creates ActivityLog + Notification', () async {
      // Two non-admin users in different branches with the same password.
      const sharedPassword = 'shared-secret-1234';
      final userA = await insertUserWithHash(
        username: 'user-aa',
        password: sharedPassword,
      );
      await assignBranches(userA, [branchA]);

      final userB = await insertUserWithHash(
        username: 'user-bb',
        password: sharedPassword,
      );
      await assignBranches(userB, [branchB]);

      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );

      final logs = await readCollisionActivityLogs();
      expect(logs, hasLength(greaterThanOrEqualTo(1)),
          reason: 'FR-011 — at least one audit row');

      final notifs = await readCollisionNotifications();
      expect(notifs.where((n) => n.userId == adminUserId), hasLength(1),
          reason: 'FR-010 — exactly one warning emitted to System Admin');
      final pair =
          (jsonDecode(notifs.first.body) as Map<String, dynamic>)['pair'] as List;
      expect(pair.cast<int>().toSet(), {userA, userB},
          reason: 'pair key is the unordered (smaller, larger) tuple');
    });

    test('(b) same-branch collision is a no-op (FR-016)', () async {
      const sharedPassword = 'same-branch-pass-7777';
      final u1 = await insertUserWithHash(
        username: 'same1',
        password: sharedPassword,
      );
      await assignBranches(u1, [branchA]);

      final u2 = await insertUserWithHash(
        username: 'same2',
        password: sharedPassword,
      );
      await assignBranches(u2, [branchA]);

      await scanner.scanAndNotify(
        affectedUserId: u2,
        plaintext: sharedPassword,
      );

      expect(await readCollisionActivityLogs(), isEmpty);
      expect(await readCollisionNotifications(), isEmpty);
    });

    test('(c) self-update with the same password is a no-op (FR-017)', () async {
      const password = 'unchanged-pass-9999';
      final user = await insertUserWithHash(
        username: 'self',
        password: password,
      );
      await assignBranches(user, [branchA]);

      // Capture the user's stored hash to feed into the FR-017 self-equality
      // probe — the realistic call path from updateUserPassword's pre-write.
      final stored =
          await (db.select(db.users)..where((u) => u.id.equals(user))).getSingle();

      // Add a second user in another branch with the same password — if the
      // self-equality guard does NOT short-circuit, this would otherwise
      // produce a collision warning.
      final other = await insertUserWithHash(
        username: 'other',
        password: password,
      );
      await assignBranches(other, [branchB]);

      await scanner.scanAndNotify(
        affectedUserId: user,
        plaintext: password,
        skipIfMatchesHash: stored.passwordHash,
        skipIfMatchesSalt: stored.passwordSalt,
      );

      expect(await readCollisionActivityLogs(), isEmpty,
          reason: 'FR-017 self-equality short-circuits before any candidate scan');
      expect(await readCollisionNotifications(), isEmpty);
    });

    test('(d)+(e) duplicate Notification deduped, ActivityLog still records every event',
        () async {
      const sharedPassword = 'dedup-pair-pass';
      final userA = await insertUserWithHash(
        username: 'dedupA',
        password: sharedPassword,
      );
      await assignBranches(userA, [branchA]);

      final userB = await insertUserWithHash(
        username: 'dedupB',
        password: sharedPassword,
      );
      await assignBranches(userB, [branchB]);

      // Run the scanner twice for the same affected user. The second run must
      // produce a fresh ActivityLog row but suppress the duplicate Notification.
      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );
      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );

      final logs = await readCollisionActivityLogs();
      expect(logs.length, greaterThanOrEqualTo(2),
          reason: '(e) ActivityLog records every detection event (A2)');

      final notifs = await readCollisionNotifications();
      expect(notifs.where((n) => n.userId == adminUserId), hasLength(1),
          reason: '(d) FR-014 — only one unresolved Notification per pair per admin');
    });
  });

  group('resolveCollisionsInvolving', () {
    test('(f) marks every unresolved warning involving [userId] as read', () async {
      const sharedPassword = 'resolve-me';
      final userA = await insertUserWithHash(
        username: 'resolveA',
        password: sharedPassword,
      );
      await assignBranches(userA, [branchA]);

      final userB = await insertUserWithHash(
        username: 'resolveB',
        password: sharedPassword,
      );
      await assignBranches(userB, [branchB]);

      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );

      final before = await readCollisionNotifications();
      expect(before.every((n) => !n.isRead), isTrue,
          reason: 'sanity — newly emitted warnings start as unread');

      await scanner.resolveCollisionsInvolving(userB);

      final after = await readCollisionNotifications();
      expect(after.every((n) => n.isRead), isTrue,
          reason: 'resolveCollisionsInvolving flips isRead for every row whose '
              'body.pair contains the userId');
    });
  });

  group('isClient gate (U1)', () {
    test('scanAndNotify is a no-op on a paired client', () async {
      const sharedPassword = 'client-no-op';
      final userA = await insertUserWithHash(
        username: 'clientA',
        password: sharedPassword,
      );
      await assignBranches(userA, [branchA]);

      final userB = await insertUserWithHash(
        username: 'clientB',
        password: sharedPassword,
      );
      await assignBranches(userB, [branchB]);

      NetworkService.instance.debugSetModeForTests(NetworkMode.client);

      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );

      expect(await readCollisionActivityLogs(), isEmpty,
          reason: 'U1 — paired clients defer the scan to the server');
      expect(await readCollisionNotifications(), isEmpty);
    });

    test('resolveCollisionsInvolving is a no-op on a paired client', () async {
      // Pre-seed a notification (using server-mode write) so we can prove the
      // resolve method does not touch it once we flip to client mode.
      const sharedPassword = 'client-resolve-no-op';
      final userA = await insertUserWithHash(
        username: 'rclientA',
        password: sharedPassword,
      );
      await assignBranches(userA, [branchA]);

      final userB = await insertUserWithHash(
        username: 'rclientB',
        password: sharedPassword,
      );
      await assignBranches(userB, [branchB]);

      await scanner.scanAndNotify(
        affectedUserId: userB,
        plaintext: sharedPassword,
      );

      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      await scanner.resolveCollisionsInvolving(userB);

      final notifs = await readCollisionNotifications();
      expect(notifs.every((n) => !n.isRead), isTrue,
          reason: 'client-mode resolveCollisionsInvolving must not alter rows');
    });
  });
}
