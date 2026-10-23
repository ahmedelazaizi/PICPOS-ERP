// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 full-audit — D-03 (MAJOR): region cash-flow double-counts the
// global (branch_id = NULL) journal lines — once per branch.
// ═══════════════════════════════════════════════════════════════════════════
//
// DriftAccountingRepository.getCashFlowStatement used to handle a region
// (regionId != null && branchId == null, ≥2 branches) by looping
// `_db.getCashFlowStatement(branchId: bid)` over each branch and SUMMING the
// sections. But every per-branch DAO call re-includes the `je.branch_id IS
// NULL` rows (head-office / company-level entries) via `_buildBranchFilter`
// (`branch_id IN (..) OR branch_id IS NULL`). Result: an N-branch region
// counts every NULL-branch cash line N times.
//
// The DAO explicitly warns against this loop (accounting_reports_dao.dart:50-54)
// and the sibling trial/income/balance reports avoid it through
// reporting_repository_impl (single `branchIds IN (..)` query). Cash-flow was
// the one live path still on the loop (called via accountingRepositoryProvider
// from financial_statements_screen).
//
// FIX: resolve the region to its branch-id SET and issue ONE scoped query
// (branch_id IN (region ids) OR branch_id IS NULL) so the NULL rows are counted
// exactly once and the branch rows stay scoped.
//
// RED (pre-fix): the NULL cash line of amount C contributes 2×C for a 2-branch
// region. GREEN (post-fix): it contributes exactly C.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late int cashId;
  late int revenueId;
  late int regionId;
  late int branch1;
  late int branch2;

  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  // Global (head-office) cash line amount — the value that must NOT be
  // multiplied by the branch count.
  const globalCash = 500.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    await db.syncDefaultAccounts();
    cashId = (await db.getAccountByCode('1111'))!.id; // الصندوق الرئيسي (asset)
    revenueId = (await db.getAccountByCode('4121'))!.id; // إيراد

    regionId = await db.into(db.regions).insert(
          RegionsCompanion.insert(
            name: 'منطقة القاهرة — D03',
            globalId: const Value('gid-region-d03'),
          ),
        );
    branch1 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 1 — D03',
            globalId: const Value('gid-br1-d03'),
            regionId: Value(regionId),
          ),
        );
    branch2 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 2 — D03',
            globalId: const Value('gid-br2-d03'),
            regionId: Value(regionId),
          ),
        );

    // Head-office cash JE with a genuine NULL branch_id, dated BEFORE `from`
    // so it lands in the opening-balance query. createJournalEntry auto-resolves
    // a fallback branch when branchId is null (can't yield a NULL row), so the
    // JE + lines are inserted directly — same technique as the B12 test.
    final globalJe = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'JE-HO-D03',
            entryDate: DateTime(2025, 12, 1), // before `from`
            isPosted: const Value(true),
          ),
        );
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: globalJe, accountId: cashId, debit: const Value(globalCash)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: globalJe,
        accountId: revenueId,
        credit: const Value(globalCash)));
  });

  tearDown(() => db.close());

  group('D-03 region cash-flow does not double-count NULL-branch rows', () {
    test(
        'NULL-branch cash line counted ONCE for a 2-branch region '
        '(pre-fix: 2×C)', () async {
      final cf = await repo.getCashFlowStatement(from, to, regionId: regionId);

      // openingBalance = SUM(cash debit - credit) BEFORE `from` for the region.
      // Only the single global line exists → must equal C exactly, not 2×C.
      expect(
        (cf['openingBalance'] as num).toDouble(),
        closeTo(globalCash, 0.01),
        reason: 'the branch_id=NULL cash line ($globalCash) must be counted '
            'once for the whole region, not once per branch (pre-fix summed '
            '2 branches → ${globalCash * 2})',
      );
    });

    test(
        'branch-scoped rows preserved AND NULL counted once '
        '(100 + 200 + 500 = 800, not 1300)', () async {
      // Branch-specific opening cash, both dated before `from`. Direct insert
      // (not createJournalEntry) so we control branch_id explicitly and skip the
      // fiscal-year gate — same technique the setUp uses for the global row.
      Future<void> seedBranchCash(
          int branchId, double amount, DateTime date, String n) async {
        final je = await db.into(db.journalEntries).insert(
              JournalEntriesCompanion.insert(
                entryNumber: n,
                entryDate: date,
                isPosted: const Value(true),
                branchId: Value(branchId),
              ),
            );
        await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
                entryId: je, accountId: cashId, debit: Value(amount)));
        await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
                entryId: je, accountId: revenueId, credit: Value(amount)));
      }

      await seedBranchCash(branch1, 100, DateTime(2025, 12, 2), 'JE-B1-D03');
      await seedBranchCash(branch2, 200, DateTime(2025, 12, 3), 'JE-B2-D03');

      final cf = await repo.getCashFlowStatement(from, to, regionId: regionId);

      // branch1 (100) + branch2 (200) + global (500, once) = 800.
      // Pre-fix loop: (100+500) + (200+500) = 1300 (global double-counted).
      expect(
        (cf['openingBalance'] as num).toDouble(),
        closeTo(800, 0.01),
        reason: 'branch rows must stay in the region total while the global '
            'NULL line is counted once (pre-fix loop → 1300)',
      );
    });
  });
}
