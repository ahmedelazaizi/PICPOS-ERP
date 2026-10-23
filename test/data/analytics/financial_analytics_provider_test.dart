import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/financial_analytics_provider.dart';
import 'package:picpos_erp/domain/analytics/account_classifier.dart';
import 'package:picpos_erp/domain/analytics/kpi_comparison.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 1, 31);

  // AppDatabase.forTesting() seeds the standard chart and its default
  // account mappings, so tests use the SEEDED accounts, looked up by code.
  Future<int> idOf(String code) async => (await (db.select(db.accounts)
            ..where((a) => a.code.equals(code)))
          .getSingle())
      .id;

  Future<void> rename(String code, String name) => (db.update(db.accounts)
        ..where((a) => a.code.equals(code)))
      .write(AccountsCompanion(name: Value(name)));
  Future<void> post(DateTime date, List<(int, double, double)> lines) async {
    final entryId = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'T-${date.microsecondsSinceEpoch}-${lines.length}',
            entryDate: date,
            isPosted: const Value(true),
          ),
        );
    for (final l in lines) {
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: entryId,
              accountId: l.$1,
              debit: Value(l.$2),
              credit: Value(l.$3),
            ),
          );
    }
  }

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('budgetMonthFraction pro-rates partial months by days', () {
    expect(budgetMonthFraction(2026, 1, from, to), closeTo(1.0, 1e-9));
    expect(budgetMonthFraction(2026, 2, from, to), 0);
    expect(budgetMonthFraction(2026, 1, DateTime(2026, 1, 1),
        DateTime(2026, 1, 15)), closeTo(15 / 31, 1e-9));
  });

  test('ratios come from account-code classification, not names', () async {
    // Deliberately misleading names: classification must ignore them.
    await rename('1111', 'Loans');
    await rename('1136', 'Cash');
    await rename('2141', 'Inventory');
    final cash = await idOf('1111');
    final stock = await idOf('1136');
    final ar = await idOf('1121');
    final ap = await idOf('2111');
    final loan = await idOf('2141');
    final capital = await idOf('311');
    final sales = await idOf('4121');
    final cogs = await idOf('5211');
    final interest = await idOf('6311');
    // Jan: capital 1000 in cash, stock bought on credit 200, loan 300 in
    // cash, receivable sale 500 (cogs 200), interest 20 paid in cash.
    await post(DateTime(2026, 1, 2), [(cash, 1300, 0), (capital, 0, 1000), (loan, 0, 300)]);
    await post(DateTime(2026, 1, 3), [(stock, 200, 0), (ap, 0, 200)]);
    await post(DateTime(2026, 1, 10), [(ar, 500, 0), (sales, 0, 500)]);
    await post(DateTime(2026, 1, 10), [(cogs, 200, 0), (stock, 0, 200)]);
    await post(DateTime(2026, 1, 20), [(interest, 20, 0), (cash, 0, 20)]);

    final res = await computeFinancialAnalytics(db, (from: from, to: to));
    final s = res.current;
    expect(s.cash, 1280);
    expect(s.inventory, 0); // bought 200, sold 200
    expect(s.receivables, 500);
    expect(s.payables, 200);
    expect(s.debt, 300);
    expect(s.interest, 20);
    expect(s.currentAssets, 1780); // tree '11': cash + AR (stock is 0)
    expect(s.currentLiabilities, 500); // 2111 + 2141 under prefix 21
    expect(s.revenue, 500);

    final cr = res.ratios.firstWhere((r) => r.key == 'current_ratio');
    expect(cr.value, closeTo(1780 / 500, 1e-9));
    final cashRatio = res.ratios.firstWhere((r) => r.key == 'cash_ratio');
    expect(cashRatio.value, closeTo(1280 / 500, 1e-9));
  });

  test('account_mappings purpose beats code prefix in the provider', () async {
    final a = await idOf('1111');
    final b = await idOf('1113');
    final cap = await idOf('311');
    await post(DateTime(2026, 1, 2), [(a, 100, 0), (b, 40, 0), (cap, 0, 140)]);
    // Only 'bank' → 1113 remains mapped for the cash bucket.
    await (db.delete(db.accountMappings)
          ..where((m) => m.purpose.isIn(['cash', 'petty_cash', 'bank2', 'click'])))
        .go();
    await (db.update(db.accountMappings)..where((m) => m.purpose.equals('bank')))
        .write(AccountMappingsCompanion(accountId: Value(b)));
    final purposes = await loadPurposeMap(db);
    expect(purposes['bank'], b);
    final recs = await loadAccountRecords(db, from, to);
    expect(classifyAccounts(recs, purposes)[AccountBucket.cash], 40);
    expect(classifyAccounts(recs, const {})[AccountBucket.cash], 140);
  });

  test('budget is aggregated per account type and exposed to KpiComparison',
      () async {
    final existing = await db.getFiscalYearByDate(DateTime(2026, 1, 15));
    final fy = existing?.id ??
        await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
              name: '2026',
              startDate: DateTime(2026, 1, 1),
              endDate: DateTime(2026, 12, 31),
            ));
    final sales = await idOf('4121');
    final cogs = await idOf('5211');
    final cash = await idOf('1111');    await post(DateTime(2026, 1, 5),
        [(cash, 400, 0), (sales, 0, 400)]);
    await db.createBudget(fiscalYearId: fy, accountId: sales, annualAmount: 12000);
    await db.createBudget(fiscalYearId: fy, accountId: cogs, annualAmount: 6000);

    final res = await computeFinancialAnalytics(db, (from: from, to: to));
    expect(res.budget.revenue, closeTo(1000, 1e-6)); // 12000/12 for Jan
    expect(res.budget.expenses, closeTo(500, 1e-6));
    expect(res.budget.netIncome, closeTo(500, 1e-6));

    final rev = res.comparisons.firstWhere((c) => c.key == 'revenue');
    expect(rev.actual, 400);
    expect(rev.vsBudget.amount, closeTo(-600, 1e-6));
    expect(rev.vsBudget.favourability, Favourability.unfavourable);
  });

  test('no budget rows → budget targets null, variance unknown', () async {
    final res = await computeFinancialAnalytics(db, (from: from, to: to));
    expect(res.budget.isEmpty, isTrue);
    final rev = res.comparisons.firstWhere((c) => c.key == 'revenue');
    expect(rev.vsBudget.favourability, Favourability.unknown);
  });
}
