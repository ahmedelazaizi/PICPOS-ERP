// =======================================================================
// ACCOUNTING AUTO-POSTING DAO
// Extracted from accounting_dao.dart - Sprint 12 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Accounting Auto-Posting operations
/// تاريخ ترحيل قيد المرتجع.
///
/// ── العطل اللي الدالة دي موجودة عشانه ───────────────────────────────────────
/// القيد كان بيتسجّل بـ`originalInvoice.invoiceDate` — تاريخ **الفاتورة
/// الأصلية**. أثرين:
///
/// ١. إعادة تشكيل فترة منتهية: مرتجع أغسطس بيقلّل إيراد مارس ويعكس تكلفة
///    مارس، فقائمة دخل مارس اللي اتطبعت واتقدّمت للضرايب بتتغيّر بأثر رجعي،
///    وأغسطس بيظهر مبيعات بلا مرتجعات.
///
/// ٢. قفل كامل للمرتجعات: `createJournalEntry` بينادي
///    `validateFinancialPeriod(date)`، فأول ما الشهر القديم يتقفل أي مرتجع
///    لفواتيره **بيترفض تماماً** — والمستدعي عكس المخزون والخزنة جوه نفس
///    الترانزاكشن، فالعملية كلها بترجع والكاشير مش قادر يعمل مرتجع مشروع.
///
/// المرتجع **حدث لاحق** له فترته الخاصة مش تعديل على المستند الأصلي.
///
/// `null` بيقع على تاريخ الفاتورة عشان المسارات اللي لسه ما بتمرّرش تاريخ
/// تفضل شغّالة بسلوكها القديم — الانتقال تدريجي مش كسر.
@visibleForTesting
DateTime resolveReturnPostingDate({
  required DateTime? returnDate,
  required DateTime originalInvoiceDate,
}) =>
    returnDate ?? originalInvoiceDate;

extension AccountingAutopostDao on AppDatabase {

  /// Spec 136 — shared derivation of the balanced primary + discount legs for
  /// the three auto-post paths (cash sale, credit sale, purchase). Extracted
  /// verbatim from the formerly-triplicated block; **no value change** — the
  /// arithmetic and the AUTOPOST-WARN emission are identical to the inline code.
  ///
  /// Returns the rounded `primaryLeg` (Sales credit on the sales side /
  /// Inventory debit on the purchase side) and `discountLeg` (sales-discount
  /// debit / purchase-discount credit), both derived from the invoice's OWN
  /// arithmetic so the JE balances by construction whether the upstream
  /// `subtotal` was gross or already net of discount (AQ-POS-1 repro: a poison
  /// invoice with subtotal==total + non-zero discount imbalanced by exactly the
  /// discount and dead-lettered, flooding the server with retries).
  ///
  /// VAT/delivery amounts are only subtracted from the net when their account
  /// is mapped (so they will actually be posted on their own leg); when
  /// unmapped, the amount stays folded into the primary leg to keep the JE
  /// balanced, and [unmappedVatWarning] is logged. Purchase callers pass
  /// `deliveryFee: 0` / `deliveryAccount: null` (no separately-booked delivery).
  ({double primaryLeg, double discountLeg}) _deriveBalancedLegs({
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required double deliveryFee,
    required Account? vatAccount,
    required Account? deliveryAccount,
    required Account? discountAccount,
    required String unmappedVatWarning,
  }) {
    final vatLeg = (tax > 0 && vatAccount != null) ? tax : 0.0;
    final deliveryLeg =
        (deliveryFee > 0 && deliveryAccount != null) ? deliveryFee : 0.0;
    if (tax > 0 && vatAccount == null) {
      unawaited(DiagnosticLogger.log('AUTOPOST-WARN', unmappedVatWarning));
    }
    final net = total - vatLeg - deliveryLeg;
    final rawDiscount =
        (discount > 0 && discountAccount != null) ? (subtotal - net) : 0.0;
    final discountLeg = rawDiscount > 0
        ? double.parse(rawDiscount.toStringAsFixed(AppConstants.decimalPlaces))
        : 0.0;
    final primaryLeg = double.parse(
        (net + discountLeg).toStringAsFixed(AppConstants.decimalPlaces));
    return (primaryLeg: primaryLeg, discountLeg: discountLeg);
  }

  /// Helper to resolve branch-specific safe account vs global mapped account
  Future<Account?> _resolveBranchSafeAccount(int? branchId, String type, String fallbackPurpose) async {
    if (branchId != null) {
      // P2: branch-level safe
      final branchSafe = await (select(safes)
            ..where((s) =>
                s.branchId.equals(branchId) &
                s.safeType.equals(type) &
                s.isActive.equals(true))
            ..orderBy([(s) => OrderingTerm(expression: s.isDefault, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();

      if (branchSafe?.linkedAccountId != null) {
        return accountingDao.getAccountById(branchSafe!.linkedAccountId!);
      }

      // P2b: region-level safe — branch exists but has no matching safe
      final branchRow = await (select(branches)..where((b) => b.id.equals(branchId))..limit(1)).getSingleOrNull();
      if (branchRow?.regionId != null) {
        Safe? targetSafe = await (select(safes)
              ..where((s) =>
                  s.regionId.equals(branchRow!.regionId!) &
                  s.safeType.equals(type) &
                  s.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();
        if (targetSafe != null) {
          debugPrint('[SafeRoute] P2b: region safe #${targetSafe.id} for region #${branchRow!.regionId}');
          if (targetSafe.linkedAccountId != null) {
            return accountingDao.getAccountById(targetSafe.linkedAccountId!);
          }
        }
      }
    }

    // P3: system default
    final fallbackCode = await accountingDao.getMappedAccountCode(fallbackPurpose, AccountingDao.accountPurposes[fallbackPurpose]!);
    return accountingDao.getAccountByCode(fallbackCode);
  }

  /// Spec 136 ISS-13: resolve the GL account for a sale's payment leg from the
  /// ACTUAL safe the receipt landed in, not the branch's *default* safe.
  ///
  /// Field incident: a branch (Aqaba) cash sale autoposted its cash debit to
  /// the ADMIN cash account (111-00001) instead of the branch cash safe
  /// (111-00003). Root cause: [_resolveBranchSafeAccount] picks the branch's
  /// first *default* active safe of the type and returns its `linkedAccountId`;
  /// when that default safe has a NULL link it gives up and falls through to the
  /// global mapped account — even though the safe the cash physically went into
  /// (recorded in `safe_transactions` by `_recordSalesReceipt`) IS linked.
  /// Shift-close was already branch-correct because it resolves the account from
  /// the actual safe (like `autoPostReceipt`); only the sale autopost wasn't.
  ///
  /// Resolution order:
  ///   1. The safe of [safeType] referenced by this sale's receipt row(s) in
  ///      `safe_transactions` → its `linkedAccountId`. This works on every
  ///      posting path (POS, server sync, failed-autopost repair) and is immune
  ///      to client/server id-drift because the receipt row was written
  ///      server-side with the server's own safe id.
  ///   2. Fallback to the previous branch-default resolution
  ///      ([_resolveBranchSafeAccount]) when the sale has no recorded safe of
  ///      that type (e.g. a repaired sale whose receipt row never landed) or
  ///      that safe has no linked account.
  Future<Account?> _resolveSaleLegAccount(
    int saleId,
    int? branchId,
    String safeType,
  ) async {
    final row = await (select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
          ..where(safeTransactions.referenceType.equals('sales_invoice') &
              safeTransactions.referenceId.equals(saleId) &
              safeTransactions.transactionType.equals('receipt') &
              safes.safeType.equals(safeType))
          ..limit(1))
        .getSingleOrNull();
    if (row != null) {
      final safe = row.readTable(safes);
      if (safe.linkedAccountId != null) {
        final acct = await accountingDao.getAccountById(safe.linkedAccountId!);
        if (acct != null) return acct;
      }
    }
    // Fallback: previous branch-default behaviour.
    return _resolveBranchSafeAccount(branchId, safeType, safeType);
  }

  /// Resolve the effective AR/AP account for a given party.
  ///
  /// Every party row (created via [PartyDao.createParty]) is paired with a
  /// dedicated sub-account under the control parent (1121-XXXXX for AR /
  /// 2111-XXXXX for AP, both seeded by seedChartOfAccounts) and linked via
  /// `parties.accountId`. Routing journal lines through that sub-account
  /// is what makes per-party balances visible in the Chart of Accounts
  /// tree and the General Ledger drill-down — the `LIKE '1121%'` rollup
  /// in `getAccountLedger` then aggregates
  /// all customer sub-accounts under their parent, and each customer shows
  /// its own balance in the COA.
  ///
  /// Prior behaviour posted every AR/AP line straight at the parent control
  /// account, so party sub-accounts always read 0 in the ledger even though
  /// `parties.balance` was correctly maintained.
  ///
  /// Falls back to [fallbackControl] when the party has no linked account
  /// (e.g. legacy data or system parties without a sub-account).
  Future<Account?> _resolvePartySubAccount(int? partyId, Account? fallbackControl) async {
    if (partyId == null) return fallbackControl;
    final party = await (select(parties)..where((p) => p.id.equals(partyId))..limit(1))
        .getSingleOrNull();
    if (party?.accountId == null) return fallbackControl;
    final sub = await accountingDao.getAccountById(party!.accountId!);
    return sub ?? fallbackControl;
  }

  /// P5 (Issue #6): Resolve a `parties` row that represents the given delivery
  /// company so the receivable is posted to a real ledger account instead of
  /// going into a generic cash bucket. Resolution order:
  ///   1. Sale's `deliveryCompanyPartyId` (explicit FK, if populated).
  ///   2. parties.name == delivery_companies.name AND is_delivery_company=true.
  /// Returns null when no matching party exists — caller falls back to the
  /// previous cash-debit behaviour so the JE still posts.
  Future<int?> _resolveDeliveryCompanyPartyId({
    int? explicitPartyId,
    int? deliveryCompanyId,
  }) async {
    if (explicitPartyId != null) {
      final exists = await (select(parties)
            ..where((p) => p.id.equals(explicitPartyId))
            ..limit(1))
          .getSingleOrNull();
      if (exists != null) return exists.id;
    }
    if (deliveryCompanyId == null) return null;
    final company = await (select(deliveryCompanies)
          ..where((d) => d.id.equals(deliveryCompanyId))
          ..limit(1))
        .getSingleOrNull();
    if (company == null) return null;
    final party = await (select(parties)
          ..where((p) =>
              p.name.equals(company.name) & p.isDeliveryCompany.equals(true))
          ..limit(1))
        .getSingleOrNull();
    return party?.id;
  }

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
    final salesAccount = await accountingDao.getAccountByCode(
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
    // Reject the invoice if any tracked item has cost_price <= 0 — posting
    // revenue without COGS overstates profit and breaks trial-balance reporting.
    final trackedRows = await customSelect(
      'SELECT sii.product_id, sii.cost_price, p.track_inventory, p.name '
      'FROM sales_invoice_items sii '
      'JOIN products p ON p.id = sii.product_id '
      'WHERE sii.invoice_id = ?',
      variables: [Variable(sale.id)],
      readsFrom: {salesInvoiceItems, products},
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
        debugPrint('[ZeroCost] فاتورة ${sale.invoiceNumber}: أصناف متعقبة بتكلفة '
            'صفر — $names. الإيراد يُرحّل بدون COGS لهذه الأصناف.');
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
    final salesAccount = await accountingDao.getAccountByCode(
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
      'SELECT sii.product_id, sii.cost_price, p.track_inventory, p.name '
      'FROM sales_invoice_items sii '
      'JOIN products p ON p.id = sii.product_id '
      'WHERE sii.invoice_id = ?',
      variables: [Variable(sale.id)],
      readsFrom: {salesInvoiceItems, products},
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
        debugPrint('[ZeroCost] فاتورة ${sale.invoiceNumber}: أصناف متعقبة بتكلفة '
            'صفر — $names. الإيراد يُرحّل بدون COGS لهذه الأصناف.');
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

    final inventoryAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
    );
    final inputVatAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('input_vat', AccountingDao.accountPurposes['input_vat']!),
    );
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

    final salesReturnAccount = await accountingDao.getAccountByCode(
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

  /// Auto-post an operational expense (مصروفات تشغيلية) — IAS 1.99
  /// Dr: Expense Account | Cr: Cash or Bank (F-12: based on paymentMethod)
  Future<int?> autoPostOperationalExpense({
    required int expenseId,
    required double amount,
    required String description,
    required String expenseAccountCode,
    int? costCenterId,
    int? branchId, // Added branchId
    DateTime? date,
    String? paymentMethod, // F-12: 'cash', 'bank', or null (default: cash)
  }) async {
    if (amount <= 0) return null;
    if (await hasAutoPostEntry('op_expense', expenseId)) return null;

    // F-12: Resolve credit account based on payment method
    final creditPurpose = (paymentMethod == 'bank') ? 'bank' : 'cash';
    final creditCode = await accountingDao.getMappedAccountCode(
      creditPurpose,
      AccountingDao.accountPurposes[creditPurpose]!,
    );
    Account? creditAccount = await accountingDao.getAccountByCode(creditCode);
    if (creditAccount == null) {
      // Self-heal: re-seed the standard chart of accounts (same recovery
      // treasury_dao.dart uses for its cash account) then retry once.
      await accountingDao.syncDefaultAccounts();
      creditAccount = await accountingDao.getAccountByCode(creditCode);
    }
    // Last-resort: leaf-safe purpose lookup, in case the seed's code
    // changed under a customised CoA.
    creditAccount ??= await accountingDao.getLeafAccountByPurpose(creditPurpose);

    // EXP-1: expenseAccountCode comes from the category row and may be
    // stale/legacy (the old '5299' default — see createExpenseCategory —
    // which the seed never creates). Previously an unresolved code here
    // made this whole method silently `return null`: the op_expenses row
    // stayed committed with NO journal entry, so the expense vanished from
    // the GL/P&L while the UI reported success. Never do that again — fall
    // back to the dedicated 'op_expenses' purpose mapping (default '6214',
    // the same account journal_entry_factory.dart's shift-closing path
    // resolves to), self-healing the seed first if even that is missing.
    Account? expenseAccount =
        await accountingDao.getAccountByCode(expenseAccountCode);
    expenseAccount ??=
        await accountingDao.getLeafAccountByPurpose('op_expenses');
    if (expenseAccount == null) {
      await accountingDao.syncDefaultAccounts();
      expenseAccount = await accountingDao.getLeafAccountByPurpose('op_expenses');
    }

    if (creditAccount == null || expenseAccount == null) {
      // Fail LOUD instead of dropping the JE: the op_expenses row (already
      // committed by the caller) must never end up with no GL entry and no
      // signal to the operator. The caller (opex_record_edit_dialog.dart)
      // lets this propagate instead of swallowing it behind a success toast.
      throw Exception(
        'تعذّر ترحيل المصروف التشغيلي #$expenseId إلى دفتر الأستاذ: '
        '${expenseAccount == null ? 'حساب المصروف ($expenseAccountCode)' : 'حساب الصندوق/البنك'} '
        'غير موجود في الدليل المحاسبي. يرجى مراجعة إعدادات الحسابات ← ربط الحسابات.',
      );
    }

    // B13 (EXP-5 / S-EXP-REST): branch consistency between the op_expenses
    // row and its JE. This USED to borrow the branch of an ARBITRARY
    // first-matching safe of `creditPurpose` type (`.limit(1)`, no ordering,
    // no relation to the actual expense) whenever the caller passed
    // branchId == null — which is exactly what the opex dialog's default
    // "كل الفروع" selection does. That made the JE land on whichever safe
    // happened to sort first, while the op_expenses row itself stayed
    // branch_id = NULL — the row and its JE silently disagreed on branch.
    // Never borrow a branch the caller didn't ask for. When branchId is null
    // we pass null through; createJournalEntry then applies its own canonical
    // Spec-108 fallback (the lowest-id active branch — a JE must carry a
    // branch to be reportable, so the JE does NOT stay null). The op_expenses
    // row keeps whatever the caller set (may be null); row-null / JE-fallback
    // is intended and now deterministic, instead of tied to whichever safe
    // happened to sort first.
    final resolvedBranchId = branchId;

    final creditLabel = creditPurpose == 'bank' ? 'بنك' : 'نقدي';
    return accountingDao.createJournalEntry(
      description: 'مصروف تشغيلي: $description',
      date: date ?? DateTime.now(),
      lines: [
        JournalLine(accountId: expenseAccount.id, debit: amount, description: description),
        JournalLine(accountId: creditAccount.id, credit: amount, description: 'دفع مصروف تشغيلي ($creditLabel)'),
      ],
      referenceType: 'op_expense',
      referenceId: expenseId,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: resolvedBranchId, // Standardized branch propagation
    );
  }

  /// Auto-post a purchase return (مرتجعات مشتريات) — IAS 2
  /// Dr: Payables (or Cash) | Cr: Inventory
  /// Dr: Output refund on Input VAT (if applicable)
  Future<int?> autoPostPurchaseReturn({
    required PurchaseInvoiceData originalPurchase,
    /// تاريخ حدث المرتجع. `null` = السلوك القديم (تاريخ الفاتورة الأصلية).
    DateTime? returnDate,
    required double returnAmount,
    double vatAmount = 0,
    int? costCenterId,
    // B8 (S-LANDED-LIFECYCLE / PRET-1): per-return-event discriminator —
    // callers pass the return's own sequential voucher number (e.g. from
    // `generateInvoiceNumber('PRET-')`), minted once per return call. It is
    // reproduced identically on a genuine retry of a rolled-back attempt
    // (the counter row rolls back with the failed transaction, so the retry
    // draws the SAME number), which is what keeps a true retry of the same
    // return event deduping. Threading it into the key stops two DISTINCT
    // partial returns of the SAME amount on one invoice from colliding —
    // previously the key was `invoiceId + amount` alone, so the second
    // return's JE was silently skipped by hasAutoPostEntry while its
    // stock/WAC/AP mutations had already been applied for real. Falls back
    // to the amount-only key if omitted (keeps any other caller compiling
    // with unchanged behaviour).
    String? returnEventId,
    // B9 (S-RETURNS-ACCURACY / PRET-2): optional AP/cash split. Both
    // callers (_processPurchaseReturnBody in purchases_repository_impl.dart
    // and postPurchaseReturn/postPurchaseReturnEdit in api_purchase_handler.dart)
    // already compute this split on the GROSS (VAT-inclusive) refund —
    //   grossReturnAmount = returnAmount + vatAmount
    //   apPortion         = grossReturnAmount.clamp(0, oldRemaining)   // unpaid portion
    //   cashPortion       = grossReturnAmount - apPortion              // paid portion
    // so `apPortion + cashPortion` sums to EXACTLY `returnAmount + vatAmount`
    // by construction — no separate VAT proration is needed here; the VAT
    // simply rides along with whichever leg(s) the caller's split assigned
    // it to. When BOTH are omitted (other/legacy callers), the original
    // single-lump behaviour keyed on paymentMethod is preserved unchanged.
    double? apPortion,
    double? cashPortion,
    /// سببُ المردود من القائمة الثابتة — يُكتب في `PurchaseReturns.reason`.
    ///
    /// ⚠️ **وموضعُ كتابته هنا لا في المنادي:** هذه الدالّةُ هي القُمعُ
    /// الوحيدُ الذي تمرّ به المساراتُ الثلاث، وهي عينُ من يكتب صفَّ
    /// المستند أصلاً — فسببٌ يُمرَّر ولا يُكتب يصير حقلاً ميّتاً من جديد.
    String? reason,
  }) async {
    if (returnAmount <= 0) return null;
    // F-04 / F-02 (Spec 151): key the return JE by the ORIGINATING invoice id
    // (the SAME id the stock/safe rows and the edit-reverse query use) instead
    // of a hash. The old hash forced _reversePurchaseReturn (and the server's
    // postPurchaseReturnEdit) to fall back to a `description LIKE '%فاتورة
    // {number}%'` match, which cross-reversed substring-colliding invoices
    // (editing "12" also reversed "120"'s return JE and flipped its
    // isAutoPosted). Per-event uniqueness is carried by the deterministic
    // globalId below, so 'purchase_return' is exempt from createJournalEntry's
    // (refType,refId) dedup.
    final String eventDiscriminator =
        (returnEventId != null && returnEventId.isNotEmpty)
            ? returnEventId
            : returnAmount.toStringAsFixed(AppConstants.decimalPlaces);
    final returnKey = '${originalPurchase.id}_$eventDiscriminator'.hashCode.abs();
    // Deterministic JE globalId — dedup guard + journal_entries.globalId (UNIQUE).
    final purretSourceGid =
        '${originalPurchase.globalId ?? 'pinvid${originalPurchase.id}'}rk$returnKey';
    final jeGid = JournalEntryGid.computeAndLog(
      sourceType: JournalEntryGid.sourcePurchaseReturn,
      sourceGid: purretSourceGid,
      verb: 'post',
      invId: originalPurchase.id,
    );
    if (await _hasAutoPostEntryByGlobalId(jeGid)) return null;

    // Resolve Branch from Warehouse
    final warehouse = await (select(warehouses)..where((w) => w.id.equals(originalPurchase.warehouseId))).getSingleOrNull();
    final branchId = warehouse?.branchId;

    final payableControlAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('payables', AccountingDao.accountPurposes['payables']!),
    );
    // Route the AP debit to the supplier's sub-account so their ledger
    // card shows the refund (returns to the control account still roll up
    // correctly via the `LIKE '2101%'` aggregation in getAccountLedger).
    final payableAccount = await _resolvePartySubAccount(
      originalPurchase.supplierId,
      payableControlAccount,
    );
    final inventoryAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
    );
    final cashAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!),
    );
    // B8 (S-LANDED-LIFECYCLE / PRET-1): this used to `return null` — silently
    // skipping the JE — while the caller (_processPurchaseReturnBody /
    // api_purchase_handler.postPurchaseReturn) had ALREADY reversed stock,
    // rebalanced WAC, and adjusted the supplier's AP/cash inside the SAME
    // open transaction. A missing inventory-account mapping left the return
    // half-applied: real stock/AP effect, zero GL trace. Throwing here rolls
    // the whole enclosing transaction back (R3) instead of shipping a silent
    // financial gap.
    if (inventoryAccount == null) {
      throw StateError(
        'تعذّر ترحيل قيد مرتجع المشتريات — حساب المخزون غير مربوط في دليل '
        'الحسابات. يرجى ربط حساب المخزون من إعدادات الحسابات المحاسبية '
        'قبل تنفيذ مرتجع المشتريات.',
      );
    }

    final lines = <JournalLine>[];

    // Debit: Payables or Cash (reducing what we owe or getting cash back)
    if (apPortion != null || cashPortion != null) {
      // B9 (PRET-2): split refund — see param doc above for the
      // reconciliation rule. Skip a leg whose portion is 0 (e.g. a fully
      // unpaid invoice has cashPortion == 0, a fully paid one has
      // apPortion == 0).
      final ap = apPortion ?? 0;
      final cash = cashPortion ?? 0;
      if (ap > 0) {
        if (payableAccount == null) {
          throw StateError(
            'تعذّر ترحيل قيد مرتجع المشتريات — حساب الذمم الدائنة غير مربوط '
            'في دليل الحسابات. يرجى ربط حساب الموردين من إعدادات الحسابات '
            'المحاسبية قبل تنفيذ مرتجع المشتريات.',
          );
        }
        lines.add(JournalLine(
          accountId: payableAccount.id,
          debit: ap,
          description: 'تخفيض ذمم الموردين',
        ));
      }
      if (cash > 0) {
        if (cashAccount == null) {
          throw StateError(
            'تعذّر ترحيل قيد مرتجع المشتريات — حساب النقدية غير مربوط في '
            'دليل الحسابات. يرجى ربط حساب النقدية من إعدادات الحسابات '
            'المحاسبية قبل تنفيذ مرتجع المشتريات.',
          );
        }
        lines.add(JournalLine(
          accountId: cashAccount.id,
          debit: cash,
          description: 'استرداد نقدي مرتجع مشتريات',
        ));
      }
    } else if (originalPurchase.paymentMethod == 'cash' && cashAccount != null) {
      lines.add(JournalLine(
        accountId: cashAccount.id,
        debit: returnAmount + vatAmount,
        description: 'استرداد نقدي مرتجع مشتريات',
      ));
    } else if (payableAccount != null) {
      lines.add(JournalLine(
        accountId: payableAccount.id,
        debit: returnAmount + vatAmount,
        description: 'تخفيض ذمم الموردين',
      ));
    }

    // Resolve Input-VAT up front. When it isn't mapped we FOLD the VAT into the
    // inventory credit so credits still == the gross debit (cash/payable carry
    // returnAmount+vatAmount) — otherwise the entry is short by vatAmount and
    // hard-fails, blocking the return. Symmetric with the original purchase.
    final inputVatAccount = vatAmount > 0
        ? await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('input_vat', AccountingDao.accountPurposes['input_vat']!),
          )
        : null;

    // Credit: Inventory (returning goods reduces our inventory)
    lines.add(JournalLine(
      accountId: inventoryAccount.id,
      credit: (vatAmount > 0 && inputVatAccount == null)
          ? returnAmount + vatAmount
          : returnAmount,
      description: 'مرتجع مشتريات — تخفيض مخزون',
    ));

    // Credit: Input VAT reversal (if applicable)
    if (vatAmount > 0 && inputVatAccount != null) {
      lines.add(JournalLine(
        accountId: inputVatAccount.id,
        credit: vatAmount,
        description: 'عكس ضريبة مدخلات مرتجع',
      ));
    }

    if (lines.isEmpty) return null;

    // المرتجع حدث لاحق له فترته الخاصة — مش تعديل على المستند الأصلي.
    final postingDate = resolveReturnPostingDate(
      returnDate: returnDate,
      originalInvoiceDate: originalPurchase.invoiceDate,
    );

    // ── §٦‑٢: مستندُ المرتجع — الطرفُ الثاني في تسوية ض.ق.م ────────────────
    //
    // كان مرتجعُ الشراء بلا صفٍّ في أيِّ جدولِ مستندات، فتسويةُ ض.ق.م تشتقُّ
    // ضريبتَه **من الأستاذ نفسِه** ⇒ الطرفان يقرآن مصدراً واحداً ويتّفقان
    // بالبناء، فلا يُطابَق هذا المكوِّنُ مطابقةً مستقلّة.
    //
    // ⚠️ **وموضعُه هنا لا في مُنادٍ** — بعد حارس `_hasAutoPostEntryByGlobalId`
    //    مباشرةً: `autoPostPurchaseReturn` هو القُمعُ الوحيدُ الذي تمرُّ به
    //    المسارات الثلاثة (`purchases_repository_impl` · `api_purchase_handler`
    //    · `auto_posting_service`)، فالكتابةُ فيه تضمن مستنداً لكلِّ قيدٍ
    //    وقيداً لكلِّ مستند. وتوزيعُها على المنادين يفتح ثقباً في أيِّهم يُنسى.
    //
    // ⚠️ **والتاريخُ هو `postingDate` عينُه** لا `DateTime.now()`: التسويةُ
    //    دوريّةٌ تقارن مدًى بمدًى، فتاريخانِ مختلفانِ لحدثٍ واحدٍ يُنتجان
    //    فرقاً على حدِّ كلِّ شهر.
    //
    // ولا `try` حوله عمداً: فشلُ كتابة المستند يجب أن يُسقط المعاملةَ كلَّها
    // كما يفعل غيابُ حساب المخزون أعلاه — قيدٌ بلا مستندٍ هو بعينه الفجوةُ
    // التي وُجد هذا الجدولُ لسدّها.
    await into(purchaseReturns).insert(
      PurchaseReturnsCompanion.insert(
        originalInvoiceId: originalPurchase.id,
        supplierId: originalPurchase.supplierId,
        warehouseId: Value(originalPurchase.warehouseId),
        branchId: Value(branchId),
        returnDate: postingDate,
        subtotal: Value(returnAmount),
        tax: Value(vatAmount),
        total: Value(returnAmount + vatAmount),
        costCenterId: Value(costCenterId),
        // نفسُ بذرةِ معرّف القيد — فالمستندُ والقيدُ يتشاركان هويّةَ الحدث،
        // وإعادةُ محاولةٍ حقيقيّةٌ تُنتج نفسَ المعرّفَين معاً.
        globalId: Value('pret$purretSourceGid'),
        reason: Value(reason),
        lastModifiedAt: Value(postingDate),
      ),
    );

    return accountingDao.createJournalEntry(
      description: 'قيد مرتجع مشتريات فاتورة ${originalPurchase.invoiceNumber}',
      date: postingDate,
      lines: lines,
      referenceType: 'purchase_return',
      // F-04: the edit-reverse query keys on the originating invoice id
      // (see the top-of-method comment). Uniqueness rides on globalId.
      referenceId: originalPurchase.id,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: jeGid,
    );
  }

  /// §٦‑٢ — يُبطِل مستنداتِ مرتجع الشراء لفاتورةٍ، مقابلَ عكسِ قيودها.
  ///
  /// مسارُ التعديل يعكس قيدَ المرتجع بقيدٍ مقابلٍ فيصفو أثرُ الأستاذ. وبلا
  /// نظيرٍ على طرف المستند يبقى الصفُّ حيّاً، فتقرأ تسويةُ ض.ق.م ضريبةَ
  /// مرتجعٍ أُلغي — وينقلب الفرقُ الزائفُ الذي وُجد هذا الجدولُ لسدِّه إلى
  /// **الاتّجاه الآخر**.
  ///
  /// حذفٌ ناعمٌ لا صلب: `is_deleted` عمودُ مزامنةٍ ينتشر إلى بقيّة الأجهزة،
  /// أمّا الحذفُ الصلبُ فيترك المرآةَ تحمل صفّاً لا مصدرَ له.
  ///
  /// يعيد عددَ الصفوف المُبطَلة.
  Future<int> voidPurchaseReturnDocs(int originalInvoiceId) async {
    final now = DateTime.now();
    return (update(purchaseReturns)
          ..where((r) =>
              r.originalInvoiceId.equals(originalInvoiceId) &
              r.isDeleted.equals(false)))
        .write(
      PurchaseReturnsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        lastModifiedAt: Value(now),
      ),
    );
  }

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
