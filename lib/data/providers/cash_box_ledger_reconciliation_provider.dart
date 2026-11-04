import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import '../../core/i18n/tr.dart';

class CashBoxLedgerComparison {
  const CashBoxLedgerComparison({
    required this.safeName,
    required this.safeBalance,
    required this.accountCode,
    required this.ledgerBalance,
    required this.isUnlinkedCashControl,
  });

  final String? safeName;
  String get displayName => isUnlinkedCashControl
      ? tr('حساب نقدية غير مرتبط بصندوق')
      : safeName ?? '';
  final double safeBalance;
  final String? accountCode;
  final double ledgerBalance;
  final bool isUnlinkedCashControl;

  double get difference => safeBalance - ledgerBalance;
}

/// Read-only comparison; balances are never repaired or written here.
final cashBoxLedgerReconciliationProvider =
    FutureProvider.autoDispose<List<CashBoxLedgerComparison>>((ref) async {
  final branchScope = await ref.watch(branchScopeProvider.future);
  final db = ref.watch(databaseProvider);
  final safes = await ref.watch(scopedSafesProvider.future);
  final comparisons = await _safeLedgerComparisons(db, safes, branchScope);
  final control = await _unlinkedCashControlComparison(db, safes, branchScope);
  return [...comparisons, ?control];
});

Future<List<CashBoxLedgerComparison>> _safeLedgerComparisons(
  AppDatabase db,
  List<SafeData> safes,
  BranchScope branchScope,
) async {
  final comparisons = <CashBoxLedgerComparison>[];
  for (final safe in safes) {
    comparisons.add(await _safeLedgerComparison(db, safe, branchScope));
  }
  return comparisons;
}

Future<CashBoxLedgerComparison> _safeLedgerComparison(
  AppDatabase db,
  SafeData safe,
  BranchScope branchScope,
) async {
  final accountId = safe.linkedAccountId;
  final account = accountId == null ? null : await db.getAccountById(accountId);
  final ledgerBalance = accountId == null
      ? 0.0
      : await _readLedgerBalance(db, accountId, safe.branchId, branchScope);
  return CashBoxLedgerComparison(
    safeName: safe.name,
    safeBalance: safe.balance,
    accountCode: account?.code,
    ledgerBalance: ledgerBalance,
    isUnlinkedCashControl: false,
  );
}

Future<CashBoxLedgerComparison?> _unlinkedCashControlComparison(
  AppDatabase db,
  List<SafeData> safes,
  BranchScope branchScope,
) async {
  final account = await db.getAccountByCode('1111');
  if (account == null || safes.any((safe) => safe.linkedAccountId == account.id)) {
    return null;
  }
  return CashBoxLedgerComparison(
    safeName: null,
    safeBalance: 0,
    accountCode: account.code,
    ledgerBalance: await _readLedgerBalance(db, account.id, null, branchScope),
    isUnlinkedCashControl: true,
  );
}

Future<double> _readLedgerBalance(
  AppDatabase db,
  int accountId,
  int? branchId,
  BranchScope branchScope,
) async {
  final branchFilter = _ledgerBranchFilter(branchId, branchScope);
  final row = await db.customSelect(
    'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS balance '
    'FROM journal_entry_lines l '
    'JOIN journal_entries e ON e.id = l.entry_id '
    'WHERE e.is_posted = true AND e.is_deleted = false AND l.account_id = ?'
    '${branchFilter.clause}',
    variables: [Variable<int>(accountId), ...branchFilter.variables],
  ).getSingle();
  return (row.data['balance'] as num).toDouble();
}

({String clause, List<Variable> variables}) _ledgerBranchFilter(
  int? branchId,
  BranchScope branchScope,
) {
  if (branchId != null) {
    return (clause: ' AND (e.branch_id IS NULL OR e.branch_id = ?)',
        variables: [Variable<int>(branchId)]);
  }
  if (branchScope.hasFullAccess) return (clause: '', variables: []);
  final branchIds = branchScope.allowedBranchIds!.toList();
  if (branchIds.isEmpty) {
    return (clause: ' AND e.branch_id IS NULL', variables: []);
  }
  final placeholders = List.filled(branchIds.length, '?').join(',');
  return (
    clause: ' AND (e.branch_id IS NULL OR e.branch_id IN ($placeholders))',
    variables: branchIds.map((id) => Variable<int>(id)).toList(),
  );
}
