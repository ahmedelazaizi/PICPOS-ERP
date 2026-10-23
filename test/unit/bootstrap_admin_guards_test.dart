// Spec 061 / SC-005 — Bootstrap admin guards regression test.
//
// The bootstrap admin user (id=1, username='admin') is seeded by the
// initial migration and MUST NEVER be deactivated, locked, deleted, or
// demoted. Recovery from such a state requires direct SQLCipher surgery.
//
// QA findings D1-002 (P0 server) + D1-003 (P0 local) addressed by spec 061.
// This test pins the DAO-layer + predicate contract in CI so a future
// refactor cannot silently re-introduce the lockout vector.
//
// The server-side guards (HTTP 403) are not covered here — they would
// require a heavier shelf handler fixture. Manual smoke per quickstart.md
// covers SC-003 + SC-004.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/auth/bootstrap_admin.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Bootstrap admin predicate (Spec 061 / FR-001)', () {
    test('isBootstrapAdmin returns true for id=1 alone', () {
      expect(isBootstrapAdmin(1), isTrue);
    });

    test('isBootstrapAdmin returns true for any id when username=="admin"', () {
      expect(isBootstrapAdmin(99, username: 'admin'), isTrue);
    });

    test('isBootstrapAdmin returns false for non-1 id and non-admin username', () {
      expect(isBootstrapAdmin(2, username: 'cashier'), isFalse);
      expect(isBootstrapAdmin(2), isFalse);
      expect(isBootstrapAdmin(99), isFalse);
    });
  });

  group('Bootstrap admin DAO guards (Spec 061 / FR-002 + FR-003)', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase.forTesting();
      // The seeding runs in onCreate, but the bootstrap admin row should
      // already exist after `forTesting()`. Confirm before exercising the guard.
      final admin = await (database.select(database.users)
            ..where((u) => u.id.equals(1)))
          .getSingleOrNull();
      expect(admin, isNotNull, reason: 'bootstrap admin (id=1) must be seeded');
    });

    tearDown(() async {
      await database.close();
    });

    test('toggleUserActive(userId: 1, isActive: false) throws StateError', () async {
      expect(
        () => database.toggleUserActive(userId: 1, isActive: false),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('لا يمكن'),
        )),
        reason: 'DAO must refuse to deactivate the bootstrap admin',
      );
    });

    test('toggleUserActive(userId: 1, isActive: true) does NOT throw '
        '(re-enable is allowed)', () async {
      // First we'd need admin to be inactive, but we can't make it so via
      // the guarded API. Instead just confirm that the guard fires only on
      // the deactivate direction.
      expect(
        () => database.toggleUserActive(userId: 1, isActive: true),
        returnsNormally,
        reason: 'Re-enable (isActive=true) must always be allowed',
      );
    });

    test('setUserLocked(1, true) throws StateError', () async {
      expect(
        () => database.setUserLocked(1, true),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('لا يمكن'),
        )),
        reason: 'DAO must refuse to lock the bootstrap admin',
      );
    });

    test('setUserLocked(1, false) does NOT throw (unlock is allowed)', () async {
      expect(
        () => database.setUserLocked(1, false),
        returnsNormally,
        reason: 'Unlock (isLocked=false) must always be allowed',
      );
    });

    test('toggleUserActive(userId: 2, isActive: false) does NOT throw '
        '(non-admin users are unaffected)', () async {
      // Create a non-admin user first to test the guard's scope.
      final nonAdminId = await database.into(database.users).insert(
            UsersCompanion.insert(
              username: 'tester_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'dummy',
              passwordSalt: const Value('dummy'),
              displayName: 'Tester',
            ),
          );
      expect(nonAdminId, isNot(1),
          reason: 'inserted user must not collide with bootstrap admin');
      expect(
        () => database.toggleUserActive(userId: nonAdminId, isActive: false),
        returnsNormally,
        reason: 'Non-admin users can still be deactivated',
      );
    });
  });
}
