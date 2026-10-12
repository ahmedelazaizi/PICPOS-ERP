// Accounting auto-post: operational expense, purchase return and its void.
part of '../database.dart';

/// Accounting auto-post: operational expense, purchase return and its void. (split from accounting_autopost_dao.dart - pure move).
extension AccountingAutopostPurchaseReturnDao on AppDatabase {
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
    // J1b: a return credits the SAME «حساب المشتريات» its original invoice
    // debited; NULL (or invalid) ⇒ the mapped inventory account.
    final inventoryAccount =
        await resolvePurchaseAccountOverride(originalPurchase.id) ??
            await accountingDao.getAccountByCode(
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
}
