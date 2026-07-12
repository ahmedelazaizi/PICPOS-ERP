// ═══════════════════════════════════════════════════════════════════════════
// COA ROLLUP — pure hierarchical balance aggregation for the Chart of Accounts
// ═══════════════════════════════════════════════════════════════════════════
//
// Spec 135 BUG-E. The COA tree showed each account's OWN balance only
// (coa_tree_node), so a parent ("الأصول المتداولة") rendered its direct
// postings — usually 0 — instead of the sum of its children, and the group
// header used a flat fold of every account's own balance. Operators expected
// each parent node to show the subtotal of everything beneath it.
//
// Account balances are stored OWN-only (createJournalEntry recomputes each
// account.balance as SUM(debit) - SUM(credit) over that account's OWN lines),
// so the roll-up is a pure tree aggregation: leaf = own; parent = own + the
// rolled-up balance of every descendant. The grand total of a type is the sum
// over its ROOTS only (each leaf/own contributes exactly once through its
// root's subtree) — equal to a flat fold of all own balances, but expressed
// over roots so it stays consistent with the per-node subtotals.
//
// Compute on the UNFILTERED account list so a parent's subtotal still includes
// children hidden by a search/filter in the view. Display-only — no R3/R4/R5/R9.
//
// Constitution §IV / R7: this helper stays free of the data/database layer — it
// operates on plain (id, parentId, balance) records, and the screen maps its
// Account rows to those records. Keeps presentation off a direct DB import.

/// A minimal account node for roll-up: stable id, optional parent, own balance.
typedef CoaNode = ({int id, int? parentId, double balance});

class CoaRollup {
  /// accountId → rolled-up balance (own + all descendants).
  final Map<int, double> _rolled;

  const CoaRollup._(this._rolled);

  /// Build the roll-up over [nodes] (pass the FULL, unfiltered list).
  factory CoaRollup.compute(Iterable<CoaNode> nodes) {
    final childrenByParent = <int, List<CoaNode>>{};
    for (final n in nodes) {
      final pid = n.parentId;
      if (pid != null) {
        (childrenByParent[pid] ??= <CoaNode>[]).add(n);
      }
    }

    final rolled = <int, double>{};
    final visiting = <int>{}; // guards against a malformed parent cycle

    double dfs(CoaNode n) {
      final cached = rolled[n.id];
      if (cached != null) return cached;
      if (!visiting.add(n.id)) return n.balance; // cycle — count own only
      var sum = n.balance;
      for (final child in childrenByParent[n.id] ?? const <CoaNode>[]) {
        sum += dfs(child);
      }
      visiting.remove(n.id);
      rolled[n.id] = sum;
      return sum;
    }

    for (final n in nodes) {
      dfs(n);
    }
    return CoaRollup._(rolled);
  }

  /// Rolled-up balance for the account [id] (own + descendants). Falls back to
  /// [ownBalance] if the id wasn't part of the computed set.
  double balanceOf(int id, double ownBalance) => _rolled[id] ?? ownBalance;

  /// Grand total over the given [roots] only — each account counted once.
  double grandTotalOfRoots(Iterable<CoaNode> roots) =>
      roots.fold(0.0, (sum, r) => sum + balanceOf(r.id, r.balance));
}
