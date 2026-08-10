// =======================================================================
// OPERATIONAL EXPENSES & STOCK RECONCILIATION DAO
// Extracted from manufacturing_assets_dao.dart — Phase 6 God File Splitting
// =======================================================================
part of '../database.dart';

extension OperationalExpensesDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // ENHANCED INVENTORY AUDIT (جرد المخزون المتقدم)
  // ─────────────────────────────────────────────────────────────────────────

  /// Perform stock reconciliation: compare actual vs book quantity
  Future<Map<String, dynamic>> reconcileStock(
    int warehouseId,
    Map<int, double> actualQuantities,
  ) async {
    final results = <Map<String, dynamic>>[];
    double totalVariance = 0;

    final productMap = await getProductsByIds(actualQuantities.keys.toList());
    for (final entry in actualQuantities.entries) {
      final productId = entry.key;
      final actualQty = entry.value;

      final product = productMap[productId];
      final bookQty = product?.currentStock ?? 0;
      final variance = actualQty - bookQty;

      if (variance.abs() > 0.001) {
        results.add({
          'productId': productId,
          'productName': product?.name ?? '',
          'bookQuantity': bookQty,
          'actualQuantity': actualQty,
          'variance': variance,
          'costImpact': variance * (product?.costPrice ?? 0),
        });
        totalVariance += variance * (product?.costPrice ?? 0);
      }
    }

    return {
      'items': results,
      'totalVariance': totalVariance,
      'itemsWithVariance': results.length,
    };
  }

  /// Apply stock adjustment after audit — uses adjustStock for proper integration
  /// C-02: Creates accounting JE for inventory variance (IAS 2.34)
  Future<void> applyStockAdjustment(
    int warehouseId,
    Map<int, double> actualQuantities, {
    String? auditNotes,
  }) async {
    await transaction(() async {
      double totalShortage = 0; // negative variance (book > actual)
      double totalSurplus = 0;  // positive variance (actual > book)

      final productMap = await getProductsByIds(actualQuantities.keys.toList());
      for (final entry in actualQuantities.entries) {
        final productId = entry.key;
        final actualQty = entry.value;

        final product = productMap[productId];
        final bookQty = product?.currentStock ?? 0;
        final variance = actualQty - bookQty;

        if (variance.abs() > 0.001) {
          await adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: variance,
            type: variance > 0 ? 'audit_surplus' : 'audit_shortage',
            referenceType: 'inventory_audit',
            notes: auditNotes ?? 'تسوية جرد',
          );

          final costImpact = variance.abs() * (product?.costPrice ?? 0);
          if (variance < 0) {
            totalShortage += costImpact;
          } else {
            totalSurplus += costImpact;
          }
        }
      }

      // C-02: Create accounting JE for inventory variance.
      // B7 (S-FAILLOUD / ACC-2): the account-resolution guards below used to
      // silently `return`/skip a leg when a required account wasn't mapped —
      // meanwhile the adjustStock() calls above (inside this SAME
      // transaction) had already mutated stock. That let a stock movement
      // commit with its variance JE partially or fully skipped. Resolve all
      // required accounts up-front and THROW when one is missing so the
      // whole transaction (including the stock adjustment) rolls back
      // instead of committing an un-reconciled stock change.
      if (totalShortage > 0 || totalSurplus > 0) {
        final inventoryAccount = await accountingDao.getAccountByCode(
          await accountingDao.getMappedAccountCode('inventory', AccountingDao.accountPurposes['inventory']!),
        );
        if (inventoryAccount == null) {
          throw StateError(
            'تعذّر ترحيل قيد تسوية الجرد: حساب المخزون غير موجود في الدليل '
            'المحاسبي. راجع إعدادات الحسابات ← ربط الحسابات قبل تنفيذ الجرد.',
          );
        }

        final lines = <JournalLine>[];

        if (totalShortage > 0) {
          // Shortage: Dr Inventory Shrinkage / Cr Inventory
          final shrinkageAccount = await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('inventory_shrinkage', AccountingDao.accountPurposes['inventory_shrinkage']!),
          );
          if (shrinkageAccount == null) {
            throw StateError(
              'تعذّر ترحيل قيد عجز الجرد: حساب عجز المخزون '
              '(inventory_shrinkage) غير موجود في الدليل المحاسبي.',
            );
          }
          lines.add(JournalLine(accountId: shrinkageAccount.id, debit: totalShortage, description: 'عجز جرد'));
          lines.add(JournalLine(accountId: inventoryAccount.id, credit: totalShortage, description: 'تخفيض مخزون — عجز'));
        }

        if (totalSurplus > 0) {
          // Surplus: Dr Inventory / Cr Inventory Surplus
          final surplusAccount = await accountingDao.getAccountByCode(
            await accountingDao.getMappedAccountCode('inventory_surplus', AccountingDao.accountPurposes['inventory_surplus']!),
          );
          if (surplusAccount == null) {
            throw StateError(
              'تعذّر ترحيل قيد فائض الجرد: حساب فائض المخزون '
              '(inventory_surplus) غير موجود في الدليل المحاسبي.',
            );
          }
          lines.add(JournalLine(accountId: inventoryAccount.id, debit: totalSurplus, description: 'زيادة مخزون — فائض'));
          lines.add(JournalLine(accountId: surplusAccount.id, credit: totalSurplus, description: 'إيرادات فائض جرد'));
        }

        // lines is guaranteed non-empty here: the outer guard requires
        // totalShortage>0 or totalSurplus>0, and each branch above either
        // adds its two lines or throws — no more silent `if (lines.isNotEmpty)`
        // skip gate.
        final warehouse = await getWarehouseById(warehouseId);
        final branchId = warehouse?.branchId;

        await accountingDao.createJournalEntry(
          description: 'قيد تسوية جرد مستودع #$warehouseId — ${auditNotes ?? ""}',
          date: DateTime.now(),
          lines: lines,
          referenceType: 'inventory_audit',
          referenceId: warehouseId,
          isAutoPosted: true,
          branchId: branchId,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OPERATIONAL EXPENSES — المصروفات التشغيلية
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all expense categories
  Stream<List<OpExpenseCategoryData>> watchExpenseCategories() =>
      (select(opExpenseCategories)
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  /// Get active expense categories
  Future<List<OpExpenseCategoryData>> getActiveExpenseCategories() =>
      (select(opExpenseCategories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  /// Create expense category
  ///
  /// EXP-1: default changed from '5299' to '6214'. The seeded chart of
  /// accounts (accounting_dao_writes.dart syncDefaultAccounts /
  /// database_seeder_accounts.dart) never creates account '5299' — every
  /// category left at the old default silently failed to post to the GL
  /// (autoPostOperationalExpense's account lookup returned null). '6214'
  /// (مصروفات متنوعة - إدارة) is always seeded and is also the resolved
  /// target of the 'op_expenses'/'misc_expense' account-mapping purposes
  /// (accounting_dao_reads.dart accountPurposes), so it matches what the
  /// autopost fallback resolves to when a category still carries a bad code.
  Future<int> createExpenseCategory({
    required String name,
    String type = 'indirect',
    bool isProductionRelated = true,
    String allocationMethod = 'fixed_monthly',
    double defaultRate = 0,
    String accountCode = '6214', // EXP-1: GL account code (was '5299', never seeded)
  }) =>
      into(opExpenseCategories).insert(OpExpenseCategoriesCompanion.insert(
        name: name,
        type: Value(type),
        isProductionRelated: Value(isProductionRelated),
        allocationMethod: Value(allocationMethod),
        defaultRate: Value(defaultRate),
        accountCode: Value(accountCode),
      ));

  /// Update expense category
  Future<bool> updateExpenseCategory(int id, OpExpenseCategoriesCompanion data) =>
      (update(opExpenseCategories)..where((c) => c.id.equals(id))).write(data).then((rows) => rows > 0);

  /// Delete expense category
  Future<bool> deleteExpenseCategory(int id) =>
      (delete(opExpenseCategories)..where((c) => c.id.equals(id))).go().then((rows) => rows > 0);

  /// EXP-1: one-shot backfill — categories created before the
  /// [createExpenseCategory] default fix (or via any other legacy path)
  /// still carry account_code='5299', an account the seed never creates.
  /// Re-points them to '6214' (مصروفات متنوعة - إدارة, always seeded by
  /// syncDefaultAccounts()) so expenses recorded against them post to the
  /// GL instead of silently missing the P&L.
  ///
  /// Server/standalone only (mirrors the `_isClientMode()` gate already used
  /// by `_syncPermissionsAndAccounts()` in database_startup.dart): per R5,
  /// op_expense_categories is master data (serverWins) on client/mirror
  /// installs — a local UPDATE there would just be overwritten by the next
  /// sync. Idempotent, guarded by a durable settings flag so it runs at most
  /// once per install (mirrors `backfillStockMovementUnitCost`, C-PERF-2).
  ///
  /// Returns rows fixed, or -1 when skipped (already applied / client mode).
  Future<int> backfillLegacyExpenseCategoryAccountCode() async {
    const flag = 'exp1_category_account_backfill_v1_applied';
    if (await getSettingValue(flag) == 'true') return -1;

    // Client/mirror: the server owns this table. Arm the flag anyway so a
    // later re-check doesn't keep re-scanning on every boot — sync will
    // converge these rows from the server's already-fixed copy.
    if (await _isClientMode()) {
      await setSetting(flag, 'true');
      return -1;
    }

    int fixed = 0;
    try {
      fixed = await customUpdate(
        "UPDATE op_expense_categories SET account_code = '6214' "
        "WHERE account_code = '5299'",
        updates: {opExpenseCategories},
      );
    } catch (e) {
      debugPrint('[EXP-1] backfillLegacyExpenseCategoryAccountCode: $e');
      return 0;
    }
    await setSetting(flag, 'true');
    if (fixed > 0) {
      debugPrint('[EXP-1] backfillLegacyExpenseCategoryAccountCode: '
          're-pointed $fixed categories 5299→6214');
    }
    return fixed;
  }

  /// Record an operational expense
  Future<int> recordExpense({
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    String period = 'monthly',
    int? manufacturingOrderId,
    String? reference,
    String? notes,
    required int userId,
    int? branchId,
  }) =>
      into(opExpenses).insert(OpExpensesCompanion.insert(
        categoryId: categoryId,
        amount: amount,
        expenseDate: expenseDate,
        period: Value(period),
        manufacturingOrderId: Value(manufacturingOrderId),
        reference: Value(reference),
        notes: Value(notes),
        userId: userId,
        branchId: Value(branchId),
      ));

  /// EXP-2 (batch B7 / S-FAILLOUD): atomic record + GL-post for an
  /// operational expense.
  ///
  /// Previously the caller (opex_record_edit_dialog.dart) made two
  /// independent DAO calls — [recordExpense] (insert) then
  /// [AccountingAutopostDao.autoPostOperationalExpense] (JE post) — with no
  /// shared transaction. If the post threw (e.g. EXP-1's unresolvable-
  /// account guard), the op_expenses row from the FIRST call was already
  /// committed with no rollback path: the expense existed with no journal
  /// entry and no automatic recovery beyond the separate orphan-repost pass
  /// (autopost_repair_dao.dart). Wrapping both writes in ONE transaction
  /// makes them atomic — a thrown post rolls the insert back too, so a
  /// failed save leaves no trace instead of a silent GL-less orphan.
  ///
  /// [autoPostOperationalExpense] does not open its own `transaction()` (it
  /// ends in a single [AccountingDao.createJournalEntry] call), so nesting it
  /// here is the same safe pattern already used by [applyStockAdjustment]
  /// and `createPurchaseInvoice` — NOT the autoPostCashSale/autoPostCreditSale
  /// case that is documented as unsafe to nest (see autoPostDeliveryConfirmed
  /// above for that specific caveat).
  ///
  /// Returns the new op_expenses row id.
  ///
  /// B13 (EXP-3 / S-EXP-REST): a CASH expense also moves the safe. Previously
  /// this method posted ONLY the GL entry (Dr expense / Cr cash-or-bank) and
  /// never touched `safe_transactions` / `safes.balance` — the physical cash
  /// drawer stayed untouched while the GL said cash left. [safeId] lets the
  /// caller pick an explicit safe; when omitted the default cash safe is
  /// resolved. Scope: CASH only — a `paymentMethod == 'bank'` expense stays
  /// GL-only for now (no per-transaction bank-safe movement flow is wired to
  /// this dialog yet); see the comment at the safe-movement block below.
  ///
  /// Double-count guard: the new safe_transactions row is tagged
  /// `referenceType: 'op_expense', referenceId: expenseId` so
  /// [getExpensesForReport] / [getMonthlyExpenseSummary] — which UNION
  /// `op_expenses` with expense-flavored `safe_transactions` — can exclude
  /// it from their safe_transactions side of the union and count the expense
  /// exactly once (via the op_expenses side). See the `reference_type <>
  /// 'op_expense'` filter added to both queries below.
  Future<int> recordAndPostOperationalExpense({
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required String description,
    required String expenseAccountCode,
    String period = 'monthly',
    int? manufacturingOrderId,
    String? reference,
    String? notes,
    required int userId,
    int? branchId,
    int? costCenterId,
    String? paymentMethod,
    // B13 (EXP-3): optional explicit safe for a CASH expense. Omitted →
    // resolves the default cash safe (getDefaultSafeByType('cash')).
    int? safeId,
  }) async {
    return transaction(() async {
      final expenseId = await recordExpense(
        categoryId: categoryId,
        amount: amount,
        expenseDate: expenseDate,
        period: period,
        manufacturingOrderId: manufacturingOrderId,
        reference: reference,
        notes: notes,
        userId: userId,
        branchId: branchId,
      );

      // EXP-1: throws (never silently returns null) when a required GL
      // account can't be resolved — that now rolls back the insert above too.
      final jeId = await accountingDao.autoPostOperationalExpense(
        expenseId: expenseId,
        amount: amount,
        description: description,
        expenseAccountCode: expenseAccountCode,
        costCenterId: costCenterId,
        branchId: branchId,
        date: expenseDate,
        paymentMethod: paymentMethod,
      );

      // B13 (EXP-3): move the safe AFTER the GL JE posts, so a safe
      // movement never lands without its GL counterpart (jeId != null —
      // autoPostOperationalExpense only returns null for the amount<=0 /
      // already-posted early-outs, neither of which applies to a fresh
      // insert with a caller-validated amount>0).
      //
      // 'bank' stays GL-only for now — mirrors autoPostOperationalExpense's
      // own cash/bank leg choice (creditPurpose) one call above; a
      // per-transaction bank-safe movement flow isn't wired to this dialog.
      //
      // R4 gate (committee B13 finding #1): treasury is server-authoritative
      // in client/mirror mode — the client must NOT write the safe locally
      // (this raw row carries no threaded globalId, so a local write would
      // risk a divergent/duplicated cash movement on the next sync). Restrict
      // the safe move to standalone/server, where it is the source of truth.
      // Full client-mode op-expense treasury submit is a deferred multi-device
      // gap (the same flow's GL JE already submits via createJournalEntry;
      // the treasury submit counterpart does not exist yet).
      final isCashExpense = paymentMethod != 'bank';
      if (jeId != null && isCashExpense && !SyncInterceptor.isClientMode) {
        Safe? targetSafe;
        if (safeId != null) {
          targetSafe = await (select(safes)..where((s) => s.id.equals(safeId)))
              .getSingleOrNull();
        }
        targetSafe ??= await getDefaultSafeByType('cash');

        // Fail loud instead of silently posting a GL entry with no treasury
        // movement — consistent with B7's addPurchasePayment no-safe guard.
        if (targetSafe == null) {
          throw StateError(
            'تعذّر تسجيل المصروف التشغيلي: لا يوجد صندوق نقدي مُهيّأ لخصم '
            'المبلغ منه. راجع إعدادات الصناديق قبل تسجيل مصروف نقدي.',
          );
        }

        final newBalance = targetSafe.balance - amount;
        final voucherNumber = await generateInvoiceNumber('PV');

        await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: targetSafe.id,
            transactionType: 'payment',
            category: 'expense',
            amount: amount,
            balanceAfter: newBalance,
            referenceType: const Value('op_expense'),
            referenceId: Value(expenseId),
            userId: Value(userId),
            costCenterId: Value(costCenterId),
          ),
        );

        // H15 — حسابٌ ذرّيّ لا كتابةٌ مطلقة: مصروفان نقديّان متزامنان على
        // نفس الخزنة كانا يقرآن نفسَ الرصيد فيضيع أحدُ الخصمين.
        await adjustSafeBalance(targetSafe.id, -amount);
      }

      return expenseId;
    });
  }

  /// Get expenses for a date range with category name
  Future<List<Map<String, dynamic>>> getExpensesReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final results = await customSelect(
      '''
      SELECT e.*, c.name as category_name, c.type as category_type
      FROM op_expenses e
      JOIN op_expense_categories c ON e.category_id = c.id
      WHERE e.expense_date BETWEEN ? AND ?
      ORDER BY e.expense_date DESC
      ''',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {opExpenses, opExpenseCategories},
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Map an Arabic-friendly label to the loose `category` text values that
  /// `safe_transactions` uses across treasury vouchers, POS quick expenses,
  /// and sales-return refunds. Keeps the report grouping readable instead
  /// of showing raw codes like `supplier_payment` next to ops categories.
  String _safeTxCategoryLabel(String? raw) {
    switch (raw) {
      case 'sales_return':
        return 'مرتجع مبيعات نقدي';
      case 'sales_return_balance':
        return 'مرتجع مبيعات (تسوية رصيد)';
      case 'supplier_payment':
        return 'سداد مورد (سند صرف)';
      case 'salary':
        return 'رواتب';
      case 'rent':
        return 'إيجار';
      case 'expense':
        return 'مصروف عام';
      case 'other_expense':
        return 'مصروفات أخرى';
      case 'other':
        return 'أخرى';
      case 'advance':
        return 'سلف';
      case 'supplies':
        return 'مستلزمات';
      case 'utilities':
        return 'مرافق';
      case 'maintenance':
        return 'صيانة';
      case null:
      case '':
        return 'بدون فئة';
      default:
        return raw;
    }
  }

  /// Categories on safe_transactions that should NOT be treated as
  /// expenses in this report — they're inflows / transfers / sale
  /// proceeds, not money leaving the business.
  static const _nonExpenseSafeCategories = {
    'sales',
    'sales_collection',
    'customer_receipt',
    'transfer',
    'opening_balance',
    'cash_in',
  };

  /// Authoritative branch-scope cap for the expenses report. Same contract as
  /// the canonical `_buildAuthScopeFilter` (accounting_reports_dao.dart:79,
  /// sales_analytics_dao.dart:57 — redeclared here because four extensions on
  /// AppDatabase already carry that name, so a shared call would be ambiguous):
  ///   null  → no cap (admin / userId=1 / mirror / cross-branch-elevated)
  ///   {}    → `AND 1 = 0` (fail-closed — no branch access means no rows)
  ///   {ids} → those branches OR NULL-branch (head-office / shared) rows
  ///
  /// Why it is needed here: the screen capped nothing at all. It seeded
  /// `_selectedBranchId` from `activeBranchIdProvider`, which returns null for a
  /// user with no branch assignment — the very user branchScopeProvider hands
  /// `{}` («sees nothing»). Fail-closed inverted to fail-open: that user read
  /// the WHOLE company's expense amounts, categories, payment methods and notes.
  ({String filter, List<Variable> vars}) _expenseAuthScope(
    Set<int>? allowedBranchIds,
    String tableAlias,
  ) {
    if (allowedBranchIds == null) return (filter: '', vars: <Variable>[]);
    if (allowedBranchIds.isEmpty) {
      return (filter: 'AND 1 = 0', vars: <Variable>[]);
    }
    final col = '$tableAlias.branch_id';
    final ph = allowedBranchIds.map((_) => '?').join(', ');
    return (
      filter: 'AND ($col IN ($ph) OR $col IS NULL)',
      vars: allowedBranchIds.map<Variable>((id) => Variable<int>(id)).toList(),
    );
  }

  /// Get monthly expense summary by category — combines `op_expenses` rows
  /// with the expense-flavored `safe_transactions` (POS quick expense,
  /// treasury "سند صرف", cash sales-return refunds). Filtered by branch +
  /// user. `safe_transactions` has no `branch_id` of its own, so the branch
  /// is taken from the owning safe (`safes.branch_id` via the join) — and a
  /// safe with no branch is treated as **shared**, exactly like an
  /// `op_expenses` row with no branch. Both halves must agree on what NULL
  /// means or Σ(table) ≠ card.
  Future<List<Map<String, dynamic>>> getMonthlyExpenseSummary({
    required DateTime from,
    required DateTime to,
    int? branchId,
    int? userId,
    Set<int>? allowedBranchIds,
  }) async {
    final opBranchFilter = branchId != null
        ? 'AND (e.branch_id IS NULL OR e.branch_id = $branchId)'
        : '';
    final opUserFilter = userId != null ? 'AND e.user_id = $userId' : '';
    final opScope = _expenseAuthScope(allowedBranchIds, 'e');
    final stScope = _expenseAuthScope(allowedBranchIds, 's');
    final opRows = await customSelect(
      '''
      SELECT c.id as cat_id, c.name as cat_name, c.type as cat_type,
             c.is_production_related,
             COALESCE(SUM(e.amount), 0) as total_amount,
             COUNT(e.id) as entry_count
      FROM op_expense_categories c
      LEFT JOIN op_expenses e ON c.id = e.category_id
        AND e.expense_date BETWEEN ? AND ?
        $opBranchFilter
        $opUserFilter
        ${opScope.filter}
      -- H11 · `c.is_active` وحدَه كان يُسقط مصروفَ أيّ تصنيفٍ عُطِّل لاحقاً،
      -- بينما جدولُ التفصيل (`getExpensesForReport`) لا يعرف هذا الشرط أصلاً
      -- ⇒ الصفُّ يظهر في الجدول ولا يدخل الإجمالي، و`_averagePerEntry` يقسم
      -- مجموعَ مجموعةٍ على عدد مجموعةٍ أخرى. مقيس في الحصر: ١٬٠٠٠ مقابل
      -- ١٬٧٥٠.
      --
      -- تعطيلُ التصنيف قرارٌ مستقبليّ («لا تُسجّل عليه بعد اليوم») لا يمحو
      -- مالاً أُنفق. فالشرطُ يحكم **إظهارَ التصنيفات الفارغة** فقط: التصنيفُ
      -- الفعّال يُدرَج ولو بصفر، وأيُّ تصنيفٍ عليه صرفٌ في المدى يُدرَج مهما
      -- كانت حالتُه.
      WHERE c.is_active = ${sqlBool(true)} OR e.id IS NOT NULL
      GROUP BY c.id
      ''',
      variables: [dateVar(from), dateVar(to), ...opScope.vars],
      readsFrom: {opExpenses, opExpenseCategories},
    ).get();

    // Aggregate categorized safe_transactions by `category` text. Memo
    // rows are excluded — they exist purely as ledger annotations and
    // would double-count against the matching cash refund row.
    //
    // B13 (EXP-3) double-count guard: also exclude rows whose
    // reference_type = 'op_expense'. Those are the safe movements that
    // [recordAndPostOperationalExpense] now writes for CASH operational
    // expenses (category = 'expense') — the SAME expense is already
    // counted once via the `opRows` query above (the op_expenses side of
    // this UNION). Without this filter a cash op-expense would be summed
    // TWICE: once from op_expenses, once from its own safe_transactions
    // movement.
    final stUserFilter = userId != null ? 'AND st.user_id = $userId' : '';
    // NULL = «مشترَكة» — نفسُ معنى شقّ `op_expenses` أعلاه ونفسُ ما يفعله
    // `_expenseAuthScope` على الشقّين. وكان `s.branch_id = ?` وحدَه، وNULL
    // لا تساوي شيئاً في SQL ⇒ الخزنةُ الافتراضية (‏`branch_id` فارغ في
    // تجهيزةٍ بفرعٍ واحد) تسقط، فيُخفي أيُّ اختيارِ فرعٍ **كلَّ** سندات
    // الصرف النقدية بلا أن ينطق.
    final stBranchFilter = branchId != null
        ? 'AND (s.branch_id IS NULL OR s.branch_id = $branchId)'
        : '';
    final stRows = await customSelect(
      '''
      SELECT COALESCE(st.category, '') as category,
             COALESCE(SUM(st.amount), 0) as total_amount,
             COUNT(st.id) as entry_count
      FROM safe_transactions st
      LEFT JOIN safes s ON st.safe_id = s.id
      WHERE st.created_at BETWEEN ? AND ?
        AND st.deleted_at IS NULL
        AND st.transaction_type IN ('payment', 'withdrawal')
        AND COALESCE(st.category, '') NOT IN
            ('sales','sales_collection','customer_receipt','transfer',
             'opening_balance','cash_in')
        AND COALESCE(st.reference_type, '') != 'op_expense'
        $stUserFilter
        $stBranchFilter
        ${stScope.filter}
      GROUP BY st.category
      ''',
      variables: [dateVar(from), dateVar(to), ...stScope.vars],
      readsFrom: {safeTransactions, safes},
    ).get();

    // Merge: emit one row per op_expense_categories entry (so the
    // existing UI keeps showing categories with zero current activity)
    // followed by the cash-side categories that don't have a matching
    // op_expense_categories row. The shape mirrors the previous return
    // value so the screen doesn't need any new fields.
    final merged = <Map<String, dynamic>>[];
    for (final r in opRows) {
      merged.add({
        'id': r.data['cat_id'],
        'name': r.data['cat_name'],
        'type': r.data['cat_type'],
        'is_production_related': r.data['is_production_related'],
        'total_amount': (r.data['total_amount'] as num?)?.toDouble() ?? 0.0,
        'entry_count': r.data['entry_count'] ?? 0,
      });
    }
    for (final r in stRows) {
      merged.add({
        'id': null,
        'name': _safeTxCategoryLabel(r.data['category'] as String?),
        'type': 'cash_outflow',
        'is_production_related': false,
        'total_amount': (r.data['total_amount'] as num?)?.toDouble() ?? 0.0,
        'entry_count': r.data['entry_count'] ?? 0,
      });
    }
    merged.sort((a, b) {
      final av = (a['total_amount'] as num?)?.toDouble() ?? 0.0;
      final bv = (b['total_amount'] as num?)?.toDouble() ?? 0.0;
      return bv.compareTo(av);
    });
    return merged;
  }

  /// Get expenses for report — combines `op_expenses` rows with
  /// expense-flavored `safe_transactions` (POS quick expense, treasury
  /// "سند صرف", cash sales-return refunds). Returns a single date-sorted
  /// list with a `source` tag so callers can distinguish if needed.
  Future<List<Map<String, dynamic>>> getExpensesForReport({
    required DateTime from,
    required DateTime to,
    int? branchId,
    int? userId,
    Set<int>? allowedBranchIds,
  }) async {
    // Was `e.branch_id = ?` while the summary above used
    // `(e.branch_id IS NULL OR e.branch_id = ?)`. A head-office expense with no
    // branch counted toward the KPI card but never appeared in the table, so
    // Σ rows ≠ card and `_averagePerEntry` divided one set's total by another
    // set's count. The summary's semantics win — NULL-branch rows are shared.
    final opBranchFilter = branchId != null
        ? 'AND (e.branch_id IS NULL OR e.branch_id = $branchId)'
        : '';
    final opUserFilter = userId != null ? 'AND e.user_id = $userId' : '';
    final opScope = _expenseAuthScope(allowedBranchIds, 'e');
    final stScope = _expenseAuthScope(allowedBranchIds, 's');
    final opRowsRaw = await customSelect(
      '''
      SELECT e.id, e.amount, e.expense_date, e.period, e.reference, e.notes,
             e.status, e.payment_method, e.branch_id, e.user_id,
             c.name as category_name, c.type as category_type,
             b.name as branch_name,
             u.username as user_name
      FROM op_expenses e
      JOIN op_expense_categories c ON e.category_id = c.id
      LEFT JOIN branches b ON e.branch_id = b.id
      LEFT JOIN users u ON e.user_id = u.id
      WHERE e.expense_date BETWEEN ? AND ?
        $opBranchFilter
        $opUserFilter
        ${opScope.filter}
      ORDER BY e.expense_date DESC
      ''',
      variables: [dateVar(from), dateVar(to), ...opScope.vars],
      readsFrom: {opExpenses, opExpenseCategories, branches, users},
    ).get();

    // B13 (EXP-3) double-count guard — same rationale as
    // getMonthlyExpenseSummary above: exclude safe_transactions rows that
    // reference an op_expense (recordAndPostOperationalExpense's own cash
    // movement) since that expense already appears via `opRowsRaw`.
    final stUserFilter = userId != null ? 'AND st.user_id = $userId' : '';
    // NULL = «مشترَكة» — نفسُ معنى شقّ `op_expenses` أعلاه ونفسُ ما يفعله
    // `_expenseAuthScope` على الشقّين. وكان `s.branch_id = ?` وحدَه، وNULL
    // لا تساوي شيئاً في SQL ⇒ الخزنةُ الافتراضية (‏`branch_id` فارغ في
    // تجهيزةٍ بفرعٍ واحد) تسقط، فيُخفي أيُّ اختيارِ فرعٍ **كلَّ** سندات
    // الصرف النقدية بلا أن ينطق.
    final stBranchFilter = branchId != null
        ? 'AND (s.branch_id IS NULL OR s.branch_id = $branchId)'
        : '';
    final stRowsRaw = await customSelect(
      '''
      SELECT st.id, st.amount, st.created_at as expense_date,
             st.voucher_number as reference, st.description as notes,
             st.transaction_type, st.category, st.user_id,
             s.name as safe_name, s.safe_type as safe_type,
             s.branch_id as safe_branch_id,
             b.name as branch_name,
             u.username as user_name
      FROM safe_transactions st
      LEFT JOIN safes s ON st.safe_id = s.id
      LEFT JOIN branches b ON s.branch_id = b.id
      LEFT JOIN users u ON st.user_id = u.id
      WHERE st.created_at BETWEEN ? AND ?
        AND st.deleted_at IS NULL
        AND st.transaction_type IN ('payment', 'withdrawal')
        AND COALESCE(st.category, '') NOT IN
            ('sales','sales_collection','customer_receipt','transfer',
             'opening_balance','cash_in')
        AND COALESCE(st.reference_type, '') != 'op_expense'
        $stUserFilter
        $stBranchFilter
        ${stScope.filter}
      ORDER BY st.created_at DESC
      ''',
      variables: [dateVar(from), dateVar(to), ...stScope.vars],
      readsFrom: {safeTransactions, safes, branches, users},
    ).get();

    final merged = <Map<String, dynamic>>[];
    for (final r in opRowsRaw) {
      final m = Map<String, dynamic>.from(r.data);
      m['source'] = 'op_expense';
      merged.add(m);
    }
    for (final r in stRowsRaw) {
      // Prefer the safe's linked branch over a NULL fallback so the
      // detail row still tells the user where the cash came from.
      final branchLabel = (r.data['branch_name'] as String?) ??
          (r.data['safe_name'] as String?) ??
          '—';
      merged.add({
        'id': r.data['id'],
        'amount': r.data['amount'],
        'expense_date': r.data['expense_date'],
        'reference': r.data['reference'],
        'notes': r.data['notes'],
        'status': null,
        'payment_method': r.data['safe_type'],
        'branch_id': r.data['safe_branch_id'],
        'user_id': r.data['user_id'],
        'category_name': _safeTxCategoryLabel(r.data['category'] as String?),
        'category_type': 'cash_outflow',
        'branch_name': branchLabel,
        'user_name': r.data['user_name'],
        'source': 'safe_tx',
      });
    }

    // Sort by expense_date desc. Both columns return DateTime objects via
    // Drift's `customSelect` so a direct compare works.
    merged.sort((a, b) {
      final da = a['expense_date'];
      final db_ = b['expense_date'];
      if (da == null && db_ == null) return 0;
      if (da == null) return 1;
      if (db_ == null) return -1;
      return (db_ as Comparable).compareTo(da as Comparable);
    });
    return merged;
  }

  /// Get total production-related expenses for a period
  Future<double> getTotalProductionExpenses({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(e.amount), 0) as total
      FROM op_expenses e
      JOIN op_expense_categories c ON e.category_id = c.id
      WHERE c.is_production_related = ${sqlBool(true)}
        AND e.expense_date BETWEEN ? AND ?
      ''',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {opExpenses, opExpenseCategories},
    ).getSingle();
    return (result.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// C-01: Delete an operational expense WITH GL reversal
  /// Finds and removes the associated journal entry before deleting the expense record.
  Future<int> deleteExpense(int expenseId) async {
    return transaction(() async {
      // Find and delete the associated journal entry (if any)
      final relatedEntry = await (select(journalEntries)
            ..where((e) => e.referenceType.equals('op_expense') & e.referenceId.equals(expenseId)))
          .getSingleOrNull();

      if (relatedEntry != null) {
        // Query affected account IDs BEFORE deleting lines
        final affectedLines = await customSelect(
          'SELECT DISTINCT account_id FROM journal_entry_lines WHERE entry_id = ?',
          variables: [Variable(relatedEntry.id)],
          readsFrom: {journalEntryLines},
        ).get();
        final affectedAccountIds = affectedLines.map((r) => r.read<int>('account_id')).toList();

        // Delete journal entry lines first (FK constraint)
        await (delete(journalEntryLines)..where((l) => l.entryId.equals(relatedEntry.id))).go();
        // Delete the journal entry
        await (delete(journalEntries)..where((e) => e.id.equals(relatedEntry.id))).go();

        // Recalculate affected account balances (self-healing)
        for (final accId in affectedAccountIds) {
          await accountingDao._updateAccountBalance(accId, 0);
        }
      }

      // F-03 (Spec 151): reverse the TREASURY leg too, atomically in this
      // same transaction. recordAndPostOperationalExpense records a
      // `safe_transactions` row (referenceType 'op_expense', referenceId =
      // expenseId) and DEBITS the safe (updateSafeBalance) for a CASH expense
      // in standalone/server mode. Deleting the expense used to reverse ONLY
      // the GL — the safe row stayed as an orphan child and safes.balance
      // stayed down, so the cash subledger diverged from the GL on every
      // opex-tab delete.
      //
      // Existence-driven, NOT condition-derived: we reverse EXACTLY what the
      // create side actually recorded. A client-mode or 'bank' expense never
      // inserted such a row (the create-side gate is
      // `jeId != null && paymentMethod != 'bank' && !SyncInterceptor.isClientMode`),
      // so this query returns nothing and correctly leaves every safe
      // untouched — no risk of wrongly crediting a safe that was never
      // debited. Each row is reversed by its OWN recorded safeId + amount
      // (the opposite direction of the original payment), so an explicit-safe
      // expense restores the exact safe it drew from. adjustSafeBalance issues
      // an atomic `balance = balance + ?`, so the reversal is correct under
      // concurrency as well.
      final expenseSafeTxns = await (select(safeTransactions)
            ..where((t) =>
                t.referenceType.equals('op_expense') &
                t.referenceId.equals(expenseId)))
          .get();
      for (final tx in expenseSafeTxns) {
        await adjustSafeBalance(tx.safeId, tx.amount);
      }
      if (expenseSafeTxns.isNotEmpty) {
        await (delete(safeTransactions)
              ..where((t) =>
                  t.referenceType.equals('op_expense') &
                  t.referenceId.equals(expenseId)))
            .go();
      }

      return (delete(opExpenses)..where((e) => e.id.equals(expenseId))).go();
    });
  }
}
