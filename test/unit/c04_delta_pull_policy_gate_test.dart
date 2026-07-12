// Spec 151 / C-04 — DeltaPull inbound conflict-policy gate guard.
//
// BLOCKER C-04 root cause: DeltaPull's `_upsertRow` called
// `ConflictResolutionService.shouldApplyServerRow(table, row)` with NO
// `policy:` argument, so it fell to the enum's `newerWins` default. On a
// CLIENT/MIRROR device the server is the Single Source of Truth (R4), but the
// v129 `{t}_bump_version` trigger bumps `row_version` on ANY local UPDATE —
// so a locally-edited, server-authoritative row out-versions the real server
// row and `newerWins` PERMANENTLY rejects the server-wins self-heal. The row
// drifts forever and never re-converges (the C-04 amplifier).
//
// The fix threads the per-table policy: `shouldApplyServerRow(table, row,
// policy: ConflictResolutionService.instance.policyForTable(table))`, which
// resolves to `serverWins` for master/appendOnly tables and only `newerWins`
// for the R5 lastWriteWins tables (parties, shifts).
//
// This grep-style test guards the exact revert vector: if a refactor drops the
// `policy:` argument and reverts to the bare `shouldApplyServerRow(table, row)`
// call, the build fails here BEFORE the silent, non-self-healing data drift
// ships to the field again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeltaPull inbound conflict-policy gate (Spec 151 / C-04)', () {
    const relPath = 'lib/services/delta_pull_service.dart';

    test('_upsertRow threads policyForTable(table) into shouldApplyServerRow',
        () {
      final file = File(relPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'expected DeltaPull service file to exist at $relPath',
      );

      // Normalize whitespace so the assertions survive reformatting /
      // line-wrapping of the (multi-line) call site — matching the
      // whitespace-tolerant convention used by the other grep-guard tests.
      final normalized =
          file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

      // (a) The per-table policy MUST be threaded as the `policy:` argument to
      // shouldApplyServerRow. Without it the call falls to the enum's
      // `newerWins` default and C-04's non-self-healing drift returns.
      final policyThreaded = RegExp(
        r'policy:\s*[A-Za-z0-9_.]*\.?policyForTable\(\s*table\s*\)',
      );
      expect(
        policyThreaded.hasMatch(normalized),
        isTrue,
        reason:
            '$relPath no longer threads `policy: '
            'ConflictResolutionService.instance.policyForTable(table)` into '
            'shouldApplyServerRow. The call reverts to the `newerWins` default, '
            'and on client/mirror a locally-bumped row_version permanently '
            'rejects the server-wins self-heal (BLOCKER C-04). See '
            'specs/151-full-audit/findings/ (C-04).',
      );

      // (b) The pre-fix form — a bare `shouldApplyServerRow(table, row)` with
      // no `policy:` argument — MUST NOT reappear. This is the precise revert
      // vector that silently re-introduces the BLOCKER.
      final prefixForm = RegExp(
        r'shouldApplyServerRow\(\s*table\s*,\s*row\s*,?\s*\)',
      );
      expect(
        prefixForm.hasMatch(normalized),
        isFalse,
        reason:
            '$relPath contains the pre-fix bare call '
            '`shouldApplyServerRow(table, row)` with no `policy:` argument. '
            'That form uses the `newerWins` default, which on client/mirror '
            '(server = SoT, R4) lets a locally-bumped row_version out-version '
            'the authoritative server row and permanently blocks the '
            'server-wins self-heal — BLOCKER C-04. Thread '
            '`policy: policyForTable(table)` instead.',
      );
    });
  });
}
