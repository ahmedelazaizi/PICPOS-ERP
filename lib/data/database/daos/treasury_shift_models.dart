part of '../database.dart';

/// One expense line item surfaced by [getShiftClosingAggregates] for the
/// dialog's "detailed expenses" drop-down.
class ShiftClosingExpenseItem {
  final String description;
  final double amount;
  final String safeType; // 'cash' | 'bank' | 'click'
  const ShiftClosingExpenseItem({
    required this.description,
    required this.amount,
    required this.safeType,
  });
}

/// Per-channel aggregation of everything that touched the cashier's drawer
/// during a shift. Produced by [getShiftClosingAggregates] and consumed by
/// the shift-close reconciliation dialog so the accountant can match each
/// channel (cash drawer / bank POS tape / e-wallet / AR) against what the
/// system recorded.
///
/// Channels used everywhere:
///   - `cash`   — physical money in the cash drawer.
///   - `bank`   — any card / transfer / POS-machine channel.
///   - `click`  — mobile-wallet (Click Pay) channel.
///   - `credit` — not a drawer; tracks AR movement only (no "actual" count).
///
/// Every `cash/bank/click` field corresponds to a matching
/// `sales_invoices.payment_method` bucket or a `safes.safe_type` bucket for
/// vouchers. `credit` applies to invoices only — a voucher is always paid
/// through a physical safe, not an AR ledger.
class ShiftClosingAggregates {
  // ── Sales (customer-paid us) ──────────────────────────────────────────
  final double salesCash;
  final double salesBank;
  final double salesClick;
  final double salesCredit; // sum of `total` for paymentMethod=='credit'
  final int salesCreditCount; // number of credit/partial-credit sales
  final int salesCount; // non-return invoices
  final int counterSalesCount;
  final int tableSalesCount;
  final double counterSalesTotal;
  final double tableSalesTotal;

  // ── Returns (we paid back customer) ───────────────────────────────────
  final double returnsCash;
  final double returnsBank;
  final double returnsClick;
  final double returnsCredit; // AR-only refunds (paymentMethod=='credit')
  final int returnsCount;

  // ── Receipt vouchers (money IN, non-sales) ────────────────────────────
  // Typical cause: a customer paying off an older credit invoice.
  final double receiptCash;
  final double receiptBank;
  final double receiptClick;
  final int receiptCount;

  // ── Payment vouchers (money OUT to suppliers / other) ─────────────────
  // Excludes expenses (tracked separately) — these are `payment` rows with
  // non-expense categories (e.g. supplier settlements).
  final double paymentCash;
  final double paymentBank;
  final double paymentClick;
  final int paymentCount;

  // ── Expenses (money OUT for salaries / rent / utilities / etc.) ───────
  final double expensesCash;
  final double expensesBank;
  final double expensesClick;
  final int expensesCount;
  final List<ShiftClosingExpenseItem> expensesList;

  // ── Opening balance + shift metadata ──────────────────────────────────
  final double openingBalance; // cash only — bank/click start at 0 each shift
  final DateTime? shiftStartTime;

  const ShiftClosingAggregates({
    this.salesCash = 0,
    this.salesBank = 0,
    this.salesClick = 0,
    this.salesCredit = 0,
    this.salesCreditCount = 0,
    this.salesCount = 0,
    this.counterSalesCount = 0,
    this.tableSalesCount = 0,
    this.counterSalesTotal = 0,
    this.tableSalesTotal = 0,
    this.returnsCash = 0,
    this.returnsBank = 0,
    this.returnsClick = 0,
    this.returnsCredit = 0,
    this.returnsCount = 0,
    this.receiptCash = 0,
    this.receiptBank = 0,
    this.receiptClick = 0,
    this.receiptCount = 0,
    this.paymentCash = 0,
    this.paymentBank = 0,
    this.paymentClick = 0,
    this.paymentCount = 0,
    this.expensesCash = 0,
    this.expensesBank = 0,
    this.expensesClick = 0,
    this.expensesCount = 0,
    this.expensesList = const [],
    this.openingBalance = 0,
    this.shiftStartTime,
  });

  // ── Derived helpers (the "system expected" math) ──────────────────────
  double get systemCash =>
      openingBalance +
      salesCash +
      receiptCash -
      returnsCash -
      expensesCash -
      paymentCash;

  double get systemBank =>
      salesBank + receiptBank - returnsBank - expensesBank - paymentBank;

  double get systemClick =>
      salesClick + receiptClick - returnsClick - expensesClick - paymentClick;

  /// AR-only movement. Positive = customers owe more to us (net credit
  /// sales). Negative = credit returns outweighed credit sales.
  double get systemCreditNet => salesCredit - returnsCredit;

  double get totalIncomeCash => salesCash + receiptCash;
  double get totalIncomeBank => salesBank + receiptBank;
  double get totalIncomeClick => salesClick + receiptClick;

  double get totalOutflowCash => returnsCash + expensesCash + paymentCash;
  double get totalOutflowBank => returnsBank + expensesBank + paymentBank;
  double get totalOutflowClick => returnsClick + expensesClick + paymentClick;
}

class ShiftReportDto {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final String userName;
  final double openingBalance;
  final double? expectedCash;
  final double? actualCash;
  final double? variance;
  final String status;
  final String? notes;
  // Feature 017 — exposed so the shifts report screen can filter
  // client-side by branch / region without changing the DAO query.
  final int? branchId;

  /// Owner of the shift. Needed to recompute a closed shift's aggregates,
  /// which are scoped per user.
  final int userId;

  /// v151 — raw JSON of the figures the closing report was printed from,
  /// or null for shifts closed before the column existed (those are
  /// recomputed and labelled as such).
  final String? closingSnapshot;

  ShiftReportDto({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.userName,
    required this.openingBalance,
    this.expectedCash,
    this.actualCash,
    this.variance,
    required this.status,
    this.notes,
    this.branchId,
    this.userId = 0,
    this.closingSnapshot,
  });
}

/// PIR-06: Internal result DTO for shift settlement step
class _ShiftSettlementResult {
  final double variance;
  final List<SafeTransactionData> transactions;

  /// الدرجُ الذي حُسب عليه [variance] — يُكتب عليه صفُّ التسوية كي لا يبقى
  /// الفرقُ في الأستاذ بلا طرفٍ في الخزنة. `null` حين لا درجَ نقديّاً أصلاً.
  final int? drawerSafeId;

  const _ShiftSettlementResult({
    required this.variance,
    required this.transactions,
    this.drawerSafeId,
  });
}
