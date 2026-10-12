// Accounting auto-post: auto-post lookups and sales return.
part of '../database.dart';

/// Accounting auto-post: auto-post lookups and sales return. (split from accounting_autopost_dao.dart - pure move).
extension AccountingAutopostSalesReturnDao on AppDatabase {
  /// Check if a transaction already has an auto-posted entry
  Future<bool> hasAutoPostEntry(String referenceType, int referenceId) async {
    final existing =
        await (select(journalEntries)
              ..where(
                (e) =>
                    e.referenceType.equals(referenceType) &
                    e.referenceId.equals(referenceId) &
                    e.isAutoPosted.equals(true),
              )
              ..limit(1))
            .get();
    return existing.isNotEmpty;
  }

  Future<int?> _activeSaleEntryId(int saleId) async {
    final entries = await (select(journalEntries)
          ..where((e) => e.referenceType.equals('sale') &
              e.referenceId.equals(saleId) &
              e.isPosted.equals(true) &
              e.isDeleted.equals(false)))
        .get();
    for (final entry in entries) {
      final reversal = await (select(journalEntries)
            ..where((e) => e.referenceType.equals('reversal') &
                e.referenceId.equals(entry.id) &
                e.isPosted.equals(true) &
                e.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();
      if (reversal == null) return entry.id;
    }
    return null;
  }

  /// A-01 / A-02 / F-04 (Spec 151): dedup guard for auto-posted RETURN JEs.
  ///
  /// Return JEs are keyed on the ORIGINATING invoice id (so cancel/edit can
  /// reverse them by that id — see the producers below), which is NOT unique
  /// across multiple partial returns of one invoice. The (refType,refId)
  /// [hasAutoPostEntry] guard — and createJournalEntry's own internal dedup —
  /// would therefore wrongly collapse a SECOND distinct return onto the first.
  /// The deterministic globalId is unique per return EVENT (invoice.globalId +
  /// per-event key), so return producers dedup on it instead: distinct returns
  /// pass, and a genuine retry (identical gid) is caught for a clean idempotent
  /// skip before the journal_entries.globalId UNIQUE index would hard-fail it.
  Future<bool> _hasAutoPostEntryByGlobalId(String globalId) async {
    final existing = await (select(journalEntries)
          ..where((e) => e.globalId.equals(globalId))
          ..limit(1))
        .getSingleOrNull();
    return existing != null;
  }

  /// Auto-post a sales return (مرتجعات مبيعات) — IFRS 15.B20
  /// Dr: Sales Returns (contra_revenue) | Cr: Cash/Bank/Receivables
  /// Dr: Inventory | Cr: COGS (reverse the cost entry)
  ///
  /// Feature 009 / T032 (Issue 6 / Cluster 021): when [reversalCogs] is
  /// non-null and non-empty, the inventory-debit / COGS-credit value uses
  /// the sum of frozen `unit_cost_at_sale` from the BOM consumption rows
  /// instead of the legacy [cogsAmount] (which was computed from
  /// `item.costPrice × returnQty` and can drift if WAC moves between sale
  /// and return). The JE shape stays identical (single Inventory / single
  /// COGS line) — the per-raw-material structure is forward-compatible
  /// for future per-product accounts. Constitution I: legacy callers (no
  /// reversalCogs param) get exactly the same JE as before.
  Future<int?> autoPostSalesReturn({
    required SalesInvoiceData originalInvoice,
    /// تاريخ حدث المرتجع. `null` = السلوك القديم (تاريخ الفاتورة الأصلية).
    DateTime? returnDate,
    required double returnAmount,
    required double cogsAmount,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    double vatAmount = 0,
    int? costCenterId,
    List<CogsLine>? reversalCogs,
    // A-01 (Spec 151): per-return-event discriminator — the caller's sequential
    // SRET-N voucher number, threaded so two DISTINCT partial returns of the
    // SAME amount on one invoice get DISTINCT journal entries instead of
    // colliding on a shared amount-only key. A genuine retry of the SAME return
    // event redraws the same voucher (its counter row rolls back with the
    // failed transaction) → same gid → deduped. Falls back to the amount when
    // omitted: the POS quick-return passes the return invoice itself as
    // [originalInvoice], whose id/globalId is already unique per event.
    String? returnEventId,
  }) async {
    if (returnAmount <= 0) return null;
    // A-02 / A-01 (Spec 151): key the return JE by the ORIGINATING invoice id —
    // the SAME id the stock movements, safe transactions, AR adjustment and the
    // cancelSalesReturn reverse query all use — instead of a hash of
    // (invoiceId+amount). The old hash made cancelSalesReturn's
    // `referenceId == invoiceId` reverse query match ZERO rows, so the contra-
    // revenue / COGS GL legs + AR were never reversed on cancel (permanent GL
    // drift). Per-event uniqueness is carried by the deterministic globalId
    // below (NOT by referenceId), so 'sales_return' is exempt from
    // createJournalEntry's (refType,refId) dedup.
    final eventDiscriminator =
        (returnEventId != null && returnEventId.isNotEmpty)
            ? returnEventId
            : returnAmount.toStringAsFixed(AppConstants.decimalPlaces);
    final returnKey =
        '${originalInvoice.id}_$eventDiscriminator'.hashCode.abs();
    // Deterministic JE globalId — used BOTH as the dedup guard and as the
    // journal_entries.globalId (UNIQUE). Distinct return events → distinct gid
    // → distinct JE; a true retry → identical gid → clean idempotent skip.
    final saleretSourceGid =
        '${originalInvoice.globalId ?? 'invid${originalInvoice.id}'}rk$returnKey';
    final jeGid = JournalEntryGid.computeAndLog(
      sourceType: JournalEntryGid.sourceSalesReturn,
      sourceGid: saleretSourceGid,
      verb: 'post',
      invId: originalInvoice.id,
    );
    if (await _hasAutoPostEntryByGlobalId(jeGid)) return null;

    // Resolve Branch from Warehouse
    final warehouse = await (select(warehouses)..where((w) => w.id.equals(originalInvoice.warehouseId))).getSingleOrNull();
    final branchId = warehouse?.branchId;

    // C2: a return of an invoice that chose its own «حساب المبيعات» debits
    // that SAME account (resolved from the original — directly, or through
    // the quick-return link note). NULL ⇒ the mapped 'sales_return' account.
    final salesReturnAccount =
        await resolveSalesRevenueAccountOverride(originalInvoice.id) ??
            await accountingDao.getAccountByCode(
              await accountingDao.getMappedAccountCode('sales_return', AccountingDao.accountPurposes['sales_return']!),
            );
    final cashAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!),
    );
    final bankAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('bank', AccountingDao.accountPurposes['bank']!),
    );
    final receivableControlAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('receivables', AccountingDao.accountPurposes['receivables']!),
    );
    // Route AR refund line to the customer's sub-account so the reversal is
    // visible on the customer's ledger card (not just the 1201 control).
    final receivableAccount = await _resolvePartySubAccount(
      originalInvoice.customerId,
      receivableControlAccount,
    );
    // Fail loud (mirrors autoPostPurchaseReturn): the caller has ALREADY
    // reversed stock/safe/AR inside the same open transaction. Returning null
    // here would commit those subledger reversals with ZERO GL trace — a silent
    // ledger↔subledger divergence. Throwing rolls the whole transaction back (R3).
    if (salesReturnAccount == null) {
      throw StateError(
        'تعذّر ترحيل قيد مرتجع المبيعات — حساب مردودات المبيعات غير مربوط في '
        'دليل الحسابات. يرجى ربط حساب المردودات من إعدادات الحسابات المحاسبية '
        'قبل تنفيذ مرتجع المبيعات.',
      );
    }

    final lines = <JournalLine>[];

    // Debit: Sales Returns (contra revenue) — **NET** amount. The VAT
    // portion is recorded on its own line so the total debit matches
    // the gross credit (cash/bank/AR). Otherwise the entry is out of
    // balance by `vatAmount` and `createJournalEntry`'s double-entry
    // validator throws "المدين لا يساوى الدائن" (the exact error the
    // user reported for count-item returns).
    //
    // Accounting symmetry with the original sale:
    //   Sale:   Dr Cash/AR (gross)          Cr Sales (net), Cr Output VAT
    //   Return: Dr Sales Returns (net),     Cr Cash/AR (gross)
    //           Dr Output VAT (reverses)
    // Resolve Output-VAT up front: only split VAT onto its own reversal line
    // (and exclude it from the contra-revenue net) when the account exists. If
    // VAT isn't mapped we FOLD it into the sales-returns leg so debits still ==
    // the gross credit — symmetric with the original sale, which likewise folds
    // unmapped VAT. Previously net always excluded VAT, so an unmapped VAT
    // account left the entry short by vatAmount → hard-fail, return blocked.
    final vatAccount = vatAmount > 0
        ? await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('output_vat', AccountingDao.accountPurposes['output_vat']!),
          )
        : null;
    final salesReturnNet = (vatAmount > 0 && vatAccount != null)
        ? (returnAmount - vatAmount)
        : returnAmount;
    lines.add(JournalLine(
      accountId: salesReturnAccount.id,
      debit: salesReturnNet,
      description: 'مردودات مبيعات (صافى)',
    ));

    // Debit: Output VAT reversal (عكس ضريبة المبيعات)
    if (vatAmount > 0 && vatAccount != null) {
      lines.add(JournalLine(
        accountId: vatAccount.id,
        debit: vatAmount,
        description: 'عكس ضريبة مرتجع',
      ));
    }

    // Credit: Cash refund
    if (cashRefund > 0 && cashAccount != null) {
      lines.add(JournalLine(
        accountId: cashAccount.id,
        credit: cashRefund,
        description: 'رد نقدي',
      ));
    }

    // Credit: Bank refund
    if (bankRefund > 0 && bankAccount != null) {
      lines.add(JournalLine(
        accountId: bankAccount.id,
        credit: bankRefund,
        description: 'رد بنكي',
      ));
    }

    // Credit: AR adjustment
    if (arRefund > 0 && receivableAccount != null) {
      lines.add(JournalLine(
        accountId: receivableAccount.id,
        credit: arRefund,
        description: 'تسوية ذمم مدينة',
      ));
    }

    // Reverse COGS: Dr Inventory / Cr COGS
    //
    // Feature 009 / T032: when reversalCogs is non-empty, the inventory leg
    // uses the sum of FROZEN unit_cost_at_sale from the BOM consumption
    // rows. This stays accurate even if WAC moved between sale and return.
    // Otherwise the legacy cogsAmount path runs unchanged.
    final effectiveCogs = (reversalCogs != null && reversalCogs.isNotEmpty)
        ? reversalCogs.fold<double>(0.0, (s, l) => s + l.totalCost)
        : cogsAmount;
    if (effectiveCogs > 0) {
      final cogsAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cogs', AccountingDao.accountPurposes['cogs']!),
      );
      final inventoryAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
      );
      if (cogsAccount != null && inventoryAccount != null) {
        lines.add(JournalLine(
          accountId: inventoryAccount.id,
          debit: effectiveCogs,
          description: 'إرجاع مخزون',
        ));
        lines.add(JournalLine(
          accountId: cogsAccount.id,
          credit: effectiveCogs,
          description: 'عكس تكلفة بضاعة',
        ));
      }
    }

    // ── عكسُ فرق التقريب — على المرتجع الكامل وحدَه ────────────────────────
    //
    // الشرطُ **نفسُه حرفيّاً** في `SalesReturnRefundSplit.from`: هناك يُخصَم
    // الفرقُ من المبلغ المردود، وهنا يُعكَس سطرُه في القيد. واختلافُ الشرطَين
    // كان سيفصل النقدَ الخارجَ من الدرج عن الدفتر.
    //
    // والجزئيُّ لا يمسّه: التقريبُ وقع على تسويةِ الفاتورة كلِّها لا على سطرٍ
    // بعينه، فنصفُ الأصناف لا يحمل نصفَ قرشِ التقريب.
    final returnRoundingAdj = originalInvoice.roundingAdjustment;
    if (returnRoundingAdj != 0 &&
        returnAmount >= originalInvoice.total - 0.01) {
      final roundingAccount =
          await accountingDao.getLeafAccountByPurpose('rounding_difference');
      if (roundingAccount != null) {
        lines.add(JournalLine(
          accountId: roundingAccount.id,
          // بعكس اتجاه سطر البيع تماماً: ما كان مديناً هناك دائنٌ هنا.
          debit: returnRoundingAdj < 0 ? -returnRoundingAdj : 0,
          credit: returnRoundingAdj > 0 ? returnRoundingAdj : 0,
          description: 'عكس فروق تقريب',
        ));
      }
    }

    if (lines.isEmpty) return null;

    return accountingDao.createJournalEntry(
      description: 'قيد مرتجع مبيعات فاتورة ${originalInvoice.invoiceNumber}',
      // المرتجع حدث لاحق له فترته الخاصة — مش تعديل على المستند الأصلي.
      date: resolveReturnPostingDate(
        returnDate: returnDate,
        originalInvoiceDate: originalInvoice.invoiceDate,
      ),
      lines: lines,
      referenceType: 'sales_return',
      // A-02: the cancel/reverse query keys on the originating invoice id
      // (see the top-of-method comment). Uniqueness rides on globalId.
      referenceId: originalInvoice.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: jeGid,
    );
  }
}
