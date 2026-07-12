// Spec 078 — Tests for RoleGrantPreflightService.
//
// Covers the 3-state contract:
//   1. Fresh install (seeder ran) → no missing perms across known roles.
//   2. Operator removed a perm → it shows up in the report.
//   3. After grantMissingDefaults → re-scan returns zero missing.
//
// Also confirms custom roles are SURFACED but NOT GRANTED.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/core/permissions/role_grant_matrix.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/role_grant_preflight_service.dart';

void main() {
  group('RoleGrantPreflightService (Spec 078)', () {
    late AppDatabase db;
    late RoleGrantPreflightService svc;

    setUp(() async {
      db = AppDatabase.forTesting();
      svc = RoleGrantPreflightService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('fresh install — Spec 084b self-heal closes the latent gaps', () async {
      // Pre-Spec-084b history (kept for context):
      //   The seeder's role-grant loops (seedRolesAndPermissions) ref'd
      //   perm codes that landed LATER via syncAllPermissions, so 5
      //   (role, perm) pairs slipped through and required the operator
      //   to click "منح الصلاحيات الافتراضية" to close.
      //
      //   Known pre-084b latent gaps:
      //     - كاشير متقدم: pos_payment_cash, pos_payment_card
      //     - مدير فرع: pos_payment_cash, pos_payment_card (inherited)
      //     - مدير مخزون: inventory_transfer
      //
      // Post-Spec-084b: `_syncPermissionsAndAccounts` calls
      // `grantMissingDefaults()` on every server-mode boot, so the
      // gaps are closed before any code observing the DB can see them.
      // `AppDatabase.forTesting()` triggers the same startup, so the
      // test's setUp produces an already-healed state.
      //
      // If this count drifts UP, a new latent gap appeared that
      // self-heal isn't catching — investigate the matrix vs the perm
      // seed list (Spec 084 found one: `sales_create` was missing as
      // a perm ROW, not just a grant).
      final report = await svc.scanMissingGrants();
      expect(report.totalMissingPairs, equals(0),
          reason: 'Post-084b: startup self-heal has already applied '
              'the 5 pre-existing gaps. Surfaced (should be empty): '
              '${report.missingByKnownRole}');
    });

    test('removing a perm from a role surfaces it in the report', () async {
      // Remove pos_shift_open from كاشير.
      final cashierRole = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير')))
              .getSingle());
      final permId = (await (db.select(db.permissions)
                ..where((p) => p.code.equals('pos_shift_open')))
              .getSingle())
          .id;
      await (db.delete(db.rolePermissions)
            ..where((rp) =>
                rp.roleId.equals(cashierRole.id) &
                rp.permissionId.equals(permId)))
          .go();

      final report = await svc.scanMissingGrants();
      expect(report.knownRolesAreReady, isFalse);
      expect(report.missingByKnownRole['كاشير'], contains('pos_shift_open'));
    });

    test('grantMissingDefaults inserts and re-scan is green', () async {
      // Remove a perm from advancedCashier too — make sure multiple
      // roles can be repaired in one call.
      final advCashier = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير متقدم')))
              .getSingle());
      final shiftOpenId = (await (db.select(db.permissions)
                ..where((p) => p.code.equals('pos_shift_open')))
              .getSingle())
          .id;
      await (db.delete(db.rolePermissions)
            ..where((rp) =>
                rp.roleId.equals(advCashier.id) &
                rp.permissionId.equals(shiftOpenId)))
          .go();

      final preReport = await svc.scanMissingGrants();
      expect(preReport.knownRolesAreReady, isFalse);
      final insertedCount = await svc.grantMissingDefaults();
      expect(insertedCount, greaterThan(0));

      final postReport = await svc.scanMissingGrants();
      expect(postReport.knownRolesAreReady, isTrue,
          reason: 'After grantMissingDefaults all known roles should '
              'be back to fully-granted state');
    });

    test('grantMissingDefaults is idempotent — second call inserts zero',
        () async {
      // Post-Spec-084b: startup self-heal already ran during forTesting()
      // boot, so the seeder's latent 5 gaps are closed before this test
      // sees the DB. Both passes should therefore return 0 on a clean
      // (healed) DB — the idempotency contract still holds.
      final firstPass = await svc.grantMissingDefaults();
      expect(firstPass, equals(0),
          reason: 'Post-084b: startup self-heal already closed gaps');
      expect(await svc.grantMissingDefaults(), equals(0),
          reason: 'Idempotent: still zero after the no-op first call');

      // Now remove a perm and verify the next call inserts exactly one.
      final cashier = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير')))
              .getSingle());
      final permId = (await (db.select(db.permissions)
                ..where((p) => p.code.equals('pos_shift_open')))
              .getSingle())
          .id;
      await (db.delete(db.rolePermissions)
            ..where((rp) =>
                rp.roleId.equals(cashier.id) &
                rp.permissionId.equals(permId)))
          .go();

      expect(await svc.grantMissingDefaults(), equals(1));
      expect(await svc.grantMissingDefaults(), equals(0));
    });

    test('custom roles are surfaced but NOT granted', () async {
      // Insert a custom role lacking everything.
      await db.into(db.roles).insert(
            RolesCompanion.insert(
              name: 'كاشير العقبة',
              description: const Value('custom role for branch Aqaba'),
              isSystemRole: const Value(false),
              globalId: const Value('test-custom-role-globalid'),
            ),
          );
      final customRole = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير العقبة')))
              .getSingle());

      final preReport = await svc.scanMissingGrants();
      expect(preReport.customRolesPresent, contains('كاشير العقبة'));
      // Custom role does NOT contribute to missingByKnownRole.
      expect(preReport.missingByKnownRole.keys, isNot(contains('كاشير العقبة')));

      // Grant should NOT touch the custom role.
      final preCustomPerms = (await (db.select(db.rolePermissions)
                ..where((rp) => rp.roleId.equals(customRole.id)))
              .get())
          .length;
      await svc.grantMissingDefaults();
      final postCustomPerms = (await (db.select(db.rolePermissions)
                ..where((rp) => rp.roleId.equals(customRole.id)))
              .get())
          .length;
      expect(postCustomPerms, equals(preCustomPerms),
          reason: 'Custom role perm count must not change');
    });

    test('matrix knownRoleNames is in sync with seeder-shipped roles',
        () async {
      // This is a safety net — if a future seeder edit adds a role
      // without adding it to the matrix, this test fails loud.
      // Spec 086: matrix now includes 'مدير النظام' as a safety-net
      // entry (3 essentials) — seeder's catch-all is still authoritative
      // for the full admin perm set; the matrix entry just guards the
      // codes that have field-failed silently.
      final allRoles = await db.select(db.roles).get();
      final dbRoleNames = allRoles.map((r) => r.name).toSet();
      final matrixCovers = RoleGrantMatrix.knownRoleNames;
      expect(matrixCovers, equals(dbRoleNames),
          reason: 'RoleGrantMatrix.defaultGrants must list every system '
              'role from the seeder (including مدير النظام after Spec 086).\n'
              'DB has: $dbRoleNames\n'
              'Matrix covers: $matrixCovers');
    });
  });
}
