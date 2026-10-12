// Purchase payment/journal reversal helpers and payment/status updates.
part of '../database.dart';

extension PurchasePaymentsDao on AppDatabase {
  /// F-02 (Spec 151): reverse the posted purchase JE for [invoiceId] by hard-
  /// deleting the entry + its lines and recomputing the affected accounts'
  /// balances from the POSTED lines that survive. Mirrors the GL-reversal step
  /// of updateFullSalesInvoice (the sales sibling). Called only from
  /// [updatePurchaseInvoice], already inside its transaction(); the subsequent
  /// autoPostPurchase re-posts the entry with the new amounts.
  ///
  /// Matches BOTH reference-type aliases a purchase JE can carry: the inline
  /// createPurchaseInvoice path stores 'purchase_invoice'; autoPostPurchase
  /// stores 'purchase'. Deleting both lets autoPostPurchase's dedup guard pass.
  Future<void> _reverseOldPurchaseJournalEntry(int invoiceId) async {
    final oldEntries = await (select(journalEntries)
          ..where((e) =>
              e.referenceType.isIn(kPurchaseJeReferenceTypes.toList()) &
              e.referenceId.equals(invoiceId) &
              e.isAutoPosted.equals(true)))
        .get();
    if (oldEntries.isEmpty) return;

    final affectedAccountIds = <int>{};
    for (final entry in oldEntries) {
      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();
      for (final l in lines) {
        affectedAccountIds.add(l.accountId);
      }
      await (delete(journalEntryLines)..where((l) => l.entryId.equals(entry.id)))
          .go();
      await (delete(journalEntries)..where((e) => e.id.equals(entry.id))).go();
    }

    // Recompute each affected account's balance from the POSTED lines that
    // survive the delete — the same self-healing Σdebit − Σcredit recompute
    // createJournalEntry and _updateAccountBalance use (is_posted = 1 filter).
    for (final accId in affectedAccountIds) {
      final result = await customSelect(
        'SELECT COALESCE(SUM(jel.debit),0) AS d, COALESCE(SUM(jel.credit),0) AS c '
        'FROM journal_entry_lines jel '
        'INNER JOIN journal_entries je ON je.id = jel.entry_id '
        'WHERE jel.account_id = ? AND je.is_posted = 1',
        variables: [Variable<int>(accId)],
        readsFrom: {journalEntryLines, journalEntries},
      ).getSingle();
      final d = (result.data['d'] as num).toDouble();
      final c = (result.data['c'] as num).toDouble();
      await (update(accounts)..where((a) => a.id.equals(accId)))
          .write(AccountsCompanion(balance: Value(d - c)));
    }
  }

  /// F-02 (Spec 151): reverse the ORIGINAL treasury payment(s) recorded for
  /// [invoiceId] by createPurchaseInvoice/_recordPurchasePayment/addPurchasePayment
  /// — restore each safe's balance, reverse the separate GL 'payment' JE (if
  /// any), and delete the payment safe_transaction row(s) — so
  /// [updatePurchaseInvoice] can re-record the payment for the new `paid` amount
  /// cleanly (delete-and-reapply: the same shape this edit already uses for the
  /// items and the base GL). Called only from updatePurchaseInvoice, inside its
  /// transaction(). No-op when the invoice had no payment.
  ///
  /// Returns the safeId of the FIRST original payment (or null when there was
  /// none) so the caller can re-record the new payment against the SAME safe
  /// (F02-2) instead of silently falling back to the global default safe — a
  /// payment made from a non-default safe would otherwise be reversed from the
  /// original safe but re-recorded to the default one (per-safe misallocation).
  ///
  /// Targets the purchase-payment rows (referenceType 'purchase_invoice',
  /// transactionType 'payment'); void reversals live under
  /// 'purchase_invoice_void' and are untouched.
  ///
  /// F02-1: a prior [addPurchasePayment] posts a SEPARATE, balanced GL 'payment'
  /// JE via autoPostPayment (referenceType 'payment', referenceId = this
  /// safe_txn.id, isAutoPosted=TRUE) — Dr payables(supplier) / Cr cash. The
  /// create-time down-payment does NOT (its cash leg lives inside the base
  /// purchase JE). If that 'payment' JE is left live while the re-post below
  /// credits cash again for the full invoice.paid, the payment is DOUBLE-COUNTED
  /// in the GL (cash credited twice, payables under-credited). So mirror-reverse
  /// it here (audit trail preserved), keyed on the UNIQUE safe_txn.id. Uses the
  /// shared reverser's default requireAutoPosted:true — autoPostPayment JEs are
  /// auto-posted, so the default is correct. All inside updatePurchaseInvoice's
  /// transaction() (R3), balanced by construction.
  Future<int?> _reverseOldPurchasePayment(int invoiceId) async {
    final oldPayments = await (select(safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    int? primarySafeId;
    for (final txn in oldPayments) {
      // F02-2: remember the FIRST original payment's safe so the re-record
      // lands back on the same safe.
      primarySafeId ??= txn.safeId;
      final safe = await (select(safes)..where((s) => s.id.equals(txn.safeId)))
          .getSingleOrNull();
      if (safe != null) {
        // The original payment DEBITED the safe (balance −= amount); restore it.
        // H15 — ردٌّ ذرّيّ: القراءةُ ثم الكتابة كانت تضيّع ردّاً موازياً.
        await adjustSafeBalance(safe.id, txn.amount);
      }
      // F02-1: reverse the separate GL 'payment' JE that addPurchasePayment
      // posted for THIS safe_txn (no-op for create-time down-payments, which
      // carry no such JE). Without this the base-JE re-post below double-counts
      // the cash/payables legs. safe_txn.globalId is null for these rows, so
      // qualify the deterministic reversal gid with the unique safe_txn id to
      // avoid a '<null>-rev' collision across multiple payments.
      final srcGid = txn.globalId ?? 'paytxn${txn.id}';
      await reverseAutoPostedJournalEntriesFor(
        referenceType: 'payment',
        referenceId: txn.id,
        voidReferenceType: 'payment_void',
        sourceGlobalId: srcGid,
        description: 'عكس قيد سداد (تعديل فاتورة مشتريات) #$invoiceId',
      );
      await (delete(safeTransactions)..where((t) => t.id.equals(txn.id))).go();
    }
    return primarySafeId;
  }

  /// Add payment to a purchase invoice.
  ///
  /// P2 (batch B7 / S-FAILLOUD): this used to move cash out of the safe
  /// (via [_recordPurchasePayment]) and mark the invoice more-paid WITHOUT
  /// ever posting a journal entry — the supplier payable in the GL never
  /// reduced, silently diverging from the treasury/party-balance side.
  /// Now posts a balanced payment JE (Dr payables sub-account / Cr cash-or-
  /// bank) via the existing [AccountingAutopostDao.autoPostPayment] — its
  /// 'purchase' category routing already does exactly this shape — inside
  /// the SAME transaction as the payment write, so a resolution failure
  /// rolls back the invoice.paid/status update and the safe transaction
  /// together instead of leaving a payment with no GL trace.
  Future<void> addPurchasePayment({
    required int invoiceId,
    required double amount,
    String paymentMethod = 'cash',
    int? safeId,
    int? userId,
    String? globalId,
     double? paymentRate,
     double? foreignAmount,
  }) async {
    return transaction(() async {
      // Spec 151 C-03 idempotency: a payment is ADDITIVE, so an offline-outbox
      // replay or a mirror re-submit carrying the SAME globalId must NOT
      // double-apply (200 → 400 on retry, over-crediting the safe and
      // double-reducing payables). The payment's safe_transaction stamps this
      // globalId below, so if one already exists this event was applied →
      // return without touching paid/safe/JE. Dedup lives here (not only in the
      // HTTP handler) so BOTH the local path and the server handler are
      // idempotent. Inside the transaction so it can't race a concurrent apply.
      if (globalId != null && globalId.isNotEmpty) {
        final existing = await (select(safeTransactions)
              ..where((t) => t.globalId.equals(globalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) return;
      }

      final invoice = await getPurchaseInvoiceById(invoiceId);
      if (invoice == null) throw Exception('Invoice not found');

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'سداد دفعة مشتريات');

      final settledAtBooking = invoice.currencyId != null &&
               invoice.exchangeRate != null &&
               invoice.exchangeRate! > 0 &&
               foreignAmount != null
           ? foreignAmount * invoice.exchangeRate!
           : amount;
       final newPaid = invoice.paid + settledAtBooking;
      final newRemaining = invoice.total - newPaid;
      final newStatus = newRemaining <= 0 ? 'paid' : 'partial';

      await (update(
        purchaseInvoices,
      )..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          paid: Value(newPaid),
          status: Value(newStatus),
        ),
      );
      await resignPurchaseInvoice(invoiceId);
       final safeTxn = await _recordPurchasePayment(
        invoiceId, amount, paymentMethod, invoice.costCenterId,
        safeId: safeId,
        supplierId: invoice.supplierId,
        userId: userId,
        globalId: globalId,
         paymentRate: paymentRate,
         foreignAmount: foreignAmount,
      );

      // B7 (S-FAILLOUD): a payment must move cash AND post a balanced JE.
      // If no target safe resolved, nothing moved in treasury and no JE can
      // be posted — fail loud so the invoice.paid/status advance above rolls
      // back too, instead of leaving the invoice marked more-paid with no
      // cash movement and no GL trace (the same side-effect-without-JE class
      // this batch closes, previously left open for the no-safe config).
      if (safeTxn == null) {
        throw StateError(
          'تعذّر تسجيل دفعة المشتريات للفاتورة #${invoice.invoiceNumber}: '
          'لا يوجد صندوق/بنك محدد لصرف الدفعة منه. '
          'راجع إعدادات الصناديق قبل تسجيل الدفعة.',
        );
      }
      final jeId = await autoPostPayment(safeTxn, costCenterId: invoice.costCenterId);
      if (jeId == null) {
        throw StateError(
          'تعذّر ترحيل قيد سداد دفعة المشتريات للفاتورة #${invoice.invoiceNumber}: '
          'تحقق من ربط حساب الدائنون (الموردين) وحساب الصندوق/البنك '
          'في إعدادات الربط المحاسبي.',
        );
      }

      // Spec 151 (FIN-B-ACC-1) — decrement the supplier's cached parties.balance
      // so it stops OVERSTATING payables after a payment. Invoice create/edit/
      // void all maintain this denormalized balance; the payment path
      // historically did not (the asymmetry the Wave B committee caught vs the
      // sales-collection twin, which credits the customer's balance via
      // createReceiptVoucher). Inside the transaction → rolls back with the JE
      // on any failure; idempotent because the whole method dedups on globalId.
      await adjustPartyBalance(invoice.supplierId, -settledAtBooking);
      await resignPurchaseInvoice(invoiceId);
    });
  }

  /// Update payment amount for a purchase invoice (simple update)
  Future<void> updatePurchaseInvoicePayment(
    int invoiceId,
    double newPaid,
  ) async {
    final invoice = await getPurchaseInvoiceById(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    // 0. Soft/Hard Period Closing Gating
    await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'تعديل سداد مشتريات');

    final newRemaining = invoice.total - newPaid;
    final newStatus = newRemaining <= 0
        ? 'paid'
        : (newPaid > 0 ? 'partial' : 'pending');

    await (update(
      purchaseInvoices,
    )..where((i) => i.id.equals(invoiceId))).write(
      PurchaseInvoicesCompanion(
         paid: Value(newPaid),
         status: Value(newStatus),
       ),
    );
    await resignPurchaseInvoice(invoiceId);
  }

  /// Update purchase invoice status intentionally (e.g. for returns)
  Future<void> updatePurchaseInvoiceStatus(int invoiceId, String status) async {
    await (update(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).write(
      PurchaseInvoicesCompanion(status: Value(status)),
    );
  }
}
