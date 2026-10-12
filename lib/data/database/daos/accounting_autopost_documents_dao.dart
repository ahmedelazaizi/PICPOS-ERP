// Accounting auto-post: credit sale, purchase invoice, receipt and payment vouchers.
part of '../database.dart';

/// Accounting auto-post: credit sale, purchase invoice, receipt and payment vouchers. (split from accounting_autopost_dao.dart - pure move).
extension AccountingAutopostDocumentsDao on AppDatabase {
  /// Auto-post a credit sale (بيع اجل آجل)
  /// Debit: Receivables | Credit: Sales + VAT + Delivery
  /// Debit: Sales Discount (if applicable)
  /// APG-04: IFRS 15.38 — skip auto-posting for undelivered delivery orders
  Future<int?> autoPostCreditSale(
    SalesInvoiceData sale, {
    int? costCenterId,
    bool repostAfterReversal = false,
    int repostRevision = 0,
  }) async {
    // نفس حارس `autoPostCashSale` — شوف التعليق هناك.
    if (sale.saleType == 'return') return null;
    if (sale.total <= 0) return null;
    // APG-04: Defer revenue for undelivered delivery orders
    if (sale.deliveryStatus != null &&
        sale.deliveryStatus != 'delivered' &&
        sale.deliveryStatus != '') {
      // GAP-22: Create deferred revenue entry instead of silently skipping
      // Dr Receivables / Cr Deferred Revenue (2133)
      return await _autoPostDeferredRevenue(sale, isCashSale: false);
    }
    // TOCTOU FIX: Wrap entire check+insert in a single transaction.
    return transaction(() async {
    // Duplicate protection (atomic — inside serialised write transaction)
    if (repostAfterReversal) {
      final activeId = await _activeSaleEntryId(sale.id);
      if (activeId != null) return activeId;
    } else if (await hasAutoPostEntry('sale', sale.id)) {
      return null;
    }

    // Resolve Branch from Warehouse
    final warehouse = await (select(warehouses)..where((w) => w.id.equals(sale.warehouseId))).getSingleOrNull();
    final branchId = warehouse?.branchId;

    final receivableControlAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode(
        'receivables',
        AccountingDao.accountPurposes['receivables']!,
      ),
    );
    // Route AR to the customer's dedicated sub-account so balances roll up
    // to 1201 in the Chart of Accounts (and each customer appears under it).
    final receivableAccount = await _resolvePartySubAccount(
      sale.customerId,
      receivableControlAccount,
    );
    // C2: the invoice's own «حساب المبيعات» wins over the mapped default.
    final salesAccount = await resolveSalesRevenueAccountOverride(sale.id) ??
        await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('sales', AccountingDao.accountPurposes['sales']!),
        );
    final vatAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('output_vat', AccountingDao.accountPurposes['output_vat']!),
    );
    final discountAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode(
        'sales_discount',
        AccountingDao.accountPurposes['sales_discount']!,
      ),
    );
    final deliveryAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode(
        'delivery_revenue',
        AccountingDao.accountPurposes['delivery_revenue']!,
      ),
    );
    if (salesAccount == null || receivableAccount == null) return null;

    final lines = <JournalLine>[];

    // F-07: Compute net receivable upfront (avoid fragile removeWhere)
    final netReceivable = sale.total - sale.paid;

    // Debit: Receivables (net of partial payment) — posted at the customer
    // sub-account so the COA tree shows this customer's running balance.
    if (netReceivable > 0) {
      lines.add(
        JournalLine(
          accountId: receivableAccount.id,
          debit: netReceivable,
          description: 'مدينون',
        ),
      );
    }

    // Debit: Cash for partial payment if any (via the ACTUAL safe the
    // down-payment receipt landed in — Spec 136 ISS-13).
    if (sale.paid > 0) {
      final cashAccount = await _resolveSaleLegAccount(sale.id, branchId, 'cash');
      if (cashAccount != null) {
        lines.add(
          JournalLine(
            accountId: cashAccount.id,
            debit: sale.paid,
            description: 'دفعة مقدمة',
          ),
        );
      }
    }

    // Credit: Sales — Spec 136 (field fix 2026-06-04): derive the discount
    // leg from the invoice arithmetic so debit == credit by construction
    // (see autoPostCashSale for the full rationale / AQ-POS-1 repro).
    // Spec 136 (field 2026-06-08): subtract from netRevenue ONLY the legs that
    // will ACTUALLY be posted. Pre-fix, tax + delivery were always subtracted
    // from netRevenue, but the VAT/delivery legs only credit when their account
    // is mapped; when output_vat (or delivery_revenue) is UNMAPPED on the
    // server, that amount vanished from the credit side → the JE was short by
    // exactly the tax → every TAXABLE sale dead-lettered ("المدين لا يساوي
    // الدائن", diff == tax) and the tax never reached the ledger. Folding the
    // un-postable amount into Sales keeps the JE balanced so the sale posts;
    // the warning tells the operator to map the account in الربط المحاسبي.
    final legs = _deriveBalancedLegs(
      total: sale.total,
      subtotal: sale.subtotal,
      tax: sale.tax,
      discount: sale.discount,
      deliveryFee: sale.deliveryFee,
      vatAccount: vatAccount,
      deliveryAccount: deliveryAccount,
      discountAccount: discountAccount,
      unmappedVatWarning:
          'sale #${sale.id}: output_vat account UNMAPPED — tax ${sale.tax} '
          'folded into Sales to keep the JE balanced. Map output_vat in الربط '
          'المحاسبي so VAT posts to its own liability account + shows in the ledger.',
    );
    final discountDebit = legs.discountLeg;
    final salesCreditAmount = legs.primaryLeg;
    lines.add(
      JournalLine(
        accountId: salesAccount.id,
        credit: salesCreditAmount,
        description: 'مبيعات',
      ),
    );

    // Credit: VAT
    if (sale.tax > 0 && vatAccount != null) {
      lines.add(
        JournalLine(
          accountId: vatAccount.id,
          credit: sale.tax,
          description: 'ضريبة مبيعات',
        ),
      );
    }

    // Debit: Sales discount if applicable (separate tracking).
    // discountDebit is the gross→net gap (Spec 136); 0 when subtotal is
    // already net, so no phantom contra-revenue leg is posted.
    if (discountDebit > 0 && discountAccount != null) {
      lines.add(
        JournalLine(
          accountId: discountAccount.id,
          debit: discountDebit,
          description: 'خصم مبيعات',
        ),
      );
    }

    // Credit: Delivery fee if applicable
    if (sale.deliveryFee > 0 && deliveryAccount != null) {
      lines.add(
        JournalLine(
          accountId: deliveryAccount.id,
          credit: sale.deliveryFee,
          description: 'إيراد توصيل',
        ),
      );
    }

    // COGS Entry (IAS 2.34): Dr 5101 / Cr 1103
    // Same zero-cost safeguard as autoPostCashSale — see that method for rationale.
    final trackedRowsCr = await customSelect(
      'SELECT sii.product_id, sii.quantity, sii.cost_price, p.track_inventory, p.name '
      'FROM sales_invoice_items sii '
      'JOIN products p ON p.id = sii.product_id '
      'WHERE sii.invoice_id = ? AND sii.id NOT IN ('
      'SELECT sale_invoice_item_id FROM sale_bom_consumptions '
      'WHERE sale_invoice_id = ? AND reversed_by_return_id IS NULL)',
      variables: [Variable(sale.id), Variable(sale.id)],
      readsFrom: {salesInvoiceItems, products, saleBomConsumptions},
    ).get();
    final zeroCostTrackedCr = trackedRowsCr.where((r) {
      final tv = r.data['track_inventory'];
      final tracks = tv == true || tv == 1; // PG returns bool, SQLite returns int
      final cp = (r.data['cost_price'] as num?)?.toDouble() ?? 0.0;
      return tracks && cp <= 0;
    }).toList();
    if (zeroCostTrackedCr.isNotEmpty) {
      final names = zeroCostTrackedCr.map((r) => r.data['name'] as String? ?? '#${r.data['product_id']}').join('، ');
      final policy = (await getSettingValue('zero_cost_policy')) ?? 'warn';
      if (policy == 'block') {
        throw Exception(
          'تعذّر ترحيل الفاتورة ${sale.invoiceNumber}: '
          'الأصناف التالية متعقّبة للمخزون وتكلفتها صفر — $names. '
          'لا يمكن ترحيل إيراد بدون تكلفة مقابلة.',
        );
      }
      if (policy == 'warn') {
        for (final row in zeroCostTrackedCr) {
          await DiagnosticLogger.logZeroCostSale(
            invoiceId: sale.id,
            invoiceNumber: sale.invoiceNumber,
            productId: (row.data['product_id'] as num).toInt(),
            quantity: (row.data['quantity'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }
    }

    final cogsTotal = await customSelect(
      // SAL-1: quantity is in SALE units, cost_price is per BASE unit (WAC).
      // quantity_in_base converts sale-unit qty to physical base-unit qty —
      // without it, COGS is understated on every carton/box (non-base-unit) sale.
      'SELECT COALESCE(SUM(quantity * quantity_in_base * cost_price), 0) as total FROM sales_invoice_items WHERE invoice_id = ?',
      variables: [Variable(sale.id)],
      readsFrom: {salesInvoiceItems},
    ).getSingle();
    final cogsAmount = (cogsTotal.data['total'] as num?)?.toDouble() ?? 0.0;
    if (cogsAmount > 0) {
      final cogsAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cogs', AccountingDao.accountPurposes['cogs']!),
      );
      final inventoryAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
      );
      if (cogsAccount != null && inventoryAccount != null) {
        lines.add(JournalLine(
          accountId: cogsAccount.id,
          debit: cogsAmount,
          description: 'تكلفة بضاعة مباعة',
        ));
        lines.add(JournalLine(
          accountId: inventoryAccount.id,
          credit: cogsAmount,
          description: 'تخفيض مخزون',
        ));
      }
    }

    // Spec 135 — deterministic JE globalId (credit sale). Same invoice → same
    // sourceGid as the cash path; an invoice is only ever cash OR credit, so
    // exactly one base-sale JE per invoice. See cash path above for rationale.
    final saleSourceGid = sale.globalId ?? 'invid${sale.id}';
    final saleJeGid = JournalEntryGid.computeAndLog(
      sourceType: JournalEntryGid.sourceSale,
      sourceGid: saleSourceGid,
      verb: repostAfterReversal ? 'repost$repostRevision' : 'post',
      invId: sale.id,
      suffix: repostAfterReversal ? ' (credit repost $repostRevision)' : ' (credit)',
    );
    final jeId = await accountingDao.createJournalEntry(
      description: 'قيد مبيعات بيع آجل ${sale.invoiceNumber}',
      date: sale.invoiceDate,
      lines: lines,
      referenceType: 'sale',
      referenceId: sale.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: saleJeGid,
      allowRepost: repostAfterReversal,
    );

    // ISS-004: Lock sales invoice after successful autopost.
    if (jeId != 0) {
      try {
        await (update(salesInvoices)..where((i) => i.id.equals(sale.id))).write(
          const SalesInvoicesCompanion(isLocked: Value(true)),
        );
      } catch (e) {
        debugPrint('[AUTOPOST-LOCK] Failed to lock credit sale #${sale.id}: $e');
      }
    }
    return jeId;
    }); // end TOCTOU-safe transaction
  }

  /// Auto-post a purchase invoice (مشتريات فوري)
  /// Debit: Inventory + Input VAT | Credit: Cash/Payables
  Future<int?> autoPostPurchase(PurchaseInvoiceData purchase, {int? costCenterId}) async {
    if (purchase.total <= 0) return null;
    // TOCTOU FIX: Wrap entire check+insert in a single transaction.
    // This serialises concurrent callers so only one can ever commit a JE
    // for the same purchase, even when the DAO inline path and autoPostPurchase()
    // are called concurrently for the same invoice.
    return transaction(() async {
    // Duplicate protection — check both reference types (atomic — inside transaction)
    // The DAO inline path uses 'purchase_invoice'; this method uses 'purchase'.
    if (await hasAutoPostEntry('purchase', purchase.id)) return null;
    if (await hasAutoPostEntry('purchase_invoice', purchase.id)) return null;

    // Resolve Branch from Warehouse
    final warehouse = await (select(warehouses)..where((w) => w.id.equals(purchase.warehouseId))).getSingleOrNull();
    final branchId = warehouse?.branchId;

    // J1b: the invoice's own «حساب المشتريات» wins over the mapped inventory
    // default; NULL (or an invalid stored account) keeps the mapping.
    final inventoryAccount = await resolvePurchaseAccountOverride(purchase.id) ??
        await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
        );
    final inputVatAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('input_vat', AccountingDao.accountPurposes['input_vat']!),
    );
  // ignore: unused_local_variable
    final cashAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!),
    );
    final payableControlAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('payables', AccountingDao.accountPurposes['payables']!),
    );
    // Route AP to the supplier's dedicated sub-account (2111-XXXXX) so each
    // supplier shows its own balance in the Chart of Accounts tree.
    final payableAccount = await _resolvePartySubAccount(
      purchase.supplierId,
      payableControlAccount,
    );
    if (inventoryAccount == null) return null;

    final lines = <JournalLine>[];

    // F-11: Resolve purchase_discount account for separate tracking
    final purchaseDiscountAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode(
        'purchase_discount',
        AccountingDao.accountPurposes['purchase_discount']!,
      ),
    );

    // Debit: Inventory (gross goods cost). F-11 + Spec 136 ISS-24
    // (2026-06-04): derive the purchase-discount leg from the invoice's OWN
    // arithmetic — the SAME class of bug fixed on the sales side
    // (autoPostCashSale). The old code credited Purchase-Discount with the
    // raw `discount` while debiting Inventory with `subtotal`, which only
    // balances when total = subtotal - discount + tax. A poison invoice with
    // subtotal already net (subtotal == total) + a non-zero discount would
    // imbalance by exactly the discount.
    //
    // netGoodsCost = what is actually paid for goods (total minus input VAT;
    // purchase has no separately-booked delivery leg). The discount leg is the
    // gap between gross subtotal and that net cost:
    //   • subtotal gross       → discountCredit == discount (unchanged)
    //   • subtotal already net → discountCredit == 0 (no phantom leg)
    // Inventory debit = netGoodsCost + discountCredit ⇒ debit == credit by
    // construction.
    // Spec 136 (field 2026-06-08) — only subtract input VAT from netGoodsCost
    // when it will actually be debited (input_vat account mapped). Otherwise
    // the tax was subtracted from inventory but never debited to Input VAT →
    // the purchase JE was short on the debit side by the tax → taxable
    // purchases dead-lettered. Fold the un-postable tax into inventory cost so
    // the JE balances; warn the operator to map input_vat.
    final purchaseLegs = _deriveBalancedLegs(
      total: purchase.total,
      subtotal: purchase.subtotal,
      tax: purchase.tax,
      discount: purchase.discount,
      deliveryFee: 0, // purchase has no separately-booked delivery leg
      vatAccount: inputVatAccount,
      deliveryAccount: null,
      discountAccount: purchaseDiscountAccount,
      unmappedVatWarning:
          'purchase #${purchase.id}: input_vat account UNMAPPED — tax '
          '${purchase.tax} folded into inventory cost to keep the JE balanced. '
          'Map input_vat in الربط المحاسبي.',
    );
    final discountCredit = purchaseLegs.discountLeg;
    final inventoryDebit = purchaseLegs.primaryLeg;
    lines.add(
      JournalLine(
        accountId: inventoryAccount.id,
        debit: inventoryDebit,
        description: 'مشتريات بضاعة',
      ),
    );

    // Credit: Purchase discount if tracked separately (F-11). discountCredit is
    // the gross→net gap (Spec 136); 0 when subtotal is already net.
    if (discountCredit > 0 && purchaseDiscountAccount != null) {
      lines.add(
        JournalLine(
          accountId: purchaseDiscountAccount.id,
          credit: discountCredit,
          description: 'خصم مشتريات',
        ),
      );
    }

    // Debit: Input VAT
    if (purchase.tax > 0 && inputVatAccount != null) {
      lines.add(
        JournalLine(
          accountId: inputVatAccount.id,
          debit: purchase.tax,
          description: 'ضريبة مدخلات',
        ),
      );
    }

    // Credit — البند 6 (approved 2026-07-25): the supplier's payable is ALWAYS
    // the counter-party, cash or credit alike; the cash leg is posted from the
    // payment voucher by autoPostPayment (Dr payable / Cr the paying safe's own
    // account). Keeps this re-post identical in shape to createPurchaseInvoice,
    // so editing an invoice no longer silently reverts it to the old model.
    //
    // The removed `paymentMethod == 'cash'` branch credited Cash for the FULL
    // total even when only part was paid (ح-3), and resolved cash from the
    // GLOBAL mapping rather than the paying safe (ح-4).
    if (payableAccount != null) {
      lines.add(
        JournalLine(
          accountId: payableAccount.id,
          credit: purchase.total,
          description: 'دائنون',
        ),
      );
    }

    // Spec 135 — deterministic JE globalId for the base purchase JE. sourceGid
    // is the purchase invoice's shared globalId so client and server converge
    // on one id (UNIQUE-deduped on DeltaPull). invid<localId> fallback for
    // legacy/standalone rows without a globalId yet.
    final purSourceGid = purchase.globalId ?? 'invid${purchase.id}';
    final purJeGid = JournalEntryGid.computeAndLog(
      sourceType: JournalEntryGid.sourcePurchase,
      sourceGid: purSourceGid,
      verb: 'post',
      invId: purchase.id,
    );
    final jeId = await accountingDao.createJournalEntry(
      description: 'قيود مشتريات ${purchase.invoiceNumber}',
      date: purchase.invoiceDate,
      lines: lines,
      referenceType: 'purchase',
      referenceId: purchase.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: purJeGid,
    );

    // PIR P0-03: Lock purchase invoice after successful autopost to prevent
    // retroactive edits that would cause GL/invoice discrepancy.
    if (jeId != 0) {
      try {
        await (update(purchaseInvoices)..where((i) => i.id.equals(purchase.id))).write(
          const PurchaseInvoicesCompanion(isLocked: Value(true)),
        );
      } catch (e) {
        debugPrint('[AUTOPOST-LOCK] Failed to lock purchase #${purchase.id}: $e');
      }
    }
    return jeId;
    }); // end TOCTOU-safe transaction
  }

  /// Auto-post a receipt voucher (سند قبض)
  /// F-05: Routes credit to correct account based on transaction category
  /// Debit: Cash/Bank | Credit: Receivables/Equity/Loans based on category
  Future<int?> autoPostReceipt(SafeTransactionData txn, {int? costCenterId}) async {
    if (txn.amount <= 0) return null;
    // Duplicate protection
    if (await hasAutoPostEntry('receipt', txn.id)) return null;

    // Safe branch is direct
    final safe = await (select(safes)..where((s) => s.id.equals(txn.safeId))).getSingleOrNull();
    final branchId = safe?.branchId;

    // Determine which asset account (cash vs bank)
    Account? assetAccount;
    if (safe?.linkedAccountId != null) {
      assetAccount = await accountingDao.getAccountById(safe!.linkedAccountId!);
    }
    
    // Fallback to global mapping if safe has no linked account
    if (assetAccount == null) {
      final assetType = safe?.safeType == 'bank' ? 'bank' : 'cash';
      final defaultCode = safe?.safeType == 'bank'
          ? AccountingDao.accountPurposes['bank']!
          : AccountingDao.accountPurposes['cash']!;
      final assetCode = await accountingDao.getMappedAccountCode(assetType, defaultCode);
      assetAccount = await accountingDao.getAccountByCode(assetCode);
    }
    if (assetAccount == null) return null;

    // F-05: Determine credit account based on transaction category
    String creditPurpose;
    String creditDescription;
    switch (txn.category) {
      case 'equity':
        creditPurpose = 'owner_equity';
        creditDescription = 'رأس مال مالك';
        break;
      case 'loan':
        creditPurpose = 'loans_payable';
        creditDescription = 'قروض مستحقة';
        break;
      case 'income':
        creditPurpose = 'other_income';
        creditDescription = 'إيرادات أخرى';
        break;
      default: // 'sales', 'customer', or unspecified → receivables
        creditPurpose = 'receivables';
        creditDescription = 'تسوية عميل';
    }
    final creditCode = await accountingDao.getMappedAccountCode(
      creditPurpose,
      AccountingDao.accountPurposes[creditPurpose] ?? AccountingDao.accountPurposes['receivables']!,
    );
    final creditControlAccount = await accountingDao.getAccountByCode(creditCode);
    // For a customer receipt (the 'receivables' branch) route the credit
    // at the customer's sub-account so the receipt reduces that customer's
    // specific balance in the COA. Equity/loan/income buckets stay on the
    // mapped account — they have no party.
    final creditAccount = creditPurpose == 'receivables'
        ? await _resolvePartySubAccount(txn.partyId, creditControlAccount)
        : creditControlAccount;
    if (creditAccount == null) {
      // Fallback to receivables if mapped account not found
      final fallbackAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('receivables', AccountingDao.accountPurposes['receivables']!),
      );
      if (fallbackAccount == null) return null;
      final fallbackLines = <JournalLine>[
        JournalLine(accountId: assetAccount.id, debit: txn.amount, description: 'قبض'),
        JournalLine(accountId: fallbackAccount.id, credit: txn.amount + txn.discount, description: 'تسوية عميل'),
      ];
      // GAP-02 FIX: Settlement discount on receipt
      if (txn.discount > 0) {
        final discountAccount = await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('discount_allowed', AccountingDao.accountPurposes['discount_allowed']!),
        );
        if (discountAccount != null) {
          fallbackLines.add(JournalLine(accountId: discountAccount.id, debit: txn.discount, description: 'خصم مسموح به'));
        }
      }
      return accountingDao.createJournalEntry(
        description: 'قيود سند قبض ${txn.voucherNumber}',
        date: txn.createdAt,
        lines: fallbackLines,
        referenceType: 'receipt',
        referenceId: txn.id,
        isAutoPosted: true,
        costCenterId: costCenterId,
        branchId: branchId,
      );
    }

    // GAP-02 FIX: Settlement discount on receipt — full credit = amount + discount
    final receiptLines = <JournalLine>[
      JournalLine(
        accountId: assetAccount.id,
        debit: txn.amount,
        description: 'قبض',
      ),
      JournalLine(
        accountId: creditAccount.id,
        credit: txn.amount + txn.discount,
        description: creditDescription,
      ),
    ];
    if (txn.discount > 0) {
      final discountAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('discount_allowed', AccountingDao.accountPurposes['discount_allowed']!),
      );
      if (discountAccount != null) {
        receiptLines.add(JournalLine(
          accountId: discountAccount.id,
          debit: txn.discount,
          description: 'خصم مسموح به',
        ));
      }
    }

    return accountingDao.createJournalEntry(
      description: 'قيود سند قبض ${txn.voucherNumber}',
      date: txn.createdAt,
      lines: receiptLines,
      referenceType: 'receipt',
      referenceId: txn.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
    );
  }

  /// Auto-post a payment voucher (سند صرف)
  /// Debit: Supplier/Expense | Credit: Cash/Bank
  Future<int?> autoPostPayment(SafeTransactionData txn, {int? costCenterId}) async {
    if (txn.amount <= 0) return null;
    // Duplicate protection
    if (await hasAutoPostEntry('payment', txn.id)) return null;

    final safe = await (select(
      safes,
    )..where((s) => s.id.equals(txn.safeId))).getSingleOrNull();
    final branchId = safe?.branchId;
    // Determine which asset account (cash vs bank)
    Account? assetAccount;
    if (safe?.linkedAccountId != null) {
      assetAccount = await accountingDao.getAccountById(safe!.linkedAccountId!);
    }
    
    // Fallback to global mapping if safe has no linked account
    if (assetAccount == null) {
      final assetType = safe?.safeType == 'bank' ? 'bank' : 'cash';
      final defaultCode = safe?.safeType == 'bank'
          ? AccountingDao.accountPurposes['bank']!
          : AccountingDao.accountPurposes['cash']!;
      final assetCode = await accountingDao.getMappedAccountCode(assetType, defaultCode);
      assetAccount = await accountingDao.getAccountByCode(assetCode);
    }
    if (assetAccount == null) return null;

    // Determine debit account based on category
    String debitCode;
    switch (txn.category) {
      case 'purchase':
        debitCode = await accountingDao.getMappedAccountCode(
          'payables',
          AccountingDao.accountPurposes['payables']!,
        ); // Payables
        break;
      case 'salary':
      case 'salaries':
        debitCode = await accountingDao.getMappedAccountCode(
          'salary_expense',
          AccountingDao.accountPurposes['salary_expense']!,
        ); // Salary expense
        break;
      case 'employee_advance':
        debitCode = await accountingDao.getMappedAccountCode(
          'employee_advances',
          AccountingDao.accountPurposes['employee_advances']!,
        ); // Employee advances (asset)
        break;
      case 'expense':
        debitCode = await accountingDao.getMappedAccountCode(
          'misc_expense',
          AccountingDao.accountPurposes['misc_expense']!,
        ); // Miscellaneous
        break;
      default:
        debitCode = await accountingDao.getMappedAccountCode(
          'misc_expense',
          AccountingDao.accountPurposes['misc_expense']!,
        );
    }
    final debitControlAccount = await accountingDao.getAccountByCode(debitCode);
    // For supplier payments ('purchase' category → payables) route the debit
    // at the supplier's sub-account so their ledger card reflects it.
    // Salary/expense/advance categories have no party association.
    final debitAccount = (txn.category == 'purchase')
        ? await _resolvePartySubAccount(txn.partyId, debitControlAccount)
        : debitControlAccount;
    if (debitAccount == null) return null;

    // GAP-05 FIX: Settlement discount on payment — debit full payable = amount + discount
    final paymentLines = <JournalLine>[
      JournalLine(
        accountId: debitAccount.id,
        debit: txn.amount + txn.discount,
        description: txn.description ?? 'صرف',
      ),
      JournalLine(
        accountId: assetAccount.id,
        credit: txn.amount,
        description: 'صرف من ${safe?.name ?? "الصندوق"}',
      ),
    ];
    // Credit: Purchase discount earned (خصم مكتسب)
    if (txn.discount > 0) {
      final discountReceivedAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('discount_received', AccountingDao.accountPurposes['discount_received']!),
      );
      if (discountReceivedAccount != null) {
        paymentLines.add(JournalLine(
          accountId: discountReceivedAccount.id,
          credit: txn.discount,
          description: 'خصم مكتسب',
        ));
      }
    }

    return accountingDao.createJournalEntry(
      description: 'قيود سند صرف ${txn.voucherNumber}',
      date: txn.createdAt,
      lines: paymentLines,
      referenceType: 'payment',
      referenceId: txn.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
    );
  }
}
