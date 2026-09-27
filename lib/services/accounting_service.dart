// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING SERVICE (FACADE)
// ═══════════════════════════════════════════════════════════════════════════
//
// ISS-08: Refactored into facade pattern.
// Delegates to AccountingValidator (validation) and JournalEntryFactory (JE).
// Existing callers continue working unchanged.
// ═══════════════════════════════════════════════════════════════════════════

import '../data/database/database.dart';
import '../domain/repositories/accounting_repository.dart';
import '../domain/repositories/parties_repository.dart';
import '../domain/repositories/i_products_repository.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/treasury_repository.dart';
import '../domain/repositories/audit_repository_interface.dart';
import 'accounting_validator.dart';
import 'journal_entry_factory.dart';

/// Accounting validation result
class AccountingValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const AccountingValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  factory AccountingValidationResult.success() =>
      const AccountingValidationResult(isValid: true);

  factory AccountingValidationResult.failure(List<String> errors) =>
      AccountingValidationResult(isValid: false, errors: errors);
}

/// Shift close validation result with variance severity (PIR F10)
class ShiftCloseValidation {
  final double expectedCash;
  final double actualCash;
  final double variance;
  final String severity; // OK, WARNING, CRITICAL
  final String message;

  const ShiftCloseValidation({
    required this.expectedCash,
    required this.actualCash,
    required this.variance,
    required this.severity,
    required this.message,
  });

  bool get isOk => severity == 'OK';
  bool get isCritical => severity == 'CRITICAL';
}

/// Accounting validation and business rules service — **Facade**.
///
/// Delegates to [AccountingValidator] for validation/business rules
/// and [JournalEntryFactory] for JE generation. Existing callers
/// continue working unchanged (backward compatible).
class AccountingService {
  /// Sub-services (accessible for direct injection in new code)
  late final AccountingValidator validator;
  late final JournalEntryFactory journalFactory;
  final IAccountingRepository _accountingRepo;

  AccountingService(
    IAccountingRepository accountingRepo,
    IPartiesRepository partiesRepo,
    ITreasuryRepository treasuryRepo,
    IProductRepository productRepo,
    InventoryRepository inventoryRepo,
    ISettingsRepository settingsRepo,
    IAuditRepository auditRepo,
  ) : _accountingRepo = accountingRepo {
    validator = AccountingValidator(
      accountingRepo,
      partiesRepo,
      treasuryRepo,
      productRepo,
      inventoryRepo,
      settingsRepo,
    );
    journalFactory = JournalEntryFactory(
      accountingRepo,
      partiesRepo,
      treasuryRepo,
      productRepo,
      inventoryRepo,
      auditRepo,
    );
  }

  /// ISS-003 / F01: Load zero-cost policy from settings.
  /// Call once after construction when settings are available.
  Future<void> loadZeroCostPolicyFromSettings(
    ISettingsRepository settingsRepo,
  ) async {
    try {
      final policyStr = await settingsRepo.getSetting('zero_cost_policy');
      if (policyStr != null) {
        switch (policyStr) {
          case 'block':
            journalFactory.setZeroCostPolicy(ZeroCostPolicy.block);
            break;
          case 'allow':
            journalFactory.setZeroCostPolicy(ZeroCostPolicy.allow);
            break;
          default:
            journalFactory.setZeroCostPolicy(ZeroCostPolicy.warn);
        }
      }
    } catch (_) {
      // Settings not available yet — keep default (warn)
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // VALIDATION DELEGATES → AccountingValidator
  // ═══════════════════════════════════════════════════════════════════════

  Future<AccountingValidationResult> validateCreditPurchase({
    required int customerId,
    required double purchaseAmount,
  }) => validator.validateCreditPurchase(
    customerId: customerId,
    purchaseAmount: purchaseAmount,
  );

  Future<AccountingValidationResult> validateSafeWithdrawal({
    required int safeId,
    required double amount,
    bool allowNegative = false,
  }) => validator.validateSafeWithdrawal(
    safeId: safeId,
    amount: amount,
    allowNegative: allowNegative,
  );

  Future<AccountingValidationResult> validateStockForSale({
    required int productId,
    required double quantity,
  }) =>
      validator.validateStockForSale(productId: productId, quantity: quantity);

  AccountingValidationResult validateInvoiceTotals({
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    bool isReturn = false,
  }) => validator.validateInvoiceTotals(
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    total: total,
    paid: paid,
    isReturn: isReturn,
  );

  AccountingValidationResult validateSplitPayment({
    required double paid,
    required double cashPaid,
    required double bankPaid,
    double clickPaid = 0,
    required String paymentMethod,
  }) => validator.validateSplitPayment(
    paid: paid,
    cashPaid: cashPaid,
    bankPaid: bankPaid,
    clickPaid: clickPaid,
    paymentMethod: paymentMethod,
  );

  AccountingValidationResult validateCostPrices({
    required List<Map<String, dynamic>> items,
  }) => validator.validateCostPrices(items: items);

  ShiftCloseValidation validateShiftClose({
    required double expectedCash,
    required double actualCash,
    double tolerance = 1.0,
  }) => validator.validateShiftClose(
    expectedCash: expectedCash,
    actualCash: actualCash,
    tolerance: tolerance,
  );

  static double roundCurrency(double amount) =>
      AccountingValidator.roundCurrency(amount);

  static double roundToQuarter(double amount) =>
      AccountingValidator.roundToQuarter(amount);

  static String formatCurrency(double amount, {String? symbol}) =>
      AccountingValidator.formatCurrency(amount, symbol: symbol);

  bool isWithinFiscalPeriod(
    DateTime date, {
    DateTime? fiscalStart,
    DateTime? fiscalEnd,
  }) => validator.isWithinFiscalPeriod(
    date,
    fiscalStart: fiscalStart,
    fiscalEnd: fiscalEnd,
  );

  Future<bool> isClosedPeriod(DateTime date) => validator.isClosedPeriod(date);

  Future<void> ensureOpenFiscalPeriod(DateTime date) =>
      validator.ensureOpenFiscalPeriod(date);

  Future<void> ensureNoActiveStocktake() => validator.ensureNoActiveStocktake();

  // ═══════════════════════════════════════════════════════════════════════
  // JE GENERATION DELEGATES → JournalEntryFactory
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> generateSalesAccountingEntry({
    required int invoiceId,
    required String invNumber,
    required double tax,
    required double paid,
    required double remaining,
    double? invoiceTotal,

    /// فرقُ تقريب الإجماليّ — يُمرَّر كما هو إلى المصنع.
    double roundingAdjustment = 0,
    required String paymentMethod,
    required double deliveryFee,
    required List<SalesInvoiceItem> items,
    int? customerId,
    int? costCenterId,
    int? branchId,
    String? branchName, // NEW: passed to factory for JE description
    String? regionName, // Phase 9: region label in JE description
    DateTime? invoiceDate,
    // Feature 009 / T017 — see JournalEntryFactory for semantics.
    List<CogsLine>? cogsBreakdown,
    Set<int>? autoDepletedItemIds,
  }) => journalFactory.generateSalesAccountingEntry(
    invoiceId: invoiceId,
    invNumber: invNumber,
    tax: tax,
    paid: paid,
    remaining: remaining,
    invoiceTotal: invoiceTotal,
    roundingAdjustment: roundingAdjustment,
    paymentMethod: paymentMethod,
    deliveryFee: deliveryFee,
    items: items,
    customerId: customerId,
    costCenterId: costCenterId,
    branchId: branchId,
    branchName: branchName,
    regionName: regionName,
    invoiceDate: invoiceDate,
    cogsBreakdown: cogsBreakdown,
    autoDepletedItemIds: autoDepletedItemIds,
  );

  Future<void> generatePurchaseAccountingEntry({
    required int invoiceId,
    required double subtotal,
    required double tax,
    required double total,
    required double paid,
    required double remaining,
    double discount = 0,
    required String? notes,
    int? supplierId,
    int? costCenterId,
    int? branchId,
    DateTime? invoiceDate,
  }) => journalFactory.generatePurchaseAccountingEntry(
    invoiceId: invoiceId,
    subtotal: subtotal,
    tax: tax,
    total: total,
    paid: paid,
    remaining: remaining,
    discount: discount,
    notes: notes,
    supplierId: supplierId,
    costCenterId: costCenterId,
    branchId: branchId,
    invoiceDate: invoiceDate,
  );

  Future<void> generateReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
    required double totalReturn,
    required double totalTaxReturn,
    required double totalCogsReturn,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    int? customerId,
    int? costCenterId,
    int? branchId,
  }) => journalFactory.generateReturnAccountingEntry(
    invoiceId: invoiceId,
    invNumber: invNumber,
    totalReturn: totalReturn,
    totalTaxReturn: totalTaxReturn,
    totalCogsReturn: totalCogsReturn,
    cashRefund: cashRefund,
    bankRefund: bankRefund,
    arRefund: arRefund,
    customerId: customerId,
    costCenterId: costCenterId,
    branchId: branchId,
  );

  Future<void> reverseReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
  }) => journalFactory.reverseReturnAccountingEntry(
    invoiceId: invoiceId,
    invNumber: invNumber,
  );

  Future<void> reverseTransaction({
    required String referenceType,
    required int referenceId,
    required String descriptionPrefix,
    required String newReferenceType,
  }) => journalFactory.reverseTransaction(
    referenceType: referenceType,
    referenceId: referenceId,
    descriptionPrefix: descriptionPrefix,
    newReferenceType: newReferenceType,
  );

  /// F-02 fix (MJE-1 / MJE-2): reverse a single journal entry by its own
  /// primary key — see [reverseTransaction] above for the bug this avoids.
  /// Returns the new reversal JE id, or 0 if nothing was reversed
  /// (already reversed / entry not found).
  Future<int> reverseJournalEntryById({
    required int entryId,
    String? descriptionPrefix,
  }) => journalFactory.reverseJournalEntryById(
    entryId: entryId,
    descriptionPrefix: descriptionPrefix,
  );

  Future<void> cancelSalesReturn({
    required SalesInvoiceData invoice,
    required int userId,
    required String userName,
  }) => journalFactory.cancelSalesReturn(
    invoice: invoice,
    userId: userId,
    userName: userName,
  );

  Future<void> generateClosingAccountingEntry({
    required double cashAmount,
    required double bankAmount,
    required double clickAmount,
    required double totalExpenses,
    required double totalSales,
    required String employeeName,
    int? branchId,
    int? costCenterId,
  }) => journalFactory.generateClosingAccountingEntry(
    cashAmount: cashAmount,
    bankAmount: bankAmount,
    clickAmount: clickAmount,
    totalExpenses: totalExpenses,
    totalSales: totalSales,
    employeeName: employeeName,
    branchId: branchId,
    costCenterId: costCenterId,
  );

  // Spec 147 (S-COUNT): generateCycleCountEntry delegate removed — the
  // cycle-count settlement JE now posts inside finalizeCycleCountTask (DAO).

  /// ONE-TIME REMEDIATION: Backfill missing cost center IDs from parent entries to lines.
  /// This fixes visibility issues in financial reports for historical transactions.
  Future<int> remediateHistoricalData() async {
    return _accountingRepo.remediateHistoricalCostCenters();
  }

  /// ONE-OFF REPAIR: move historical auto-posted entries off the global «عام»
  /// (GEN) centre onto each transaction's branch cost center. Pass
  /// [dryRun] = true to preview counts without writing.
  Future<BranchCostCenterRepairReport> repairBranchCostCenters({
    bool dryRun = true,
  }) {
    return _accountingRepo.repairBranchCostCenterAttribution(dryRun: dryRun);
  }
}
