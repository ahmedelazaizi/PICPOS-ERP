// Spec 133 — Cheque Receipt Voucher: Single Customer Credit (FR-011 audit).
//
// Read-only diagnostic that lists customers whose `parties.balance` was
// over-credited by the double-credit bug observed on build 3.1.0+202 and
// any prior build that shared the asymmetry between the receipt-voucher
// path and the commercial-papers autopost.
//
// Signature detected: for every received-cheque commercial paper still
// in `pending` status, there is (usually) a corresponding receipt-voucher
// row in `safe_transactions` for the same party + amount + day. Counting
// those matches per party gives the drift population directly. We do NOT
// recompute balances from journal entries — false positives from other
// historical drift sources (Spec 081's deferred supplier-balance drift,
// etc.) would muddy the count.
//
// Repair is intentionally out of scope (deferred to a follow-on spec).
// Audit MUST NOT modify data.
//
// Surface (FR-011): startup log line + admin maintenance screen entry.
//   - `[CHEQUE-RECEIPT-DRIFT] affectedCustomers=N totalOverCredit=M.MM`
//   - `ChequeReceiptDriftAdminDialog` in settings > أدوات صيانة المسؤول
//
// Gate: server mode only. Standalone installs never ran in client/server
// mode (no pull-induced amplification), and client/mirror installs sync
// from the server's authoritative state — so the server is the canonical
// place to audit. Repeating the audit on every mirror would over-count.

import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';

class ChequeReceiptDriftRecord {
  final int partyId;
  final String partyName;
  final int chequeCount;
  final double overCreditTotal;

  const ChequeReceiptDriftRecord({
    required this.partyId,
    required this.partyName,
    required this.chequeCount,
    required this.overCreditTotal,
  });
}

class ChequeReceiptDriftAuditService {
  ChequeReceiptDriftAuditService(this._db);

  final AppDatabase _db;

  /// Spec 138 FR-012 — exclude any party that already carries a non-deleted
  /// `cheque_drift_repair` correction JE (i.e. already healed). This makes the
  /// audit mean "un-repaired drift", so a re-run after a heal reports 0 for the
  /// healed population WITHOUT mutating `commercial_papers` / `safe_transactions`
  /// (FR-013 stays intact). `reference_id` is the healed party id — see
  /// `ChequeReceiptDriftRepairService.repair()`.
  String get _notAlreadyRepaired => '''
        AND NOT EXISTS (
          SELECT 1
          FROM journal_entries je
          WHERE je.reference_type = 'cheque_drift_repair'
            AND je.reference_id = cp.party_id
            AND je.is_deleted = ${_db.sqlBool(false)}
        )''';

  /// Per-customer breakdown of the drift. Ordered by `overCreditTotal`
  /// descending — biggest impact first.
  Future<List<ChequeReceiptDriftRecord>> getBreakdown() async {
    // Raw SQL is the clearest path here — the join condition is a custom
    // EXISTS predicate on safe_transactions (the receipt-voucher row whose
    // description carries the cheque number) keyed off the commercial-papers
    // row. Drift's join helpers would obscure the predicate.
    final rows = await _db.customSelect(
      '''
      SELECT
        p.id        AS party_id,
        p.name      AS party_name,
        COUNT(cp.id) AS cheque_count,
        COALESCE(SUM(cp.amount), 0.0) AS over_credit_total
      FROM commercial_papers cp
      INNER JOIN parties p ON p.id = cp.party_id
      WHERE cp.direction = 'received'
        AND cp.type = 'cheque'
        AND cp.status = 'pending'
        AND EXISTS (
          SELECT 1
          FROM safe_transactions st
          WHERE st.party_id = cp.party_id
            AND st.transaction_type = 'receipt'
            AND st.description LIKE '%' || cp.paper_number || '%'
            -- Spec 138 R3 — tighten the drift signature: a short cheque number
            -- could substring-match an unrelated receipt, and this is now a
            -- money write. The receipt voucher stores the NET total across ALL
            -- its cheques in ONE safe_transactions row (amount = Σ per-cheque
            -- split), so `>=` (not `=`) is required — exact equality would drop
            -- every genuine multi-cheque voucher's rows, while `>=` still
            -- filters receipts smaller than the cheque (the common false match).
            AND st.amount >= cp.amount
            AND st.deleted_at IS NULL
        )$_notAlreadyRepaired
      GROUP BY p.id, p.name
      HAVING COUNT(cp.id) > 0
      ORDER BY over_credit_total DESC
      ''',
      readsFrom: {
        _db.commercialPapers,
        _db.parties,
        _db.safeTransactions,
        _db.journalEntries,
      },
    ).get();

    return rows
        .map((r) => ChequeReceiptDriftRecord(
              partyId: r.read<int>('party_id'),
              partyName: r.read<String>('party_name'),
              chequeCount: r.read<int>('cheque_count'),
              overCreditTotal: r.read<double>('over_credit_total'),
            ))
        .toList(growable: false);
  }

  /// Count of distinct customers affected by the drift.
  Future<int> getAffectedCustomerCount() async {
    final rows = await _db.customSelect(
      '''
      SELECT COUNT(DISTINCT cp.party_id) AS n
      FROM commercial_papers cp
      WHERE cp.direction = 'received'
        AND cp.type = 'cheque'
        AND cp.status = 'pending'
        AND EXISTS (
          SELECT 1
          FROM safe_transactions st
          WHERE st.party_id = cp.party_id
            AND st.transaction_type = 'receipt'
            AND st.description LIKE '%' || cp.paper_number || '%'
            -- Spec 138 R3 — tighten the drift signature: a short cheque number
            -- could substring-match an unrelated receipt, and this is now a
            -- money write. The receipt voucher stores the NET total across ALL
            -- its cheques in ONE safe_transactions row (amount = Σ per-cheque
            -- split), so `>=` (not `=`) is required — exact equality would drop
            -- every genuine multi-cheque voucher's rows, while `>=` still
            -- filters receipts smaller than the cheque (the common false match).
            AND st.amount >= cp.amount
            AND st.deleted_at IS NULL
        )$_notAlreadyRepaired
      ''',
      readsFrom: {
        _db.commercialPapers,
        _db.safeTransactions,
        _db.journalEntries,
      },
    ).getSingle();
    return rows.read<int>('n');
  }

  /// Total over-credit amount (in project currency, no symbol).
  Future<double> getTotalOverCredit() async {
    final rows = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(cp.amount), 0.0) AS total
      FROM commercial_papers cp
      WHERE cp.direction = 'received'
        AND cp.type = 'cheque'
        AND cp.status = 'pending'
        AND EXISTS (
          SELECT 1
          FROM safe_transactions st
          WHERE st.party_id = cp.party_id
            AND st.transaction_type = 'receipt'
            AND st.description LIKE '%' || cp.paper_number || '%'
            -- Spec 138 R3 — tighten the drift signature: a short cheque number
            -- could substring-match an unrelated receipt, and this is now a
            -- money write. The receipt voucher stores the NET total across ALL
            -- its cheques in ONE safe_transactions row (amount = Σ per-cheque
            -- split), so `>=` (not `=`) is required — exact equality would drop
            -- every genuine multi-cheque voucher's rows, while `>=` still
            -- filters receipts smaller than the cheque (the common false match).
            AND st.amount >= cp.amount
            AND st.deleted_at IS NULL
        )$_notAlreadyRepaired
      ''',
      readsFrom: {
        _db.commercialPapers,
        _db.safeTransactions,
        _db.journalEntries,
      },
    ).getSingle();
    return rows.read<double>('total');
  }

  /// Server-mode boot hook. Suppressed when count == 0 (clean install
  /// or already-repaired install — no need to spam the log on every
  /// startup once the deferred repair spec ships).
  Future<void> emitStartupSignal() async {
    try {
      final count = await getAffectedCustomerCount();
      if (count == 0) return;
      final total = await getTotalOverCredit();
      await DiagnosticLogger.log(
        'CHEQUE-RECEIPT-DRIFT',
        'affectedCustomers=$count totalOverCredit=${total.toStringAsFixed(2)}',
      );
    } catch (e) {
      // Audit must never block boot — silent skip on any error.
      // (The same query runs from the admin dialog with proper error
      // surfacing for operator triage.)
      await DiagnosticLogger.log(
        'CHEQUE-RECEIPT-DRIFT',
        'audit-failed-at-boot: $e',
      );
    }
  }
}

