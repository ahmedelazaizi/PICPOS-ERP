// =======================================================================
// ACCOUNTING AUDIT DAO
// Extracted from accounting_dao.dart — PIR Phase 2 God File Splitting
// Fraud monitoring, AR/AP aging, closing checklists, branch isolation
// =======================================================================

part of '../database.dart';

/// Extension for Accounting Audit, Fraud, and Compliance operations
extension AccountingAuditDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // Manufacturing JE lives inline in manufacturing_dao.dart (start→'manufacturing_order',
  // complete→'manufacturing_complete', overhead, reverse). The former autoPostManufacturing
  // Start/Complete helpers here were dead (0 callers) and 'manufacturing_complete' collided
  // with the live completion JE dedup key — removed in spec 149 B14 (S-DEDUP).
  // ─────────────────────────────────────────────────────────────────────────

  // RPT-009 (audit B): scanFraudAlerts / getReceivablesAging / getPayablesAging /
  // validatePeriodClosing were removed — zero callers and they read non-existent
  // columns (paid_amount, payment_status) with wrong epoch units. Use
  // getAgedReceivables/getAgedPayables and the period-close checks instead.

  // ─────────────────────────────────────────────────────────────────────────
  // F-21: BRANCH FINANCIAL ISOLATION — عزل مالي للفروع
  // ─────────────────────────────────────────────────────────────────────────

  /// Validate that all JE lines have cost center when required
  Future<List<Map<String, dynamic>>> findJournalLinesWithoutCostCenter({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    String dateFilter = '';
    final vars = <Variable>[];
    if (fromDate != null && toDate != null) {
      dateFilter = 'AND e.entry_date BETWEEN ? AND ?';
      vars.addAll([Variable(fromDate), Variable(toDate)]);
    }

    final results = await customSelect(
      '''SELECT e.id as entry_id, e.entry_number, l.id as line_id, a.code, a.name as account_name, l.debit, l.credit
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         JOIN accounts a ON l.account_id = a.id
         WHERE l.cost_center_id IS NULL
         AND a.account_type IN ('revenue', 'expense')
         $dateFilter
         ORDER BY e.entry_date DESC
         LIMIT 100''',
      variables: vars,
    ).get();
    return results.map((r) => r.data).toList();
  }
}
