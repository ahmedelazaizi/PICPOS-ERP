// ═══════════════════════════════════════════════════════════════════════════
// F-01: Closing Entry Service — Year-End Automated Close
// Generates the closing journal entry to zero out revenue/expense accounts
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers/providers.dart';
import '../domain/repositories/accounting_repository.dart';

/// Generates the year-end closing entry.
///
/// Workflow:
/// 1. Fetch trial balance to get all account balances.
/// 2. Identify revenue (4xxx) and expense (5xxx, 6xxx) accounts.
/// 3. Create a journal entry that zeros them out.
/// 4. Post net difference to Retained Earnings (3201).
class ClosingEntryService {
  final IAccountingRepository _repo;

  ClosingEntryService(this._repo);

  /// Compute preview of closing entry without posting.
  Future<ClosingEntryPreview> preview({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final accounts = await _repo.getTrialBalance(periodStart, periodEnd);

    double totalRevenue = 0;
    double totalExpenses = 0;
    final revenueLines = <ClosingLine>[];
    final expenseLines = <ClosingLine>[];

    for (final a in accounts) {
      // Skip totals row
      if (a['id'] == -1) continue;
      final code = a['code']?.toString() ?? '';
      final name = a['name']?.toString() ?? '';
      final type = a['type']?.toString() ?? '';
      // closingDebit/closingCredit are the net position split into debit/credit display
      final closingDebit = (a['closingDebit'] as num?)?.toDouble() ?? 0;
      final closingCredit = (a['closingCredit'] as num?)?.toDouble() ?? 0;
      // Net balance: positive = debit-heavy (expense), negative = credit-heavy (revenue)
      final netBalance = closingDebit - closingCredit;
      if (netBalance.abs() < 0.01) continue;

      // C-04: Use account type field for precise classification
      if (type == 'revenue') {
        // Revenue accounts normally have credit balance (netBalance < 0)
        final revenueAmount = closingCredit - closingDebit; // positive when credit > debit
        if (revenueAmount.abs() < 0.01) continue;
        totalRevenue += revenueAmount;
        revenueLines.add(ClosingLine(
          accountCode: code,
          accountName: name,
          amount: revenueAmount,
        ));
      } else if (type == 'contra_revenue') {
        // C-04: Contra-revenue (Sales Returns 4201, Sales Discounts 4202)
        // These have DEBIT balances — reduce total revenue
        final contraAmount = closingDebit - closingCredit; // positive when debit > credit
        if (contraAmount.abs() < 0.01) continue;
        totalRevenue -= contraAmount; // Deducted from revenue
        revenueLines.add(ClosingLine(
          accountCode: code,
          accountName: name,
          amount: contraAmount, // Stored as positive — execute() will CREDIT to zero out
        ));
      } else if (type == 'expense') {
        // Expense accounts normally have debit balance (netBalance > 0)
        final expenseAmount = closingDebit - closingCredit; // positive when debit > credit
        if (expenseAmount.abs() < 0.01) continue;
        totalExpenses += expenseAmount;
        expenseLines.add(ClosingLine(
          accountCode: code,
          accountName: name,
          amount: expenseAmount,
        ));
      }
    }

    return ClosingEntryPreview(
      periodStart: periodStart,
      periodEnd: periodEnd,
      revenueLines: revenueLines,
      expenseLines: expenseLines,
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netIncome: totalRevenue - totalExpenses,
    );
  }

  /// Execute the closing entry — creates the journal entry and closes the period.
  Future<void> execute({
    required ClosingEntryPreview preview,
  }) async {
    final lines = <JournalLine>[];

    // Debit all revenue accounts (zero them out)
    for (final r in preview.revenueLines) {
      final acct = await _repo.getAccountByCode(r.accountCode);
      if (acct == null) continue;
      lines.add(JournalLine(
        accountId: acct.id,
        description: 'إقفال إيرادات: ${r.accountName}',
        debit: r.amount,
        credit: 0,
      ));
    }

    // Credit all expense accounts (zero them out)
    for (final e in preview.expenseLines) {
      final acct = await _repo.getAccountByCode(e.accountCode);
      if (acct == null) continue;
      lines.add(JournalLine(
        accountId: acct.id,
        description: 'إقفال مصروفات: ${e.accountName}',
        debit: 0,
        credit: e.amount,
      ));
    }

    // Post net difference to Retained Earnings (dynamic resolution).
    // Fallback code '313' matches the seeded chart of accounts
    // (الأرباح المبقاة) — see accountPurposes['retained_earnings'].
    final retainedEarnings = await _repo.getAccountByPurpose('retained_earnings')
        ?? await _repo.getAccountByCode('313');
    if (retainedEarnings != null && preview.netIncome.abs() > 0.01) {
      lines.add(JournalLine(
        accountId: retainedEarnings.id,
        description: preview.netIncome > 0
            ? 'صافي الربح → الأرباح المحتجزة'
            : 'صافي الخسارة → الأرباح المحتجزة',
        debit: preview.netIncome < 0 ? preview.netIncome.abs() : 0,
        credit: preview.netIncome > 0 ? preview.netIncome : 0,
      ));
    }

    if (lines.isNotEmpty) {
      await _repo.createJournalEntry(
        description: 'قيد الإقفال — ${preview.periodStart.year}',
        date: preview.periodEnd,
        lines: lines,
        referenceType: 'fiscal_close',
        isAutoPosted: true, // FIX: Must post to trial balance
      );
    }
  }
}

class ClosingEntryPreview {
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<ClosingLine> revenueLines;
  final List<ClosingLine> expenseLines;
  final double totalRevenue;
  final double totalExpenses;
  final double netIncome;

  const ClosingEntryPreview({
    required this.periodStart,
    required this.periodEnd,
    required this.revenueLines,
    required this.expenseLines,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netIncome,
  });
}

class ClosingLine {
  final String accountCode;
  final String accountName;
  final double amount;

  const ClosingLine({
    required this.accountCode,
    required this.accountName,
    required this.amount,
  });
}

/// Provider for ClosingEntryService
final closingEntryServiceProvider = Provider<ClosingEntryService>((ref) {
  final repo = ref.watch(accountingRepositoryProvider);
  return ClosingEntryService(repo);
});
