// Feature 049 (v131) — Branch soft-delete + user_branch_access bulk-reassign.
//
// Field repro (server_errors.log, 2026-05-13 14:04:07): admin tried to
// delete a duplicate "الفرع الرئيسي" on the server to dedup the data
// drift, and the DAO hit:
//   PG FAIL: foreign key constraint "user_branch_access_branch_id_fkey"
//   detail: Key (id)=(7) is still referenced from table user_branch_access
//
// Root cause was the same class as the v128 categories bug: a HARD DELETE
// on a table whose schema has `isActive` + `deletedAt` already in place
// for soft-delete. Pre-v131 the DAO's deleteBranch did
// `delete(branches).go()`, which fails on the FK constraint when any
// user_branch_access row references the branch.
//
// v131 replaces the HARD DELETE with soft-delete (`isActive=false`,
// `deletedAt=NOW()`), pre-flight FK checks on sales/purchases, and an
// optional bulk-reassign of user_branch_access rows when the caller
// supplies a destination (the dedup-duplicate-branch use case).

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع الرئيسي',
            globalId: const Value('gid-branch-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع الإسكندرية',
            globalId: const Value('gid-branch-b'),
          ),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-049',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_049',
      password: 'pw',
      displayName: 'F049',
      roleId: roleId,
    );
  });

  tearDown(() => db.close());

  group('countUsersWithBranchAccess', () {
    test('returns 0 when no users assigned', () async {
      expect(await db.countUsersWithBranchAccess(branchA), 0);
    });

    test('counts only rows for the requested branch', () async {
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchA),
          );
      expect(await db.countUsersWithBranchAccess(branchA), 1);
      expect(await db.countUsersWithBranchAccess(branchB), 0);
    });
  });

  group('deleteBranch (soft + reassign)', () {
    test('empty branch: soft-delete sets isActive=false + deletedAt', () async {
      await db.deleteBranch(branchA);
      final row = await (db.select(db.branches)
            ..where((b) => b.id.equals(branchA)))
          .getSingleOrNull();
      expect(row, isNotNull,
          reason: 'soft-delete preserves the row so historical FKs '
              '(journal entries, safes, shifts) stay valid');
      expect(row!.isActive, isFalse);
      expect(row.deletedAt, isNotNull);
    });

    test('throws clear Arabic error when users are assigned and no '
        'reassign destination is given', () async {
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchA),
          );

      Object? thrown;
      try {
        await db.deleteBranch(branchA);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);
      expect(thrown.toString(), contains('مستخدم'),
          reason: 'operator must see exactly how many users to reassign');

      // Nothing changed.
      final row = await (db.select(db.branches)
            ..where((b) => b.id.equals(branchA)))
          .getSingle();
      expect(row.isActive, isTrue);
    });

    test('with reassignUsersToBranchId: user assignments move to '
        'destination, then branch soft-deleted', () async {
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchA),
          );

      await db.deleteBranch(branchA, reassignUsersToBranchId: branchB);

      // A is gone from user_branch_access.
      final stillOnA = await (db.select(db.userBranchAccess)
            ..where((u) => u.branchId.equals(branchA)))
          .get();
      expect(stillOnA, isEmpty);

      // B now has the user.
      final onB = await (db.select(db.userBranchAccess)
            ..where((u) => u.branchId.equals(branchB)))
          .get();
      expect(onB.length, 1);
      expect(onB.first.userId, userId);

      // A is soft-deleted.
      final branchRow = await (db.select(db.branches)
            ..where((b) => b.id.equals(branchA)))
          .getSingle();
      expect(branchRow.isActive, isFalse);
    });

    test('reassign is idempotent when user already has access to '
        'destination branch (compound PK collision avoided)', () async {
      // User has access to BOTH A and B already (legitimate multi-branch
      // assignment). Reassigning A's row to B should NOT crash on the
      // compound PK and the user should still appear under B exactly once.
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchA),
          );
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchB),
          );

      await db.deleteBranch(branchA, reassignUsersToBranchId: branchB);

      final onB = await (db.select(db.userBranchAccess)
            ..where((u) =>
                u.branchId.equals(branchB) & u.userId.equals(userId)))
          .get();
      expect(onB.length, 1,
          reason: 'compound PK (userId, branchId) must not be violated');
    });

    test('rejects reassignUsersToBranchId == branchId (self-move)', () async {
      expect(
        () => db.deleteBranch(branchA, reassignUsersToBranchId: branchA),
        throwsArgumentError,
      );
    });

    test('rejects reassign destination that is inactive (soft-deleted)',
        () async {
      // Soft-delete B first to make it inactive.
      await db.deleteBranch(branchB);

      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchA),
          );

      Object? thrown;
      try {
        await db.deleteBranch(branchA, reassignUsersToBranchId: branchB);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull,
          reason: 'DAO must refuse to reassign onto a soft-deleted branch');
    });

    test('soft-deleted branch filtered out of isActive=true queries',
        () async {
      await db.deleteBranch(branchA);
      final visible = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true)))
          .get();
      expect(visible.map((b) => b.id), isNot(contains(branchA)));
      expect(visible.map((b) => b.id), contains(branchB));
    });
  });
}
