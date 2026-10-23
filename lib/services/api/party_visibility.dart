import 'package:drift/drift.dart' show Variable;

/// SEC-008 (audit 2026-10-23): branch visibility for `parties` rows.
///
/// `parties` has no `branch_id`; scope is `is_global` (visible everywhere) or a
/// CSV `branch_ids` list. A branch-restricted caller sees global parties,
/// parties with no branch list, and parties whose list intersects its scope.
class PartyVisibility {
  PartyVisibility._();

  static const balanceFields = {'balance', 'creditLimit'};
  static const balanceColumns = {'balance', 'credit_limit'};

  static Set<int> parseBranchIds(String? csv) => {
        for (final part in (csv ?? '').split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  /// In-memory predicate (`GET /api/parties`).
  static bool visible({
    required bool isGlobal,
    required String? branchIds,
    required List<int> scope,
  }) {
    if (isGlobal) return true;
    final ids = parseBranchIds(branchIds);
    if (ids.isEmpty) return true;
    return scope.any(ids.contains);
  }

  /// SQL predicate + variables for `/api/sync/pull?table=parties`.
  static (String, List<Variable>) sqlCondition(List<int> scope) {
    final likes = [
      for (final _ in scope)
        "(',' || REPLACE(branch_ids, ' ', '') || ',') LIKE ?",
    ].join(' OR ');
    return (
      "(is_global = ? OR branch_ids IS NULL OR branch_ids = ''"
          "${likes.isEmpty ? '' : ' OR $likes'})",
      [
        Variable.withBool(true),
        for (final b in scope) Variable.withString('%,$b,%'),
      ],
    );
  }
}
