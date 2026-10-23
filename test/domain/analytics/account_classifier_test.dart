import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/analytics/account_classifier.dart';
import 'package:picpos_erp/domain/analytics/budget_targets.dart';
import 'package:picpos_erp/domain/analytics/financial_snapshot.dart';

AccountRecord acc(int id, String code, String type,
        {int? parent, double bal = 0, String name = 'x'}) =>
    AccountRecord(
        id: id,
        code: code,
        name: name,
        accountType: type,
        parentId: parent,
        balance: bal);

/// Miniature of the seeded chart (ids = arbitrary).
List<AccountRecord> chart() => [
      acc(1, '1', 'asset'),
      acc(11, '11', 'asset', parent: 1),
      acc(111, '111', 'asset', parent: 11),
      acc(1111, '1111', 'asset', parent: 111, bal: 100),
      acc(1113, '1113', 'asset', parent: 111, bal: 50),
      acc(112, '112', 'asset', parent: 11),
      acc(1121, '1121', 'asset', parent: 112, bal: 80),
      acc(1124, '1124', 'asset', parent: 112, bal: -10), // contra allowance
      acc(113, '113', 'asset', parent: 11),
      acc(1136, '1136', 'asset', parent: 113, bal: 200),
      acc(12, '12', 'asset', parent: 1),
      acc(1211, '1211', 'asset', parent: 12, bal: 900), // non-current
      acc(2, '2', 'liability'),
      acc(21, '21', 'liability', parent: 2),
      acc(211, '211', 'liability', parent: 21),
      acc(2111, '2111', 'liability', parent: 211, bal: 70),
      acc(214, '214', 'liability', parent: 21),
      acc(2141, '2141', 'liability', parent: 214, bal: 40),
      acc(22, '22', 'liability', parent: 2),
      acc(221, '221', 'liability', parent: 22),
      acc(2211, '2211', 'liability', parent: 221, bal: 300),
      acc(6311, '6311', 'expense', bal: 12), // parentId null in the seed
      acc(73, '73', 'expense', bal: 9),
      acc(5131, '5131', 'expense', parent: null, bal: 5),
      acc(6213, '6213', 'expense', bal: 3),
    ];

void main() {
  test('code prefixes roll up the subtree (parents have no own balance)', () {
    final r = classifyAccounts(chart(), const {});
    expect(r[AccountBucket.cash], 150);
    expect(r[AccountBucket.receivables], 70); // 80 - 10 allowance
    expect(r[AccountBucket.inventory], 200);
    expect(r[AccountBucket.currentAssets], 420);
    expect(r[AccountBucket.payables], 70);
    expect(r[AccountBucket.debt], 340); // 214 + 221
    expect(r[AccountBucket.currentLiabilities], 110);
    expect(r[AccountBucket.interestExpense], 12);
    expect(r[AccountBucket.taxExpense], 9);
    expect(r[AccountBucket.depreciation], 8);
    expect(r.has(AccountBucket.cash), isTrue);
  });

  test('a parent is counted once even if children also match', () {
    final r = classifyAccounts(chart(), const {'bank': 111, 'cash': 1111});
    expect(r[AccountBucket.cash], 150); // 111 subtree; 1111 not added again
  });

  test('mapping purpose wins over code prefix', () {
    // Only account 1113 is mapped as cash → 1111 (prefix 111) is ignored.
    final r = classifyAccounts(chart(), const {'bank': 1113});
    expect(r[AccountBucket.cash], 50);
    // Mapping a subtree root rolls it up.
    final r2 = classifyAccounts(chart(), const {'receivables': 112});
    expect(r2[AccountBucket.receivables], 70);
    // Mapping can point outside the conventional prefix.
    final r3 = classifyAccounts(chart(), const {'inventory': 1211});
    expect(r3[AccountBucket.inventory], 900);
  });

  test('mapping to an unknown account id falls back to prefix', () {
    final r = classifyAccounts(chart(), const {'cash': 99999});
    expect(r[AccountBucket.cash], 150);
  });

  test('unknown accounts stay 0 and unmatched', () {
    final r = classifyAccounts([acc(1, '9999', 'asset', bal: 500)], const {});
    for (final b in AccountBucket.values) {
      expect(r[b], 0, reason: b.name);
      expect(r.has(b), isFalse, reason: b.name);
      expect(r.orNull(b), isNull, reason: b.name);
    }
  });

  test('account type must match the bucket family', () {
    // Code 111 but typed as expense: not cash.
    final r = classifyAccounts([acc(1, '1111', 'expense', bal: 5)], const {});
    expect(r.has(AccountBucket.cash), isFalse);
  });

  test('names are never used for classification', () {
    final r = classifyAccounts([
      acc(1, '9001', 'asset', bal: 100, name: 'الصندوق النقدية Cash'),
      acc(2, '9002', 'asset', bal: 100, name: 'مخزون Inventory'),
      acc(3, '9003', 'liability', bal: 100, name: 'قرض Loan'),
      acc(4, '9004', 'expense', bal: 100, name: 'فوائد Interest'),
    ], const {});
    expect(r.matched, isEmpty);
    // And a renamed seeded account is still found by code.
    final renamed = classifyAccounts(
        [acc(1, '1111', 'asset', bal: 7, name: 'حساب بلا معنى')], const {});
    expect(renamed[AccountBucket.cash], 7);
  });

  test('cycles and dangling parents do not hang or throw', () {
    final r = classifyAccounts([
      acc(1, '111', 'asset', parent: 2, bal: 1),
      acc(2, '1111', 'asset', parent: 1, bal: 2),
      acc(3, '1112', 'asset', parent: 777, bal: 4),
    ], const {});
    expect(r.has(AccountBucket.cash), isTrue);
    expect(r[AccountBucket.cash].isFinite, isTrue);
  });

  test('fromReports uses buckets, ignores *Details name rows, overrides win',
      () {
    final b = classifyAccounts(chart(), const {});
    final s = FinancialSnapshot.fromReports(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 30),
      balanceSheet: {
        'totalLiabilities': 410.0,
        'assetDetails': [
          {'name': 'الخزينة cash', 'balance': 9999.0},
        ],
      },
      incomeStatement: {
        'totalDepreciation': 0.0,
        'expenseDetails': [
          {'name': 'فوائد interest', 'balance': 9999.0},
        ],
      },
      buckets: b,
      tax: 1,
    );
    expect(s.cash, 150);
    expect(s.inventory, 200);
    expect(s.receivables, 70);
    expect(s.payables, 70);
    expect(s.debt, 340);
    expect(s.interest, 12);
    expect(s.tax, 1); // explicit override wins
    expect(s.depreciation, 8);
    expect(s.currentAssets, 420);
    expect(s.currentLiabilities, 110); // tree, not totalLiabilities (410)
  });

  test('fromReports without buckets: buckets 0, documented fallbacks', () {
    final s = FinancialSnapshot.fromReports(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 30),
      balanceSheet: {'totalLiabilities': 410.0},
      cashFlow: {'closingBalance': 33.0},
      incomeStatement: {'totalDepreciation': 6.0},
    );
    expect(s.cash, 33);
    expect(s.inventory, 0);
    expect(s.debt, 0);
    expect(s.interest, 0);
    expect(s.depreciation, 6);
    expect(s.currentAssets, 33);
    expect(s.currentLiabilities, 410);
  });

  group('aggregateBudget', () {
    final accounts = [
      acc(1, '4121', 'revenue'),
      acc(2, '4211', 'revenue'), // returns (group 42)
      acc(3, '4315', 'revenue'), // other income, not sales
      acc(4, '5211', 'expense'),
      acc(5, '621', 'expense'),
    ];
    test('revenue = sales − returns; net income = all revenue − expenses', () {
      final t = aggregateBudget(accounts, const [
        BudgetEntry(accountId: 1, amount: 1000),
        BudgetEntry(accountId: 2, amount: 100),
        BudgetEntry(accountId: 3, amount: 50),
        BudgetEntry(accountId: 4, amount: 600),
        BudgetEntry(accountId: 5, amount: 150),
      ]);
      expect(t.revenue, 900);
      expect(t.expenses, 750);
      expect(t.netIncome, 1000 - 100 + 50 - 750);
    });
    test('missing side → null, never zero', () {
      expect(aggregateBudget(accounts, const []).isEmpty, isTrue);
      final onlyRev =
          aggregateBudget(accounts, const [BudgetEntry(accountId: 1, amount: 5)]);
      expect(onlyRev.revenue, 5);
      expect(onlyRev.netIncome, isNull);
      final unknown = aggregateBudget(
          accounts, const [BudgetEntry(accountId: 42, amount: 5)]);
      expect(unknown.isEmpty, isTrue);
    });
  });
}
