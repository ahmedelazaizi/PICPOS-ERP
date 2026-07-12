import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/app_error.dart';
import '../data/database/database.dart';

/// Result returned by a single reconciliation run.
class ReconciliationResult {
  /// List of detected discrepancies.
  final List<ReconciliationError> errors;

  /// Number of accounts examined.
  final int accountsChecked;

  /// Number of accounts whose balance was auto-corrected (0 unless
  /// [BalanceReconciliationService.reconcile] was called with
  /// [autoCorrect] = true).
  final int accountsCorrected;

  const ReconciliationResult({
    required this.errors,
    required this.accountsChecked,
    required this.accountsCorrected,
  });

  bool get isClean => errors.isEmpty;
}

/// Service that verifies the integrity of `accounts.balance` against
/// the posted journal entry lines.
///
/// Per IAS 1 each account balance must equal:
///   SUM(debit) − SUM(credit) over all POSTED journal entry lines.
///
/// This service:
///  1. Loads all active detail accounts (accountNature = 'detail').
///  2. Computes the expected balance from posted journal entry lines in
///     a single batch SQL query.
///  3. Flags any account whose stored balance differs by more than
///     [tolerance] (default 0.01).
///  4. Optionally auto-corrects the discrepancies (autoCorrect = true).
///
/// Designed to run as a background job (e.g., nightly or after a
/// bulk import) — never called in the hot path.
class BalanceReconciliationService {
  final AppDatabase _db;

  BalanceReconciliationService(this._db);

  /// Run a reconciliation pass over all active detail accounts.
  ///
  /// [tolerance]   — maximum allowed difference before flagging (default 0.01).
  /// [autoCorrect] — if true, overwrites wrong balances with the computed value.
  ///
  /// Returns a [ReconciliationResult] with every detected mismatch.
  Future<ReconciliationResult> reconcile({
    double tolerance = 0.01,
    bool autoCorrect = false,
  }) async {
    // ── Step 1: fetch all active detail accounts ─────────────────────────────
    final detailAccounts = await (_db.select(_db.accounts)
          ..where(
            (a) =>
                a.accountNature.equals('detail') &
                a.isActive.equals(true) &
                a.deletedAt.isNull(),
          ))
        .get();

    if (detailAccounts.isEmpty) {
      return const ReconciliationResult(
        errors: [],
        accountsChecked: 0,
        accountsCorrected: 0,
      );
    }

    final accountIds = detailAccounts.map((a) => a.id).toList();

    // ── Step 2: batch-compute expected balances from posted JELs ─────────────
    // One query to get SUM(debit) - SUM(credit) per account, joined to
    // journal_entries filtered to is_posted = true.
    final placeholders = List.filled(accountIds.length, '?').join(', ');
    final rows = await _db.customSelect(
      'SELECT jl.account_id, '
      '       COALESCE(SUM(jl.debit),0)  AS total_debit, '
      '       COALESCE(SUM(jl.credit),0) AS total_credit '
      'FROM journal_entry_lines jl '
      'INNER JOIN journal_entries je ON je.id = jl.entry_id '
      'WHERE jl.account_id IN ($placeholders) '
      '  AND je.is_posted = 1 '
      'GROUP BY jl.account_id',
      variables: accountIds.map((id) => Variable.withInt(id)).toList(),
      readsFrom: {_db.journalEntryLines, _db.journalEntries},
    ).get();

    // Build map: accountId → computed balance
    final computed = <int, double>{};
    for (final row in rows) {
      final id = row.read<int>('account_id');
      final debit = (row.data['total_debit'] as num).toDouble();
      final credit = (row.data['total_credit'] as num).toDouble();
      computed[id] = debit - credit;
    }

    // ── Step 3: compare and collect errors ───────────────────────────────────
    final errors = <ReconciliationError>[];
    final toCorrect = <int, double>{};

    for (final account in detailAccounts) {
      final expected = computed[account.id] ?? 0.0;
      final diff = (account.balance - expected).abs();
      if (diff > tolerance) {
        errors.add(ReconciliationError(
          entityType: 'account',
          entityId: account.id,
          cachedValue: account.balance,
          calculatedValue: expected,
        ));
        if (autoCorrect) {
          toCorrect[account.id] = expected;
        }
      }
    }

    // ── Step 4: (optional) auto-correct discrepancies ────────────────────────
    var corrected = 0;
    if (autoCorrect && toCorrect.isNotEmpty) {
      await _db.batch((batch) {
        for (final entry in toCorrect.entries) {
          batch.update(
            _db.accounts,
            AccountsCompanion(balance: Value(entry.value)),
            where: (a) => a.id.equals(entry.key),
          );
        }
      });
      corrected = toCorrect.length;
      debugPrint(
        '[BalanceReconciliation] Auto-corrected $corrected account balance(s).',
      );
    }

    if (errors.isNotEmpty) {
      debugPrint(
        '[BalanceReconciliation] Found ${errors.length} discrepancy(ies) '
        'across ${detailAccounts.length} accounts '
        '(autoCorrect=$autoCorrect).',
      );
    }

    return ReconciliationResult(
      errors: errors,
      accountsChecked: detailAccounts.length,
      accountsCorrected: corrected,
    );
  }
}
