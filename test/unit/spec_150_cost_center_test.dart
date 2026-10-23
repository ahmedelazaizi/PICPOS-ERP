// Spec 150 (b)(c)(d) — cost-center balance/ledger reconciliation.
// (d) getCostCenterBalance must count header-tagged lines (cost_center_id
// NULL on the line, set on the parent entry instead), same as the ledger.
// (c) getCostCenterLedger must open with a 'رصيد أول المدة' row and carry a
// running balance forward from it.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('getCostCenterBalance sums line-tagged and header-tagged entries (d)', () async {
    final ccId = await db.into(db.costCenters).insert(
        CostCentersCompanion.insert(code: 'CC1', name: 'الفرع الأول'));
    final expenseAcc = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '6001', name: 'مصروف تشغيل', accountType: 'expense'));

    // Line-tagged: cost_center_id set directly on journal_entry_lines.
    final lineTaggedEntry = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-150-1', entryDate: DateTime(2026, 3, 1)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: lineTaggedEntry,
        accountId: expenseAcc,
        debit: const Value(100),
        costCenterId: Value(ccId)));

    // Header-tagged: cost_center_id only on the entry; the line leaves it null.
    final headerTaggedEntry = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(
            entryNumber: 'JE-150-2',
            entryDate: DateTime(2026, 3, 2),
            costCenterId: Value(ccId)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: headerTaggedEntry, accountId: expenseAcc, credit: const Value(40)));

    final balance = await db.getCostCenterBalance(ccId);

    expect(balance['debit'], 100, reason: 'line-tagged debit must be counted');
    expect(balance['credit'], 40, reason: 'header-tagged credit must be counted via fallback');
  });

  test('getCostCenterLedger opens with a running balance from an opening row (c)', () async {
    final ccId = await db.into(db.costCenters).insert(
        CostCentersCompanion.insert(code: 'CC2', name: 'الفرع الثاني'));
    final expenseAcc = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '6002', name: 'مصروف آخر', accountType: 'expense'));

    // Before the window: feeds the opening balance only.
    final priorEntry = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-150-3', entryDate: DateTime(2026, 1, 15)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: priorEntry, accountId: expenseAcc, debit: const Value(30), costCenterId: Value(ccId)));

    // Inside the window: debit 100, credit 40 (same shape as the balance test above).
    final from = DateTime(2026, 3, 1);
    final to = DateTime(2026, 3, 31);
    final e1 = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-150-4', entryDate: DateTime(2026, 3, 5)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: e1, accountId: expenseAcc, debit: const Value(100), costCenterId: Value(ccId)));
    final e2 = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-150-5', entryDate: DateTime(2026, 3, 10), costCenterId: Value(ccId)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: e2, accountId: expenseAcc, credit: const Value(40)));

    final ledger = await db.getCostCenterLedger(ccId, from, to);

    expect(ledger.first['is_opening'], true);
    expect(ledger.first['balance'], 30);
    expect(ledger.last['balance'], 30 + (100 - 40));
  });

  test('balance/ledger exclude the WHOLE surplus JE, not a single leg (b)',
      () async {
    final ccId = await db.into(db.costCenters).insert(
        CostCentersCompanion.insert(code: 'CC3', name: 'مركز الجرد'));
    final expenseAcc = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '6003', name: 'مصروف عادي', accountType: 'expense'));
    final inventoryAcc = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '1136', name: 'مخزون', accountType: 'asset'));
    final surplusAcc = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '4317', name: 'فائض مخزون', accountType: 'revenue'));

    // Normal cost line — must remain.
    final normal = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-N', entryDate: DateTime(2026, 3, 4)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: normal, accountId: expenseAcc, debit: const Value(100), costCenterId: Value(ccId)));

    // Surplus settlement JE: Dr مخزون / Cr فائض مخزون, both legs CC-tagged by
    // createJournalEntry's branch→CC auto-resolution. The exclusion must drop
    // BOTH legs — dropping only 4317 would orphan the asset debit (+50 skew).
    final surplus = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(entryNumber: 'JE-S', entryDate: DateTime(2026, 3, 6)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: surplus, accountId: inventoryAcc, debit: const Value(50), costCenterId: Value(ccId)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: surplus, accountId: surplusAcc, credit: const Value(50), costCenterId: Value(ccId)));

    final balance = await db.getCostCenterBalance(ccId);
    expect(balance['debit'], 100, reason: 'surplus asset leg must not leak in');
    expect(balance['credit'], 0, reason: 'surplus revenue leg excluded too');

    final ledger = await db.getCostCenterLedger(
        ccId, DateTime(2026, 3, 1), DateTime(2026, 3, 31));
    final codes = ledger.map((r) => r['account_code']).toSet();
    expect(codes.contains('4317'), isFalse);
    expect(codes.contains('1136'), isFalse);
    expect(ledger.where((r) => r['is_opening'] != true).length, 1);
  });
}
