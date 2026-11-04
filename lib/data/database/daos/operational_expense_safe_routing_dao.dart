part of '../database.dart';

extension OperationalExpenseSafeRoutingDao on AppDatabase {
  Future<Safe?> _resolveOperationalExpenseSafe(int? safeId) async {
    if (safeId != null) {
      final selected = await (select(safes)..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      if (selected != null) return selected;
    }
    return getDefaultSafeByType('cash');
  }
}
