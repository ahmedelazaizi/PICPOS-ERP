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

  // ─────────────────────────────────────────────────────────────────────────
  // F-18: FRAUD MONITORING — تنبيهات مراقبة الاحتيال
  // ─────────────────────────────────────────────────────────────────────────

  /// Scan for suspicious transactions and return alert list
  Future<List<Map<String, dynamic>>> scanFraudAlerts({
    required DateTime fromDate,
    required DateTime toDate,
    double returnThreshold = 500,
    double discountThreshold = 30,
    double manualJeThreshold = 1000,
  }) async {
    final alerts = <Map<String, dynamic>>[];

    // 1. Large returns exceeding threshold
    final largeReturns = await customSelect(
      '''SELECT s.id, s.invoice_number, s.total, s.created_at
         FROM sales_invoices s
         WHERE s.total > ? AND s.sale_type = 'return'
         AND s.created_at BETWEEN ? AND ?''',
      variables: [Variable(returnThreshold), Variable(fromDate), Variable(toDate)],
    ).get();
    for (final r in largeReturns) {
      alerts.add({
        'type': 'large_return',
        'severity': 'high',
        'message': 'مرتجع كبير: فاتورة #${r.data['invoice_number']} — ${r.data['total']}',
        'entityId': r.data['id'],
        'amount': r.data['total'],
      });
    }

    // 2. Excessive discounts (above threshold %)
    final excessiveDiscounts = await customSelect(
      '''SELECT s.id, s.invoice_number, s.subtotal, s.discount, s.total,
              CASE WHEN s.subtotal > 0 THEN (s.discount * 100.0 / s.subtotal) ELSE 0 END as pct
         FROM sales_invoices s
         WHERE s.subtotal > 0 AND (s.discount * 100.0 / s.subtotal) > ?
         AND s.created_at BETWEEN ? AND ?''',
      variables: [Variable(discountThreshold), Variable(fromDate), Variable(toDate)],
    ).get();
    for (final d in excessiveDiscounts) {
      alerts.add({
        'type': 'excessive_discount',
        'severity': 'medium',
        'message': 'خصم مفرط: فاتورة #${d.data['invoice_number']} — ${(d.data['pct'] as num).toStringAsFixed(1)}%',
        'entityId': d.data['id'],
        'amount': d.data['discount'],
      });
    }

    // 3. Large manual journal entries
    final largeManualJes = await customSelect(
      '''SELECT e.id, e.entry_number, e.description, SUM(l.debit) as total_debit
         FROM journal_entries e
         JOIN journal_entry_lines l ON l.entry_id = e.id
         WHERE e.is_auto_posted = ${sqlBool(false)} AND e.entry_date BETWEEN ? AND ?
         GROUP BY e.id, e.entry_number, e.description
         HAVING SUM(l.debit) > ?''',
      variables: [Variable(fromDate), Variable(toDate), Variable(manualJeThreshold)],
    ).get();
    for (final j in largeManualJes) {
      alerts.add({
        'type': 'large_manual_je',
        'severity': 'medium',
        'message': 'قيد يدوي كبير: #${j.data['entry_number']} — ${j.data['total_debit']}',
        'entityId': j.data['id'],
        'amount': j.data['total_debit'],
      });
    }

    // 4. After-hours sales (before 6 AM or after midnight)
    final afterHoursSales = await customSelect(
      '''SELECT s.id, s.invoice_number, s.total, s.created_at
         FROM sales_invoices s
         WHERE (CAST(strftime('%H', s.created_at / 1000, 'unixepoch', 'localtime') AS INTEGER) < 6)
         AND s.created_at BETWEEN ? AND ?''',
      variables: [Variable(fromDate), Variable(toDate)],
    ).get();
    for (final s in afterHoursSales) {
      alerts.add({
        'type': 'after_hours_sale',
        'severity': 'low',
        'message': 'بيع في وقت غير اعتيادي: فاتورة #${s.data['invoice_number']}',
        'entityId': s.data['id'],
        'amount': s.data['total'],
      });
    }

    return alerts;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // F-19: AR/AP AGING — أعمار الديون
  // ─────────────────────────────────────────────────────────────────────────

  /// Get aged receivables (customer debts) in buckets: current, 30, 60, 90+
  Future<List<Map<String, dynamic>>> getReceivablesAging() async {
    final results = await customSelect(
      '''SELECT p.id, p.name,
              SUM(CASE WHEN (julianday('now') - julianday(s.created_at / 1000, 'unixepoch')) <= 30 THEN s.total - COALESCE(s.paid_amount, 0) ELSE 0 END) as current_amount,
              SUM(CASE WHEN (julianday('now') - julianday(s.created_at / 1000, 'unixepoch')) BETWEEN 31 AND 60 THEN s.total - COALESCE(s.paid_amount, 0) ELSE 0 END) as days_30,
              SUM(CASE WHEN (julianday('now') - julianday(s.created_at / 1000, 'unixepoch')) BETWEEN 61 AND 90 THEN s.total - COALESCE(s.paid_amount, 0) ELSE 0 END) as days_60,
              SUM(CASE WHEN (julianday('now') - julianday(s.created_at / 1000, 'unixepoch')) > 90 THEN s.total - COALESCE(s.paid_amount, 0) ELSE 0 END) as days_90_plus,
              SUM(s.total - COALESCE(s.paid_amount, 0)) as total_outstanding
         FROM sales_invoices s
         JOIN parties p ON s.customer_id = p.id
         WHERE s.payment_status != 'paid' AND s.customer_id IS NOT NULL
         GROUP BY p.id, p.name
         HAVING SUM(s.total - COALESCE(s.paid_amount, 0)) > 0.01
         ORDER BY total_outstanding DESC''',
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Get aged payables (supplier debts)
  Future<List<Map<String, dynamic>>> getPayablesAging() async {
    final results = await customSelect(
      '''SELECT p.id, p.name,
              SUM(CASE WHEN (julianday('now') - julianday(pi.created_at / 1000, 'unixepoch')) <= 30 THEN pi.total - COALESCE(pi.paid_amount, 0) ELSE 0 END) as current_amount,
              SUM(CASE WHEN (julianday('now') - julianday(pi.created_at / 1000, 'unixepoch')) BETWEEN 31 AND 60 THEN pi.total - COALESCE(pi.paid_amount, 0) ELSE 0 END) as days_30,
              SUM(CASE WHEN (julianday('now') - julianday(pi.created_at / 1000, 'unixepoch')) BETWEEN 61 AND 90 THEN pi.total - COALESCE(pi.paid_amount, 0) ELSE 0 END) as days_60,
              SUM(CASE WHEN (julianday('now') - julianday(pi.created_at / 1000, 'unixepoch')) > 90 THEN pi.total - COALESCE(pi.paid_amount, 0) ELSE 0 END) as days_90_plus,
              SUM(pi.total - COALESCE(pi.paid_amount, 0)) as total_outstanding
         FROM purchase_invoices pi
         JOIN parties p ON pi.supplier_id = p.id
         WHERE pi.payment_status != 'paid' AND pi.supplier_id IS NOT NULL
         GROUP BY p.id, p.name
         HAVING SUM(pi.total - COALESCE(pi.paid_amount, 0)) > 0.01
         ORDER BY total_outstanding DESC''',
    ).get();
    return results.map((r) => r.data).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // F-20: CLOSING CHECKLIST — قائمة مراجعة الإقفال
  // ─────────────────────────────────────────────────────────────────────────

  /// Validate all pre-conditions before allowing period close
  Future<Map<String, dynamic>> validatePeriodClosing(DateTime periodStart, DateTime periodEnd) async {
    final checks = <String, dynamic>{};

    // 1. Pending invoices (not posted)
    final pendingInvoices = await customSelect(
      "SELECT COUNT(*) as cnt FROM sales_invoices WHERE created_at BETWEEN ? AND ? AND payment_status = 'pending'",
      variables: [Variable(periodStart), Variable(periodEnd)],
    ).getSingle();
    checks['pending_invoices'] = pendingInvoices.data['cnt'] as int? ?? 0;

    // 2. Unsettled VAT
    final vatData = await getVatReconciliation(
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    checks['unsettled_vat'] = vatData['netVat']?.abs() ?? 0;

    // 3. Draft journal entries pending approval
    final draftJes = await customSelect(
      "SELECT COUNT(*) as cnt FROM journal_entries WHERE status = 'draft' AND entry_date BETWEEN ? AND ?",
      variables: [Variable(periodStart), Variable(periodEnd)],
    ).getSingle();
    checks['draft_journal_entries'] = draftJes.data['cnt'] as int? ?? 0;

    // 4. Open stock audits
    final openAudits = await customSelect(
      "SELECT COUNT(*) as cnt FROM stock_audits WHERE status != 'finalized' AND created_at BETWEEN ? AND ?",
      variables: [Variable(periodStart), Variable(periodEnd)],
    ).getSingle();
    checks['open_stock_audits'] = openAudits.data['cnt'] as int? ?? 0;

    // Overall readiness
    checks['can_close'] = (checks['pending_invoices'] == 0) &&
        (checks['draft_journal_entries'] == 0) &&
        (checks['open_stock_audits'] == 0);

    return checks;
  }

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
