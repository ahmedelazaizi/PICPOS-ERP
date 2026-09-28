import '../models/document_record.dart';

/// Treasury repository interface
///
/// Defines contract for treasury/safe operations. Implementations in data layer.
abstract class ITreasuryRepository {
  /// **رقمُ** سندٍ بمعرّفه — أو `null` حين لا يوجد صفُّه بعد.
  ///
  /// ⚠️ **رقمٌ لا صفٌّ**: هذه الواجهةُ في `domain` فلا تعرف أنواعَ drift،
  /// وإعادةُ الصفّ كانت ستُدخلها. والشاشةُ تعرض الرقمَ وحدَه.
  ///
  /// و`null` حين لا يوجد: معرّفٌ من ورقةٍ وصلت بالمزامنة قد يشير إلى صفٍّ
  /// لم يصل بعد، فتعرض الشاشةُ «—» ولا تنهار.
  Future<String?> getVoucherNumberById(int id);

  // ═══════════════════════════════════════════════════════════════════════════
  // SAFE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // SHIFT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get currently open shift for a user
  Future<ShiftData?> getCurrentOpenShift(int userId);

  /// Spec 135 NOTE 2 (req 4) — open shifts on a branch (any user), newest
  /// first. Used by the closing dialog when a system admin reconciles/closes a
  /// previous cashier's shift; a picker is shown when more than one is open.
  Future<List<ShiftData>> getOpenShiftsForBranch({int? branchId});

  /// Open a new shift.
  ///
  /// Spec 008 / FR-003: [branchId] records the operating branch so the
  /// close path zeroes the correct branch's safes for multi-branch users.
  /// Pass null for full-access users (system admin / mirror admin) — the
  /// close path's legacy fallback handles those.
  Future<void> openShift(int userId, double openingBalance, {int? branchId});

  /// Close shift with blind audit (variance calculation).
  /// [onVarianceJeFailed]: optional callback when variance JE fails (GAP-24).
  Future<void> closeShiftWithAudit(int shiftId, double actualCash, {String? notes, String closingMethod = 'normal', String? closingSnapshot, void Function(double)? onVarianceJeFailed});

  /// Watch all active safes
  Stream<List<SafeData>> watchSafes();

  /// Feature 005 Phase 8 — branch-scoped variant.
  /// Returns active safes belonging to one of [branchIds] (or NULL branch_id).
  /// Pass `null` for unrestricted access (admin / financial manager).
  Stream<List<SafeData>> watchSafesForBranches(Set<int>? branchIds);

  /// سجلُّ السندات لاتّجاهٍ واحد — ما تعرضه شاشةُ السجلّ (خ‑٩).
  ///
  /// ⚠️ **يعيد [VoucherRecord] لا صفَّ drift**: هذه الواجهةُ في `domain`
  /// فلا تعرف أنواعَ المحرّك — وهو عينُ ما يقوله [getVoucherNumberById]
  /// أعلاه. وشاشاتُ السجلّ جديدةٌ فلا يجوز لها استيرادُ `data/database`
  /// أصلاً (`presentation_db_import_guard`).
  ///
  /// و`branchIds` مجموعةُ `branchScopeProvider`: `null` = وصولٌ كامل.
  Stream<List<VoucherRecord>> watchVoucherRecords({
    required VoucherDirection direction,
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
    String? search,
  });

  /// Get safe by ID
  Future<SafeData?> getSafeById(int id);

  /// Get default safe by type (cash/bank)
  Future<SafeData?> getDefaultSafeByType(String type);

  /// Update safe balance
  Future<void> updateSafeBalance(int safeId, double newBalance);

  /// Get total cash balance across all safes
  Future<double> getTotalCashBalance();

  /// Create a safe transaction (PIR Architecture)
  Future<int> createSafeTransaction({
    required String voucherNumber,
    required int safeId,
    required String transactionType,
    required String category,
    required double amount,
    required double balanceAfter,
    String? referenceType,
    int? referenceId,
    String? description,
    int? userId,
  });

  /// Get safe by ID (generic data)
  Future<SafeData?> getSafeByIdRaw(int id);

  // ═══════════════════════════════════════════════════════════════════════════
  // VOUCHER OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create receipt voucher (سند قبض)
  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    bool manualEntry = false,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    // Check metadata
    String? paperNumber,
    String? paperType,
    DateTime? paperIssueDate,
    DateTime? paperDueDate,
    String? paperBankName,
    // Issue 12: stable cross-install identity for sync dedup
    String? globalId,
    // Spec 135 BUG-C — operator's working branch for JE attribution
    int? operatingBranchId,
    int? currencyId,
    double? paymentRate,
    double? foreignAmount,
  });

  /// Create payment voucher (سند صرف)
  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    bool manualEntry = false,
    /// UUID-First: callers that also sync this voucher to a remote server
    /// can pass an explicit globalId so the local and server rows share
    /// identity — lets pull-sync dedupe by UUID instead of creating a
    /// second row for the same logical voucher.
    String? globalId,
    // Check metadata
    String? paperNumber,
    String? paperType,
    DateTime? paperIssueDate,
    DateTime? paperDueDate,
    String? paperBankName,
    // Spec 135 BUG-C — operator's working branch for JE attribution
    int? operatingBranchId,
    int? currencyId,
    double? paymentRate,
    double? foreignAmount,
  });

  /// Close safe daily (اقفال يومي)
  Future<void> closeSafe(
    int safeId, {
    double? cashAmount,
    double? bankAmount,
    String? notes,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch recent transactions
  Stream<List<TransactionData>> watchRecentTransactions({int limit = 50});

  /// Issue 14 — branch-scoped variant. `branchIds == null` ⇒ full access.
  Stream<List<TransactionData>> watchRecentTransactionsForBranches(
    Set<int>? branchIds,
  );

  /// Get transactions by date range (with optional user filter)
  Future<List<TransactionData>> getTransactionsByDateRange(
    DateTime from,
    DateTime to, {
    int? userId,
  });

  /// Get transactions by category
  Future<Map<String, double>> getTransactionsByCategory({
    required String type,
    DateTime? from,
    DateTime? to,
  });

  /// Get transactions by reference (PIR Architecture)
  Future<List<TransactionData>> getTransactionsByReference(String referenceType, int referenceId);

  /// Issue 12 (Feature 019): used by the POS quick-expense dialog to fetch
  /// the just-created safe-transaction row so the auto-print path can read
  /// the server-assigned `voucher_number`. Returns null if the row was
  /// already soft-deleted between save and lookup.
  Future<TransactionData?> getTransactionById(int id);

  /// Get actual safe accounts used by a specific reference (used for POS-to-AutoPost mapping)
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(String referenceType, int referenceId);

  /// Get transactions since date
  Future<List<TransactionData>> getTransactionsSince(DateTime since);

  /// Get transactions for a specific safe since a given date (PIR-009)
  Future<List<TransactionData>> getSafeTransactionsForDate(int safeId, DateTime since);

  /// Get last closing transaction
  Future<TransactionData?> getLastClosingTransaction();

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get treasury summary
  Future<TreasurySummaryData> getTreasurySummary({
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Delete an expense/payment transaction and reverse safe balance
  Future<void> deleteExpenseTransaction(int transactionId);

  // ═══════════════════════════════════════════════════════════════════════════
  // SAFE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new safe
  Future<int> createSafe({required String name, required String safeType, String? bankName, String? accountNumber, int? costCenterId, int? branchId, int? linkedAccountId});

  /// Update safe details (name, bank info, cost center, branch, linked account)
  Future<void> updateSafeDetails({required int safeId, required String name, String? bankName, String? accountNumber, int? costCenterId, int? branchId, int? linkedAccountId});

  /// Set a safe as the default
  Future<void> setDefaultSafe(int safeId);

  /// Toggle safe active/inactive
  Future<void> toggleSafeActive(int safeId, bool isActive);

  /// Delete a safe by ID
  Future<void> deleteSafeById(int safeId);

  /// Get all safes (generic)
  Future<List<SafeData>> getSafesList();

  /// Get calculated balance from transactions (PIR Integrity)
  Future<double> getCalculatedSafeBalance(int safeId);
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Safe data
class SafeData {
  final int id;
  final String name;
  final String safeType; // cash, bank
  final double balance;
  final bool isDefault;
  final bool isActive;
  final String? bankName;
  final String? accountNumber;
  final int? costCenterId;
  final int? branchId;
  final int? linkedAccountId;

  const SafeData({
    required this.id,
    required this.name,
    required this.safeType,
    required this.balance,
    required this.isDefault,
    required this.isActive,
    this.bankName,
    this.accountNumber,
    this.costCenterId,
    this.branchId,
    this.linkedAccountId,
  });
}

/// Transaction data
class TransactionData {
  final int id;
  final String voucherNumber;
  final int safeId;
  final String safeName;
  final String transactionType; // receipt, payment
  final String category;
  final double amount;
  final double discount;
  final double balanceAfter;
  final int? partyId;
  final String? partyName;
  final String? description;
  final int? userId;
  final String? userName;
  final DateTime createdAt;

  const TransactionData({
    required this.id,
    required this.voucherNumber,
    required this.safeId,
    required this.safeName,
    required this.transactionType,
    required this.category,
    required this.amount,
    required this.discount,
    required this.balanceAfter,
    this.partyId,
    this.partyName,
    this.description,
    this.userId,
    this.userName,
    required this.createdAt,
  });
}

/// Treasury summary data
class TreasurySummaryData {
  final double totalReceipts;
  final double totalPayments;
  final double netBalance;
  final double currentBalance;
  final int transactionCount;

  const TreasurySummaryData({
    required this.totalReceipts,
    required this.totalPayments,
    required this.netBalance,
    required this.currentBalance,
    this.transactionCount = 0,
  });
}

/// Shift data (domain-layer representation of a cashier shift)
class ShiftData {
  final int id;
  final int userId;
  final DateTime startTime;
  final DateTime? endTime;
  final double openingBalance;
  final double? expectedCash;
  final double? actualCash;
  final double? variance;
  final String status;
  final String? notes;
  // Constitution R9: stable identity used by the open/close shift flow to
  // resolve the right server-side row regardless of local↔server id divergence.
  final String? globalId;

  const ShiftData({
    required this.id,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.openingBalance,
    this.expectedCash,
    this.actualCash,
    this.variance,
    required this.status,
    this.notes,
    this.globalId,
  });
}
