// Feature 053 (v133) — Commercial-paper auto-post idempotency.
//
// Field DB diagnostic (party id=5, three cheques) showed `journal_entries`
// accumulating 2-4 rows per (paper, transition) even though the raw
// commercial_papers and safe_transactions tables had no duplicates. Root
// cause was `_autoPostPaperStatusChange` inserting a fresh JE on every
// call, with three production paths re-triggering it for one logical
// user action (dual-write to local+server in mirror mode, sync-strategy
// re-trigger on paper upsert, operator status-cycle edits).
//
// Spec 129 F5 (FR-501/FR-504) replaced the fragile
// `[IDEM:cp-<paperId>-<newStatus>]` description tag with a deterministic
// JournalEntryGid (`je-cp-<paper.globalId>-<verb>`); the UNIQUE global_id
// constraint then catches duplicates structurally. The write side no longer
// emits `[IDEM:…]` markers. These tests pin the current guard behaviour:
//   1. First post creates one JE whose globalId == the deterministic gid.
//   2. Re-posting same (paper, transition) is skipped.
//   3. Different transition on same paper posts a new JE (distinct gids).
//   4. Soft-deleted JE doesn't block re-post (clean reversal flow).
//   5. Legacy untagged JE is deduped by the FR-503 description-prefix LIKE
//      match (the read-side scanner kept alive for one release).

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/journal_entry_gid.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int partyId;
  late int paperId;

  Future<List<JournalEntryData>> papersJeFor(int pid) =>
      (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('commercial_paper') &
                e.referenceId.equals(pid) &
                e.isDeleted.equals(false)))
          .get();

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    // paper_status_history.changed_by FKs to users. These tests attribute the
    // change to a placeholder actor id 0; seed it so the FK resolves (the DAO's
    // _ensureValidActor guard now rejects an actor with no matching user).
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(0), username: 'usr0', passwordHash: 'x', displayName: 'U0'));

    partyId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد اختبار 053',
            isSupplier: const Value(true),
            globalId: const Value('gid-party-053'),
          ),
        );

    // Insert paper directly at status='pending' WITHOUT going through
    // createCommercialPaper — so no auto-post has fired yet. This lets
    // the tests trigger the very first post explicitly via
    // changePaperStatus(id, 'pending') and observe the guard from a
    // known-clean baseline.
    paperId = await db.into(db.commercialPapers).insert(
          CommercialPapersCompanion.insert(
            paperNumber: 'CHK-053',
            type: 'cheque',
            direction: 'issued',
            partyId: partyId,
            amount: 1000,
            issueDate: DateTime(2026, 5, 13, 10),
            dueDate: DateTime(2026, 6, 13),
            status: const Value('pending'),
            globalId: const Value('gid-paper-053'),
          ),
        );
  });

  tearDown(() => db.close());

  group('Feature 053 — idempotency guard', () {
    test('first post creates one JE carrying the deterministic globalId',
        () async {
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );

      final jes = await papersJeFor(paperId);
      expect(jes, hasLength(1),
          reason: 'first post for none→pending must create exactly one JE');
      // Spec 129 F5 (FR-504): the write side stopped emitting `[IDEM:…]` tags;
      // the identity now lives in the JE's globalId, computed deterministically
      // so mirror + server converge and the UNIQUE index dedups.
      expect(jes.first.globalId, _expectedGid('gid-paper-053', 'pending'),
          reason: 'the deterministic gid must be stamped so subsequent calls '
              'detect a prior post via the UNIQUE global_id constraint');
    });

    test('re-posting the same (paper, transition) is suppressed', () async {
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );
      // Second call simulates the dual-write path: same paper, same
      // target status, same caller. The guard must catch this.
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );

      final jes = await papersJeFor(paperId);
      expect(jes, hasLength(1),
          reason: 'idempotency guard must short-circuit the duplicate '
              'INSERT; production observed 2-4 rows here before the fix');
    });

    test('different transitions on same paper post separate JEs', () async {
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'cashed',
        changedBy: 0,
      );

      final jes = await papersJeFor(paperId);
      expect(jes, hasLength(2),
          reason: 'pending and cashed are separate accounting events — '
              'the guard must not over-fire and skip a legitimate '
              'second transition');
      // Spec 129 F5: each transition gets its own deterministic gid keyed on
      // the verb, so the two events carry distinct globalIds.
      final gids = jes.map((e) => e.globalId).toList();
      expect(gids, contains(_expectedGid('gid-paper-053', 'pending')));
      expect(gids, contains(_expectedGid('gid-paper-053', 'cashed')));
    });

    test('soft-deleted JE does not block re-posting the same transition',
        () async {
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );

      // Operator soft-deletes the auto-posted JE (e.g. the cheque was
      // entered against the wrong supplier and they want a clean re-do).
      await (db.update(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('commercial_paper') &
                e.referenceId.equals(paperId)))
          .write(const JournalEntriesCompanion(isDeleted: Value(true)));

      // Re-applying the same transition now should produce a fresh JE.
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );

      final jes = await papersJeFor(paperId);
      expect(jes, hasLength(1),
          reason: 'after soft-deleting the original, a re-post is the '
              'normal cleanup path and must succeed');
    });

    test('legacy untagged JE is deduped by the FR-503 description-prefix match',
        () async {
      // Simulate a pre-v133 row: same paper + reference_type, description
      // carries no [IDEM:...] tag but DOES start with the same Arabic prefix
      // the auto-poster generates for issued/pending ('إصدار شيك رقم CHK-053').
      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-LEGACY-053',
              entryDate: DateTime(2026, 5, 1),
              description: const Value(
                  'إصدار شيك رقم CHK-053 [HASH:legacy-no-idem]'),
              referenceType: const Value('commercial_paper'),
              referenceId: Value(paperId),
              isAutoPosted: const Value(true),
              globalId: const Value('gid-legacy-053'),
            ),
          );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'pending',
        changedBy: 0,
      );

      // Spec 129 F5 deliberately keeps the legacy read-side scanner alive for
      // one release (FR-503, commercial_papers_dao.dart:583): the guard also
      // matches `description LIKE '<new description>%'`. The legacy row's
      // description starts with the new post's description ('إصدار شيك رقم
      // CHK-053'), so the guard recognises it as the same transition and
      // SUPPRESSES the duplicate — leaving exactly the one (legacy) row. This
      // is the intended bridge so pre-gid rows still dedup until they are
      // migrated/repaired away.
      final jes = await papersJeFor(paperId);
      expect(jes.length, 1,
          reason: 'FR-503 legacy-dedup: the prefix-LIKE match treats the '
              'untagged legacy row as the already-posted transition and '
              'suppresses the re-post');
      expect(jes.single.globalId, 'gid-legacy-053',
          reason: 'the surviving row is the pre-existing legacy JE — no new '
              'colliding row was inserted');
    });
  });
}

/// The deterministic JE globalId the auto-poster mints for a commercial-paper
/// transition: `je-cp-<paper.globalId>-<verb>` (Spec 129 F5 / FR-501). The
/// paper here always has a non-empty globalId, so the production `cp-id-<id>`
/// fallback is not exercised.
String _expectedGid(String paperGlobalId, String verb) =>
    JournalEntryGid.compute(
      sourceType: JournalEntryGid.sourceCommercialPaper,
      sourceGid: paperGlobalId,
      verb: verb,
    );
