// Accounting auto-post: deferred revenue, delivery confirmation and startup repairs.
part of '../database.dart';

/// Accounting auto-post: deferred revenue, delivery confirmation and startup repairs. (split from accounting_autopost_dao.dart - pure move).
extension AccountingAutopostDeliveryRepairDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // GAP-22: Deferred Revenue Support
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a deferred revenue journal entry for undelivered sale orders.
  /// Called when deliveryStatus != 'delivered' to preserve double-entry balance.
  ///
  /// isCashSale=true:  Dr Cash/Bank/Click (paid) + Dr Receivables (unpaid) / Cr Deferred Revenue
  /// isCashSale=false: Dr Receivables (total) / Cr Deferred Revenue
  Future<int?> _autoPostDeferredRevenue(SalesInvoiceData sale, {required bool isCashSale}) async {
    if (sale.total <= 0) return null;
    // Dedup: use 'deferred_sale' referenceType so the normal sale dedup doesn't interfere
    if (await hasAutoPostEntry('deferred_sale', sale.id)) return null;

    final warehouse = await (select(warehouses)..where((w) => w.id.equals(sale.warehouseId))).getSingleOrNull();
    final branchId = warehouse?.branchId;

    final deferredAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('deferred_revenue', AccountingDao.accountPurposes['deferred_revenue']!),
    );
    if (deferredAccount == null) return null;

    final lines = <JournalLine>[];

    if (isCashSale) {
      // Debit: each payment channel that received money
      final cashAccount = await _resolveBranchSafeAccount(branchId, 'cash', 'cash');
      final bankAccount = await _resolveBranchSafeAccount(branchId, 'bank', 'bank');
      final clickAccount = await _resolveBranchSafeAccount(branchId, 'click', 'click');

      if (sale.cashPaid > 0 && cashAccount != null) {
        lines.add(JournalLine(accountId: cashAccount.id, debit: sale.cashPaid, description: 'نقدية مؤجلة'));
      }
      if (sale.bankPaid > 0 && bankAccount != null) {
        lines.add(JournalLine(accountId: bankAccount.id, debit: sale.bankPaid, description: 'بنك مؤجل'));
      }
      if (sale.clickPaid > 0 && clickAccount != null) {
        lines.add(JournalLine(accountId: clickAccount.id, debit: sale.clickPaid, description: 'إلكتروني مؤجل'));
      }
      // Any unpaid portion → receivables
      final unpaid = sale.total - sale.paid;
      if (unpaid > 0.01) {
        final arAccount = await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('receivables', AccountingDao.accountPurposes['receivables']!),
        );
        if (arAccount != null) {
          lines.add(JournalLine(accountId: arAccount.id, debit: unpaid, description: 'ذمم مؤجلة'));
        }
      }
    } else {
      // Credit sale: all goes to receivables
      final arAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('receivables', AccountingDao.accountPurposes['receivables']!),
      );
      if (arAccount != null) {
        lines.add(JournalLine(accountId: arAccount.id, debit: sale.total, description: 'ذمم مدينة مؤجلة'));
      }
    }

    if (lines.isEmpty) return null;

    // Credit: Deferred Revenue for the total invoice amount
    lines.add(JournalLine(accountId: deferredAccount.id, credit: sale.total, description: 'إيراد مؤجل — فاتورة #${sale.invoiceNumber}'));

    return accountingDao.createJournalEntry(
      description: 'إيراد مؤجل — فاتورة #${sale.invoiceNumber} (قبل التسليم)',
  // ignore: dead_code
      date: sale.invoiceDate ?? DateTime.now(),
      lines: lines,
      referenceType: 'deferred_sale',
      referenceId: sale.id,
      isAutoPosted: true,
      branchId: branchId,
    );
  }

  /// Called when delivery is confirmed (deliveryStatus → 'delivered').
  /// 1. Reverses the deferred revenue JE
  /// 2. Creates the proper sales revenue JE
  ///
  /// B7 (S-FAILLOUD / ACC-1): the deferred-revenue reversal and the revenue
  /// JE are two halves of ONE logical transition (deferred → recognized).
  /// They used to be posted via two INDEPENDENTLY-swallowed try/catches: if
  /// the reversal succeeded but the revenue JE then threw, the deferred
  /// revenue was reversed with NO replacement revenue JE (vanished
  /// revenue); if the reversal itself threw but was swallowed, execution
  /// still reached the revenue JE, which then posted on top of the
  /// still-live deferred JE (double revenue).
  ///
  /// NOT wrapped in a `db.transaction()` — [createJournalEntry] (called
  /// directly here, and again inside [autoPostCreditSale]/[autoPostCashSale]
  /// below) already opens its own transaction, and nesting `transaction()`
  /// around these specific calls has caused a confirmed production deadlock
  /// (SqliteException 517 "database is locked") twice in this codebase: see
  /// sales_mutations_dao.dart's `createSalesInvoice` Phase-8 comment and
  /// treasury_dao.dart's `closeShiftWithAudit` Step-2 comment. Re-nesting
  /// them here would trade one bug for a worse one.
  ///
  /// Instead this now removes ONLY the catch-and-swallow, which is enough to
  /// close both failure modes without a wrapping transaction:
  ///   - Double revenue is prevented structurally: the code is sequential —
  ///     if the reversal throws, the revenue JE call below is never reached.
  ///   - Vanished revenue self-heals on retry: [createJournalEntry]'s own
  ///     auto-post dedup guard makes the reversal call idempotent (a retry
  ///     that finds the reversal already posted returns the existing JE id
  ///     without re-inserting), so a caller that retries after a revenue-JE
  ///     failure re-enters here, skips the now-idempotent reversal, and
  ///     gets a fresh attempt at the revenue JE. The caller
  ///     (`updateSalesDeliveryStatus` in sales_mutations_dao.dart) treats any
  ///     exception here as "not yet posted" and relies on
  ///     `repairFailedDeliveryAutoposts` (GAP-P1-FIX-06, run at boot) to retry
  ///     exactly this way. Spec 151 F-05: that caller now posts this JE FIRST
  ///     and only flips `deliveryStatus` to 'delivered' AFTER it succeeds — so
  ///     the invoice can never show 'delivered' while its revenue is still
  ///     deferred (the old order wrote the status first and swallowed a JE
  ///     failure). `repairFailedDeliveryAutoposts` still heals any legacy
  ///     'delivered'-without-revenue rows.
  Future<void> autoPostDeliveryConfirmed(int invoiceId) async {
    final sale = await getSalesInvoiceById(invoiceId);
    if (sale == null) return;

    // Find the deferred JE
    final deferredJe = await (select(journalEntries)
          ..where((e) =>
              e.referenceType.equals('deferred_sale') &
              e.referenceId.equals(invoiceId) &
              e.isAutoPosted.equals(true))
          ..limit(1))
        .getSingleOrNull();

    if (deferredJe != null) {
      // Reverse the deferred JE: swap debit/credit on all lines
      final deferredLines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(deferredJe.id)))
          .get();

      final reversalLines = deferredLines.map((l) => JournalLine(
        accountId: l.accountId,
        debit: l.credit,   // swap
        credit: l.debit,   // swap
        description: 'عكس إيراد مؤجل — ${l.description ?? ''}',
      )).toList();

      if (reversalLines.isNotEmpty) {
        // Throws propagate (no catch here) — see class doc above: this stops
        // the revenue JE below from ever running on this attempt, and the
        // dedup guard inside createJournalEntry makes a retry idempotent.
        await accountingDao.createJournalEntry(
          description: 'عكس إيراد مؤجل — فاتورة #${sale.invoiceNumber}',
          date: DateTime.now(),
          lines: reversalLines,
          referenceType: 'deferred_sale_reversal',
          referenceId: invoiceId,
          isAutoPosted: true,
        );
      }
    }

    // Now create the proper revenue JE. Also no catch here — a failure
    // propagates to the caller instead of a false "posted" outcome, and
    // repairFailedDeliveryAutoposts retries the whole method later.
    //
    // Spec 151 F-05 (revenue-recognition fix): autoPostCashSale/CreditSale
    // deliberately DEFER (re-route to _autoPostDeferredRevenue → dedup no-op)
    // any sale whose deliveryStatus != 'delivered'. Since Spec 151 F-05 now
    // posts this JE BEFORE the caller flips the status, the row still reads
    // 'pending' here — so passing `sale` as-is would REVERSE the deferral and
    // then silently skip the forward revenue JE, leaving Sales/VAT unbooked
    // (deferral + reversal net to zero → revenue vanishes). This is a
    // *delivery confirmation*, so force the in-memory copy to 'delivered' for
    // the revenue post; the DB status flip (owned by the caller) is unaffected.
    final deliveredSale = sale.copyWith(deliveryStatus: const Value('delivered'));
    final isFullCredit = deliveredSale.paymentMethod == 'credit' ||
        (deliveredSale.total - deliveredSale.paid > 0.01 && deliveredSale.paid == 0);
    if (isFullCredit) {
      await autoPostCreditSale(deliveredSale);
    } else {
      await autoPostCashSale(deliveredSale);
    }
  }

  /// GAP-P1-FIX-06: Find delivered invoices that are missing a revenue GL journal
  /// entry and re-post them. Called at app startup to recover from crashes or
  /// power-loss events that interrupted the autopost pipeline.
  ///
  /// Returns the number of invoices that were successfully repaired.
  Future<int> repairFailedDeliveryAutoposts({int limit = 50}) async {
    // Delivered, non-deleted sales invoices that have no auto-posted revenue JE
    final orphaned = await customSelect('''
      SELECT si.id
      FROM sales_invoices si
      WHERE si.is_deleted = 0
        AND si.status NOT IN ('returned', 'cancelled')
        AND si.delivery_status = 'delivered'
        AND NOT EXISTS (
          SELECT 1
          FROM journal_entries je
          WHERE je.reference_id = si.id
            AND je.reference_type IN ('sales_invoice', 'sale', 'deferred_sale_reversal')
            AND je.is_auto_posted = 1
            AND je.is_deleted = 0
        )
      LIMIT ?
    ''', variables: [Variable(limit)], readsFrom: {salesInvoices, journalEntries}).get();

    int repaired = 0;
    for (final row in orphaned) {
      final invoiceId = row.data['id'] as int;
      try {
        final sale = await getSalesInvoiceById(invoiceId);
        if (sale == null) continue;

        // If a deferred_sale JE exists, the correct repair path is
        // autoPostDeliveryConfirmed() — it creates the reversal JE first,
        // then the revenue JE. Calling autoPostCashSale() directly would
        // skip the reversal and produce double-revenue.
        final hasDeferredJe = await (select(journalEntries)
              ..where((e) =>
                  e.referenceType.equals('deferred_sale') &
                  e.referenceId.equals(invoiceId) &
                  e.isAutoPosted.equals(true) &
                  e.isDeleted.equals(false))
              ..limit(1))
            .getSingleOrNull();

        if (hasDeferredJe != null) {
          await autoPostDeliveryConfirmed(invoiceId);
        } else {
          final isFullCredit = sale.paymentMethod == 'credit' ||
              (sale.total - sale.paid > 0.01 && sale.paid == 0);
          if (isFullCredit) {
            await autoPostCreditSale(sale);
          } else {
            await autoPostCashSale(sale);
          }
        }
        repaired++;
      } catch (e) {
        debugPrint('[REPAIR] Failed to re-post invoice #$invoiceId: $e');
      }
    }
    return repaired;
  }

  /// Spec 114b — Broad-spectrum JE backfill for sales AND purchase invoices.
  ///
  /// `repairFailedDeliveryAutoposts` above is narrowly scoped to delivered
  /// orders that lost their JE between deferral and delivery confirmation.
  /// This one is wider: it re-posts the JE for ANY sales or purchase
  /// invoice whose auto-posted JE is missing, regardless of how the gap
  /// arose. The historical gap that motivated this routine was the Spec 114
  /// root cause — placeholder parties created without a sub-account caused
  /// every JE that referenced them to fail validation with "حساب رئيسي",
  /// and the failure was swallowed inside a try/catch so the invoice still
  /// landed in the table while the GL row was lost.
  ///
  /// Workflow:
  /// 1. Sales: scan `sales_invoices` rows with no matching auto-posted JE
  ///    in `journal_entries` (referenceType ∈ {sale, sales_invoice,
  ///    sales_return}). For each, dispatch:
  ///      • saleType == 'return' → skipped (needs original-invoice + line
  ///        amounts; safer to re-issue from the returns dialog)
  ///      • full credit         → autoPostCreditSale
  ///      • else                → autoPostCashSale
  /// 2. Purchases: scan `purchase_invoices` with no matching JE. Dispatch
  ///    → autoPostPurchase.
  ///
  /// Idempotent — the underlying autoPost methods short-circuit when a JE
  /// already exists (`hasAutoPostEntry`).
  ///
  /// Returns a counters map:
  ///   `salesRepaired`, `salesSkipped`, `salesFailed`,
  ///   `purchasesRepaired`, `purchasesSkipped`, `purchasesFailed`,
  ///   `totalScanned`.
  Future<Map<String, int>> repairAllMissingInvoiceJEs() async {
    int salesRepaired = 0;
    int salesSkipped = 0;
    int salesFailed = 0;
    int purchasesRepaired = 0;
    int purchasesSkipped = 0;
    int purchasesFailed = 0;

    // ── Sales ────────────────────────────────────────────────────────
    final orphanedSales = await customSelect('''
      SELECT si.id
      FROM sales_invoices si
      WHERE si.is_deleted = 0
        AND NOT EXISTS (
          SELECT 1
          FROM journal_entries je
          WHERE je.reference_id = si.id
            -- Spec 151: 'sales_return' removed. Return JEs are now keyed on the
            -- ORIGINATING invoice id too, so leaving it here would let a return
            -- JE satisfy this NOT EXISTS and MASK an invoice whose SALE JE is
            -- genuinely missing (it would never be repaired). The purchase
            -- branch below already omits 'purchase_return' for the same reason.
            AND je.reference_type IN ('sale', 'sales_invoice')
            AND je.is_auto_posted = 1
            AND je.is_deleted = 0
        )
    ''', readsFrom: {salesInvoices, journalEntries}).get();

    for (final row in orphanedSales) {
      final invoiceId = row.data['id'] as int;
      try {
        final sale = await getSalesInvoiceById(invoiceId);
        if (sale == null) {
          salesSkipped++;
          continue;
        }
        if (sale.saleType == 'return') {
          // Returns need the original invoice + per-line amounts to
          // re-post cleanly. Skip and surface via diagnostic log so the
          // operator can re-save them manually if needed.
          debugPrint('[REPAIR-JE] sales_return #$invoiceId skipped — '
              're-issue from the returns dialog');
          salesSkipped++;
          continue;
        }
        final isFullCredit = sale.paymentMethod == 'credit' ||
            (sale.total - sale.paid > 0.01 && sale.paid == 0);
        final result = isFullCredit
            ? await autoPostCreditSale(sale)
            : await autoPostCashSale(sale);
        if (result != null) {
          salesRepaired++;
        } else {
          // autoPost returned null — either total<=0 (degenerate row) or
          // a mapping skip. Count as skipped (not failed) so the operator
          // sees a clean breakdown.
          salesSkipped++;
        }
      } catch (e) {
        debugPrint('[REPAIR-JE] sale #$invoiceId failed: $e');
        salesFailed++;
      }
    }

    // ── Purchases ───────────────────────────────────────────────────
    final orphanedPurchases = await customSelect('''
      SELECT pi.id
      FROM purchase_invoices pi
      WHERE pi.is_deleted = 0
        AND NOT EXISTS (
          SELECT 1
          FROM journal_entries je
          WHERE je.reference_id = pi.id
            AND je.reference_type IN ('purchase', 'purchase_invoice')
            AND je.is_auto_posted = 1
            AND je.is_deleted = 0
        )
    ''', readsFrom: {purchaseInvoices, journalEntries}).get();

    for (final row in orphanedPurchases) {
      final invoiceId = row.data['id'] as int;
      try {
        final purchase = await (select(purchaseInvoices)
              ..where((p) => p.id.equals(invoiceId))
              ..limit(1))
            .getSingleOrNull();
        if (purchase == null) {
          purchasesSkipped++;
          continue;
        }
        final result = await autoPostPurchase(purchase);
        if (result != null) {
          purchasesRepaired++;
        } else {
          purchasesSkipped++;
        }
      } catch (e) {
        debugPrint('[REPAIR-JE] purchase #$invoiceId failed: $e');
        purchasesFailed++;
      }
    }

    final totalScanned = orphanedSales.length + orphanedPurchases.length;
    debugPrint('[REPAIR-JE] done — salesRepaired=$salesRepaired '
        'salesSkipped=$salesSkipped salesFailed=$salesFailed '
        'purchasesRepaired=$purchasesRepaired '
        'purchasesSkipped=$purchasesSkipped '
        'purchasesFailed=$purchasesFailed '
        'totalScanned=$totalScanned');

    return {
      'salesRepaired': salesRepaired,
      'salesSkipped': salesSkipped,
      'salesFailed': salesFailed,
      'purchasesRepaired': purchasesRepaired,
      'purchasesSkipped': purchasesSkipped,
      'purchasesFailed': purchasesFailed,
      'totalScanned': totalScanned,
    };
  }
}
