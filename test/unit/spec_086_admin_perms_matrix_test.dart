// ═══════════════════════════════════════════════════════════════════════════
// SPEC 086 — Admin perms matrix safety net
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins:
//   1. `RoleGrantMatrix.defaultGrants['مدير النظام']` exists and contains
//      branches_manage, pos_shift_open, pos_shift_close — the three perms
//      that field-failed silently on mirror smoke V148 (admin user #1
//      hit 403 on shift open/close + branch insert against server).
//   2. The `scanMissingGrants` flow has been updated so admin is no
//      longer special-cased — it's diffed against the matrix like any
//      other role. (This is what makes `grantMissingDefaults` actually
//      grant admin the missing rows on next server-mode boot.)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/core/permissions/role_grant_matrix.dart';

void main() {
  group('Spec 086 — admin essentials safety net', () {
    test('admin (مدير النظام) is registered in the matrix', () {
      expect(RoleGrantMatrix.defaultGrants.containsKey('مدير النظام'), isTrue,
          reason: 'Field bug: syncAllPermissions auto-grant for admin can '
              'silently miss new perm codes (no per-row logging). Matrix '
              'entry gives grantMissingDefaults() a second chance to '
              'apply them on every server boot. Without this entry, '
              'admin keeps hitting 403 on branches_manage / pos_shift_* '
              'until an operator clicks "Grant defaults" — which fails '
              'because admin was skipped from the matrix scan loop.');
    });

    test('admin entry contains the 3 codes that field-failed', () {
      final adminCodes = RoleGrantMatrix.defaultGrants['مدير النظام']!;
      expect(adminCodes, containsAll(<String>[
        'branches_manage',
        'pos_shift_open',
        'pos_shift_close',
      ]),
          reason: 'These are the perms the mirror smoke V148 log showed '
              'as 403-blocked for admin (userId=1). Removing any of '
              'them re-opens the field bug.');
    });

    test('preflight service no longer special-cases admin in custom-role skip',
        () {
      // Source-pin: the old `if (role.name != 'مدير النظام')` guard
      // (which conditionally added to customRoles) must be gone. Now
      // admin has matrix entry → expectedCodes != null → never reaches
      // the customRoles branch anyway, but leaving the guard in confuses
      // future maintainers.
      final src = File('lib/services/role_grant_preflight_service.dart')
          .readAsStringSync();
      expect(src.contains("if (role.name != 'مدير النظام')"), isFalse,
          reason: 'Stale guard left over from pre-086 behavior. Now '
              'that admin is in the matrix, expectedCodes is non-null '
              'and the customRoles branch never fires for admin — '
              'the guard is dead code that misleads readers.');
    });
  });
}
