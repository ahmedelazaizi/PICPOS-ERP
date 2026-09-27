import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/commercial_papers_repository_impl.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  test('rejecting a posted journal entry fails before changing status', () async {
    final accounts = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    final entryId = await db.createJournalEntry(
      description: 'اختبار رفض قيد مرحّل',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 10),
        JournalLine(accountId: accounts[1].id, credit: 10),
      ],
      referenceType: 'audit_safe_fixes',
    );

    await expectLater(
      db.rejectJournalEntry(entryId, 1),
      throwsA(isA<Exception>()),
    );
    final entry = await (db.select(db.journalEntries)
          ..where((journalEntry) => journalEntry.id.equals(entryId)))
        .getSingle();
    expect(entry.isPosted, isTrue);
  });

  test('changing a commercial paper to its current status is a no-op', () async {
    final partyId = await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'اختبار طرف',
        isCustomer: const Value(true),
        isSupplier: const Value(false),
      ),
    );
    final repository = CommercialPapersRepositoryImpl(db);
    final paperId = await repository.createPaper(
      paperNumber: 'AUDIT-${DateTime.now().microsecondsSinceEpoch}',
      type: 'cheque',
      direction: 'received',
      partyId: partyId,
      amount: 50,
      issueDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 30)),
    );
    final before = await (db.select(db.paperStatusHistory)
          ..where((history) => history.paperId.equals(paperId)))
        .get();

    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'pending',
      changedBy: 1,
    );

    final after = await (db.select(db.paperStatusHistory)
          ..where((history) => history.paperId.equals(paperId)))
        .get();
    expect(after, hasLength(before.length));
  });

  test('deleting an expense in a closed period is blocked', () async {
    final expenseDate = DateTime.now();
    final fiscalYear = await db.getFiscalYearByDate(expenseDate);
    if (fiscalYear == null) {
      await db.into(db.fiscalYears).insert(
            FiscalYearsCompanion.insert(
              name: 'اختبار السنة المالية',
              startDate: DateTime(expenseDate.year, 1, 1),
              endDate: DateTime(expenseDate.year, 12, 31, 23, 59, 59),
            ),
          );
    }
    final categoryId = await db.createExpenseCategory(name: 'اختبار فترة');
    final expenseId = await db.recordAndPostOperationalExpense(
      categoryId: categoryId,
      amount: 25,
      expenseDate: expenseDate,
      description: 'مصروف فترة مغلقة',
      expenseAccountCode: '6214',
      userId: 1,
    );
    final existingPeriod = await (db.select(db.accountingPeriods)
          ..where((period) => period.month.equals(expenseDate.month))
          ..where((period) => period.year.equals(expenseDate.year)))
        .getSingleOrNull();
    if (existingPeriod != null) {
      await (db.update(db.accountingPeriods)
            ..where((period) => period.id.equals(existingPeriod.id)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    } else {
      final fiscalYearId = (await db.getFiscalYearByDate(expenseDate))!.id;
      await db.into(db.accountingPeriods).insert(
            AccountingPeriodsCompanion.insert(
              fiscalYearId: fiscalYearId,
              name: 'فترة اختبار مغلقة',
              month: expenseDate.month,
              year: expenseDate.year,
              startDate: DateTime(expenseDate.year, expenseDate.month, 1),
              endDate: DateTime(expenseDate.year, expenseDate.month + 1, 0, 23, 59, 59),
              isClosed: const Value(true),
            ),
          );
    }

    await expectLater(
      OperationalExpensesDao(db).deleteExpense(expenseId),
      throwsA(isA<Exception>()),
    );
    expect(
      await (db.select(db.opExpenses)
            ..where((expense) => expense.id.equals(expenseId)))
          .get(),
      hasLength(1),
    );
  });
}
