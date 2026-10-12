// Accounting auto-post: cash sale (autoPostCashSale).
part of '../database.dart';

/// Accounting auto-post: cash sale (autoPostCashSale). (split from accounting_autopost_dao.dart - pure move).
extension AccountingAutopostCashSaleDao on AppDatabase {
  /// Auto-post a cash sale (مبيعات نقد فوري)
  /// Debit: Cash (total) | Credit: Sales (subtotal-discount) + VAT (tax)
  /// APG-04: IFRS 15.38 — defer revenue for undelivered delivery orders
  Future<int?> autoPostCashSale(
    SalesInvoiceData sale, {
    int? costCenterId,
    bool repostAfterReversal = false,
    int repostRevision = 0,
  }) async {
    // فاتورة مرتجع ماتترحّلش كبيعة — مهما كان اللي نداها.
    //
    // قيد المرتجع بيتخزّن بـ`referenceType = 'sales_return'`، وحارس التكرار
    // تحت بيدوّر على `'sale'` بس ⇒ ما بيشوفهوش. فالنداء بيضيف قيد بيعة
    // **بعكس اتجاه** قيد المرتجع: النقدية في الأستاذ بترجع صفر بينما الدرج
    // ناقص، والمخزون بيرجع صفر بينما الصنف رجع على الرف فعلاً، ويظهر إيراد
    // وهمي بقيمة المرتجع.
    //
    // المسار اللي كان بيعمل كده: `api_sales_handler.dart` بينده الدالة دي
    // بلا شرط بعد `createSalesInvoice` اللي بترحّل المرتجع جوّاها — أي
    // «المرتجع السريع» من البيع السريع في وضع client/mirror.
    if (sale.saleType == 'return') return null;
    if (sale.total <= 0) return null;
    // APG-04: Defer revenue for undelivered delivery orders
    if (sale.deliveryStatus != null &&
        sale.deliveryStatus != 'delivered' &&
        sale.deliveryStatus != '') {
      // GAP-22: Create deferred revenue entry instead of silently skipping
      // Dr Cash/Bank/Click + Dr Receivables (unpaid) / Cr Deferred Revenue (2133)
      return await _autoPostDeferredRevenue(sale, isCashSale: true);
    }
    // TOCTOU FIX: Wrap entire check+insert in a single transaction.
    // SQLite serialises write transactions, so two concurrent callers cannot
    // both pass the hasAutoPostEntry guard and both commit a JE.
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

    // Debit: Cash and/or Bank via the ACTUAL safe the receipt landed in
    // (Spec 136 ISS-13 — was the branch *default* safe, which mis-routed
    // branch sales to the admin cash account).
    final cashAccount = await _resolveSaleLegAccount(sale.id, branchId, 'cash');
    final bankAccount = await _resolveSaleLegAccount(sale.id, branchId, 'bank');
    // C2: the invoice's own «حساب المبيعات» wins over the mapped default;
    // NULL (every pre-v183 invoice, POS quick sale) keeps the mapping.
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
    if (salesAccount == null) return null;

    final lines = <JournalLine>[];
    // F-10 + Spec 136 (field fix 2026-06-04, invoice AQ-POS-1): derive the
    // sales-discount leg from the invoice's OWN arithmetic instead of trusting
    // the raw `discount` field. The server had stored an invoice whose
    // `subtotal` was already net of the discount (subtotal==total) yet still
    // carried discount=0.192; the old code credited Sales with the net
    // `subtotal` AND debited Sales-Discount the full 0.192, so the JE was off
    // by exactly the discount (debit 2.088 ≠ credit 1.896) → rejected → the
    // client retried ~40×, flooding the server.
    //
    // netRevenue = what the customer pays for goods (total minus tax and
    // delivery, each booked on its own leg). The discount leg is the gap
    // between the gross `subtotal` and that net revenue:
    //   • subtotal gross        → discountDebit == discount (unchanged)
    //   • subtotal already net  → discountDebit == 0 (no phantom leg)
    // salesCredit = netRevenue + discountDebit ⇒ debit == credit by
    // construction, whatever convention the upstream creator used.
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

    // P5 (Issue #6): Delivery-company sale routing.
    // When the sale was tagged with a delivery company AND no actual cash was
    // collected at POS, the customer is the delivery company itself — they
    // pay us later, not at point of sale. Route the debit through the
    // delivery company's party sub-account so:
    //   - The party's account statement shows the invoice as a receivable.
    //   - The new "Delivery Company Settlements" screen can settle it.
    //   - Cash drawer reports stay accurate (no phantom cash entries).
    final deliveryPartyId = await _resolveDeliveryCompanyPartyId(
      explicitPartyId: sale.deliveryCompanyPartyId,
      deliveryCompanyId: sale.deliveryCompanyId,
    );
    final isDeliveryCompanyBilling =
        deliveryPartyId != null &&
        sale.cashPaid == 0 &&
        sale.bankPaid == 0 &&
        sale.clickPaid == 0;

    if (isDeliveryCompanyBilling) {
      final receivableControl = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode(
          'receivables',
          AccountingDao.accountPurposes['receivables']!,
        ),
      );
      final deliveryAr = await _resolvePartySubAccount(
        deliveryPartyId,
        receivableControl,
      );
      if (deliveryAr != null) {
        lines.add(
          JournalLine(
            accountId: deliveryAr.id,
            debit: sale.total,
            description: 'مدينون شركة توصيل',
          ),
        );
      } else if (cashAccount != null) {
        // Fallback: party has no sub-account configured — keep the old
        // cash-debit behaviour rather than dropping the JE.
        lines.add(
          JournalLine(
            accountId: cashAccount.id,
            debit: sale.paid,
            description: 'نقدية',
          ),
        );
      }
    } else {
      // Existing cash/bank/click split logic — unchanged.
      if (sale.cashPaid > 0 && cashAccount != null) {
        lines.add(
          JournalLine(
            accountId: cashAccount.id,
            debit: sale.cashPaid,
            description: 'نقدية',
          ),
        );
      }
      if (sale.bankPaid > 0 && bankAccount != null) {
        lines.add(
          JournalLine(
            accountId: bankAccount.id,
            debit: sale.bankPaid,
            description: 'بنك/تحويل',
          ),
        );
      }
      if (sale.clickPaid > 0) {
        final clickAccount = await _resolveSaleLegAccount(sale.id, branchId, 'click');
        if (clickAccount != null) {
          lines.add(
            JournalLine(
              accountId: clickAccount.id,
              debit: sale.clickPaid,
              description: 'كليك/دفع إلكتروني',
            ),
          );
        }
      }
      if (sale.cashPaid == 0 && sale.bankPaid == 0 && sale.clickPaid == 0 && cashAccount != null) {
        lines.add(
          JournalLine(
            accountId: cashAccount.id,
            debit: sale.paid,
            description: 'نقدية',
          ),
        );
      }
    }

    // Debit receivable for ANY unpaid remainder — including a walk-in sale with
    // no customerId. Previously the leg was gated on `customerId != null`, so a
    // partial-cash sale to no customer credited full revenue+VAT but debited
    // only the cash paid → credits > debits → the whole JE dead-lettered. Book
    // the remainder to the receivables CONTROL account (mirrors the factory).
    // ⚠️ **وفرقُ التقريب يُطرَح قبل المقارنة — فهو ليس ديناً.**
    // بيعةٌ ١١٤٫٠٧ قُبض عنها ١١٤٫٠٥ كانت تفتح `Dr 1121 ذمم عملاء 0.02`
    // لزبونٍ عابرٍ بلا `customerId`، فيتراكم فتاتُ التقريب على حسابِ
    // **المراقبة** بلا حسابٍ فرعيٍّ يقابله — وتنكسر مطابقةُ المراقبة مع
    // مجموع الفرعيّات، وتبقى الفاتورةُ `pending`.
    final receivableDue = FinancialUtils.round(
      sale.total - sale.paid - sale.roundingAdjustment,
    );
    if (receivableDue > 0) {
      final controlAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode(
          'receivables',
          AccountingDao.accountPurposes['receivables']!,
        ),
      );
      // H5 · الباقي كان يقع على حساب **المراقبة** دائماً، حتى مع عميلٍ معروفٍ
      // له حسابٌ فرعيّ — بينما ثمانيةُ مواضعَ في هذا الملف تستعمل
      // `_resolvePartySubAccount`. فكشفُ حساب العميل من الأستاذ ينقصه دَينُه،
      // وتنكسر مطابقةُ المراقبة مع مجموع الفرعيات.
      // مقيس: بيعةُ ٥٠٠ سُدِّد منها ٣٠٠ ⇒ الحسابُ الفرعيّ صفرٌ بدل ٢٠٠.
      // والدالةُ ترجّع حسابَ المراقبة نفسَه حين لا عميلَ أو لا حسابَ فرعيّ،
      // فحالةُ الزبون العابر (‏سببُ وجود هذا الفرع أصلاً) لا تتغيّر.
      final receivableAccount =
          await _resolvePartySubAccount(sale.customerId, controlAccount);
      if (receivableAccount != null) {
        lines.add(
          JournalLine(
            accountId: receivableAccount.id,
            debit: receivableDue,
            description: 'مدينون',
          ),
        );
      }
    }

    // ── فرقُ تقريب الإجماليّ — سطرٌ صريحٌ لا فرقٌ مبتلَع ────────────────────
    //
    // `total` يبقى حقيقيّاً و`paid` مقرَّباً، والفرقُ يقع هنا على حسابه
    // الخاصّ `4319 فروق تقريب` — فيبقى `4121 مبيعات` و`2121 ض.ق.م` سليمَين
    // ويظهر التقريبُ في الأستاذ بسطرٍ يقرؤه المدقّق.
    //
    // ⚠️ **ولا يُترَك للموازن التلقائيّ.** سقفُ
    // `FinancialUtils.balanceToleranceMinorUnits` ٠٫٠١ ثابتاً، بينما أدنى
    // خطوةِ تقريبٍ (٥ قروش) تعطي فرقاً أقصاه ٠٫٠٢٥ — و٢٥ قرشاً تعطي ٠٫١٢٥،
    // والجنيهُ ٠٫٥٠. أي **فوق السقف دائماً** فيُرمى القيدُ كلُّه بـ«المدين
    // لا يساوي الدائن»، وقد خرج المخزونُ ودخل النقدُ الدرجَ فعلاً.
    // السطرُ الصريحُ هنا يجعل القيدَ متوازناً **قبل** أن يبلغ الموازنَ أصلاً،
    // فلا ازدواجَ تصحيحٍ كذلك.
    JournalEntryDiagnostics.lastPolicyRounding = sale.roundingAdjustment;
    if (sale.roundingAdjustment != 0) {
      final roundingAccount =
          await accountingDao.getLeafAccountByPurpose('rounding_difference');
      if (roundingAccount != null) {
        final adj = sale.roundingAdjustment;
        lines.add(
          JournalLine(
            accountId: roundingAccount.id,
            // موجبٌ = قُرِّب هبوطاً (‏قُبض أقلّ) ⇒ مدين.
            // سالبٌ = قُرِّب صعوداً (‏قُبض أكثر) ⇒ دائن.
            debit: adj > 0 ? adj : 0,
            credit: adj < 0 ? -adj : 0,
            description: 'فروق تقريب',
          ),
        );
      } else {
        // `4319` مضمونٌ بالشفاء الذاتيِّ كلَّ إقلاع، فهذا الفرعُ دفاعيٌّ
        // بحت — لكنّ صمتَه كان سيُنتج قيداً غيرَ متوازنٍ يُرمى بلا سبب.
        unawaited(DiagnosticLogger.log(
            'AUTOPOST-WARN',
            'sale #${sale.id}: rounding_difference account UNMAPPED — '
            'adj=${sale.roundingAdjustment} has no leg. Map '
            'rounding_difference in الربط المحاسبي.'));
      }
    }

    // Credit: Sales revenue (computed upfront — F-10)
    lines.add(
      JournalLine(
        accountId: salesAccount.id,
        credit: salesCreditAmount,
        description: 'مبيعات',
      ),
    );

    // Credit: VAT if applicable
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
    // discountDebit is the gross→net gap (Spec 136); when subtotal is already
    // net it is 0 and no contra-revenue leg is posted.
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

    if (lines.isEmpty) return null;

    // COGS Entry (IAS 2.34): Dr 5101 تكلفة البضاعة المباعة / Cr 1103 المخزون
    // Reject zero-cost tracked lines unless a BOM consumption row supplies
    // their cost from the raw materials consumed for that line.
    final trackedRows = await customSelect(
      'SELECT sii.product_id, sii.quantity, sii.cost_price, p.track_inventory, p.name '
      'FROM sales_invoice_items sii '
      'JOIN products p ON p.id = sii.product_id '
      'WHERE sii.invoice_id = ? AND sii.id NOT IN ('
      'SELECT sale_invoice_item_id FROM sale_bom_consumptions '
      'WHERE sale_invoice_id = ? AND reversed_by_return_id IS NULL)',
      variables: [Variable(sale.id), Variable(sale.id)],
      readsFrom: {salesInvoiceItems, products, saleBomConsumptions},
    ).get();
    final zeroCostTracked = trackedRows.where((r) {
      final tv = r.data['track_inventory'];
      final tracks = tv == true || tv == 1; // PG returns bool, SQLite returns int
      final cp = (r.data['cost_price'] as num?)?.toDouble() ?? 0.0;
      return tracks && cp <= 0;
    }).toList();
    if (zeroCostTracked.isNotEmpty) {
      final names = zeroCostTracked.map((r) => r.data['name'] as String? ?? '#${r.data['product_id']}').join('، ');
      final policy = (await getSettingValue('zero_cost_policy')) ?? 'warn';
      if (policy == 'block') {
        throw Exception(
          'تعذّر ترحيل الفاتورة ${sale.invoiceNumber}: '
          'الأصناف التالية متعقّبة للمخزون وتكلفتها صفر — $names. '
          'لا يمكن ترحيل إيراد بدون تكلفة مقابلة.',
        );
      }
      if (policy == 'warn') {
        for (final row in zeroCostTracked) {
          await DiagnosticLogger.logZeroCostSale(
            invoiceId: sale.id,
            invoiceNumber: sale.invoiceNumber,
            productId: (row.data['product_id'] as num).toInt(),
            quantity: (row.data['quantity'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }
    }

    // A BOM item sold with auto-deplete has its cost in the RAW MATERIALS that
    // left stock, not in `sales_invoice_items.cost_price` (the finished good
    // usually carries 0 — no production order ever stamped a WAC on it).
    // Reading `sale_bom_consumptions` — written by applyAutoDepleteForSale in
    // this same transaction — is what makes the server path see that cost.
    //
    // Sourced from the table rather than threaded through a parameter on
    // purpose: autoPostCashSale has five call sites (API handler, deferred
    // revenue, two repair paths, the delivery flow) and none of them has the
    // breakdown in hand. Reading it here fixes all five, and the repair path
    // can retro-fix already-posted invoices.
    final autoDepleteRow = await customSelect(
      'SELECT COALESCE(SUM(consumed_qty * unit_cost_at_sale), 0) AS total '
      'FROM sale_bom_consumptions '
      'WHERE sale_invoice_id = ? AND reversed_by_return_id IS NULL',
      variables: [Variable(sale.id)],
      readsFrom: {saleBomConsumptions},
    ).getSingle();
    final autoDepleteCogs =
        (autoDepleteRow.data['total'] as num?)?.toDouble() ?? 0.0;

    final cogsTotal = await customSelect(
      // SAL-1: quantity is in SALE units, cost_price is per BASE unit (WAC).
      // quantity_in_base converts sale-unit qty to physical base-unit qty —
      // without it, COGS is understated on every carton/box (non-base-unit) sale.
      //
      // Lines already covered by a consumption row are excluded: their cost is
      // the raw materials above, and counting both would expense the goods
      // twice for a tracked finished item that does carry a book cost.
      'SELECT COALESCE(SUM(quantity * quantity_in_base * cost_price), 0) as total '
      'FROM sales_invoice_items WHERE invoice_id = ? AND id NOT IN ('
      '  SELECT sale_invoice_item_id FROM sale_bom_consumptions '
      '  WHERE sale_invoice_id = ? AND reversed_by_return_id IS NULL)',
      variables: [Variable(sale.id), Variable(sale.id)],
      readsFrom: {salesInvoiceItems, saleBomConsumptions},
    ).getSingle();
    final cogsAmount = (cogsTotal.data['total'] as num?)?.toDouble() ?? 0.0;

    // Gate on the COMBINED cost. Gating on `cogsAmount` alone dropped the whole
    // block for an all-BOM sale, leaving Dr Cash / Cr Sales — balanced, so no
    // validator fired, while the raw materials really had left stock. The
    // return path (`effectiveCogs`) always credited that cost back, so
    // sell-then-return inflated the inventory account permanently.
    final totalCogs = cogsAmount + autoDepleteCogs;
    if (totalCogs > 0.001) {
      final cogsAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cogs', AccountingDao.accountPurposes['cogs']!),
      );
      final inventoryAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
      );
      if (cogsAccount != null && inventoryAccount != null) {
        lines.add(JournalLine(
          accountId: cogsAccount.id,
          debit: totalCogs,
          description: 'تكلفة بضاعة مباعة',
        ));
        lines.add(JournalLine(
          accountId: inventoryAccount.id,
          credit: totalCogs,
          description: 'تخفيض مخزون',
        ));
      }
    }

    // Spec 135 — deterministic JE globalId for the base sale JE. sourceGid is
    // the invoice's shared globalId so the client-posted and server-posted JE
    // for ONE invoice converge on the same id (the journal_entries.globalId
    // UNIQUE index dedups on next DeltaPull). Falls back to invid<localId> when
    // the invoice has no globalId yet (legacy/standalone) — same-instance
    // unique, degraded cross-instance, matching the saleret/purret pattern.
    final saleSourceGid = sale.globalId ?? 'invid${sale.id}';
    final saleJeGid = JournalEntryGid.computeAndLog(
      sourceType: JournalEntryGid.sourceSale,
      sourceGid: saleSourceGid,
      verb: repostAfterReversal ? 'repost$repostRevision' : 'post',
      invId: sale.id,
      suffix: repostAfterReversal ? ' (cash repost $repostRevision)' : ' (cash)',
    );
    final jeId = await accountingDao.createJournalEntry(
      description: 'قيود مبيعات بيع ${sale.invoiceNumber}',
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

    // ISS-004: Lock sales invoice after successful autopost to prevent
    // retroactive edits that would cause GL/invoice discrepancy.
    if (jeId != 0) {
      try {
        await (update(salesInvoices)..where((i) => i.id.equals(sale.id))).write(
          const SalesInvoicesCompanion(isLocked: Value(true)),
        );
      } catch (e) {
        debugPrint('[AUTOPOST-LOCK] Failed to lock cash sale #${sale.id}: $e');
      }
    }
    return jeId;
    }); // end TOCTOU-safe transaction
  }
}
