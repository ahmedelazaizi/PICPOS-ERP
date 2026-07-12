import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import '../database.dart';

/// Feature 012 / Issue M-DUP-PRET — collapse duplicate return-memo rows
/// (`category = 'purchase_return_balance'` or `'sales_return_balance'`)
/// that piled up on mirror devices before the
/// `(referenceType, referenceId, partyId)` dedup landed in
/// [SafeTransactionSyncStrategy] (Feature 012).
///
/// Background: the mirror's local `processPurchaseReturn` seeds a memo
/// row using the *local* default safe (Feature 010 / Cluster D); the
/// server's authoritative memo row arrives via DeltaPull pointing at a
/// *different* safe (per-warehouse). The old dedup keyed on safeId, so
/// both rows survived → the supplier statement showed the return twice.
/// The Round-3 dedup loosening prevents NEW duplicates; this helper
/// removes the legacy ones already on disk.
///
/// Survivor preference per `(refType, refId, partyId)` group:
///   1. Row whose `voucherNumber` does NOT start with `PRET-LOC-` /
///      `SRET-LOC-` (the server's authoritative voucher).
///   2. Otherwise the row with the smallest id (oldest = first written).
extension ReturnMemoDedupExtension on AppDatabase {
  static const _categories = <String>[
    'purchase_return_balance',
    'sales_return_balance',
  ];

  /// Read-only — returns the count of duplicate rows that
  /// [mergeDuplicateReturnMemos] would delete. 0 = clean state.
  Future<int> dryRunDuplicateReturnMemos() async {
    final placeholders = List.filled(_categories.length, '?').join(',');
    final vars = _categories.map((c) => Variable.withString(c)).toList();
    final rows = await customSelect(
      'SELECT COUNT(*) - COUNT(DISTINCT '
      "reference_type || '|' || reference_id || '|' || party_id"
      ') AS extras '
      'FROM safe_transactions '
      "WHERE transaction_type = 'memo' "
      "AND category IN ($placeholders) "
      'AND reference_type IS NOT NULL '
      'AND reference_id IS NOT NULL '
      'AND party_id IS NOT NULL '
      'AND deleted_at IS NULL',
      variables: vars,
    ).get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['extras'] as int?) ?? 0;
  }

  /// Destructive — collapses each duplicate group to a single survivor
  /// per `(referenceType, referenceId, partyId)` and deletes the rest.
  /// Wrapped in a transaction so a partial failure rolls back. Returns
  /// the count of rows deleted. Idempotent: a second call returns 0.
  Future<int> mergeDuplicateReturnMemos() async {
    final extras = await dryRunDuplicateReturnMemos();
    if (extras == 0) return 0;

    final placeholders = List.filled(_categories.length, '?').join(',');
    // Pull every candidate row sorted so we can fold over the groups in
    // memory: cheap because return memos are a tiny fraction of the
    // safe_transactions table.
    final all = await customSelect(
      'SELECT id, reference_type, reference_id, party_id, voucher_number '
      'FROM safe_transactions '
      "WHERE transaction_type = 'memo' "
      "AND category IN ($placeholders) "
      'AND reference_type IS NOT NULL '
      'AND reference_id IS NOT NULL '
      'AND party_id IS NOT NULL '
      'AND deleted_at IS NULL '
      'ORDER BY reference_type, reference_id, party_id, id',
      variables: _categories.map((c) => Variable.withString(c)).toList(),
    ).get();

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in all) {
      final key =
          '${r.data['reference_type']}|${r.data['reference_id']}|${r.data['party_id']}';
      (groups[key] ??= []).add(Map<String, dynamic>.from(r.data));
    }

    var deleted = 0;
    final affectedSafeIds = <int>{};
    await transaction(() async {
      for (final entry in groups.entries) {
        final rows = entry.value;
        if (rows.length < 2) continue;
        // Prefer a non-LOC voucher (server-blessed); fall back to the
        // smallest id (already first by ORDER BY id above).
        Map<String, dynamic>? survivor;
        for (final r in rows) {
          final v = r['voucher_number'] as String? ?? '';
          if (!v.startsWith('PRET-LOC-') && !v.startsWith('SRET-LOC-')) {
            survivor = r;
            break;
          }
        }
        survivor ??= rows.first;
        for (final r in rows) {
          if (identical(r, survivor)) continue;
          final id = r['id'] as int;
          // Capture the safe before deletion so we can recalc its
          // balance (the deleted row had been mistakenly contributing).
          final safeRow = await customSelect(
            'SELECT safe_id FROM safe_transactions WHERE id = ?',
            variables: [Variable.withInt(id)],
          ).get();
          if (safeRow.isNotEmpty) {
            final s = safeRow.first.data['safe_id'] as int?;
            if (s != null) affectedSafeIds.add(s);
          }
          await customStatement(
            'DELETE FROM safe_transactions WHERE id = ?',
            [Variable.withInt(id).value],
          );
          deleted++;
          debugPrint('[RETURN-MEMO-DEDUP] deleted memo id=$id '
              '(survivor=${survivor['id']} key=${entry.key})');
        }
      }
    });
    debugPrint('[RETURN-MEMO-DEDUP] deleted $deleted duplicate memo rows total');
    return deleted;
  }
}
