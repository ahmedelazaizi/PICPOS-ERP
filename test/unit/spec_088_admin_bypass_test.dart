// ═══════════════════════════════════════════════════════════════════════════
// SPEC 088 USR-1 — Server-side bootstrap-admin permission bypass (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field bug: on a mirror device, admin (userId=1) hit 403 from the central
// server's per-user permission middleware on calls like /api/branches
// (POST), /api/shifts (open) etc. — even though Spec 086 added matrix
// safety-net entries. The matrix path is best-effort; future codes can be
// added without re-running grantMissingDefaults() in time. The durable
// fix is a server-side bypass that short-circuits the permission check
// when the caller is the bootstrap admin (userId=1, per Spec 061).
//
// These pins ensure:
//   1. The bypass uses the canonical isBootstrapAdmin predicate.
//   2. The bypass runs AFTER the 401 (missing X-User-Id) guard and BEFORE
//      the userHasPermission DB lookup — so admin's missing matrix rows
//      never matter.
//   3. The one-shot PERMS-WARN log line is wired so field operators can
//      grep for "bootstrap admin bypass engaged" after rollout.
//
// See specs/088-mirror-hotfix-pack/contracts/permission-bypass.md.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 088 USR-1 — bootstrap-admin server bypass', () {
    final src =
        File('lib/services/api/api_user_context.dart').readAsStringSync();

    test('imports the canonical isBootstrapAdmin predicate', () {
      expect(src, contains("import '../../core/auth/bootstrap_admin.dart'"),
          reason:
              'USR-1 must reuse the Spec 061 canonical predicate. Inlining '
              '`userId == 1` would silently miss the username-fallback case '
              'and split the invariant across two source files.');
    });

    test('imports DiagnosticLogger for PERMS-WARN line', () {
      expect(src,
          contains("import '../../core/logging/diagnostic_logger.dart'"),
          reason:
              'The one-shot PERMS-WARN line is the only way the field can '
              'confirm the bypass is engaged on a deployed build.');
    });

    test('bypass runs BEFORE the userHasPermission DB lookup', () {
      final bypassIdx = src.indexOf('isBootstrapAdmin(userId)');
      final lookupIdx = src.indexOf('db.userHasPermission(userId, code)');
      expect(bypassIdx, isNot(-1),
          reason: 'isBootstrapAdmin guard must exist inside requirePermission.');
      expect(lookupIdx, isNot(-1));
      expect(bypassIdx < lookupIdx, isTrue,
          reason: 'Ordering matters: the bypass must short-circuit BEFORE '
              'the DB lookup, otherwise admin with no matrix rows still '
              'returns 403 (the exact field bug).');
    });

    test('bypass runs AFTER the 401 missing X-User-Id guard', () {
      final missingIdx = src.indexOf(
          'Missing X-User-Id (per-user perms enabled)');
      final bypassIdx = src.indexOf('isBootstrapAdmin(userId)');
      expect(missingIdx, isNot(-1));
      expect(bypassIdx, isNot(-1));
      expect(missingIdx < bypassIdx, isTrue,
          reason: 'Order: the existing 401 guard for missing header must '
              'still run first. Otherwise a request with no X-User-Id '
              'would crash on the null check inside isBootstrapAdmin.');
    });

    test('per-user-perms-disabled path is preserved (returns null at top)',
        () {
      // The first guard in requirePermission must still short-circuit
      // when the feature flag is off — admin bypass should not change
      // this auto-pass behavior for non-admin users on a flag-off cluster.
      final start = src.indexOf('Future<Response?> requirePermission(');
      expect(start, isNot(-1));
      final block = src.substring(start, start + 1200);
      expect(block, contains('if (!await isPerUserPermsEnabled(db)) return null'),
          reason: 'Removing this early-return would mean admin bypass code '
              'runs even when the whole layer is disabled. The flag-off '
              'auto-pass path must be unchanged.');
    });

    test('one-shot bypass-logged flag exists', () {
      expect(src, contains('static bool _bootstrapBypassLogged = false'),
          reason: 'Without the static flag the PERMS-WARN line would fire '
              'on every admin request, drowning the diagnostic log. The '
              'flag flips on first fire and silences subsequent calls.');
      expect(src, contains('_bootstrapBypassLogged = true'),
          reason: 'The flag must actually be flipped after the first emit.');
    });

    test('PERMS-WARN line carries the canonical text field operators grep for',
        () {
      expect(src, contains("'bootstrap admin bypass engaged (userId="),
          reason: 'The exact phrase is the contract — quickstart.md '
              'instructs field operators to grep for it after a smoke '
              'build. Changing the wording silently breaks the smoke.');
    });
  });
}
