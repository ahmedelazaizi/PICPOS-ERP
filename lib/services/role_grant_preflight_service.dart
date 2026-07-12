// Spec 078 — Pre-flight check for server per-user perms flag.
//
// Before an operator flips `server_per_user_perms_enabled` to ON,
// this service answers:
//   "Which roles are missing the default perms they SHOULD have?"
//
// "Missing" = a perm code listed in [RoleGrantMatrix.defaultGrants]
// for the role's name, but with no corresponding row in
// `role_permissions`. This is the failure mode that bit field smoke
// in Spec 077: the custom role "كاشير العقبة" never received
// `pos_shift_open` after the Batch 0.5 perm code was added, because
// `syncAllPermissions()` only inserts permission CODES — it doesn't
// grant them to existing roles.
//
// Custom roles (not in [RoleGrantMatrix]) are surfaced separately
// with a "manual grant required" note. The grant button does NOT
// touch them — only the operator decides what a custom role gets.

import 'package:drift/drift.dart';

import '../core/permissions/role_grant_matrix.dart';
import '../data/database/database.dart';

class RolePreflightReport {
  RolePreflightReport({
    required this.missingByKnownRole,
    required this.customRolesPresent,
  });

  /// For each known (matrix-listed) role, the set of perm codes it's
  /// missing per the matrix. A role with an empty set is fully
  /// configured.
  final Map<String, Set<String>> missingByKnownRole;

  /// Custom role names found in the DB that aren't in the matrix.
  /// These are surfaced for operator awareness — the grant function
  /// does NOT touch them.
  final List<String> customRolesPresent;

  /// Total missing (role, perm) pairs across known roles only.
  /// Doesn't count custom roles.
  int get totalMissingPairs =>
      missingByKnownRole.values.fold(0, (sum, s) => sum + s.length);

  /// `true` when every known role is fully configured (and the
  /// operator is comfortable with any custom-role state). The dialog
  /// uses this to enable the "Enable" button.
  bool get knownRolesAreReady => totalMissingPairs == 0;
}

class RoleGrantPreflightService {
  RoleGrantPreflightService(this.db);
  final AppDatabase db;

  /// Scan every role in the DB; for known roles diff against the
  /// matrix; for custom roles add them to the customRolesPresent
  /// list. Single round-trip's worth of queries.
  Future<RolePreflightReport> scanMissingGrants() async {
    final allRoles = await db.select(db.roles).get();
    final allPerms = await db.select(db.permissions).get();
    final permByCode = {for (final p in allPerms) p.code: p.id};
    final allRolePerms = await db.select(db.rolePermissions).get();
    final permIdsByRoleId = <int, Set<int>>{};
    for (final rp in allRolePerms) {
      (permIdsByRoleId[rp.roleId] ??= <int>{}).add(rp.permissionId);
    }

    final missing = <String, Set<String>>{};
    final customRoles = <String>[];

    for (final role in allRoles) {
      final expectedCodes = RoleGrantMatrix.defaultGrants[role.name];
      if (expectedCodes == null) {
        // Custom role — not in the matrix, surfaced for operator
        // awareness only. Admin ('مدير النظام') was historically
        // skipped here too because it relied on the seeder's
        // catch-all; Spec 086 adds a minimal admin safety-net entry
        // to the matrix, so admin now falls through to the regular
        // diff loop below.
        customRoles.add(role.name);
        continue;
      }
      final heldPermIds = permIdsByRoleId[role.id] ?? const <int>{};
      final missingForRole = <String>{};
      for (final code in expectedCodes) {
        final permId = permByCode[code];
        if (permId == null) {
          // Perm code not yet registered in the DB — syncAllPermissions
          // failed or hasn't run. Report it; operator should restart
          // the app to trigger the sync.
          missingForRole.add(code);
          continue;
        }
        if (!heldPermIds.contains(permId)) {
          missingForRole.add(code);
        }
      }
      if (missingForRole.isNotEmpty) {
        missing[role.name] = missingForRole;
      }
    }

    return RolePreflightReport(
      missingByKnownRole: missing,
      customRolesPresent: customRoles..sort(),
    );
  }

  /// Idempotent: inserts every (role, perm) pair that
  /// [scanMissingGrants] surfaced. Returns the count actually
  /// inserted (zero on second call).
  ///
  /// **First step**: calls `syncAllPermissions()` to ensure every
  /// perm code from `PermissionCodes.masterList` is present as a
  /// permissions-table row. This handles the upgrade case where
  /// Spec 077 Batch 0.5 added 4 new codes — on a DB created BEFORE
  /// the upgrade, those codes existed in the new app's masterList
  /// but never landed as rows until either `syncAllPermissions`
  /// ran on next startup OR this method ran. Without this step,
  /// the grant loop's `permIdByCode[code]` lookup returned null and
  /// the missing perms were silently skipped, leaving the operator
  /// confused by a "0 granted" message after the scan clearly
  /// surfaced N missing pairs.
  ///
  /// Custom roles are NEVER touched here.
  Future<int> grantMissingDefaults() async {
    // Ensure every code referenced by the matrix is present as a
    // permissions-table row BEFORE we try to grant any.
    await db.syncAllPermissions();

    // Re-scan after the sync — perm codes that were missing may
    // now exist, and the "missing pair" set might have changed.
    final report = await scanMissingGrants();
    if (report.totalMissingPairs == 0) return 0;

    final allRoles = await db.select(db.roles).get();
    final roleIdByName = {for (final r in allRoles) r.name: r.id};
    final allPerms = await db.select(db.permissions).get();
    final permIdByCode = {for (final p in allPerms) p.code: p.id};

    int inserted = 0;
    for (final entry in report.missingByKnownRole.entries) {
      final roleId = roleIdByName[entry.key];
      if (roleId == null) continue;
      for (final code in entry.value) {
        final permId = permIdByCode[code];
        if (permId == null) continue;
        await db.into(db.rolePermissions).insert(
              RolePermissionsCompanion.insert(
                roleId: roleId,
                permissionId: permId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        inserted++;
      }
    }
    return inserted;
  }
}
