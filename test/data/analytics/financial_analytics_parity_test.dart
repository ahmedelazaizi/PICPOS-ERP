// Parity: the numbers the analytics engine reads must equal what the existing
// accounting reports (AccountingReportsDao) show for the same period and
// branch scope.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/financial_analytics_provider.dart';
import 'package:ural_erp/domain/analytics/account_classifier.dart';

import 'analytics_harness.dart';

void main() {
  late AppDatabase db;
  late Ledger gl;
  late int brA;
  late int brB;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 1, 31);
  final prev = priorPeriod(from, to);

  // Realistic set: capital, stock on credit, cash / VAT / credit sales,
  // a return, COGS, rent, depreciation, loan + interest, income tax, a safe
  // sub-account, a deposit account, a voided (reversed) and an unposted entry.
  Future<void> seed() async {
    brA = await gl.addBranch('A');
    brB = await gl.addBranch('B');
    await gl.addChildAccount('111-90001', '111', 'asset'); // a safe's account
    // ── Dec 2025 (prior period) ──
    final dec = DateTime(2025, 12, 5);
    await gl.post(dec, [('1111', 10000, 0), ('311', 0, 10000)]);
    await gl.post(dec, [('1136', 2000, 0), ('2111', 0, 2000)]);
    await gl.post(DateTime(2025, 12, 10), [('1111', 300, 0), ('4121', 0, 300)],
        branchId: brA);
    await gl.post(DateTime(2025, 12, 10), [('5211', 150, 0), ('1136', 0, 150)],
        branchId: brA);
    // ── Jan 2026 ──
    await gl.post(DateTime(2026, 1, 2),
        [('1111', 575, 0), ('4121', 0, 500), ('2121', 0, 75)],
        branchId: brA, refType: 'cash_sale');
    await gl.post(DateTime(2026, 1, 2), [('5211', 300, 0), ('1136', 0, 300)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 5), [('1121', 800, 0), ('4121', 0, 800)],
        branchId: brB, refType: 'credit_sale');
    await gl.post(DateTime(2026, 1, 5), [('5211', 480, 0), ('1136', 0, 480)],
        branchId: brB);
    await gl.post(DateTime(2026, 1, 8), [('4211', 100, 0), ('1121', 0, 100)],
        branchId: brB, refType: 'sales_return');
    await gl.post(DateTime(2026, 1, 9), [('111-90001', 300, 0), ('4121', 0, 300)],
        branchId: brB, refType: 'cash_sale');
    await gl.post(DateTime(2026, 1, 12), [('623', 200, 0), ('1111', 0, 200)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 12), [('6214', 80, 0), ('1111', 0, 80)],
        branchId: brB);
    await gl.post(DateTime(2026, 1, 15), [('6213', 100, 0), ('1219', 0, 100)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 16), [('1113', 5000, 0), ('2141', 0, 5000)]);
    await gl.post(DateTime(2026, 1, 20), [('6311', 50, 0), ('1113', 0, 50)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 25), [('73', 120, 0), ('2122', 0, 120)]);
    await gl.post(DateTime(2026, 1, 26), [('1136', 700, 0), ('2111', 0, 700)],
        branchId: brB);
    await gl.post(DateTime(2026, 1, 27), [('1115', 1000, 0), ('311', 0, 1000)]);
    // Voided: original + posted mirror reversal; plus a never-posted draft.
    await gl.post(DateTime(2026, 1, 28), [('1111', 90, 0), ('4121', 0, 90)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 29), [('4121', 90, 0), ('1111', 0, 90)],
        branchId: brA);
    await gl.post(DateTime(2026, 1, 30), [('1111', 999, 0), ('4121', 0, 999)],
        branchId: brA, posted: false);
    // Party sub-ledger kept in sync with the GL (AR 700, AP 2700).
    await gl.addParty('Customer', balance: 700);
    await gl.addParty('Supplier', balance: 2700, supplier: true);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    gl = Ledger(db);
    await seed();
  });
  tearDown(() => db.close());

  Future<void> expectParity(Set<int>? scope) async {
    final r = await computeFinancialAnalytics(db, (from: from, to: to),
        allowedBranchIds: scope);
    final inc = await db.getIncomeStatement(from, to, allowedBranchIds: scope);
    final bs = await db.getBalanceSheet(to, allowedBranchIds: scope);
    final cf = await db.getCashFlowStatement(from, to, allowedBranchIds: scope);
    final s = r.current;
    expect(s.revenue, closeTo(inc['totalRevenue'] as double, 1e-9));
    expect(s.cogs, closeTo(inc['totalCOGS'] as double, 1e-9));
    expect(s.grossProfit, closeTo(inc['grossProfit'] as double, 1e-9));
    expect(s.netIncome, closeTo(inc['netProfit'] as double, 1e-9));
    expect(s.totalAssets, closeTo(bs['totalAssets'] as double, 1e-9));
    expect(s.totalLiabilities, closeTo(bs['totalLiabilities'] as double, 1e-9));
    expect(s.equity, closeTo(bs['totalEquity'] as double, 1e-9));
    expect(s.cash, closeTo(cf['closingBalance'] as double, 1e-9));

    // The prior snapshot is the same reports over the prior window.
    final pInc =
        await db.getIncomeStatement(prev.from, prev.to, allowedBranchIds: scope);
    final pBs = await db.getBalanceSheet(prev.to, allowedBranchIds: scope);
    expect(r.prior.revenue, closeTo(pInc['totalRevenue'] as double, 1e-9));
    expect(r.prior.netIncome, closeTo(pInc['netProfit'] as double, 1e-9));
    expect(r.prior.totalAssets, closeTo(pBs['totalAssets'] as double, 1e-9));
    expect(r.prior.equity, closeTo(pBs['totalEquity'] as double, 1e-9));
  }

  test('unrestricted: P&L, balance sheet and cash equal the DAO reports',
      () async {
    await expectParity(null);
    final s = (await computeFinancialAnalytics(db, (from: from, to: to))).current;
    // Hand-computed anchors (guard against both sides being wrong together).
    expect(s.revenue, 1500); // 500+800+300 sales (+90-90) -100 return
    expect(s.cogs, 780);
    expect(s.grossProfit, 720);
    expect(s.interest, 50);
    expect(s.tax, 120);
    expect(s.depreciation, 100);
    // 720 - (200 rent + 80 misc + 100 depr. + 50 interest + 120 tax)
    expect(s.netIncome, 170);
  });

  test('unrestricted: receivables/payables equal the aged reports', () async {
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    final ar = await db.getAgedReceivables(to);
    final ap = await db.getAgedPayables(to);
    double sum(List<Map<String, dynamic>> rows) =>
        rows.fold(0.0, (t, e) => t + (e['totalBalance'] as double));
    expect(r.current.receivables, closeTo(sum(ar), 1e-9));
    expect(r.current.payables, closeTo(sum(ap), 1e-9));
    expect(r.current.receivables, 700);
    expect(r.current.payables, 2700);
  });

  test('cash is the cash-flow closing balance (covers safes and deposits)',
      () async {
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    final cf = await db.getCashFlowStatement(from, to);
    expect(r.current.cash, closeTo(cf['closingBalance'] as double, 1e-9));
    // The mapped-account bucket alone would miss 1115 (1000) and the safe's
    // sub-account (300); the report counts both.
    final recs = await loadAccountRecords(db, from, to);
    final bucket = classifyAccounts(recs, await loadPurposeMap(db))[
        AccountBucket.cash];
    expect(r.current.cash - bucket, closeTo(1300, 1e-9));
  });

  test('cash includes manual (NULL reference_type) entries and equals the '
      'cash-flow closing balance', () async {
    await gl.post(DateTime(2026, 1, 31), [('1111', 500, 0), ('311', 0, 500)],
        refType: null);
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    final recs = await loadAccountRecords(db, from, to);
    final tree = await loadCashTreeIds(db);
    final glCash =
        recs.where((a) => tree.contains(a.id)).fold(0.0, (t, a) => t + a.balance);
    expect(r.current.cash, closeTo(glCash, 1e-9));
    final closing = (await db.getCashFlowStatement(from, to))['closingBalance']
        as double;
    // The statement counts NULL reference_type entries as operating activity.
    expect(closing, closeTo(glCash, 1e-9));
  });

  test('branch A only equals the DAO reports for the same scope', () async {
    await expectParity({brA});
  });

  test('branch B only equals the DAO reports for the same scope', () async {
    await expectParity({brB});
  });

  test('both branches listed equals the unrestricted numbers', () async {
    await expectParity({brA, brB});
    final all = await computeFinancialAnalytics(db, (from: from, to: to));
    final both = await computeFinancialAnalytics(db, (from: from, to: to),
        allowedBranchIds: {brA, brB});
    expect(both.current.revenue, all.current.revenue);
    expect(both.current.totalAssets, all.current.totalAssets);
    expect(both.current.netIncome, all.current.netIncome);
  });

  test('empty branch scope matches the DAO (nothing visible)', () async {
    await expectParity(<int>{});
    final r = await computeFinancialAnalytics(db, (from: from, to: to),
        allowedBranchIds: <int>{});
    expect(r.current.revenue, 0);
    expect(r.current.receivables, 0);
  });

  test('branch scopes partition the data (A + B + global = whole)', () async {
    Future<double> rev(Set<int> s) async => (await computeFinancialAnalytics(
            db, (from: from, to: to), allowedBranchIds: s))
        .current
        .revenue;
    // All sales are branch-tagged, so the two branches add up to the company.
    expect(await rev({brA}) + await rev({brB}), closeTo(1500, 1e-9));
    expect(await rev({brA}), closeTo(500, 1e-9)); // 500 + 90 - 90
    expect(await rev({brB}), closeTo(1000, 1e-9)); // 800 + 300 - 100
  });

  test('restricted view: AR/AP follow the GL; aged reports are scope-aware',
      () async {
    final r = await computeFinancialAnalytics(db, (from: from, to: to),
        allowedBranchIds: {brA});
    // GL for branch A (+ global rows): no receivable, only the global 2000
    // stock payable — the credit sale and the 700 purchase are branch B.
    expect(r.current.receivables, 0);
    expect(r.current.payables, 2000);
    // With a scope filter the aged report totals only that scope's open
    // invoices (none are seeded here) instead of the company-wide 700.
    final ar = await db.getAgedReceivables(to, allowedBranchIds: {brA});
    expect(ar, isEmpty);
    final ap = await db.getAgedPayables(to, allowedBranchIds: {brA});
    expect(ap, isEmpty);
  });

  test('unposted and reversed entries are excluded exactly as in the DAO',
      () async {
    // The 999 draft is not posted; the 90 sale is cancelled by its reversal.
    final inc = await db.getIncomeStatement(from, to);
    expect(inc['totalRevenue'] as double, 1500);
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    expect(r.current.revenue, 1500);
    final recs = await loadAccountRecords(db, from, to);
    final sales = recs.firstWhere((a) => a.code == '4121').balance;
    expect(sales, 1600); // account balance sees the same posted lines
  });

  // C-2 (changed on BOTH sides): this test used to assert that a soft-deleted
  // posted entry is counted by the DAO reports and by the engine alike
  // (revenue 1533). The income statement, balance sheet, cash-flow statement
  // and the engine's account SQL now all exclude `is_deleted` entries, like the
  // trial balance always did, so the entry must move nothing.
  test('soft-deleted posted entry is ignored by the DAO reports AND the engine',
      () async {
    final before = await computeFinancialAnalytics(db, (from: from, to: to));
    final cfBefore = await db.getCashFlowStatement(from, to);
    final bsBefore = await db.getBalanceSheet(to);

    await gl.post(DateTime(2026, 1, 31), [('1111', 33, 0), ('4121', 0, 33)],
        deleted: true);

    await expectParity(null); // DAO and engine still agree...
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    expect(r.current.revenue, 1500); // ...and neither counts the 33
    expect(r.current.revenue, before.current.revenue);
    expect(r.current.netIncome, before.current.netIncome);
    expect(r.current.cash, before.current.cash);
    expect(r.current.totalAssets, before.current.totalAssets);
    expect(r.current.operatingCashFlow, before.current.operatingCashFlow);
    expect(
        r.ratios.map((x) => x.value).toList(),
        before.ratios.map((x) => x.value).toList(),
        reason: 'no ratio may move when a JE is soft-deleted');

    final cf = await db.getCashFlowStatement(from, to);
    expect(cf['closingBalance'], cfBefore['closingBalance']);
    expect(cf['operating'], cfBefore['operating']);
    expect((await db.getBalanceSheet(to))['totalAssets'],
        bsBefore['totalAssets']);
  });

  test('a soft-deleted entry is also invisible to loadAccountRecords',
      () async {
    final salesBefore = (await loadAccountRecords(db, from, to))
        .firstWhere((a) => a.code == '4121')
        .balance;
    await gl.post(DateTime(2026, 1, 31), [('1111', 33, 0), ('4121', 0, 33)],
        deleted: true);
    final salesAfter = (await loadAccountRecords(db, from, to))
        .firstWhere((a) => a.code == '4121')
        .balance;
    expect(salesAfter, salesBefore);
  });
}
