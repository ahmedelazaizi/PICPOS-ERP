// EXP-1 — operational-expense categories default to a GL account code that
// does not exist ('5299'), so autoPostOperationalExpense silently returned
// null (no journal entry) while the caller reported success. Expenses
// vanished from the P&L with no signal to the operator.
//
// The fix has three parts, each pinned here:
//   1. createExpenseCategory's default account_code changed to '6214'
//      (مصروفات متنوعة - إدارة), which syncDefaultAccounts() always seeds.
//   2. autoPostOperationalExpense no longer silently `return null`s when the
//      category's account_code can't be resolved — it falls back to the
//      dedicated 'op_expenses' account-mapping purpose (also '6214' by
//      default) and, only if that is genuinely unresolvable (e.g. the
//      purpose has been remapped to a garbage account id), throws instead of
//      dropping the entry.
//   3. backfillLegacyExpenseCategoryAccountCode() one-shot re-points any
//      pre-existing '5299' category row to '6214' so historical categories
//      recover without a manual data fix, gated by a durable settings flag
//      so it never re-scans.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> insertLegacyCategory(String accountCode) =>
      db.into(db.opExpenseCategories).insert(
            OpExpenseCategoriesCompanion.insert(
              name: 'فئة قديمة (كود $accountCode)',
              accountCode: Value(accountCode),
            ),
          );

  Future<int> insertExpenseRow(int categoryId, double amount) =>
      db.into(db.opExpenses).insert(
            OpExpensesCompanion.insert(
              categoryId: categoryId,
              amount: amount,
              expenseDate: DateTime(2026, 7, 1),
              userId: 1,
            ),
          );

  group('EXP-1 — createExpenseCategory default account code', () {
    test('defaults to 6214 (seeded) instead of 5299 (never seeded)',
        () async {
      final id = await db.createExpenseCategory(name: 'فئة اختبار EXP-1');

      final cat = await (db.select(db.opExpenseCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(cat.accountCode, '6214');

      // Confirms the regression premise: the OLD default genuinely does not
      // exist in the seeded chart of accounts.
      expect(await db.getAccountByCode('5299'), isNull,
          reason: 'if 5299 is ever seeded this bug (and this assertion) is '
              'moot — pins the premise the fix relies on');
      expect(await db.getAccountByCode('6214'), isNotNull,
          reason: 'the new default must resolve to a real seeded account');
    });
  });

  group('EXP-1 — autoPostOperationalExpense resilience', () {
    test(
        'legacy 5299 category falls back to the seeded 6214 account and '
        'posts a balanced JE (never silently returns null)', () async {
      final categoryId = await insertLegacyCategory('5299');
      final expenseId = await insertExpenseRow(categoryId, 250);

      final jeId = await db.autoPostOperationalExpense(
        expenseId: expenseId,
        amount: 250,
        description: 'مصروف اختبار',
        expenseAccountCode: '5299',
      );

      expect(jeId, isNotNull,
          reason: 'a resolvable fallback exists (6214) — must post a JE, '
              'not silently return null');

      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jeId!)))
          .get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit,
          reason: 'double-entry must balance even on the fallback path');
      expect(totalDebit, 250);

      final fallbackAccount = await db.getAccountByCode('6214');
      final expenseLine =
          lines.firstWhere((l) => l.accountId == fallbackAccount!.id);
      expect(expenseLine.debit, 250,
          reason: 'the expense leg must land on the fallback account '
              'instead of being dropped');
    });

    test(
        'throws instead of silently returning null when account resolution '
        'is genuinely exhausted', () async {
      // syncDefaultAccounts() (called in setUp) already auto-seeded exactly
      // one account_mappings row for purpose='op_expenses' (pointing at the
      // real 6214 account) via syncAccountMappings(). Redirect THAT row to a
      // non-existent account id instead of inserting a second one — a
      // mapping row takes priority over the hardcoded '6214' default in
      // getAccountByPurpose, so even the self-healing syncDefaultAccounts()
      // re-creating account 6214 cannot rescue this; the mapping still
      // points nowhere. This is the only way to force a truly unresolvable
      // expense account, proving the guard fails loud instead of ever
      // falling through to `return null`.
      // FK is enforced in tests now — force this dangling-mapping state with FK
      // momentarily off; the code under test still runs with FK ON.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final updated = await (db.update(db.accountMappings)
            ..where((m) => m.purpose.equals('op_expenses')))
          .write(const AccountMappingsCompanion(accountId: Value(999999)));
      await db.customStatement('PRAGMA foreign_keys = ON');
      expect(updated, 1,
          reason: 'syncDefaultAccounts() must have pre-seeded exactly one '
              "'op_expenses' mapping row for this redirect to be meaningful");

      final categoryId = await insertLegacyCategory('5299');
      final expenseId = await insertExpenseRow(categoryId, 100);

      expect(
        () => db.autoPostOperationalExpense(
          expenseId: expenseId,
          amount: 100,
          description: 'مصروف بلا حساب',
          expenseAccountCode: '5299',
        ),
        throwsA(isA<Exception>()),
        reason: 'EXP-1: an unresolvable GL account must fail loud — never '
            'silently return null while the op_expenses row stays committed '
            'with no journal entry',
      );
    });
  });

  group('EXP-1 — backfillLegacyExpenseCategoryAccountCode one-shot', () {
    test('re-points a 5299 category to 6214 and is idempotent', () async {
      // AppDatabase.forTesting() already ran this backfill once (empty
      // table) during its own beforeOpen pass, arming the flag. Reset it to
      // reproduce the real upgrade scenario: existing '5299' rows predate
      // the very first time this backfill runs.
      await db.setSetting(
          'exp1_category_account_backfill_v1_applied', 'false');

      final categoryId = await insertLegacyCategory('5299');

      final firstRun = await db.backfillLegacyExpenseCategoryAccountCode();
      expect(firstRun, 1,
          reason: 'exactly one legacy category should be re-pointed');

      final cat = await (db.select(db.opExpenseCategories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingle();
      expect(cat.accountCode, '6214');

      // Idempotent: second run is a no-op because the flag is now armed.
      final secondRun = await db.backfillLegacyExpenseCategoryAccountCode();
      expect(secondRun, -1,
          reason: 'flag already applied — must skip, not re-scan');
    });

    test(
        'skips (without mutating data) on a client-mode install — server '
        'owns this master data', () async {
      await db.setSetting(
          'exp1_category_account_backfill_v1_applied', 'false');
      await db.setSetting('network_mode', 'client');

      final categoryId = await insertLegacyCategory('5299');

      final result = await db.backfillLegacyExpenseCategoryAccountCode();
      expect(result, -1,
          reason: 'client mode must not locally mutate master data (R5 '
              'serverWins) — the flag is armed so the next boot converges '
              'via sync instead of re-scanning');

      final cat = await (db.select(db.opExpenseCategories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingle();
      expect(cat.accountCode, '5299',
          reason: 'left untouched on client — server sync is the '
              'authority here');
    });
  });
}
