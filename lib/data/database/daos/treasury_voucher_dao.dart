part of '../database.dart';

extension TreasuryVoucherDao on AppDatabase {
  /// Create a receipt voucher (سند قبض)
  ///
  /// Receipt vouchers are immutable in the current UI and have no delete
  /// operation. If an administrative cancel flow is added, it must reverse
  /// the auto-posted journal entry and soft-delete the row in one transaction.
  /// صفُّ **سند الشيك** — مستندٌ يُكتَب، وقرشٌ لا يتحرّك.
  ///
  /// ═══ قرارُ المالك 2026-09-19 (تصميم «إدارة الشيكات») ═══
  ///
  /// التصميمُ يعرض بجوار الشيك «سند القبض RV-0051» وزرَّ «عرض السند».
  /// وقياسُ المسار وجد أنّ **لا سندَ للشيك أصلاً**: مواصفة ١٣٣ تمرّر
  /// `skipSafeTransaction: true` لمنع ازدواج قيدِ العميل، فلا يُكتَب صفٌّ
  /// ولا يُولَّد رقم. والنصُّ في `commercial_papers.notes` كان يسمّي رقماً
  /// **يولّده الحوارُ في ذاكرته ولا يُخزَّن قطّ**.
  ///
  /// ⚠️ **ولا يمسّ هذا الصفُّ قرشاً**: لا `adjustSafeBalance` ولا
  /// `adjustPartyBalance` ولا قيدَ يومية. المالُ يتحرّك حين تُحصَّل الورقة،
  /// ويكتبه محرّكُ الأوراق التجاريّة.
  ///
  /// ⚠️ **و`balanceAfter` هو الرصيدُ كما هو** لا `balance + amount`:
  /// الأخيرةُ تَعِد برصيدٍ لم يقع، ويقرؤها كشفُ الخزنة سطراً.
  ///
  /// ═══ 🔴 ولماذا نوعٌ مستقلٌّ لا `receipt` ═══
  ///
  /// حسابُ الرصيد الافتتاحيّ للطرف في `party_dao` يجمع
  /// `transaction_type = 'receipt'`؛ فصفٌّ بهذا النوع يُعَدّ **دفعةً ثانيةً**
  /// من العميل — عينُ ازدواج مواصفة ١٣٣ عائداً من بابٍ آخر. والنوعُ المستقلُّ
  /// يجعل كلَّ قارئٍ يرشّح بالاسم يتجاهله **بلا تعديلٍ فيه**.
  ///
  /// ⚠️ **والقارئان اللذان لا يرشّحان** (`getPartyLedger` ·
  /// `getPartyTransactions`) يستثنيانه صراحةً — وإلّا ظهر سطراً مكرّراً في
  /// كشف الحساب بجوار قيد الترحيل الآليّ للورقة.
  /// سندٌ واحدٌ بمعرّفه — تقرؤه «إدارة الشيكات» لتسمّي سندَ الورقة المختارة.
  ///
  /// ⚠️ **ويعيد  حين لا يوجد**: معرّفٌ من ورقةٍ وصلت بالمزامنة قد يشير
  /// إلى صفٍّ لم يصل بعد، فالشاشةُ تعرض «—» لا تنهار.
  Future<SafeTransactionData?> getSafeTransactionById(int id) =>
      (select(safeTransactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> _writeChequeVoucherRow({
    required int safeId,
    required String prefix,
    required double amount,
    required String category,
    int? partyId,
    String? description,
    int? userId,
    int? costCenterId,
    String? sourceGlobalId,
  }) async {
    // ⚠️ **معاملةٌ خاصّةٌ بها** ولو كان المنادي داخلَ واحدة: مواصفة ٠٦٦
    // (‏D5-001) تشترط أن يقع `generateInvoiceNumber` وإدراجُه التابعُ في
    // معاملةٍ **في نفس الدالّة** — وإلّا تقدّم العدّادُ وفشل الإدراجُ فبقيت
    // فجوةٌ في الترقيم. وdrift يجعل الداخليّةَ `SAVEPOINT` فلا كلفةَ
    // مضاعفة، وتبقى الدالّةُ سليمةً لو ناداها أحدٌ من خارج معاملة.
    return transaction(() async {
      final safe = await (select(safes)..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      if (safe == null) return 0;

    // معرّفٌ **مشتقٌّ** لا عشوائيّ: الطرفان (عميلٌ وخادم) يشتقّانه من نفس
    // معرّف السند فيلتقيان على صفٍّ واحد — نفسُ نمط `'$gid-rev'` في العكس.
    // وعشوائيٌّ هنا يعني صفَّين بعد أوّل مزامنة.
      final gid = sourceGlobalId != null && sourceGlobalId.isNotEmpty
          ? '$sourceGlobalId-chq'
          : UuidV7.generate();

      return into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: await generateInvoiceNumber(prefix),
          safeId: safe.id,
          transactionType: kChequeVoucherTxnType,
          category: category,
          amount: amount,
          balanceAfter: safe.balance,
          partyId: Value(partyId),
          description: Value(description),
          userId: Value(userId),
          costCenterId: Value(costCenterId),
          globalId: Value(gid),
        ),
      );
    });
  }

  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    /// Optional pre-generated UUID. When the voucher is being created as
    /// part of a client→server sync and the SAME logical voucher is being
    /// written on both ends (Issue 12), pass the same globalId to both
    /// calls so SafeTransactionSyncStrategy dedupes by UUID instead of
    /// inserting a phantom second row. When null, a fresh UUID is minted.
    String? globalId,
    // Spec 133 — symmetric with createPaymentVoucher (Spec 081). When the
    // receipt voucher represents a cheque (not cash), the commercial-papers
    // autopost owns BOTH the customer-credit JE (Dr: Notes Receivable, Cr:
    // Customer) AND the parties.balance adjustment via
    // _cpApplyBalanceSideEffects. Running the cash-leg JE + safe transaction
    // + party-balance adjust here too produced a double customer credit
    // (one row from the voucher path, one from the autopost). When
    // skipJournalEntry == true the cash-leg JE is suppressed; when
    // skipSafeTransaction == true the entire safe lookup + insert +
    // balance update + party adjust + fire-and-forget sync is suppressed.
    // For cheque receipts the caller passes BOTH true (no cash arrived,
    // no JE belongs here).
    bool skipJournalEntry = false,
    bool skipSafeTransaction = false,

    /// خزنةُ **سندِ الشيك** — صفٌّ مستنديٌّ بلا أثرٍ ماليّ.
    ///
    /// راجع [_writeChequeVoucherRow]: يُطلَب صراحةً ولا يُفرَض، فمواصفة ١٣٣
    /// محروسةٌ بـ«لا صفَّ» حين لا يُمرَّر.
    int? chequeVoucherSafeId,

    /// ‏ق-٢ — يُنسَب السندُ للطرف على صفّه (تتبّعاً) **دون** أن يُنقص دَينَه.
    ///
    /// لعربون الحجز: المقابلُ حسابُ التزامٍ (`2134 عملاء - دفعات مقدمة`)
    /// يُطفأ عند التفويتر بـ«مدين الالتزام / دائن حساب العميل». فلو حُرِّك
    /// الرصيدُ عند القبض أيضاً لَعُدَّت الدفعةُ مرّتين.
    ///
    /// ⚠️ ولا تُستعمل مع سندٍ مقابلُه حسابُ العميل نفسُه — هناك تحريكُ
    /// الرصيد هو المقصود.
    bool skipPartyBalance = false,
    // Spec 135 BUG-C — the branch the OPERATOR is working in, threaded from
    // the voucher dialog (activeBranchIdProvider) and, on the server, from the
    // client's branchId. The voucher JE was attributed to targetSafe.branchId,
    // so a receipt taken in branch B into a safe that belongs to branch A
    // landed on A's books. Prefer the operating branch; fall back to the
    // safe's branch when the caller didn't supply one (legacy/standalone).
    // NOT an R9-gate issue (the push predicate is correct) — purely JE branch
    // attribution. Mirrors the manual-JE fix in drift_accounting_repository.
    int? operatingBranchId,
     int? currencyId, double? paymentRate, double? foreignAmount,
  }) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'سند قبض');

      int transactionId = 0;

      // سندُ الشيك — مستندٌ يُكتَب ولا يمسّ قرشاً. راجع
      // [_writeChequeVoucherRow] لِمَ صفٌّ أصلاً ولِمَ نوعٌ مستقلّ.
      if (skipSafeTransaction && chequeVoucherSafeId != null) {
        transactionId = await _writeChequeVoucherRow(
          safeId: chequeVoucherSafeId,
          prefix: 'RV',
          amount: amount,
          category: category,
          partyId: partyId,
          description: description,
          userId: userId,
          costCenterId: costCenterId,
          sourceGlobalId: globalId,
        );
      }

      if (!skipSafeTransaction) {
        // Phase 5B.5 (Issue 7) — on client mode, an absent safeId is a
        // dialog/UX bug, not an "use the default" prompt. Falling back to
        // getDefaultSafe() silently posted to whichever safe happened to
        // be flagged default for the device — frequently the WRONG one
        // when the user explicitly picked a branch-specific safe in the
        // dialog (the dialog had a stale state). Reject loudly so the
        // failure surfaces in the UI instead of corrupting the GL.
        // Server mode and standalone mode keep the default-safe fallback
        // — those flows never expose a safe picker to the user, so there
        // IS no "explicit selection" to honour.
        if (safeId == null && SyncInterceptor.isClientMode) {
          throw StateError(
              'safeId required on client mode — no default-safe fallback. '
              'The receipt-voucher dialog must enforce a safe selection '
              'before submit (see Phase 5B.6).');
        }

        Safe? targetSafe;
        if (safeId != null) {
          targetSafe = await (select(
            safes,
          )..where((s) => s.id.equals(safeId))).getSingleOrNull();
        } else {
          targetSafe = await getDefaultSafe();
        }

        if (targetSafe == null) throw Exception('No target safe found');

        // ── مركزُ تكلفة الخزنة يُورَّث حين لا يحدّده المنادي ──────────────
        //
        // شاشةُ إدارة الصناديق تربط كلَّ خزنةٍ بمركز تكلفة، وكان الربطُ
        // **لا يقرؤه أحد**: هذا المسارُ يكتب مركزَ المنادي وحدَه، فسندٌ من
        // حوارٍ لا يسأل عن مركزٍ يقع بلا مركزٍ مهما كانت خزنتُه مربوطة —
        // والمشغّلُ يفتح تقريرَ مراكز التكلفة فلا يجد حركةَ الخزنة فيه.
        // (‏نفسُ فئة §٣-ب: سطحُ إعدادٍ يكتب قيمةً لا يقرؤها أحد.)
        //
        // والفرعُ كان يصل سلفاً (`operatingBranchId ?? targetSafe.branchId`
        // تحت) — فهذا يُكمل الطرفَ الناقص لا يُنشئ نمطاً جديداً.
        //
        // ⚠️ سدُّ فراغٍ لا تجاوزٌ على اختيار: مركزُ المنادي الصريحُ أولى
        // دائماً، وخزنةٌ بلا مركزٍ تُبقي الحركةَ بلا مركزٍ ولا تخترع واحداً.
        final effectiveCostCenterId = costCenterId ?? targetSafe.costCenterId;

        final newBalance = targetSafe.balance + amount;
        final voucherNumber = await generateInvoiceNumber('RV');

        // Phase 5B.1 (Issues 1 + 7) — capture the effective globalId BEFORE
        // the safe-transaction insert so the journal entry can derive its
        // own deterministic globalId from it. Both client and server run
        // this DAO (server inside postReceipt). Without a stable JE globalId
        // each side wrote a JE with a random UUID, and the next pull
        // duplicated the entry in the General Ledger. With deterministic
        // identity, JournalSyncStrategy's Tier 1 match dedups cleanly.
        final effectiveGlobalId = globalId ?? UuidV7.generate();

        transactionId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: targetSafe.id,
            transactionType: 'receipt',
            category: category,
            amount: amount,
            discount: Value(discount),
            balanceAfter: newBalance,
            partyId: Value(partyId),
            description: Value(description),
            userId: Value(userId),
            costCenterId: Value(effectiveCostCenterId),
            globalId: Value(effectiveGlobalId),
             currencyId: Value(currencyId), exchangeRate: Value(paymentRate), foreignAmount: Value(foreignAmount),
          ),
        );

        // H15 — سندُ قبضٍ: زيادةٌ ذرّية. سندان متزامنان على نفس الخزنة كانا
        // يقرآن نفسَ الرصيد فيضيع أحدُ المبلغين. `newBalance` لقطةٌ لا أمر.
        await adjustSafeBalance(targetSafe.id, amount);

        // Spec 133 — party balance adjustment belongs INSIDE the
        // skipSafeTransaction guard. For cheque receipts the commercial
        // papers pipeline owns the AR side-effect via
        // `_cpApplyBalanceSideEffects` (commercial_papers_dao.dart); running
        // it here too caused parties.balance to decrement twice (mirrors
        // the Spec 081 fix on the payment side).
        // ‏ق-٢ (‏قرارُ المالك 2026-08-23): عربونُ الحجز يُنسَب للعميل على
        // صفّ السند **للتتبّع** لكنّه لا يُنقص دَينَه — مقابلُه حسابُ التزامٍ
        // (`2134`) يُطفأ عند التفويتر بـ«مدين الالتزام / دائن حساب العميل».
        // فتحريكُ الرصيد هنا **وأيضاً** هناك كان سيعدّ الدفعةَ مرّتين.
        if (partyId != null && !skipPartyBalance) {
          await adjustPartyBalance(partyId, -(amount + discount));
        }

        if (!skipJournalEntry) {
          // Create journal entry for financial reporting
          await _createVoucherJournalEntry(
            voucherNumber: voucherNumber,
            amount: amount,
            discount: discount,
            category: category,
            description: description ?? 'سند قبض',
            isReceipt: true,
            transactionId: transactionId,
            costCenterId: effectiveCostCenterId,
            branchId: operatingBranchId ?? targetSafe.branchId, // Spec 135 BUG-C
            linkedAccountId: linkedAccountId, // GAP-03
            safeId: targetSafe.id, // Use safe's linked account for cash side
            partyId: partyId, // Issue 4 (Feature 022): party AR sub-account
            safeTransactionGlobalId: effectiveGlobalId,
          );
        }

        // ── Client → Server sync (fire-and-forget) ──
        // Spec 087 (F2) — look up the party's globalId so the server
        // resolves to ITS partyId (different autoincrement on mirror)
        // and the safe-transaction row lands with the right party link
        // → voucher appears in the customer/supplier statement.
        String? receiptPartyGid;
        if (partyId != null) {
          final partyRow = await (select(parties)
                ..where((p) => p.id.equals(partyId))
                ..limit(1))
              .getSingleOrNull();
          receiptPartyGid = partyRow?.globalId;
        }
        try {
          await SyncInterceptor.instance?.submitSafeTransaction(
            safeId: targetSafe.id,
            transactionType: 'receipt',
            amount: amount,
            category: category,
            description: description,
            userId: userId,
            referenceType: 'receipt_voucher',
            referenceId: transactionId,
            // Phase 5B.4 (Issue 7) — surface the safe's globalId + the
            // dialog-selected cost center so the server resolves to ITS
            // safe.id (different autoincrement) and stamps the JE with
            // the right cost center instead of a default fallback.
            globalId: effectiveGlobalId,
            safeGlobalId: targetSafe.globalId,
            costCenterId: effectiveCostCenterId,
            partyId: partyId,
            partyGlobalId: receiptPartyGid,
             currencyId: currencyId, exchangeRate: paymentRate, foreignAmount: foreignAmount,
          );
        } catch (e) {
          debugPrint('[TREASURY-SYNC] Receipt voucher sync failed: $e');
        }
      }

      return transactionId;
    });
  }

  /// Create a payment voucher (سند صرف)
  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    /// Optional pre-generated UUID. When the voucher is being created as
    /// part of a client→server sync and the SAME logical voucher is being
    /// written on both ends, pass the same globalId to both calls so that
    /// pull-sync (SafeTransactionSyncStrategy) dedupes by UUID instead of
    /// creating a phantom second row. When null, a fresh UUID is minted.
    String? globalId,
    // When true, skips the cash/bank journal entry because the commercial
    // papers system already creates the correct accounting entry (Dr: Payables,
    // Cr: Notes Payable) upon check issuance.  Avoids duplicate JEs.
    bool skipJournalEntry = false,
    // When true, skips safe lookup / safe transaction / balance update entirely.
    // Used for check payments where no physical cash leaves the safe.
    bool skipSafeTransaction = false,

    /// خزنةُ **سندِ الشيك** — راجع [createReceiptVoucher].
    int? chequeVoucherSafeId,
    int? linkedAccountId, // E2: COA beneficiary

    // Spec 135 BUG-C — operator's working branch (see createReceiptVoucher).
    // Prefer it for the JE branch; fall back to targetSafe.branchId.
    int? operatingBranchId,
     int? currencyId, double? paymentRate, double? foreignAmount,
  }) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'سند صرف');

      int transactionId = 0;

      // سندُ الشيك — نظيرُ ما في [createReceiptVoucher] بلاحقة `PV`.
      if (skipSafeTransaction && chequeVoucherSafeId != null) {
        transactionId = await _writeChequeVoucherRow(
          safeId: chequeVoucherSafeId,
          prefix: 'PV',
          amount: amount,
          category: category,
          partyId: partyId,
          description: description,
          userId: userId,
          costCenterId: costCenterId,
          sourceGlobalId: globalId,
        );
      }

      if (!skipSafeTransaction) {
        // Phase 5B.5 (Issue 7) — same rationale as createReceiptVoucher.
        // On client mode the safe MUST be explicit. The voucher dialog is
        // responsible for enforcing this (5B.6); reaching the DAO with a
        // null safeId means the caller bypassed the dialog, in which case
        // posting to whichever safe is flagged default would silently land
        // the entry on the wrong branch's books.
        if (safeId == null && SyncInterceptor.isClientMode) {
          throw StateError(
              'safeId required on client mode — no default-safe fallback. '
              'The payment-voucher dialog must enforce a safe selection '
              'before submit (see Phase 5B.6).');
        }

        Safe? targetSafe;
        if (safeId != null) {
          targetSafe = await (select(
            safes,
          )..where((s) => s.id.equals(safeId))).getSingleOrNull();
        } else {
          targetSafe = await getDefaultSafe();
        }

        if (targetSafe == null) throw Exception('No target safe found');

        // Note: Balance check removed - expenses allowed even with zero/negative balance
        // Will be settled at daily closing (الإقفال اليومي)

        // مركزُ تكلفة الخزنة يُورَّث حين لا يحدّده المنادي — انظر
        // `createReceiptVoucher` أعلاه للتعليل الكامل. والمسارانِ متناظرانِ
        // قصداً: صرفٌ يقع بلا مركزٍ وقبضٌ يقع به يجعل تقريرَ المركز نصفَ
        // صورةٍ — إيراداتٌ بلا مصروفاتها.
        final effectiveCostCenterId = costCenterId ?? targetSafe.costCenterId;

        final newBalance = targetSafe.balance - amount;
        final voucherNumber = await generateInvoiceNumber('PV');

        // Phase 5B.1 (Issues 1 + 7) — capture the effective globalId early
        // so the JE can derive its own deterministic identity from it.
        // See createReceiptVoucher above for the full rationale.
        final effectiveGlobalId = globalId ?? UuidV7.generate();

        transactionId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: targetSafe.id,
            transactionType: 'payment',
            category: category,
            amount: amount,
            discount: Value(discount),
            balanceAfter: newBalance,
            partyId: Value(partyId),
            description: Value(description),
            userId: Value(userId),
            costCenterId: Value(effectiveCostCenterId),
            globalId: Value(effectiveGlobalId),
             currencyId: Value(currencyId), exchangeRate: Value(paymentRate), foreignAmount: Value(foreignAmount),
          ),
        );

        // H15 — سندُ صرف: خصمٌ ذرّيّ (نفسُ علّة سند القبض أعلاه).
        await adjustSafeBalance(targetSafe.id, -amount);

        // Create journal entry for financial reporting.
        // Skipped for check payments: the commercial papers system creates the
        // correct entry (Dr: Payables / Cr: Notes Payable) on check issuance.
        if (!skipJournalEntry) {
          await _createVoucherJournalEntry(
            voucherNumber: voucherNumber,
            amount: amount,
            discount: discount,
            category: category,
            description: description ?? 'سند صرف',
            isReceipt: false,
            transactionId: transactionId,
            costCenterId: effectiveCostCenterId,
            branchId: operatingBranchId ?? targetSafe.branchId, // Spec 135 BUG-C
            safeId: targetSafe.id,
            linkedAccountId: linkedAccountId,
            partyId: partyId, // Issue 4 (Feature 022): party AP sub-account
            safeTransactionGlobalId: effectiveGlobalId,
          );
        }

        // ── Client → Server sync (fire-and-forget) ──
        // Spec 087 (F2) — thread partyId + partyGlobalId so the
        // server's voucher row lands on the right supplier and
        // appears in their statement.
        String? paymentPartyGid;
        if (partyId != null) {
          final partyRow = await (select(parties)
                ..where((p) => p.id.equals(partyId))
                ..limit(1))
              .getSingleOrNull();
          paymentPartyGid = partyRow?.globalId;
        }
        try {
          await SyncInterceptor.instance?.submitSafeTransaction(
            safeId: targetSafe.id,
            transactionType: 'payment',
            amount: amount,
            category: category,
            description: description,
            userId: userId,
            referenceType: 'payment_voucher',
            referenceId: transactionId,
            // Phase 5B.4 (Issue 7) — see createReceiptVoucher above for
            // the rationale; same divergence-mitigation here for payment
            // vouchers.
            globalId: effectiveGlobalId,
            safeGlobalId: targetSafe.globalId,
            costCenterId: effectiveCostCenterId,
            partyId: partyId,
            partyGlobalId: paymentPartyGid,
             currencyId: currencyId, exchangeRate: paymentRate, foreignAmount: foreignAmount,
          );
        } catch (e) {
          debugPrint('[TREASURY-SYNC] Payment voucher sync failed: $e');
        }

        // Spec 081 — party balance adjustment belongs INSIDE the
        // skipSafeTransaction guard. For cheque payments the commercial
        // papers pipeline owns the AP side-effect via
        // `_cpApplyBalanceSideEffects` (commercial_papers_dao.dart:565);
        // running it here too caused parties.balance to decrement twice.
        if (partyId != null) {
          await adjustPartyBalance(
            partyId,
            -(amount + discount),
          ); // NEGATIVE: reduces outstanding balance
        }
      }

      return transactionId;
    });
  }

  /// Helper to create journal entry for vouchers
  /// This ensures treasury transactions appear in financial statements
  Future<void> _createVoucherJournalEntry({
    required String voucherNumber,
    required double amount,
    required double discount,
    required String category,
    required String description,
    required bool isReceipt,
    required int transactionId,
    int? costCenterId,
    int? branchId,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    int? safeId, // Safe ID to resolve linked account for cash side
    // Issue 4 (Feature 022): the voucher's party. When non-null AND the
    // operator hasn't picked an explicit CoA override, the JE's "other"
    // leg (debit on payment, credit on receipt) lands on the party's
    // AP/AR sub-account instead of the category-default expense/income
    // account. Without this, payment vouchers to suppliers were debiting
    // "مصروفات متنوعة" (5299) and the GL supplier statement diverged
    // from the CRM/parties statement.
    int? partyId,
    /// Phase 5B.1 (Issues 1 + 7) — when the parent voucher's globalId is
    /// known, the JE derives a deterministic globalId from it
    /// (`je-rcpt-<g>` / `je-pmt-<g>`). Both client and server end up
    /// computing the same JE globalId for the same logical voucher, so
    /// JournalSyncStrategy's Tier 1 dedup recognises the match instead
    /// of inserting a phantom duplicate row in the General Ledger.
    /// Optional for backward compatibility with legacy callers; absent
    /// callers keep the previous random-globalId behaviour (no
    /// cross-device dedup, but no within-device duplicate either).
    String? safeTransactionGlobalId,
  }) async {
    // GAP-03: If a linked account is specified, use it directly
    Account? categoryAccount;
    if (linkedAccountId != null) {
      categoryAccount = await accountingDao.getAccountById(linkedAccountId);
    }
    // Issue 4 (Feature 022): party-aware fallback BEFORE the generic
    // category-code fallback. Order: explicit CoA pick → party AP/AR
    // sub-account → category default. This is the fix for the bug where
    // payment vouchers to suppliers debited "مصروفات متنوعة" instead of
    // the supplier's payables sub-account.
    if (categoryAccount == null && partyId != null) {
      categoryAccount = await _resolveVoucherPartyAccount(
        partyId: partyId,
        isReceipt: isReceipt,
      );
    }
    // Fallback to category-based mapping
    if (categoryAccount == null) {
      final accountCode = _getCategoryAccountCode(category, isReceipt);
      categoryAccount = await accountingDao.getAccountByCode(accountCode);

      // If account doesn't exist, create it
      if (categoryAccount == null) {
        final accountName = _getCategoryAccountName(category, isReceipt);
        final accountType = isReceipt ? 'revenue' : 'expense';
        await into(accounts).insert(
          AccountsCompanion.insert(
            code: accountCode,
            name: accountName,
            accountType: accountType,
            isSystem: const Value(false),
            // UUID-First (Phase 1): stable cross-install identity for sync.
            globalId: Value(UuidV7.generate()),
          ),
        );
        categoryAccount = await accountingDao.getAccountByCode(accountCode);
      }
    }

    // Resolve the cash/treasury account:
    // 1. If safe has a linkedAccountId, use that account
    // 2. Otherwise fall back to default cash account '1111' (الصندوق الرئيسي)
    // Cluster 023 / Issue 3 — leaf-safe lookups so a safe whose
    // `linkedAccountId` happens to point at a parent (or a `cash` purpose
    // mapped to a parent) doesn't fail the JE post.
    Account? cashAccount;
    if (safeId != null) {
      final safe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
      if (safe?.linkedAccountId != null) {
        cashAccount = await accountingDao.getLeafAccountById(safe!.linkedAccountId!);
      }
      // خزينة مش مربوطة: الرجوع على '1111' مباشرة كان بيرحّل سند قبض على
      // «الحساب البنكي» أو «كليك» على **الصندوق الرئيسي** — النقدية في
      // الأستاذ بتزيد والبنك بينقص والخزينة بتقول العكس. الـdropdown في
      // `receipt_voucher_dialog.dart` بيعرض كل الخزائن مش الكاش بس،
      // فالمسار قابل للوصول عادي.
      //
      // نفس نمط مسار المبيعات الصح (`_resolveSaleLegAccount` →
      // `_resolveBranchSafeAccount`): الرجوع بحسب **نوع الخزينة**.
      if (cashAccount == null && safe != null) {
        final byType = kSafeTypeAccountCode[safe.safeType];
        if (byType != null) {
          cashAccount = await accountingDao.getLeafAccountById(
            (await accountingDao.getAccountByCode(byType))?.id ?? -1,
          );
        }
      }
    }
    cashAccount ??= await accountingDao.getAccountByCode('1111');
    if (cashAccount == null) {
      await accountingDao.syncDefaultAccounts();
      cashAccount = await accountingDao.getAccountByCode('1111');
    }
    // Last-resort: leaf-safe purpose lookup. Catches installs whose seed
    // doesn't have code '1111' anymore (e.g. CoA was customised) — without
    // this we silently dropped the JE at the null-guard below.
    cashAccount ??= await accountingDao.getLeafAccountByPurpose('cash');

    // Get or create discount account
    final discountCode = isReceipt ? '5205' : '4202';
    final discountName = isReceipt ? 'خصم مسموح به (Settlement)' : 'خصم مكتسب (Settlement)';
    var discountAccount = await accountingDao.getAccountByCode(discountCode);
    if (discountAccount == null && discount > 0) {
      await into(accounts).insert(AccountsCompanion.insert(
        code: discountCode,
        name: discountName,
        accountType: isReceipt ? 'expense' : 'revenue',
        isSystem: const Value(false),
        // UUID-First (Phase 1): stable cross-install identity for sync.
        globalId: Value(UuidV7.generate()),
      ));
      discountAccount = await accountingDao.getAccountByCode(discountCode);
    }

    // Cluster 023 / Issue 1 — silently returning here was the silent bug:
    // safe transaction got persisted but the JE was skipped, so the GL
    // balance drifted from the safe's actual balance. Throw loudly instead
    // — the outer transaction rolls back and the operator sees a clear
    // error pointing at the misconfigured account, instead of an invisible
    // ledger drift discovered weeks later.
    if (categoryAccount == null) {
      throw Exception(
        'تعذّر تحديد حساب التصنيف لسند ${isReceipt ? 'القبض' : 'الصرف'} '
        '(category="$category"). تأكّد من ربط الحساب فى إعدادات > دليل الحسابات > ربط الحسابات.',
      );
    }
    if (cashAccount == null) {
      throw Exception(
        'تعذّر تحديد حساب الخزينة/البنك لسند ${isReceipt ? 'القبض' : 'الصرف'}. '
        'تأكّد من ربط حساب الصندوق الرئيسي (1111) أو حساب الخزينة المختارة فى دليل الحسابات.',
      );
    }

    // Total impact on party/revenue
    final totalAmount = amount + discount;

    // Create journal entry
    // RV: DB Cash (amount), DB Discount Allowed (discount), CR Party/Revenue (total)
    // PV: DB Party/Expense (total), CR Cash (amount), CR Discount Received (discount)
    final List<JournalLine> lines = [];

    if (isReceipt) {
      // Receipt: Debit Cash, Debit Discount, Credit Revenue/Party
      lines.add(JournalLine(accountId: cashAccount.id, debit: amount, credit: 0, description: description));
      if (discount > 0 && discountAccount != null) {
        lines.add(JournalLine(accountId: discountAccount.id, debit: discount, credit: 0, description: 'خصم معجل دفع مسموح به'));
      }
      lines.add(JournalLine(accountId: categoryAccount.id, debit: 0, credit: totalAmount, description: description));
    } else {
      // Payment: Debit Expense/Party, Credit Cash, Credit Discount
      lines.add(JournalLine(accountId: categoryAccount.id, debit: totalAmount, credit: 0, description: description));
      lines.add(JournalLine(accountId: cashAccount.id, debit: 0, credit: amount, description: description));
      if (discount > 0 && discountAccount != null) {
        lines.add(JournalLine(accountId: discountAccount.id, debit: 0, credit: discount, description: 'خصم معجل دفع مكتسب'));
      }
    }

    // Phase 5B.1 (Issues 1 + 7) — derive deterministic JE globalId from
    // the parent voucher's globalId so client + server converge on the
    // same JE row after sync. See _createVoucherJournalEntry's parameter
    // docs for the full rationale. Falls back to null (random globalId)
    // when the caller didn't supply one (legacy callers / direct DAO use).
    final detGlobalId = (safeTransactionGlobalId != null && safeTransactionGlobalId.isNotEmpty)
        ? '${isReceipt ? 'je-rcpt' : 'je-pmt'}-$safeTransactionGlobalId'
        : null;

    await accountingDao.createJournalEntry(
      description: description,
      date: DateTime.now(),
      lines: lines,
      referenceType: isReceipt ? 'receipt_voucher' : 'payment_voucher',
      referenceId: transactionId,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: detGlobalId,
    );
  }

  /// Map category to account code using centralized purposes
  String _getCategoryAccountCode(String category, bool isReceipt) {
    final Map<String, String> categoryToPurpose = {
      'sales': 'sales',
      'purchase': 'cogs',
      'salary': 'salary_expense',
      'salaries': 'salary_expense',
      'rent': 'rent_expense',
      'income': 'other_income',
      'other_income': 'other_income',
      'expense': 'misc_expense',
      'other_expense': 'misc_expense',
    };

    final purpose = categoryToPurpose[category.toLowerCase()];
    if (purpose != null) {
      final code = AccountingDao.accountPurposes[purpose];
      if (code != null) return code;
    }

    // Fallback for custom or daily closing categories
    final prefix = isReceipt ? '4' : '5';
    if (category.toLowerCase() == 'daily_closing') return '${prefix}999';
    return isReceipt ? '4299' : '5299';
  }

  /// Map category to account name
  String _getCategoryAccountName(String category, bool isReceipt) {
    switch (category.toLowerCase()) {
      case 'sales':
        return 'إيرادات المبيعات';
      case 'purchase':
        return 'تكلفة البضاعة المباعة';
      case 'salary':
      case 'salaries':
        return 'مصروفات الرواتب';
      case 'rent':
        return 'مصروفات الإيجار';
      case 'utilities':
        return 'مصروفات المرافق';
      case 'supplies':
        return 'مصروفات المستلزمات';
      case 'other_income':
        return 'إيرادات أخرى';
      case 'other_expense':
        return 'مصروفات أخرى';
      case 'daily_closing':
        return 'إقفال يومي';
      default:
        return isReceipt ? 'إيرادات متنوعة' : 'مصروفات متنوعة';
    }
  }

  /// Issue 4 (Feature 022): resolve a voucher's "other-leg" account when the
  /// voucher targets a specific party. Prefers the party's AP/AR sub-account
  /// (so the GL party statement shows every voucher under the right ledger
  /// row); falls back to the configured `payables` / `receivables` control
  /// account when the party has no linked sub-account (legacy data, system
  /// parties).
  ///
  /// Returns null only if the control-account lookup itself fails — caller
  /// then falls through to the existing category-based path so the JE still
  /// posts somewhere rather than silently dropping.
  Future<Account?> _resolveVoucherPartyAccount({
    required int partyId,
    required bool isReceipt,
  }) async {
    final party = await (select(parties)
          ..where((p) => p.id.equals(partyId))
          ..limit(1))
        .getSingleOrNull();
    if (party?.accountId != null) {
      // Cluster 023 / Issue 3 — leaf-safe lookup so a party whose
      // `accountId` happens to point at a parent (legacy data drift) doesn't
      // cause the JE validator to reject the post on a "view" account.
      final sub = await accountingDao.getLeafAccountById(party!.accountId!);
      if (sub != null) return sub;
    }
    // Fallback to the control account, leaf-safe so a misconfigured
    // `receivables` / `payables` mapping (e.g. pointing at code "22") is
    // walked down to a postable child instead of failing the post.
    final purpose = isReceipt ? 'receivables' : 'payables';
    return accountingDao.getLeafAccountByPurpose(purpose);
  }

  /// Close safe daily (اقفال يومي)
  /// Zeroes out the balance by creating a 'daily_closing' transaction
  /// T-02 HARDENED: now posts a journal entry for the closing transfer
}
