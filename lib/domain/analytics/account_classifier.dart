// Financial Intelligence — identity-based account classification.
//
// Pure Dart (no Flutter, no database). Replaces matching Arabic/English
// keywords in account NAMES, which breaks as soon as a user renames an
// account. Classification uses only:
//   1. the account-mapping PURPOSES (AccountMappings: purpose -> accountId),
//   2. account-CODE prefixes taken from the seeded chart,
//   3. otherwise the bucket stays 0 / unmatched. Names are never inspected.
//
// ── Input contract ─────────────────────────────────────────────────────────
// [AccountRecord.balance] is the account's OWN balance (journal lines posted
// directly to it, NOT already rolled up from children), signed toward the
// account's natural side: debit-credit for asset/expense, credit-debit for
// liability/equity/revenue. A contra account (e.g. 1124 allowance) therefore
// carries a negative value and reduces its parent's subtree total.
// A parent (`view`) account contributes the sum of its subtree via parentId.
//
// ── Priority per bucket ────────────────────────────────────────────────────
// If ANY purpose of the bucket maps to an account present in the list, the
// bucket is the subtree total of ONLY those mapped accounts (an account whose
// ancestor is also selected is not counted twice). Otherwise the code-prefix
// rule is used. Otherwise: total 0 and `matched` false.
//
// ── Seeded chart (database_seeder_accounts.dart) → prefixes ────────────────
//   cash               asset      111  (1111 main cash, 1112 petty, 1113/1114
//                                  banks, 1115 deposits, 1116 Click)
//   receivables        asset      112  (1121/1122 customers, 1123 notes,
//                                  1124 allowance — contra, negative)
//   inventory          asset      113  (1131..1136 stock, 1137 allowance)
//   currentAssets      asset      11   (111 cash, 112 AR, 113 stock, 114 other)
//   payables           liability  211  (2111/2112 suppliers, 2113 notes)
//   debt               liability  214 (short-term loans/facilities/current
//                                  portion) and 221 (long-term loans, bonds)
//   currentLiabilities liability  21
//   interestExpense    expense    6311 (bank loan interest)
//   taxExpense         expense    73   (income tax)
//   depreciation       expense    5131, 5132, 6213
// The chart HAS a current / non-current split (11 vs 12, 21 vs 22), so
// currentAssets / currentLiabilities come from the tree. When neither the
// prefixes nor a tree are present the caller keeps its documented fallback
// (cash+inventory+receivables, and totalLiabilities).
//
// Prefix rules apply per account CODE (not tree position) because some
// seeded accounts (e.g. 6311) have no parentId. The account type must belong
// to the bucket's family (asset / liability / expense); 'contra_asset' counts
// as asset family.

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.accountType,
    this.parentId,
    this.balance = 0,
  });

  final int id;
  final String code;

  /// Carried for display only; never used for classification.
  final String name;
  final String accountType;
  final int? parentId;
  final double balance;
}

enum AccountBucket {
  cash,
  inventory,
  receivables,
  payables,
  debt,
  interestExpense,
  taxExpense,
  depreciation,
  currentAssets,
  currentLiabilities,
}

enum _Family { asset, liability, expense }

class _Rule {
  const _Rule(this.family, this.prefixes, this.purposes);
  final _Family family;
  final List<String> prefixes;
  final List<String> purposes;
}

/// Purpose keys are those of `account_mapping_purposes.dart` plus
/// `depreciation_expense`, which the income-statement DAO reads.
/// Current assets/liabilities have no purpose: prefix (tree) only.
const Map<AccountBucket, _Rule> _rules = {
  AccountBucket.cash: _Rule(
    _Family.asset,
    ['111'],
    ['cash', 'petty_cash', 'bank', 'bank2', 'click'],
  ),
  AccountBucket.receivables: _Rule(
    _Family.asset,
    ['112'],
    ['receivables', 'foreign_receivables', 'notes_receivable'],
  ),
  AccountBucket.inventory: _Rule(
    _Family.asset,
    ['113'],
    ['inventory', 'raw_materials', 'wip', 'goods_in_transit'],
  ),
  AccountBucket.currentAssets: _Rule(_Family.asset, ['11'], []),
  AccountBucket.payables: _Rule(
    _Family.liability,
    ['211'],
    ['payables', 'foreign_payables', 'notes_payable'],
  ),
  AccountBucket.debt: _Rule(
    _Family.liability,
    ['214', '221'],
    ['loans_payable'],
  ),
  AccountBucket.currentLiabilities: _Rule(_Family.liability, ['21'], []),
  AccountBucket.interestExpense: _Rule(_Family.expense, ['6311'], []),
  AccountBucket.taxExpense: _Rule(_Family.expense, ['73'], []),
  AccountBucket.depreciation: _Rule(
    _Family.expense,
    ['5131', '5132', '6213'],
    ['depreciation_expense'],
  ),
};

_Family? _familyOf(String type) {
  switch (type) {
    case 'asset':
    case 'contra_asset':
      return _Family.asset;
    case 'liability':
      return _Family.liability;
    case 'expense':
      return _Family.expense;
  }
  return null;
}

/// Per-bucket totals. Unmatched buckets are 0 and absent from [matched].
class ClassifiedBuckets {
  const ClassifiedBuckets(this.totals, this.matched);

  const ClassifiedBuckets.empty()
      : totals = const {},
        matched = const {};

  final Map<AccountBucket, double> totals;
  final Set<AccountBucket> matched;

  double operator [](AccountBucket b) => totals[b] ?? 0.0;
  bool has(AccountBucket b) => matched.contains(b);

  /// The total when matched, otherwise null (lets callers fall back).
  double? orNull(AccountBucket b) => has(b) ? this[b] : null;
}

/// Classifies [accounts] into [AccountBucket]s. [purposeToAccountId] holds the
/// global (non cost-centre) mapping purpose -> account id.
ClassifiedBuckets classifyAccounts(
  List<AccountRecord> accounts,
  Map<String, int> purposeToAccountId,
) {
  final byId = {for (final a in accounts) a.id: a};
  final children = <int, List<int>>{};
  for (final a in accounts) {
    final p = a.parentId;
    if (p != null && p != a.id && byId.containsKey(p)) {
      (children[p] ??= []).add(a.id);
    }
  }

  final memo = <int, double>{};
  double subtree(int id, Set<int> path) {
    final cached = memo[id];
    if (cached != null) return cached;
    if (!path.add(id)) return 0.0; // cycle guard
    var t = _finite(byId[id]!.balance);
    for (final c in children[id] ?? const <int>[]) {
      t += subtree(c, path);
    }
    path.remove(id);
    memo[id] = t;
    return t;
  }

  bool hasSelectedAncestor(int id, Set<int> selected) {
    final seen = <int>{id};
    var p = byId[id]!.parentId;
    while (p != null && byId.containsKey(p) && seen.add(p)) {
      if (selected.contains(p)) return true;
      p = byId[p]!.parentId;
    }
    return false;
  }

  final totals = <AccountBucket, double>{};
  final matched = <AccountBucket>{};

  for (final entry in _rules.entries) {
    final rule = entry.value;
    var selected = <int>{
      for (final purpose in rule.purposes)
        if (byId.containsKey(purposeToAccountId[purpose]))
          purposeToAccountId[purpose]!,
    };
    if (selected.isEmpty) {
      selected = {
        for (final a in accounts)
          if (_familyOf(a.accountType) == rule.family &&
              rule.prefixes.any(a.code.startsWith))
            a.id,
      };
    }
    if (selected.isEmpty) continue;
    var total = 0.0;
    for (final id in selected) {
      if (!hasSelectedAncestor(id, selected)) total += subtree(id, <int>{});
    }
    totals[entry.key] = total;
    matched.add(entry.key);
  }
  return ClassifiedBuckets(totals, matched);
}

double _finite(double v) => v.isFinite ? v : 0.0;
