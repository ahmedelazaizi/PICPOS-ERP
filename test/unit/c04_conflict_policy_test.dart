// ═══════════════════════════════════════════════════════════════════════════
// C-04 (BLOCKER) — DeltaPull per-table conflict policy
// ═══════════════════════════════════════════════════════════════════════════
//
// The live inbound delta-pull path (delta_pull_service.dart) used to call
// ConflictResolutionService.shouldApplyServerRow(table, row) with NO `policy:`
// argument, so it defaulted to ConflictPolicy.newerWins for EVERY table. Combined
// with the v129 `{t}_bump_version` trigger (bumps `row_version` on ANY local
// UPDATE), a locally-edited server-authoritative row out-versions the authoritative
// server row → server-wins self-heal never happens.
//
// The fix resolves a per-table policy (ConflictResolutionService.policyForTable):
//   • default → serverWins (master data + appendOnly transaction tables — server
//     is SoT on client/mirror, R4).
//   • R5 lastWriteWins tables (parties, shifts) → newerWins.
//
// These are pure unit tests against ConflictResolutionService with an in-memory
// AppDatabase (same setup pattern as product_import_transaction_test.dart).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/conflict_resolution_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
    ConflictResolutionService.instance.initialize(db);
  });

  tearDown(() => db.close());

  group('C-04 DeltaPull per-table conflict policy', () {
    test(
        'server-authoritative table heals: a locally-bumped row_version does NOT '
        'reject the authoritative server row (resolver → serverWins)', () async {
      // Seed a local `products` row with a HIGH row_version — simulating the v129
      // bump-version trigger firing after a local edit of a server-owned row.
      await db.customStatement(
        "INSERT INTO products (code, name, global_id, row_version) "
        "VALUES ('P1', 'Local edit', 'gid-prod-c04', 5)",
      );
      final serverRow = <String, dynamic>{
        'global_id': 'gid-prod-c04',
        'row_version': 2, // authoritative server row carries the LOWER version
      };

      // Repro the bug: under the OLD blanket newerWins, local (5) beats server
      // (2) → false → the server-wins self-heal is permanently rejected.
      final underOldPolicy = await ConflictResolutionService.instance
          .shouldApplyServerRow('products', serverRow,
              policy: ConflictPolicy.newerWins);
      expect(underOldPolicy, isFalse,
          reason: 'reproduces C-04: newerWins rejects the server heal');

      // The fix: the resolver picks serverWins for a server-authoritative table.
      final resolved =
          ConflictResolutionService.instance.policyForTable('products');
      expect(resolved, ConflictPolicy.serverWins);
      final underFix = await ConflictResolutionService.instance
          .shouldApplyServerRow('products', serverRow, policy: resolved);
      expect(underFix, isTrue,
          reason: 'server row must apply — server is SoT on client/mirror (R4)');
    });

    test(
        'parties keeps lastWriteWins: a newer local edit is preserved over a '
        'stale server row (resolver → newerWins)', () async {
      await db.customStatement(
        "INSERT INTO parties (name, global_id, row_version) "
        "VALUES ('Customer', 'gid-party-c04', 9)",
      );
      final serverRow = <String, dynamic>{
        'global_id': 'gid-party-c04',
        'row_version': 3, // stale server row, lower than the local edit
      };

      final resolved =
          ConflictResolutionService.instance.policyForTable('parties');
      expect(resolved, ConflictPolicy.newerWins,
          reason: 'parties is a documented lastWriteWins table (R5)');
      final apply = await ConflictResolutionService.instance
          .shouldApplyServerRow('parties', serverRow, policy: resolved);
      expect(apply, isFalse,
          reason: 'local edit (v9) is newer than server (v3) → keep local');
    });
  });
}
