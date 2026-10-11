part of '../database.dart';

/// Shift-close reconciliation aggregation.
extension TreasuryShiftAggregatesDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT-CLOSE RECONCILIATION AGGREGATION
  //
  // Returns a single ShiftClosingAggregates snapshot that the shift-close
  // dialog uses to render a per-channel reconciliation table. Replaces the
  // ad-hoc aggregation loop that used to live inside `pos_closing_controller`
  // so the math is in one place and unit-testable.
  //
  // Rules:
  //   * Non-system-admin users see ONLY their own transactions. System
  //     admins see everyone's. (Matches the legacy controller semantics.)
  //   * Time window is `[shiftStart, shiftEnd ?? now]` when `shiftStart` is
  //     known; otherwise falls back to start-of-today (safe floor so we never
  //     bleed into yesterday's closed shift). `shiftEnd` is only passed when
  //     RECOMPUTING a closed shift — leaving it null there would extend the
  //     window to the present and swallow everything sold since.
  //   * `paymentMethod='mixed'` invoices are split across cash/bank/click
  //     using the per-field `cashPaid`, `bankPaid`, `clickPaid` columns.
  //   * `paymentMethod='credit'` invoices count towards AR only — they
  //     never touch the cash/bank/click buckets.
  //   * Voucher safe routing is read from `safes.safe_type` (cash / bank /
  //     click; anything else degrades to cash).
  //   * A `transaction_type='payment'` row is an **expense** when its
  //     `category` is in the well-known expense list; otherwise it's a
  //     **payment voucher** (supplier settlement, transfer out, ...).
  //   * Time-zone note: `shift_start` is stored as local DateTime; this
  //     method compares with local DateTime — no conversion needed.
  // ═══════════════════════════════════════════════════════════════════════

  /// Well-known categories that represent an *expense* rather than a
  /// payment voucher. Kept at DAO scope so UI-only code doesn't have to
  /// hard-code the list.
  static const Set<String> _expenseCategories = {
    'salary',
    'rent',
    'utilities',
    'supplies',
    'other_expense',
    'expense',
  };

  static String _normalizeSafeType(String? raw) {
    final t = (raw ?? 'cash').toLowerCase();
    if (t == 'bank') return 'bank';
    if (t == 'click') return 'click';
    return 'cash';
  }

  Future<ShiftClosingAggregates> getShiftClosingAggregates({
    required int userId,
    required bool includeAllUsers,
    DateTime? shiftStart,
    double openingBalance = 0,
    /// Issue 16 — when set, restricts the aggregate to invoices stamped
    /// with this branch and to safe_transactions whose safe lives in this
    /// branch. `null` keeps the legacy "all branches" behaviour for the
    /// admin closing path. Rows with NULL `branch_id` are intentionally
    /// included so legacy/seed data isn't silently excluded from the
    /// cashier's drawer count.
    int? branchId,

    /// Upper bound of the aggregation window. Defaults to "now", which is
    /// what closing a live shift wants.
    ///
    /// Required for RECOMPUTING an already-closed shift: without it the
    /// window runs to the present moment, so a shift closed this morning
    /// would swallow every sale made since. Only pass it for a closed
    /// shift, using that shift's `endTime`.
    DateTime? shiftEnd,
  }) async {
    final now = DateTime.now();
    final effectiveFrom = shiftStart ??
        DateTime(now.year, now.month, now.day);
    final effectiveTo = shiftEnd ?? now;

    // ── Sales invoices — SQL GROUP BY aggregation ─────────────────────
    // Previous approach loaded ALL invoice rows into Dart (potentially
    // hundreds per shift) and aggregated in a Dart loop. Replacing with
    // a single GROUP BY query reduces the result set to ≤20 rows while
    // computing the same sums inside the DB engine (where it belongs).
    //
    // Groups by (payment_method, sale_type, no_customer) so the credit-
    // routing logic below (which depends on whether a customer is attached)
    // can work on aggregate data without needing individual rows.
    final userWhere = !includeAllUsers ? 'AND user_id = ?' : '';
    // Issue 16 — branch filter on sales_invoices. NULL branch_id passes
    // through so legacy rows (pre-v133 backfill) keep being counted in
    // the cashier's drawer.
    final branchWhere = branchId != null
        ? 'AND (branch_id = ? OR branch_id IS NULL)'
        : '';
    final invoiceRows = await customSelect(
      '''
      SELECT
        payment_method,
        sale_type,
        CAST(customer_id IS NULL AS INTEGER)          AS no_customer,
        COUNT(*)                                       AS cnt,
        SUM(ABS(paid))                                AS total_paid,
        SUM(total)                                    AS total_amount,
        SUM(ABS(COALESCE(cash_paid,  0)))             AS total_cash,
        SUM(ABS(COALESCE(bank_paid,  0)))             AS total_bank,
        SUM(ABS(COALESCE(click_paid, 0)))             AS total_click,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01
               THEN total - paid ELSE 0 END
        )                                             AS credit_unpaid,
        COUNT(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01
               THEN 1 END
        )                                             AS credit_cnt,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01 AND paid > 0
               THEN paid ELSE 0 END
        )                                             AS partial_credit_cash,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NULL
               THEN CASE WHEN paid > 0 THEN paid ELSE total END
               ELSE 0 END
        )                                             AS no_cust_credit_cash,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid <= 0.01
               THEN paid ELSE 0 END
        )                                             AS full_credit_cash,
        SUM(
          CASE WHEN payment_method IN ('mixed','multiple')
                    AND total - COALESCE(cash_paid,0)
                              - COALESCE(bank_paid,0)
                              - COALESCE(click_paid,0) > 0.0001
               THEN total - COALESCE(cash_paid,0)
                          - COALESCE(bank_paid,0)
                          - COALESCE(click_paid,0)
               ELSE 0 END
        )                                             AS mixed_credit
      FROM sales_invoices
      WHERE invoice_date >= ? AND invoice_date <= ?
        AND is_deleted = 0
        $userWhere
        $branchWhere
      GROUP BY payment_method,
               sale_type,
               CAST(customer_id IS NULL AS INTEGER)
      ''',
      variables: [
        Variable<DateTime>(effectiveFrom),
        Variable<DateTime>(effectiveTo),
        if (!includeAllUsers) Variable<int>(userId),
        if (branchId != null) Variable<int>(branchId),
      ],
    ).get();

    double salesCash = 0, salesBank = 0, salesClick = 0, salesCredit = 0;
    double returnsCash = 0, returnsBank = 0, returnsClick = 0, returnsCredit = 0;
    int salesCount = 0, returnsCount = 0;
    int salesCreditCount = 0;
    int counterSalesCount = 0, tableSalesCount = 0;
    double counterSalesTotal = 0, tableSalesTotal = 0;

    for (final row in invoiceRows) {
      final method = (row.read<String?>('payment_method') ?? '').toLowerCase();
      final saleType = row.read<String?>('sale_type') ?? '';
      final cnt = row.read<int>('cnt');
      final totalPaid = row.read<double?>('total_paid') ?? 0.0;
      final totalAmount = row.read<double?>('total_amount') ?? 0.0;
      final totalCash = row.read<double?>('total_cash') ?? 0.0;
      final totalBank = row.read<double?>('total_bank') ?? 0.0;
      final totalClick = row.read<double?>('total_click') ?? 0.0;

      final isPosReturn = saleType == 'return';

      if (isPosReturn) {
        // Returns: amounts were already ABS'd in SQL → subtract from drawer.
        returnsCount += cnt;
        switch (method) {
          case 'cash':
            returnsCash += totalPaid;
          case 'click':
            returnsClick += totalPaid;
          case 'card':
          case 'transfer':
          case 'bank':
            returnsBank += totalPaid;
          case 'credit':
            // No money moved — AR credited back. Use total for AR movement.
            returnsCredit += totalAmount.abs();
          case 'mixed':
          case 'multiple':
            returnsCash += totalCash;
            returnsBank += totalBank;
            returnsClick += totalClick;
          default:
            returnsCash += totalPaid; // unknown → treat as cash
        }
      } else {
        salesCount += cnt;
        if (saleType == 'table') {
          tableSalesCount += cnt;
          tableSalesTotal += totalAmount;
        } else {
          counterSalesCount += cnt;
          counterSalesTotal += totalAmount;
        }
        switch (method) {
          case 'cash':
            salesCash += totalPaid;
          case 'click':
            salesClick += totalPaid;
          case 'card':
          case 'transfer':
          case 'bank':
            salesBank += totalPaid;
          case 'credit':
            // Aggregate credit columns computed in SQL handle all sub-cases:
            //   • no-customer credit → salesCash
            //   • partially-paid credit with customer → salesCredit + salesCash
            //   • fully-paid credit → salesCash
            salesCredit += row.read<double?>('credit_unpaid') ?? 0.0;
            salesCreditCount += row.read<int?>('credit_cnt') ?? 0;
            salesCash += (row.read<double?>('partial_credit_cash') ?? 0.0) +
                (row.read<double?>('no_cust_credit_cash') ?? 0.0) +
                (row.read<double?>('full_credit_cash') ?? 0.0);
          case 'mixed':
          case 'multiple':
            salesCash += totalCash;
            salesBank += totalBank;
            salesClick += totalClick;
            salesCredit += row.read<double?>('mixed_credit') ?? 0.0;
          default:
            salesCash += totalPaid;
        }
      }
    }

    // ── Safe transactions (vouchers + expenses) ───────────────────────
    // Join with safes to read safe_type for channel routing. Auto-generated
    // sales/purchase shadow rows are excluded at the SQL level so Dart never
    // sees them — this halves the result set on a typical busy-shift query.
    final txQuery = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
      ..where(safeTransactions.createdAt.isBiggerOrEqualValue(effectiveFrom))
      ..where(safeTransactions.createdAt.isSmallerOrEqualValue(effectiveTo))
      ..where(
        safeTransactions.referenceType.isNull() |
        safeTransactions.referenceType.isNotIn(
          ['sales_invoice', 'purchase_invoice'],
        ),
      )
      // Issue 16 — exclude soft-deleted vouchers from the cashier's
      // drawer count. The flag was already used by the treasury list
      // and reports; the closing aggregate inherited a stale row count
      // for any voucher admin had reversed during the shift.
      ..where(safeTransactions.deletedAt.isNull());
    if (!includeAllUsers) {
      txQuery.where(safeTransactions.userId.equals(userId));
    }
    if (branchId != null) {
      // Issue 16 — restrict to safes belonging to this branch (or NULL
      // branch for legacy seed safes that never got a branch link).
      txQuery.where(safes.branchId.equals(branchId) | safes.branchId.isNull());
    }
    final txRows = await txQuery.get();

    double receiptCash = 0, receiptBank = 0, receiptClick = 0;
    double paymentCash = 0, paymentBank = 0, paymentClick = 0;
    double expensesCash = 0, expensesBank = 0, expensesClick = 0;
    int receiptCount = 0, paymentCount = 0, expensesCount = 0;
    final List<ShiftClosingExpenseItem> expenseItems = [];

    // `sales_invoice` and `purchase_invoice` auto-ref rows are already
    // excluded by the SQL query above, so no Dart-level skip is needed.
    // `sales_return` rows come from the "returns screen" dialog and must
    // be counted here (the underlying invoice is outside the shift window).
    const returnsScreenRefs = {
      'sales_return',
    };

    for (final row in txRows) {
      final t = row.readTable(safeTransactions);
      final s = row.readTable(safes);
      final channel = _normalizeSafeType(s.safeType);
      final amt = t.amount.abs();

      // Returns-screen refunds: the invoice was saved in an earlier
      // shift (or this shift) and the status-change flow only recorded
      // a safe_transaction for the cash/bank/click refund. Categorise
      // those into the returns buckets so the reconciliation subtracts
      // the refund from the drawer the same way a POS return does.
      if (t.referenceType != null &&
          returnsScreenRefs.contains(t.referenceType)) {
        final cat = t.category.toLowerCase();
        // Memo entries for AR-only refunds (`category` ends with
        // `_balance`) reflect a credit customer's balance reduction.
        // No cash moved — route them to the credit returns bucket so
        // the AR column on the dialog shows the movement but the cash
        // columns stay untouched.
        if (cat.endsWith('_balance')) {
          returnsCount++;
          returnsCredit += amt;
          continue;
        }
        returnsCount++;
        switch (channel) {
          case 'bank':
            returnsBank += amt;
            break;
          case 'click':
            returnsClick += amt;
            break;
          default:
            returnsCash += amt;
        }
        continue;
      }

      // Purchase returns flow in the opposite direction (supplier gives
      // us money back — a cash INFLOW). They bucket under "receipts"
      // with the rest of the cash inflows. The balance-adjustment memo
      // (`category` ends with `_balance`) is a pure AP reduction —
      // no cash moved — so we skip those entirely, otherwise we would
      // inflate the expected cash count.
      if (t.referenceType == 'purchase_return') {
        final cat = t.category.toLowerCase();
        if (cat.endsWith('_balance')) {
          // Supplier's AP was reduced, no cash hit the drawer.
          continue;
        }
        receiptCount++;
        switch (channel) {
          case 'bank':
            receiptBank += amt;
            break;
          case 'click':
            receiptClick += amt;
            break;
          default:
            receiptCash += amt;
        }
        continue;
      }

      if (t.transactionType == 'receipt') {
        receiptCount++;
        switch (channel) {
          case 'bank':
            receiptBank += amt;
            break;
          case 'click':
            receiptClick += amt;
            break;
          default:
            receiptCash += amt;
        }
      } else if (t.transactionType == 'payment') {
        final cat = (t.category).toLowerCase();
        final isExpense = _expenseCategories.contains(cat);
        if (isExpense) {
          expensesCount++;
          switch (channel) {
            case 'bank':
              expensesBank += amt;
              break;
            case 'click':
              expensesClick += amt;
              break;
            default:
              expensesCash += amt;
          }
          final desc = (t.description != null && t.description!.isNotEmpty)
              ? t.description!
              : (cat.isNotEmpty ? cat : 'مصروف');
          expenseItems.add(ShiftClosingExpenseItem(
            description: desc,
            amount: amt,
            safeType: channel,
          ));
        } else {
          paymentCount++;
          switch (channel) {
            case 'bank':
              paymentBank += amt;
              break;
            case 'click':
              paymentClick += amt;
              break;
            default:
              paymentCash += amt;
          }
        }
      }
      // 'transfer' / 'closing' / 'adjustment' are ignored here — they are
      // internal to treasury (move between safes, zero out at close, etc.)
      // and must not affect the cashier's per-channel reconciliation.
    }

    return ShiftClosingAggregates(
      salesCash: salesCash,
      salesBank: salesBank,
      salesClick: salesClick,
      salesCredit: salesCredit,
      salesCreditCount: salesCreditCount,
      salesCount: salesCount,
      counterSalesCount: counterSalesCount,
      tableSalesCount: tableSalesCount,
      counterSalesTotal: counterSalesTotal,
      tableSalesTotal: tableSalesTotal,
      returnsCash: returnsCash,
      returnsBank: returnsBank,
      returnsClick: returnsClick,
      returnsCredit: returnsCredit,
      returnsCount: returnsCount,
      receiptCash: receiptCash,
      receiptBank: receiptBank,
      receiptClick: receiptClick,
      receiptCount: receiptCount,
      paymentCash: paymentCash,
      paymentBank: paymentBank,
      paymentClick: paymentClick,
      paymentCount: paymentCount,
      expensesCash: expensesCash,
      expensesBank: expensesBank,
      expensesClick: expensesClick,
      expensesCount: expensesCount,
      expensesList: expenseItems,
      openingBalance: openingBalance,
      shiftStartTime: shiftStart,
    );
  }
}
