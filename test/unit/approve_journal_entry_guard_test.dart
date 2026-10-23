// C-1: approveJournalEntry must refuse an unbalanced or soft-deleted draft
// (inside its transaction, before anything is posted) and still post a valid
// draft exactly as before.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/daos/journal_approval_guard.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late Account cash;
  late Account sales;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    final all = await repo.getAllAccounts();
    cash =
        all.firstWhere((a) => a.code == '1111' && a.accountNature == 'detail');
    sales = all.firstWhere(
        (a) => a.code.startsWith('41') && a.accountNature == 'detail');
  });

  tearDown(() => db.close());

  Future<int> makeDraft() => repo.createJournalEntry(
        description: 'مسودة',
        date: DateTime(2026, 8, 27),
        lines: [
          JournalLine(accountId: cash.id, debit: 500, credit: 0),
          JournalLine(accountId: sales.id, debit: 0, credit: 500),
        ],
        asDraft: true,
      );

  Future<int> approver() async => (await db.select(db.users).get()).first.id;

  Future<JournalEntryData> rowOf(int id) => (db.select(db.journalEntries)
        ..where((e) => e.id.equals(id)))
      .getSingle();

  Future<double> balanceOf(int accountId) async => (await (db.select(
              db.accounts)
            ..where((a) => a.id.equals(accountId)))
          .getSingle())
      .balance;

  test('unbalanced draft → throws, nothing is posted, balances untouched',
      () async {
    final id = await makeDraft();
    await db.customStatement(
        'UPDATE journal_entry_lines SET credit = 400 WHERE entry_id = ? '
        'AND credit > 0',
        [id]);
    final cashBefore = await balanceOf(cash.id);

    await expectLater(
      db.approveJournalEntry(id, await approver()),
      throwsA(predicate((e) => e.toString().contains('غير متوازن'))),
    );

    expect((await rowOf(id)).isPosted, isFalse);
    expect(await balanceOf(cash.id), cashBefore);
    expect(await balanceOf(sales.id), 0);
  });

  test('soft-deleted draft → throws and is not posted', () async {
    final id = await makeDraft();
    await db.customStatement(
        'UPDATE journal_entries SET is_deleted = 1 WHERE id = ?', [id]);

    await expectLater(
      db.approveJournalEntry(id, await approver()),
      throwsA(predicate((e) => e.toString().contains('محذوف'))),
    );

    expect((await rowOf(id)).isPosted, isFalse);
    expect(await balanceOf(cash.id), 0);
  });

  test('already-posted entry is still rejected', () async {
    final id = await makeDraft();
    final who = await approver();
    await db.approveJournalEntry(id, who);
    await expectLater(db.approveJournalEntry(id, who), throwsException);
  });

  test('valid balanced draft posts exactly as before', () async {
    final id = await makeDraft();
    expect((await rowOf(id)).isPosted, isFalse);

    await db.approveJournalEntry(id, await approver());

    final row = await rowOf(id);
    expect(row.isPosted, isTrue);
    expect(await balanceOf(cash.id), 500);
    expect(await balanceOf(sales.id), -500);
  });

  group('draftApprovalBlocker', () {
    test('balanced → null; 1 minor unit tolerated like the writer', () {
      expect(
          draftApprovalBlocker(isDeleted: false, lines: const [
            (debit: 100.0, credit: 0.0),
            (debit: 0.0, credit: 100.0),
          ]),
          isNull);
      expect(
          draftApprovalBlocker(isDeleted: false, lines: const [
            (debit: 100.0, credit: 0.0),
            (debit: 0.0, credit: 100.01),
          ]),
          isNull);
    });
    test('unbalanced / deleted / empty → reason', () {
      expect(
          draftApprovalBlocker(isDeleted: false, lines: const [
            (debit: 100.0, credit: 0.0),
            (debit: 0.0, credit: 90.0),
          ]),
          contains('غير متوازن'));
      expect(draftApprovalBlocker(isDeleted: true, lines: const []),
          contains('محذوف'));
      expect(draftApprovalBlocker(isDeleted: false, lines: const []),
          contains('بلا مبالغ'));
    });
  });
}
