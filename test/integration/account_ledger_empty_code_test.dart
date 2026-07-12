// D-PERF-3 (A9) — getAccountLedger must not dump the whole journal for an
// account whose code is empty/missing. The child-account filter used
// `code LIKE '<code>%'`; when the code was '' that became `LIKE '%'`, matching
// EVERY account, so the ledger of a code-less account showed the entire book.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  test('empty-code account ledger returns only its own lines (A9)', () async {
    final db = AppDatabase.forTesting();

    final withCode = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '520001', name: 'مصروف مرمز', accountType: 'expense'));
    final emptyCode = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '', name: 'حساب بدون كود', accountType: 'expense'));

    final eid = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(
            entryNumber: 'JE-A9-1', entryDate: DateTime(2026, 1, 15)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: eid, accountId: withCode, debit: const Value(100)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: eid, accountId: emptyCode, credit: const Value(100)));

    final ledger = await db.getAccountLedger(
        emptyCode, DateTime(2026, 1, 1), DateTime(2026, 1, 31));
    final lines = ledger.where((r) => r['is_opening'] != true).toList();

    expect(lines.length, 1,
        reason: 'code-less account must not pull the coded account\'s line');
    expect(lines.first['credit'], 100);

    await db.close();
  });
}
