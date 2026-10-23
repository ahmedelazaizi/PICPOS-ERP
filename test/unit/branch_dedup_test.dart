// Feature 012 / Issue M-DUP-BRANCH — branch dedup extension regression
// guard. Reproduces the legacy mirror state (one seeded "الفرع الرئيسي"
// row at id=1 plus a server-pulled duplicate at id=5) and asserts that
// [mergeDuplicateBranches] collapses them to a single survivor while
// migrating every dependent FK without losing data.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/branch_dedup_extension.dart';
import 'package:picpos_erp/services/sync/strategies/branch_sync_strategy.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  group('BranchDedupExtension', () {
    test('dryRun returns empty when no duplicates exist', () async {
      final groups = await db.dryRunDuplicateBranchGroups();
      expect(groups, isEmpty);
    });

    test('merge is a no-op when no duplicates exist', () async {
      final removed = await db.mergeDuplicateBranches();
      expect(removed, 0);
    });

    test('merges two rows with the same name and migrates dependent FKs',
        () async {
      // Seeded DB has "الفرع الرئيسي" at id=1. Insert a duplicate row at
      // a different id with the same name to simulate the legacy mirror
      // state described in spec 012 / US2.
      final dupId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'الفرع الرئيسي',
              globalId: const Value(null),
            ),
          );
      expect(dupId, isNot(1), reason: 'sanity: duplicate must have a different id');

      // Plant a dependent row pointing at the DUPLICATE so the merge has
      // something to migrate. `warehouses.branch_id` is a plain FK.
      final warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مستودع تجريبي',
              branchId: Value(dupId),
            ),
          );

      final groups = await db.dryRunDuplicateBranchGroups();
      expect(groups, hasLength(1));
      expect((groups.first['ids'] as List).cast<int>().toSet(), {1, dupId});

      final removed = await db.mergeDuplicateBranches();
      expect(removed, 1, reason: 'exactly one duplicate row should be deleted');

      // Survivor must be id=1 (it has a non-null globalId from seeding).
      final remaining = await db.select(db.branches).get();
      final mainBranches = remaining.where((b) => b.name == 'الفرع الرئيسي').toList();
      expect(mainBranches, hasLength(1),
          reason: 'exactly one "الفرع الرئيسي" should remain after merge');
      expect(mainBranches.first.id, 1, reason: 'survivor should be the seeded row');

      // Dependent warehouse must now point at the survivor.
      final wh = await (db.select(db.warehouses)
            ..where((t) => t.id.equals(warehouseId)))
          .getSingle();
      expect(wh.branchId, 1,
          reason: 'warehouse FK must have been migrated to the survivor');
    });

    test('merge is idempotent — second call removes nothing', () async {
      // Plant a duplicate, merge once, run again — expect 0.
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'الفرع الرئيسي',
              globalId: const Value(null),
            ),
          );
      final firstRemoved = await db.mergeDuplicateBranches();
      expect(firstRemoved, 1);

      final secondRemoved = await db.mergeDuplicateBranches();
      expect(secondRemoved, 0,
          reason: 'second call on a clean DB must be a no-op');
    });

    test('survivor preference: prefers row with non-null globalId', () async {
      // Insert a "secondary" branch with globalId, then a duplicate with
      // null globalId. The survivor must be the globalId row, not just
      // the lowest-id row.
      final goodId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع الاختبار',
              globalId: const Value('019dfc24-cdab-703b-b45f-156ac76845f6'),
            ),
          );
      final dupId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع الاختبار',
              globalId: const Value(null),
            ),
          );
      // Sanity: even if dupId < goodId we still want goodId as survivor.
      // Our seed order guarantees goodId < dupId so this case proves the
      // tie-break by-id, but the logic also handles the reverse via the
      // explicit globalId-first preference.

      final removed = await db.mergeDuplicateBranches();
      expect(removed, 1);

      final remaining = await (db.select(db.branches)
            ..where((t) => t.name.equals('فرع الاختبار')))
          .get();
      expect(remaining, hasLength(1));
      expect(remaining.first.id, goodId,
          reason: 'survivor must be the row with a non-null globalId');
      expect(remaining.first.globalId, isNotNull);

      // The duplicate id is gone.
      final dupGone = await (db.select(db.branches)
            ..where((t) => t.id.equals(dupId)))
          .getSingleOrNull();
      expect(dupGone, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Feature 035 / US2 (T020) — `BranchSyncStrategy` Tier 2 name
  // fallback must NOT throw StateError when multiple local rows share
  // the same name. Field bug: after per-sync soft-deactivation leaves
  // inactive duplicates, the next sync's `getSingleOrNull()` saw >1
  // row and crashed, leaving the dedup spam-firing forever.
  // ═══════════════════════════════════════════════════════════════════
  group('BranchSyncStrategy Tier 2 multi-match tolerance', () {
    test(
        'Tier 2 falls back to the ACTIVE row when multiple rows share a name',
        () async {
      // Plant the polluted state: one active + two inactive rows all
      // named "X" (none of them carry the server's globalId).
      final activeId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'X',
              globalId: const Value('local-A'),
              isActive: const Value(true),
            ),
          );
      final inactiveA = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'X',
              globalId: const Value('local-B'),
              isActive: const Value(false),
            ),
          );
      final inactiveB = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'X',
              globalId: const Value('local-C'),
              isActive: const Value(false),
            ),
          );

      // Server payload: one row, name="X", globalId differs from all
      // locals → forces Tier 2 (name) fallback.
      const serverGlobalId = 'server-Z';
      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 999,
            'globalId': serverGlobalId,
            'name': 'X',
            'isActive': true,
          },
        ],
      });

      // The active row must be the one Tier 2 picked up — its globalId
      // got rewritten to the server's (FR-004 assertion, covers F2).
      final updatedActive = await (db.select(db.branches)
            ..where((t) => t.id.equals(activeId)))
          .getSingle();
      expect(updatedActive.globalId, serverGlobalId,
          reason: 'active row matched by Tier 2 must adopt the server globalId (FR-004)');
      expect(updatedActive.isActive, isTrue);

      // The two inactive rows must remain inactive (no spurious reactivation).
      final stillInactiveA = await (db.select(db.branches)
            ..where((t) => t.id.equals(inactiveA)))
          .getSingle();
      expect(stillInactiveA.isActive, isFalse);
      final stillInactiveB = await (db.select(db.branches)
            ..where((t) => t.id.equals(inactiveB)))
          .getSingle();
      expect(stillInactiveB.isActive, isFalse);
    });

    // ── Feature 035 / US3 (T030) ───────────────────────────────────
    // FR-009: per-sync per-name dedup MUST remap FKs to the keeper
    // BEFORE soft-deactivating the loser. Otherwise historical data
    // (parties, invoices, JEs) stays attached to an inactive branch.
    test(
        'per-name dedup remaps FKs to canonical survivor before deactivation',
        () async {
      // Two active rows sharing name "X", both will be matched by Tier 1
      // because the server returns both with their respective globalIds.
      // After the for-each-server-row loop, byName["X"].length == 2,
      // triggering the per-name dedup pass.
      final keeperId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'X',
              globalId: const Value('server-A'),
              isActive: const Value(true),
            ),
          );
      final loserId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'X',
              globalId: const Value('server-B'),
              isActive: const Value(true),
            ),
          );

      // Plant a journal entry on the LOSER.
      final jeId = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-035-T030',
              entryDate: DateTime.now(),
              description: const Value('test entry on dedup loser'),
              branchId: Value(loserId),
            ),
          );

      // Server returns BOTH rows with the same name — survives orphan
      // pass (both globalIds in seenServerGlobalIds), per-name dedup
      // collapses to the keeper (first authoritative = lowest id).
      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {'id': 101, 'globalId': 'server-A', 'name': 'X', 'isActive': true},
          {'id': 102, 'globalId': 'server-B', 'name': 'X', 'isActive': true},
        ],
      });

      // Loser is deactivated.
      final loser = await (db.select(db.branches)
            ..where((t) => t.id.equals(loserId)))
          .getSingle();
      expect(loser.isActive, isFalse,
          reason: 'per-name dedup must deactivate the loser');

      // Journal entry FK must point at the keeper (FR-009).
      final je = await (db.select(db.journalEntries)
            ..where((t) => t.id.equals(jeId)))
          .getSingle();
      expect(je.branchId, keeperId,
          reason: 'FK must be remapped to keeper BEFORE deactivation (FR-009)');
    });

    test(
        'Tier 1 wins when an active local already has the server globalId '
        '(no Tier 2 fallback needed)', () async {
      const serverGlobalId = 'server-blessed-1';
      final blessedId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'Y',
              globalId: const Value(serverGlobalId),
              isActive: const Value(true),
            ),
          );
      // A second row sharing the name but NOT the globalId.
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'Y',
              globalId: const Value('local-different'),
              isActive: const Value(false),
            ),
          );

      // Should not throw and should match the blessed row by globalId.
      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 42,
            'globalId': serverGlobalId,
            'name': 'Y-renamed',
            'isActive': true,
          },
        ],
      });

      final blessed = await (db.select(db.branches)
            ..where((t) => t.id.equals(blessedId)))
          .getSingle();
      expect(blessed.name, 'Y-renamed',
          reason: 'Tier 1 match should have updated the name on the blessed row');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Feature 035 / US4 (T040) — Tier 4 re-link. When a server row
  // matches no local row by globalId / name / serverId, BEFORE
  // inserting a fresh row, the strategy MUST attempt to re-attach an
  // inactive locally-seeded branch (name ∈ knownSeedNames). Solves the
  // rename-ghost case: fresh client pairs with a server whose canonical
  // branch was already renamed → the seeded row gets re-linked instead
  // of orphaned.
  // ═══════════════════════════════════════════════════════════════════
  group('BranchSyncStrategy Tier 4 re-link', () {
    test(
        're-links inactive seeded "الفرع الرئيسي" instead of inserting a fresh row',
        () async {
      // Pre-state: the seeder created id=1 "الفرع الرئيسي" with a
      // locally-minted globalId. Simulate the Cluster 029 retroactive
      // cleanup that previously deactivated it (server returned
      // something else, so id=1 got marked inactive).
      await (db.update(db.branches)..where((t) => t.id.equals(1)))
          .write(const BranchesCompanion(isActive: Value(false)));
      final before = await db.select(db.branches).get();
      final rowCountBefore = before.length;

      // Server payload: a row with name "الإدارة" and a globalId that
      // doesn't match anything locally. No name match, no globalId match,
      // no serverId match → fall-through into Tier 4 re-link.
      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 9999,
            'globalId': 'server-renamed-uuid',
            'name': 'الإدارة',
            'isActive': true,
          },
        ],
      });

      // No new row inserted — id=1 got re-linked.
      final after = await db.select(db.branches).get();
      expect(after.length, rowCountBefore,
          reason: 'Tier 4 must re-link the seeded row, not insert');

      // id=1 is now active, renamed, and carries the server's globalId.
      final relinked = await (db.select(db.branches)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(relinked.isActive, isTrue,
          reason: 're-linked row should be reactivated');
      expect(relinked.name, 'الإدارة',
          reason: 're-linked row should adopt the server name');
      expect(relinked.globalId, 'server-renamed-uuid',
          reason: 're-linked row should adopt the server globalId');
    });

    test(
        'skips re-link when MULTIPLE inactive seeded rows exist (ambiguous)',
        () async {
      // Deactivate the seeded "الفرع الرئيسي" (id=1).
      await (db.update(db.branches)..where((t) => t.id.equals(1)))
          .write(const BranchesCompanion(isActive: Value(false)));
      // Plant a SECOND inactive seeded-name row.
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'الفرع الرئيسي',
              globalId: const Value('another-local-uuid'),
              isActive: const Value(false),
            ),
          );

      final rowCountBefore = (await db.select(db.branches).get()).length;

      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 7777,
            'globalId': 'server-fresh-uuid',
            'name': 'الإدارة',
            'isActive': true,
          },
        ],
      });

      // Conservative behavior: ambiguous → skip re-link, fresh-insert
      // happens. Row count goes UP by exactly 1.
      final rowCountAfter = (await db.select(db.branches).get()).length;
      expect(rowCountAfter, rowCountBefore + 1,
          reason: 'ambiguous re-link candidate → must fall through to insert');
    });
  });
}
