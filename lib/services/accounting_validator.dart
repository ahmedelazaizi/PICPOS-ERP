// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING VALIDATOR
// ═══════════════════════════════════════════════════════════════════════════
//
// ISS-08: Extracted from AccountingService.
// Pure validation + business rules (no JE generation).
// ═══════════════════════════════════════════════════════════════════════════

import '../domain/repositories/accounting_repository.dart';
import '../domain/repositories/treasury_repository.dart';
import '../domain/repositories/parties_repository.dart';
import '../domain/repositories/i_products_repository.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../../core/constants/app_constants.dart';
import '../core/utils/financial_utils.dart';
import 'accounting_service.dart' show AccountingValidationResult, ShiftCloseValidation;

/// Accounting validation and business rules.
///
/// Handles credit limits, safe balance checks, stock validation,
/// invoice totals verification, fiscal period gating, etc.
/// Does NOT generate journal entries — see [JournalEntryFactory].
class AccountingValidator {
  final IAccountingRepository _accountingRepo;
  final IPartiesRepository _partiesRepo;
  final ITreasuryRepository _treasuryRepo;
  final IProductRepository _productRepo;
  final InventoryRepository _inventoryRepo;
  final ISettingsRepository _settingsRepo;

  AccountingValidator(
    this._accountingRepo,
    this._partiesRepo,
    this._treasuryRepo,
    this._productRepo,
    this._inventoryRepo,
    this._settingsRepo,
  );

  // ═══════════════════════════════════════════════════════════════════════
  // CREDIT LIMIT VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if customer can make a credit purchase
  Future<AccountingValidationResult> validateCreditPurchase({
    required int customerId,
    required double purchaseAmount,
  }) async {
    try {
      final customer = await _partiesRepo.getPartyById(customerId);
      if (customer == null) {
        return AccountingValidationResult.failure(['العميل غير موجود']);
      }

      final currentBalance = customer.balance;
      final creditLimit = customer.creditLimit;
      final projectedBalance = currentBalance + purchaseAmount;

      final errors = <String>[];
      final warnings = <String>[];

      if (creditLimit > 0 && projectedBalance > creditLimit) {
        errors.add(
          'تجاوز حد الائتمان. الحد: $creditLimit، الرصيد المتوقع: $projectedBalance',
        );
      }

      if (creditLimit > 0 &&
          projectedBalance > creditLimit * 0.8 &&
          errors.isEmpty) {
        warnings.add(
          'تحذير: الرصيد قريب من حد الائتمان (${(projectedBalance / creditLimit * 100).toStringAsFixed(0)}%)',
        );
      }

      return AccountingValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      return AccountingValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SAFE/TREASURY VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if safe has sufficient balance for withdrawal
  Future<AccountingValidationResult> validateSafeWithdrawal({
    required int safeId,
    required double amount,
    bool allowNegative = false,
  }) async {
    try {
      final safe = await _treasuryRepo.getSafeById(safeId);
      if (safe == null) {
        return AccountingValidationResult.failure(['الخزينة غير موجودة']);
      }

      final currentBalance = safe.balance;
      final errors = <String>[];
      final warnings = <String>[];

      if (!allowNegative && currentBalance < amount) {
        errors.add(
          'رصيد الخزينة غير كافي. الرصيد الحالي: $currentBalance، المطلوب: $amount',
        );
      }

      if (currentBalance > 0 &&
          (currentBalance - amount) < currentBalance * 0.1) {
        warnings.add('تحذير: هذه العملية ستترك رصيدًا منخفضًا في الخزينة');
      }

      return AccountingValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      return AccountingValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INVENTORY VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if product has sufficient stock for sale
  Future<AccountingValidationResult> validateStockForSale({
    required int productId,
    required double quantity,
  }) async {
    try {
      final product = await _productRepo.getProductById(productId);
      if (product == null) {
        return AccountingValidationResult.failure(['المنتج غير موجود']);
      }

      final errors = <String>[];
      final warnings = <String>[];

      if (product.trackInventory) {
        final currentStock = product.currentStock;

        // Cluster 024 / Issue 2 — global negative-sales toggle overrides
        // the per-product flag in the validator too, otherwise sales would
        // be blocked here even when the operator turned the global ON.
        final globalNegativeSalesRaw =
            await _settingsRepo.getSetting('enable_negative_sales');
        final globalNegativeSales = globalNegativeSalesRaw == 'true';

        if (!product.allowNegativeSale &&
            !globalNegativeSales &&
            currentStock < quantity) {
          errors.add(
            'المخزون غير كافي. المتاح: $currentStock، المطلوب: $quantity',
          );
        }

        if ((currentStock - quantity) < product.minStock) {
          warnings.add(
            'تحذير: المخزون سيصبح أقل من الحد الأدنى (${product.minStock})',
          );
        }
      }

      return AccountingValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      return AccountingValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INVOICE VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate invoice totals match calculated values
  AccountingValidationResult validateInvoiceTotals({
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    bool isReturn = false,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    final expectedTotal = subtotal - discount + tax;

    if ((expectedTotal - total).abs() > 0.01) {
      errors.add(
        'الإجمالي غير متطابق. المتوقع: ${expectedTotal.toStringAsFixed(AppConstants.decimalPlaces)}، المُدخل: ${total.toStringAsFixed(AppConstants.decimalPlaces)}',
      );
    }

    if (paid > total) {
      warnings.add('المبلغ المدفوع أكبر من الإجمالي - سيتم إنشاء رصيد دائن');
    }

    if (!isReturn && (subtotal < 0 || discount < 0 || tax < 0 || total < 0)) {
      errors.add('لا يمكن أن تكون القيم سالبة');
    }

    if (discount > subtotal) {
      errors.add('الخصم لا يمكن أن يتجاوز الإجمالي الفرعي');
    }

    return AccountingValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SPLIT PAYMENT VALIDATION (PIR F8)
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate that cashPaid + bankPaid + clickPaid == paid for split/multiple payments
  AccountingValidationResult validateSplitPayment({
    required double paid,
    required double cashPaid,
    required double bankPaid,
    double clickPaid = 0,
    required String paymentMethod,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    if (paymentMethod == 'multiple' || paymentMethod == 'mixed' || (cashPaid > 0 && bankPaid > 0)) {
      final splitTotal = cashPaid + bankPaid + clickPaid;
      if ((splitTotal - paid).abs() > 0.01) {
        errors.add(
          'المدفوع نقداً (${cashPaid.toStringAsFixed(AppConstants.decimalPlaces)}) + '
          'بنك (${bankPaid.toStringAsFixed(AppConstants.decimalPlaces)}) + '
          'كليك (${clickPaid.toStringAsFixed(AppConstants.decimalPlaces)}) = '
          '${splitTotal.toStringAsFixed(AppConstants.decimalPlaces)} ≠ '
          'الإجمالي المدفوع (${paid.toStringAsFixed(AppConstants.decimalPlaces)})',
        );
      }
    }

    if (cashPaid < 0 || bankPaid < 0 || clickPaid < 0) {
      errors.add('لا يمكن أن تكون قيم الدفع سالبة');
    }

    return AccountingValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // COST PRICE VALIDATION (PIR F4)
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate that all items have non-zero cost prices.
  /// Returns warnings (not errors) for items with costPrice == 0.
  AccountingValidationResult validateCostPrices({
    required List<Map<String, dynamic>> items,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    for (final item in items) {
      final costPrice = (item['costPrice'] as num?)?.toDouble() ?? 0;
      final name = item['name'] as String? ?? 'صنف';
      final trackInventory = item['trackInventory'] as bool? ?? true;

      if (costPrice <= 0 && trackInventory) {
        warnings.add(
          'تنبيه: الصنف "$name" بدون سعر تكلفة — قد يؤثر على حساب الأرباح',
        );
      }
    }

    return AccountingValidationResult(
      isValid: true,
      errors: errors,
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT CLOSE VALIDATION (PIR F10)
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate shift closing balance — compare expected vs actual cash.
  /// Returns severity: OK (≤ tolerance), WARNING (> tolerance), CRITICAL (> 5x tolerance).
  ShiftCloseValidation validateShiftClose({
    required double expectedCash,
    required double actualCash,
    double tolerance = 1.0,
  }) {
    final variance = actualCash - expectedCash;
    final absVariance = variance.abs();

    String severity;
    if (absVariance <= tolerance) {
      severity = 'OK';
    } else if (absVariance <= tolerance * 5) {
      severity = 'WARNING';
    } else {
      severity = 'CRITICAL';
    }

    return ShiftCloseValidation(
      expectedCash: expectedCash,
      actualCash: actualCash,
      variance: variance,
      severity: severity,
      message: severity == 'OK'
          ? 'الوردية متوازنة'
          : 'فرق ${variance > 0 ? "فائض" : "عجز"}: '
              '${absVariance.toStringAsFixed(AppConstants.decimalPlaces)}',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CURRENCY & ROUNDING
  // ═══════════════════════════════════════════════════════════════════════

  /// Round amount to JOD financial precision (3dp).
  /// BUG-H03: delegate to the central helper instead of a hardcoded 2dp so
  /// shift-close/validation paths agree with POS totals.
  static double roundCurrency(double amount) {
    return FinancialUtils.round(amount);
  }

  /// Round to nearest quarter (for cash transactions)
  static double roundToQuarter(double amount) {
    return (amount * 4).round() / 4;
  }

  /// Format amount as currency string
  static String formatCurrency(double amount, {String? symbol}) {
    final currencySymbol = symbol ?? AppConstants.currencySymbolAr;
    return '${roundCurrency(amount).toStringAsFixed(AppConstants.decimalPlaces)} $currencySymbol';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FISCAL PERIOD VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if date is within current fiscal period
  bool isWithinFiscalPeriod(
    DateTime date, {
    DateTime? fiscalStart,
    DateTime? fiscalEnd,
  }) {
    final now = DateTime.now();
    final start = fiscalStart ?? DateTime(now.year, 1, 1);
    final end = fiscalEnd ?? DateTime(now.year, 12, 31, 23, 59, 59);

    return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
        date.isBefore(end.add(const Duration(seconds: 1)));
  }

  /// Check if date is in a closed period
  Future<bool> isClosedPeriod(DateTime date) async {
    final closingDateStr = await _settingsRepo.getSetting('fiscal_closing_date');
    if (closingDateStr != null) {
      final closedDate = DateTime.tryParse(closingDateStr);
      if (closedDate != null &&
          date.isBefore(closedDate.add(const Duration(seconds: 1)))) {
        return true;
      }
    }

    final fy = await _accountingRepo.getFiscalYearByDate(date);
    if (fy != null && fy.isClosed) {
      return true;
    }

    return false;
  }

  /// Strict gatekeeper: Throws an exception if the period is closed.
  Future<void> ensureOpenFiscalPeriod(DateTime date) async {
    if (await isClosedPeriod(date)) {
      throw Exception(
        'لا يمكن إجراء هذه العملية: الفترة المحاسبية مغلقة أو تم تدقيقها.',
      );
    }
  }

  /// Stocktake guard (U-STOCKTAKE): Throws if an inventory count is in progress.
  Future<void> ensureNoActiveStocktake() async {
    final hasActive = await _inventoryRepo.hasActiveStockAudit();
    if (hasActive) {
      throw Exception(
        'لا يمكن إجراء عمليات مخزنية أثناء الجرد. أغلق الجرد الحالي أولاً.',
      );
    }
  }
}
