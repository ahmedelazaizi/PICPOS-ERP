// =======================================================================
// AUTOPOST REPAIR DAO
// PIR Phase 1.2: Detect and re-post orphaned invoices (missing JE)
// =======================================================================

part of '../database.dart';

/// Extension for detecting and repairing orphaned auto-posts.
///
/// An "orphan" is an invoice that exists but has no matching journal entry.
/// This can happen if:
/// - The autoPost silently failed (non-blocking try/catch)
/// - A DB migration reset JE links
/// - Manual deletion of JEs
extension AutoPostRepairDao on AppDatabase {

  /// Find sales invoices without a matching auto-posted journal entry.
  /// Returns a list of orphaned invoice IDs + numbers.
  Future<List<Map<String, dynamic>>> findOrphanedSalesInvoices() async {
    final results = await customSelect(
      '''SELECT s.id, s.invoice_number, s.total, s.payment_method, s.created_at
         FROM sales_invoices s
         WHERE s.status != 'voided'
         AND NOT EXISTS (
           SELECT 1 FROM journal_entries j
           WHERE (j.reference_type = 'sale' OR j.reference_type = 'sales_invoice')
           AND j.reference_id = s.id
           AND j.is_auto_posted = 1
         )
         ORDER BY s.created_at DESC
         LIMIT 100''',
      readsFrom: {salesInvoices, journalEntries},
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Find purchase invoices without a matching auto-posted journal entry.
  Future<List<Map<String, dynamic>>> findOrphanedPurchaseInvoices() async {
    final results = await customSelect(
      '''SELECT p.id, p.invoice_number, p.total, p.created_at
         FROM purchase_invoices p
         WHERE p.status != 'voided'
         AND NOT EXISTS (
           SELECT 1 FROM journal_entries j
           WHERE (j.reference_type = 'purchase' OR j.reference_type = 'purchase_invoice')
           AND j.reference_id = p.id
           AND j.is_auto_posted = 1
         )
         ORDER BY p.created_at DESC
         LIMIT 100''',
      readsFrom: {purchaseInvoices, journalEntries},
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Attempt to re-post all orphaned sales invoices.
  /// Returns the number of successfully re-posted invoices.
  Future<int> repostOrphanedSalesInvoices() async {
    final orphans = await findOrphanedSalesInvoices();
    int reposted = 0;

    for (final orphan in orphans) {
      try {
        final invoiceId = orphan['id'] as int;
        final invoice = await (select(salesInvoices)
              ..where((s) => s.id.equals(invoiceId)))
            .getSingleOrNull();
        if (invoice == null) continue;

        // Determine: cash sale (fully paid) vs credit sale (has remaining balance)
        // This covers all 3 sources: POS main, Sales Invoices, Table Service POS
        // all of which may use cash/bank/click payment methods.
        final hasRemaining = (invoice.total - invoice.paid) > 0.01;
        if (!hasRemaining) {
          await autoPostCashSale(invoice);
        } else {
          await autoPostCreditSale(invoice);
        }
        reposted++;
      } catch (e) {
        debugPrint('[AutoPostRepair] Failed to repost sale #${orphan['id']}: $e');
      }
    }

    return reposted;
  }

  /// Attempt to re-post all orphaned purchase invoices.
  /// Returns the number of successfully re-posted invoices.
  Future<int> repostOrphanedPurchaseInvoices() async {
    final orphans = await findOrphanedPurchaseInvoices();
    int reposted = 0;

    for (final orphan in orphans) {
      try {
        final invoiceId = orphan['id'] as int;
        final invoice = await getPurchaseInvoiceById(invoiceId);
        if (invoice == null) continue;

        await autoPostPurchase(invoice);
        reposted++;
      } catch (e) {
        debugPrint('[AutoPostRepair] Failed to repost purchase #${orphan['id']}: $e');
      }
    }

    return reposted;
  }

  /// EXP-1: find operational expenses without a matching auto-posted journal
  /// entry. Orphans left behind by the pre-fix `autoPostOperationalExpense`
  /// silent-null path (unresolved/legacy '5299' GL account on the category) —
  /// that path now throws instead of silently dropping the JE going forward,
  /// but rows already committed before the fix landed still need this scan.
  Future<List<Map<String, dynamic>>> findOrphanedOpExpenses() async {
    final results = await customSelect(
      '''SELECT e.id, e.amount, e.expense_date, e.notes, e.category_id,
                e.cost_center_id, e.branch_id, e.payment_method,
                c.name AS category_name, c.account_code
         FROM op_expenses e
         JOIN op_expense_categories c ON c.id = e.category_id
         WHERE NOT EXISTS (
           SELECT 1 FROM journal_entries j
           WHERE j.reference_type = 'op_expense'
           AND j.reference_id = e.id
           AND j.is_auto_posted = 1
         )
         ORDER BY e.expense_date DESC
         LIMIT 100''',
      readsFrom: {opExpenses, opExpenseCategories, journalEntries},
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// EXP-1: attempt to re-post all orphaned operational expenses.
  /// Returns the number of successfully re-posted expenses. A per-row
  /// try/catch keeps one still-unresolvable account (e.g. category deleted)
  /// from blocking the rest of the batch.
  Future<int> repostOrphanedOpExpenses() async {
    final orphans = await findOrphanedOpExpenses();
    int reposted = 0;

    for (final orphan in orphans) {
      try {
        final expenseId = orphan['id'] as int;
        final amount = (orphan['amount'] as num).toDouble();
        final categoryName = orphan['category_name'] as String? ?? '';
        final notes = orphan['notes'] as String?;
        final accountCode = orphan['account_code'] as String? ?? '6214';
        final costCenterId = orphan['cost_center_id'] as int?;
        final branchId = orphan['branch_id'] as int?;
        final paymentMethod = orphan['payment_method'] as String?;
        final expenseDateRaw = orphan['expense_date'];
        final expenseDate = expenseDateRaw is DateTime ? expenseDateRaw : DateTime.now();

        final posted = await autoPostOperationalExpense(
          expenseId: expenseId,
          amount: amount,
          description: (notes != null && notes.isNotEmpty) ? '$categoryName — $notes' : categoryName,
          expenseAccountCode: accountCode,
          costCenterId: costCenterId,
          branchId: branchId,
          date: expenseDate,
          paymentMethod: paymentMethod,
        );
        if (posted != null) reposted++;
      } catch (e) {
        debugPrint('[AutoPostRepair] Failed to repost op_expense #${orphan['id']}: $e');
      }
    }

    return reposted;
  }

  /// Run full AutoPost repair scan and fix.
  /// Returns a summary map with counts.
  Future<Map<String, int>> runAutoPostRepair() async {
    final salesOrphans = await findOrphanedSalesInvoices();
    final purchaseOrphans = await findOrphanedPurchaseInvoices();
    final opExpenseOrphans = await findOrphanedOpExpenses();

    final salesFixed = await repostOrphanedSalesInvoices();
    final purchasesFixed = await repostOrphanedPurchaseInvoices();
    final opExpensesFixed = await repostOrphanedOpExpenses();

    debugPrint('[AutoPostRepair] Sales: ${salesOrphans.length} orphans, $salesFixed fixed');
    debugPrint('[AutoPostRepair] Purchases: ${purchaseOrphans.length} orphans, $purchasesFixed fixed');
    debugPrint('[AutoPostRepair] OpExpenses: ${opExpenseOrphans.length} orphans, $opExpensesFixed fixed');

    return {
      'sales_orphans': salesOrphans.length,
      'sales_fixed': salesFixed,
      'purchase_orphans': purchaseOrphans.length,
      'purchase_fixed': purchasesFixed,
      'op_expense_orphans': opExpenseOrphans.length,
      'op_expense_fixed': opExpensesFixed,
    };
  }
}
