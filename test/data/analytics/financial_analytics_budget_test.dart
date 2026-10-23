// Budget handling of the analytics provider: fiscal-year month mapping,
// period spanning two fiscal years, prior-period budget, branch scope and
// cost-centre handling.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/financial_analytics_provider.dart';
import 'package:picpos_erp/domain/analytics/kpi_comparison.dart';

import 'analytics_harness.dart';

void main() {
  late AppDatabase db;
  late Ledger gl;

  setUp(() {
    db = AppDatabase.forTesting();
    gl = Ledger(db);
  });
  tearDown(() => db.close());

  Future<double?> salesBudget(DateTime from, DateTime to) async {
    final r = await computeFinancialAnalytics(db, (from: from, to: to));
    return r.budget.revenue;
  }

  group('fiscal year starting 1 July', () {
    late int fy;
    setUp(() async {
      fy = await gl.addFiscalYear(
          'FY25/26', DateTime(2025, 7, 1), DateTime(2026, 6, 30));
      // fiscal month 1 = July 2025 (1000), month 7 = January 2026 (7000).
      await gl.addBudget(fy, '4121', {1: 1000, 7: 7000});
    });

    test('month N is the N-th month from the real start date', () async {
      expect(await salesBudget(DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
          closeTo(7000, 1e-6)); // NOT month 1's 1000 (calendar mapping)
      expect(await salesBudget(DateTime(2025, 7, 1), DateTime(2025, 7, 31)),
          closeTo(1000, 1e-6));
    });

    test('a month outside the year gets nothing', () async {
      expect(await salesBudget(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
          isNull);
    });

    test('partial month is pro-rated by days', () async {
      expect(await salesBudget(DateTime(2026, 1, 1), DateTime(2026, 1, 15)),
          closeTo(7000 * 15 / 31, 1e-6));
    });
  });

  test('period spanning two fiscal years sums both years', () async {
    final a = await gl.addFiscalYear(
        'FY25/26', DateTime(2025, 7, 1), DateTime(2026, 6, 30));
    final b = await gl.addFiscalYear(
        'FY26/27', DateTime(2026, 7, 1), DateTime(2027, 6, 30));
    await gl.addBudget(a, '4121', {12: 12000}); // June 2026
    await gl.addBudget(b, '4121', {1: 3100}); // July 2026
    // 16 Jun – 15 Jul: June 16..30 = 15/30 of 12000, July 1..15 = 15/31 of 3100
    expect(await salesBudget(DateTime(2026, 6, 16), DateTime(2026, 7, 15)),
        closeTo(6000 + 1500, 1e-6));
  });

  test('a mid-month fiscal start (15 Jul) shifts every month boundary',
      () async {
    final fy = await gl.addFiscalYear(
        'odd', DateTime(2025, 7, 15), DateTime(2026, 7, 14));
    await gl.addBudget(fy, '4121', {1: 3100}); // 15 Jul – 14 Aug (31 days)
    expect(await salesBudget(DateTime(2025, 7, 15), DateTime(2025, 8, 14)),
        closeTo(3100, 1e-6));
    expect(await salesBudget(DateTime(2025, 7, 1), DateTime(2025, 7, 14)),
        isNull);
  });

  group('prior-period budget', () {
    late int fy;
    setUp(() async {
      fy = await gl.addFiscalYear(
          'FY2026', DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      await gl.addBudget(fy, '4121', {1: 500, 2: 1000});
      await gl.post(DateTime(2026, 1, 10), [('1111', 400, 0), ('4121', 0, 400)]);
      await gl.post(DateTime(2026, 2, 10), [('1111', 900, 0), ('4121', 0, 900)]);
    });

    test('is computed for the prior window and feeds the comparison',
        () async {
      // Feb 2026 is 28 days, so the prior period is 4 Jan – 31 Jan.
      final r = await computeFinancialAnalytics(
          db, (from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28)));
      expect(r.budget.revenue, closeTo(1000, 1e-6));
      expect(r.priorBudget.revenue, closeTo(500 * 28 / 31, 1e-6));
      final rev = r.comparisons.firstWhere((c) => c.key == 'revenue');
      expect(rev.vsBudget.baseline, closeTo(1000, 1e-6));
      expect(rev.priorVsBudget.baseline, closeTo(500 * 28 / 31, 1e-6));
      expect(rev.priorVsBudget.amount, closeTo(400 - 500 * 28 / 31, 1e-6));
      expect(rev.budgetChange.amount, closeTo(1000 - 500 * 28 / 31, 1e-6));
      expect(rev.budgetChange.favourability, Favourability.favourable);
    });

    test('is null (variance unknown) when the prior window has no budget',
        () async {
      final r = await computeFinancialAnalytics(
          db, (from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31)));
      expect(r.budget.revenue, closeTo(500, 1e-6));
      expect(r.priorBudget.revenue, isNull); // December 2025: no fiscal year
      final rev = r.comparisons.firstWhere((c) => c.key == 'revenue');
      expect(rev.priorVsBudget.favourability, Favourability.unknown);
      expect(rev.budgetChange.favourability, Favourability.unknown);
    });
  });

  group('branch scope', () {
    late int brA;
    late int brB;
    setUp(() async {
      brA = await gl.addBranch('A');
      brB = await gl.addBranch('B');
      final fy = await gl.addFiscalYear(
          'FY2026', DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      await gl.addBudget(fy, '4121', {1: 1000, 2: 1000});
    });
    final from = DateTime(2026, 2, 1);
    final to = DateTime(2026, 2, 28);

    test('restricted view marks the budget unavailable (null), not company-wide',
        () async {
      final r = await computeFinancialAnalytics(db, (from: from, to: to),
          allowedBranchIds: {brA});
      expect(r.budgetAvailable, isFalse);
      expect(r.budget.isEmpty, isTrue);
      expect(r.priorBudget.isEmpty, isTrue);
      final rev = r.comparisons.firstWhere((c) => c.key == 'revenue');
      expect(rev.vsBudget.favourability, Favourability.unknown);
      expect(rev.vsBudget.baseline, isNull);
    });

    test('unrestricted and all-branches views keep the budget', () async {
      final open = await computeFinancialAnalytics(db, (from: from, to: to));
      // The test DB also seeds a default branch, so "all" means every row.
      final every = (await db.select(db.branches).get()).map((b) => b.id).toSet();
      expect(every, containsAll([brA, brB]));
      final all = await computeFinancialAnalytics(db, (from: from, to: to),
          allowedBranchIds: every);
      expect(await isBranchRestricted(db, {brA, brB}), isTrue);
      for (final r in [open, all]) {
        expect(r.budgetAvailable, isTrue);
        expect(r.budget.revenue, closeTo(1000, 1e-6));
      }
    });

    test('empty scope is restricted too', () async {
      final r = await computeFinancialAnalytics(db, (from: from, to: to),
          allowedBranchIds: <int>{});
      expect(r.budgetAvailable, isFalse);
    });
  });

  group('cost centres', () {
    late int fy;
    late int cc1;
    late int cc2;
    setUp(() async {
      fy = await gl.addFiscalYear(
          'FY2026', DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      cc1 = await gl.addCostCenter('CC1');
      cc2 = await gl.addCostCenter('CC2');
    });
    final from = DateTime(2026, 1, 1);
    final to = DateTime(2026, 1, 31);

    test('cost-centre-only budgets for an account are summed', () async {
      await gl.addBudget(fy, '4121', {1: 600}, costCenterId: cc1);
      await gl.addBudget(fy, '4121', {1: 400}, costCenterId: cc2);
      expect(await salesBudget(from, to), closeTo(1000, 1e-6));
    });

    test('a company-wide row wins over cost-centre rows (no double count)',
        () async {
      await gl.addBudget(fy, '4121', {1: 1000});
      await gl.addBudget(fy, '4121', {1: 600}, costCenterId: cc1);
      await gl.addBudget(fy, '4121', {1: 400}, costCenterId: cc2);
      expect(await salesBudget(from, to), closeTo(1000, 1e-6));
    });
  });

  group('cost-centre mapping overrides', () {
    test('provider reads the GLOBAL mapping, like the report DAOs', () async {
      final cc = await gl.addCostCenter('CC1');
      final petty = await gl.idOf('1112');
      final main = await gl.idOf('1111');
      await db.into(db.accountMappings).insert(AccountMappingsCompanion.insert(
          purpose: 'cash', accountId: petty, costCenterId: Value(cc)));
      final purposes = await loadPurposeMap(db);
      expect(purposes['cash'], main); // override row ignored
      // The posting engine DOES honour the override for that cost centre,
      // and falls back to the global mapping for the company-wide view.
      expect((await db.accountingDao.getAccountByPurpose('cash',
              costCenterId: cc))!
          .id, petty);
      expect((await db.accountingDao.getAccountByPurpose('cash'))!.id, main);
    });

    test('cost-centre override leaves the cash figure and classification '
        'unchanged', () async {
      final cc = await gl.addCostCenter('CC1');
      final petty = await gl.idOf('1112');
      await gl.post(DateTime(2026, 1, 3), [('1111', 100, 0), ('311', 0, 100)]);
      final params = (from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31));
      final before = await computeFinancialAnalytics(db, params);
      await db.into(db.accountMappings).insert(AccountMappingsCompanion.insert(
          purpose: 'cash', accountId: petty, costCenterId: Value(cc)));
      final after = await computeFinancialAnalytics(db, params);
      expect(after.current.cash, before.current.cash);
      expect(after.current.cash, 100);
    });
  });
}
