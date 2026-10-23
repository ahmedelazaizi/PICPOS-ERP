// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 P1-8b — the client and server transactional-table sets MUST match.
// ═══════════════════════════════════════════════════════════════════════════
//
// The token-omission closure depends on TWO hand-maintained sets agreeing:
//   • server  `ApiHandler._transactionalPullTables`     — /api/sync/pull denies
//     these to a caller with no session token.
//   • client  `DeltaPullService.branchScopedPullTables` — the client SKIPs
//     these tokenless and never seeds/advances their watermark.
//
// If they drift apart a future edit silently reopens a hole:
//   • a table only on the CLIENT set  → server still serves it tokenless (LEAK).
//   • a table only on the SERVER set  → client seeds its watermark on a
//     tokenless bootstrap → post-login backfill is skipped (POISON / data loss).
// This test fails loudly on any drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

void main() {
  test('client branchScopedPullTables == server _transactionalPullTables', () {
    expect(
      DeltaPullService.branchScopedPullTables,
      equals(ApiHandler.transactionalPullTablesForTest),
      reason: 'The client skip/watermark-guard set and the server delta-deny '
          'set must be identical — a mismatch reopens the tokenless '
          'transactional leak (client-only entry) or watermark poison '
          '(server-only entry). Update BOTH when adding a transactional table.',
    );
  });
}
