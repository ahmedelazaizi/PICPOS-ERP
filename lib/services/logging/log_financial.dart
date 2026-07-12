part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FINANCIAL — Treasury, Journal Entries, Fiscal Year, Reconciliation
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerFinancial on ActivityLogger {
  Future<void> logSafeAdjustment(int userId, String userName, String safeName, double oldBal, double newBal) {
    return log(userId: userId, userName: userName, action: 'safe_adjustment', entityType: 'safe',
        description: 'تعديل يدوي لرصيد الخزينة $safeName', oldValue: oldBal.toString(),
        newValue: newBal.toString(), amount: newBal - oldBal);
  }

  Future<void> logJournalEntry(int userId, String userName, int entryId, double totalDebit, String description_) {
    return log(userId: userId, userName: userName, action: 'journal_entry_create', entityType: 'journal_entry',
        entityId: entryId, description: 'إنشاء قيد محاسبي: $description_', amount: totalDebit);
  }

  Future<void> logFiscalYearClose(int userId, String userName, String fiscalYearName, int fiscalYearId) {
    return log(userId: userId, userName: userName, action: 'fiscal_year_close', entityType: 'fiscal_year',
        entityId: fiscalYearId, description: 'إقفال سنة مالية: $fiscalYearName');
  }

  Future<void> logReceiptVoucher(int userId, String userName, double amount, String safeName,
      {String? partyName, int? transactionId}) {
    // PII redaction (2026-05-12): party name dropped from description.
    // Safe name kept — it's the merchant's own asset, not customer PII.
    return log(userId: userId, userName: userName, action: 'receipt_voucher', entityType: 'safe_transaction',
        entityId: transactionId,
        description: 'سند قبض في $safeName', amount: amount);
  }

  Future<void> logPaymentVoucher(int userId, String userName, double amount, String safeName,
      {String? partyName, int? transactionId}) {
    // PII redaction (2026-05-12): party name dropped from description.
    return log(userId: userId, userName: userName, action: 'payment_voucher', entityType: 'safe_transaction',
        entityId: transactionId,
        description: 'سند صرف من $safeName', amount: amount);
  }

  Future<void> logReconciliation(int userId, String userName, String entityType_, int discrepanciesFound, int fixed) {
    return log(userId: userId, userName: userName, action: 'reconciliation', entityType: entityType_,
        description: 'تسوية أرصدة $entityType_: تم اكتشاف $discrepanciesFound فرق، تم إصلاح $fixed');
  }

  Future<void> logDailyClosing(int userId, String userName, String safeName, {double? closingBalance}) {
    return log(userId: userId, userName: userName, action: 'daily_closing', entityType: 'safe',
        description: 'إقفال يومي لخزينة: $safeName', amount: closingBalance);
  }
}
