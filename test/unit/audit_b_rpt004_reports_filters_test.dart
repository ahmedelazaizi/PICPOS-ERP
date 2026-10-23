// Audit B RPT-004 / RPT-007 — GL-side reports must ignore soft-deleted and
// unposted journal entries.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int vat;
  late int cash;
  final day = DateTime(2026, 3, 10);
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31, 23, 59, 59);

  setUp(() async {
    db = AppDatabase.forTesting();
    Future<int> acc(String code) async => (await (db.select(db.accounts)
              ..where((a) => a.code.equals(code)))
            .getSingle())
        .id;
    vat = await acc('2121');
    cash = await acc('1111');
  });
  tearDown(() => db.close());

  Future<int> je(String no, double amount,
      {bool deleted = false,
      bool posted = true,
      String? refType,
      int? refId}) async {
    final id = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: no,
            entryDate: day,
            isPosted: Value(posted),
            isDeleted: Value(deleted),
            referenceType: Value(refType),
            referenceId: Value(refId),
          ),
        );
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: id, accountId: cash, debit: Value(amount)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: id, accountId: vat, credit: Value(amount)));
    return id;
  }

  test('tax report ignores soft-deleted VAT journal entries', () async {
    await je('JE-OK', 15);
    await je('JE-DEL', 99, deleted: true);
    final r = await db.getTaxReport(from, to);
    expect(r['salesTax'], 15);
  });

  test('hierarchical trial balance equals flat TB with a deleted JE',
      () async {
    await je('JE-OK', 100);
    await je('JE-DEL', 50, deleted: true);
    final h = await db.getHierarchicalTrialBalance(from, to);
    expect(h['totalDebit'], 100);
    expect(h['totalCredit'], 100);
  });

  test('posting reconciliation orphan list skips soft-deleted JEs', () async {
    await je('JE-ORPHAN', 10, refType: 'sale', refId: 9999);
    await je('JE-ORPHAN-DEL', 10, refType: 'sale', refId: 9998, deleted: true);
    final rows = await db.getPostingReconciliation(from, to);
    final numbers = rows.map((r) => r['jeNumber']);
    expect(numbers.where((n) => n == 'JE-ORPHAN-DEL'), isEmpty);
    expect(numbers.where((n) => n == 'JE-ORPHAN'), isNotEmpty);
  });

  test('budget actuals exclude draft and deleted journal entries', () async {
    final fy = await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: 'FY', startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 12, 31)));
    final budgetId = await db.createBudget(
        fiscalYearId: fy, accountId: cash, annualAmount: 1200);
    await je('JE-OK', 100);
    await je('JE-DRAFT', 40, posted: false);
    await je('JE-DEL', 70, deleted: true);
    await db.updateBudgetActuals(budgetId);
    final lines = await db.getBudgetLines(budgetId);
    expect(lines.firstWhere((l) => l.month == 3).actualAmount, 100);
  });
}
