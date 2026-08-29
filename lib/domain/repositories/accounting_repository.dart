import '../../data/database/database.dart';
import '../entities/accounting_entities.dart';

export '../entities/accounting_entities.dart';

/// Repository for Accounting and Chart of Accounts (COA) operations
abstract class IAccountingRepository {
  // --- Accounts (COA) ---
  Future<List<Account>> getAllAccounts();
  Stream<List<Account>> watchAllAccounts();
  Future<Account?> getAccountById(int id);
  Future<Account?> getAccountByCode(String code);
  Future<int> createAccount({required String code, required String name, required String accountType, int? parentId});
  Future<int> updateAccount(int id, {String? name, String? code, bool? isActive, bool? isHiddenFromEntries});
  Future<void> deleteAccount(int id);
  Future<List<Map<String, dynamic>>> getAccountLedger(int accountId, DateTime from, DateTime to, {int? costCenterId, int? branchId, Set<int>? allowedBranchIds});

  // --- Journal Entries ---
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,

    /// يُحفَظ **غيرَ مرحَّلٍ** وبانتظار الاعتماد — «حفظ كمسودة» في التصميم.
    ///
    /// ⚠️ والفرقُ ماليٌّ لا وصفيّ: المسودّةُ **لا تحرّك رصيدَ أيّ حساب**
    /// حتى يعتمدها [approveJournalEntry]. وهي متوازنةٌ كغيرها — التحقّقُ
    /// من تساوي المدين والدائن يقع قبل الحفظ في الحالتين.
    bool asDraft = false,

    /// مَن أنشأ القيد — يُسجَّل ليمنع [approveJournalEntry] اعتمادَه بيده.
    ///
    /// ⚠️ `null` يعني «منشئٌ غيرُ معروف» (‏قيدٌ آليٌّ أو أقدمُ من الضابط)،
    /// وعندئذٍ **لا** يُمنَع الاعتماد — فالمنعُ بما لا يُعلَم يُجمّد قيوداً
    /// لا يمكن إثباتُ منشئها.
    int? createdBy,
  });
  Future<List<JournalEntryData>> getJournalEntries({DateTime? from, DateTime? to});
  Stream<List<JournalEntryData>> watchJournalEntries({DateTime? from, DateTime? to});
  Stream<List<JournalEntryData>> watchJournalEntriesPaged({
    required int limit,
    required int offset,
    DateTime? from,
    DateTime? to,
  });
  Future<List<JournalEntryData>> getJournalEntriesByReference(String referenceType, int referenceId);
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(int entryId);

  // --- Fiscal Years ---
  Future<List<FiscalYearData>> getFiscalYears();
  Stream<List<FiscalYearData>> watchFiscalYears();
  Future<FiscalYearData?> getCurrentFiscalYear();
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date);
  Future<int> createFiscalYear({required String name, required DateTime startDate, required DateTime endDate});
  Future<void> closeFiscalYear(int yearId, int userId);
  Future<Map<String, double>> getYearSummary(int yearId);
  Stream<List<AccountingPeriodData>> watchAccountingPeriods(int yearId);
  Future<void> generatePeriodsForYear(int yearId, DateTime startDate, DateTime endDate);
  Future<void> closeAccountingPeriod(int periodId, int userId);
  Future<void> reopenAccountingPeriod(int periodId);

  // --- Cost Centers & Activity Profiles ---
  Future<List<CostCenter>> getCostCenters();
  Future<List<CostCenter>> getActiveCostCenters();

  /// مركزُ تكلفةٍ بعينه ولو كان موقوفاً — لمسارِ تحرير مستندٍ قائمٍ يحمله.
  Future<CostCenter?> getCostCenterById(int id);
  Stream<List<CostCenter>> watchCostCenters();
  Future<int> createCostCenter({required String code, required String name, int? parentId});
  Future<void> updateCostCenter(int id, {String? code, String? name, int? parentId, bool? isActive});
  Future<void> deactivateCostCenter(int id);
  Future<Map<String, double>> getCostCenterBalance(int costCenterId);
  Future<List<Map<String, dynamic>>> getCostCenterLedger(int costCenterId, DateTime from, DateTime to);
  Future<List<ActivityProfile>> getActivityProfiles();

  // --- Journal Templates ---
  Stream<List<JournalEntryTemplateData>> watchAllTemplates();
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates();
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int templateId);
  Future<int> createJournalTemplate({required String name, String? description, required List<Map<String, dynamic>> lines});
  Future<void> updateJournalTemplate(int id, {required String name, String? description, required List<Map<String, dynamic>> lines});
  Future<void> deleteJournalTemplate(int templateId);

  // --- Account Mapping ---
  Future<String> getMappedAccountCode(String purpose, String defaultCode, {int? costCenterId});
  Future<Account?> getAccountByPurpose(String purpose, {int? costCenterId});
  /// Cluster 023 / Issue 3 — leaf-safe variants. If the resolved account is
  /// a `view` (parent), walks down to the first leaf descendant and emits a
  /// diagnostic warning. Use these in JE-emitting paths so misconfigured
  /// purpose mappings (e.g. `output_vat → '22'`) do not block the post.
  Future<Account?> getLeafAccountByPurpose(String purpose, {int? costCenterId});
  Future<Account?> getLeafAccountById(int id);
  Future<void> setAccountMapping(String purpose, int accountId, {int? costCenterId});
  Future<void> deleteAccountMapping(String purpose, {int? costCenterId});
  Future<void> saveAccountMappings(Map<String, int?> selectedAccounts, {int? costCenterId});
  Future<List<AccountMapping>> getAccountMappings({int? costCenterId});
  Future<List<AccountMapping>> getAllAccountMappings();
  Future<void> deleteAccountMappingById(int mappingId);
  Future<void> syncDefaultAccounts();
  Future<void> syncAccountMappings();
  Future<void> resetToDefaultMappings();

  // --- Auto-Posting ---
  Future<int?> autoPostCashSale(SalesInvoiceData sale);
  Future<int?> autoPostCreditSale(SalesInvoiceData sale);
  Future<int?> autoPostPurchase(PurchaseInvoiceData purchase);
  Future<int?> autoPostReceipt(SafeTransactionData txn);
  Future<int?> autoPostPayment(SafeTransactionData txn);
  Future<int?> autoPostSalesReturn({
    required SalesInvoiceData originalInvoice,
    required double returnAmount,
    required double cogsAmount,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    double vatAmount = 0,
    int? costCenterId,
  });
  /// REMEDIATION: Backfill missing cost center IDs for historical data
  Future<int> remediateHistoricalCostCenters();

  /// REPAIR: re-attribute historical auto-posted entries from the global «عام»
  /// (GEN) centre to their branch's own cost center. [dryRun] only previews.
  Future<BranchCostCenterRepairReport> repairBranchCostCenterAttribution({bool dryRun});

  Future<int?> autoPostOperationalExpense({
    required int expenseId,
    required double amount,
    required String description,
    required String expenseAccountCode,
    int? costCenterId,
    int? branchId,
    DateTime? date,
    String? paymentMethod, // F-12: 'cash' | 'bank'
  });

  /// EXP-2 (batch B7 / S-FAILLOUD): atomic record + GL-post for an
  /// operational expense — see AppDatabase.recordAndPostOperationalExpense
  /// for the full rationale. Replaces the previous two-call pattern
  /// (recordExpense on the manufacturing repo + autoPostOperationalExpense
  /// above) with ONE transactional write so a failed post never leaves an
  /// orphan op_expenses row with no journal entry.
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
    // B13 (EXP-3 / S-EXP-REST): optional explicit safe for a CASH expense.
    // Omitted → AppDatabase.recordAndPostOperationalExpense resolves the
    // default cash safe (getDefaultSafeByType('cash')).
    int? safeId,
  });

  Future<bool> hasAutoPostEntry(String referenceType, int referenceId);

  // --- Financial Reports ---
  Future<List<Map<String, dynamic>>> getTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId});
  Future<Map<String, dynamic>> getIncomeStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId});
  Future<Map<String, dynamic>> getBalanceSheet(DateTime atDate, {int? costCenterId, int? branchId, int? regionId});
  Future<Map<String, dynamic>> getCashFlowStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
  Future<Map<String, dynamic>> getHierarchicalTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, Set<int>? allowedBranchIds});
  Future<List<Map<String, dynamic>>> getAgedPayables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
  Future<List<Map<String, dynamic>>> getAgedReceivables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds});
  Future<Map<String, dynamic>> getTaxReport(DateTime from, DateTime to, {Set<int>? allowedBranchIds});
  Future<List<Map<String, dynamic>>> getPostingReconciliation(DateTime from, DateTime to, {int? branchId, Set<int>? allowedBranchIds});

  /// Approve a draft manual journal entry — sets is_posted = true and updates balances
  Future<void> approveJournalEntry(int entryId, int approverId);

  /// Reverse accounting entries when a return is cancelled
  Future<void> reverseReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
  });

  /// Generically reverse any accounting transaction
  Future<void> reverseTransaction({
    required String referenceType,
    required int referenceId,
    required String descriptionPrefix,
    required String newReferenceType,
  });

  /// F-02 fix (MJE-1 / MJE-2): reverse a single journal entry by its own
  /// primary key. See the DAO implementation for why this replaces
  /// [reverseTransaction] for the journal-entries screen's "عكس القيد"
  /// action. Returns the new reversal JE id, or 0 if nothing was reversed
  /// (entry not found or already reversed — idempotent).
  Future<int> reverseJournalEntryById({
    required int entryId,
    String? descriptionPrefix,
  });

  /// Run multiple operations in a single database transaction
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Update status of an entity in a generic way (PIR Architecture)
  Future<void> updateEntityStatus(String table, int id, String status, {String column = 'status'});

  // --- Deferred Schedules ---
  Future<int> processDueRecognitions();
  Future<List<dynamic>> getActiveSchedules();

  // --- Exchange Rates ---
  Future<List<dynamic>> getActiveCurrencies();
  Future<void> recordExchangeRate({required int currencyId, required double rate});

  /// Get calculated balance from journal entries (PIR Integrity)
  Future<double> getCalculatedAccountBalance(int accountId);

  /// Update account balance directly (Manual adjustment or reconciliation)
  Future<void> updateAccountBalance(int accountId, double balance);

  // ── Bank Reconciliation ───────────────────────────────────────────────

  /// Get all bank reconciliation sessions
  Future<List<BankReconciliationData>> getReconciliationSessions();

  /// Create a new bank reconciliation session
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  });

  /// Complete a reconciliation
  Future<void> completeReconciliation(int reconciliationId);

  // --- Compliance & Workflows ---
  Future<List<Map<String, dynamic>>> runComplianceAudit();
  Future<List<dynamic>> getActiveWorkflows();

  // --- SOD Matrix ---
  Future<void> seedDefaultSodConflicts();
  Future<List<SodConflictData>> getActiveSodConflicts();
  Future<List<SodViolationData>> getSodViolationReport({DateTime? from, DateTime? to});

  /// Get all active accounts
  Future<List<Account>> getActiveAccounts();
}
