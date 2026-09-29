import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// CENTRALIZED ERROR HANDLING — PIR Sprint 2
// ═══════════════════════════════════════════════════════════════════════════
//
// Structured error hierarchy for the UralCash ERP system.
// Replaces scattered Exception/String error patterns with typed errors.

/// Base class for all application errors
sealed class AppError implements Exception {
  /// Arabic user-facing error message
  String get messageAr;

  /// English technical message for logs
  String get messageTech;

  @override
  String toString() => messageAr;
}

// ═══════════════════════════════════════════════════════════════════════
// VALIDATION ERRORS
// ═══════════════════════════════════════════════════════════════════════

/// General validation error (form inputs, business rules)
class ValidationError extends AppError {
  final List<String> errors;

  ValidationError(this.errors);

  @override
  String get messageAr => errors.join('\n');

  @override
  String get messageTech => 'Validation failed: ${errors.join(', ')}';
}

/// Split payment amounts don't sum to total
class SplitPaymentError extends AppError {
  final double cashPaid;
  final double bankPaid;
  final double expectedTotal;

  SplitPaymentError({
    required this.cashPaid,
    required this.bankPaid,
    required this.expectedTotal,
  });

  @override
  String get messageAr =>
      tr('المدفوع نقداً ({cashPaid}) + بنك ({bankPaid}) ≠ الإجمالي ({expectedTotal})', {'cashPaid': cashPaid, 'bankPaid': bankPaid, 'expectedTotal': expectedTotal});

  @override
  String get messageTech =>
      'Split payment mismatch: cash=$cashPaid + bank=$bankPaid ≠ total=$expectedTotal';
}

// ═══════════════════════════════════════════════════════════════════════
// FINANCIAL ERRORS
// ═══════════════════════════════════════════════════════════════════════

/// Attempting to write in a closed fiscal period
class FiscalPeriodError extends AppError {
  final DateTime date;
  final String fiscalYearName;

  FiscalPeriodError({required this.date, required this.fiscalYearName});

  @override
  String get messageAr =>
      tr('لا يمكن الكتابة في السنة المالية المقفلة: {fiscalYearName}', {'fiscalYearName': fiscalYearName});

  @override
  String get messageTech =>
      'Fiscal period closed for date $date in year "$fiscalYearName"';
}

/// Journal entry debits don't equal credits
class UnbalancedJournalError extends AppError {
  final double totalDebit;
  final double totalCredit;

  UnbalancedJournalError(
      {required this.totalDebit, required this.totalCredit});

  @override
  String get messageAr =>
      tr('القيد غير متوازن: مدين ({totalDebit}) ≠ دائن ({totalCredit})', {'totalDebit': totalDebit, 'totalCredit': totalCredit});

  @override
  String get messageTech =>
      'Unbalanced journal: debit=$totalDebit ≠ credit=$totalCredit';
}

// ═══════════════════════════════════════════════════════════════════════
// INVENTORY ERRORS
// ═══════════════════════════════════════════════════════════════════════

/// Insufficient stock for the operation
class InsufficientStockError extends AppError {
  final int productId;
  final String productName;
  final double available;
  final double requested;

  InsufficientStockError({
    required this.productId,
    required this.productName,
    required this.available,
    required this.requested,
  });

  @override
  String get messageAr =>
      tr('الكمية المطلوبة ({requested}) أكبر من المتاح ({available}) للصنف {productName}', {'requested': requested, 'available': available, 'productName': productName});

  @override
  String get messageTech =>
      'Insufficient stock for product $productId: available=$available, requested=$requested';
}

/// Return quantity exceeds original sale quantity
class ExcessReturnError extends AppError {
  final int productId;
  final double requested;
  final double maxReturnable;

  ExcessReturnError({
    required this.productId,
    required this.requested,
    required this.maxReturnable,
  });

  @override
  String get messageAr =>
      tr('الكمية المرتجعة ({requested}) أكبر من المتاح للإرجاع ({maxReturnable}) للصنف رقم {productId}', {'requested': requested, 'maxReturnable': maxReturnable, 'productId': productId});

  @override
  String get messageTech =>
      'Excess return for product $productId: requested=$requested, max=$maxReturnable';
}

// ═══════════════════════════════════════════════════════════════════════
// RECONCILIATION ERRORS
// ═══════════════════════════════════════════════════════════════════════

/// Balance discrepancy detected during reconciliation
class ReconciliationError extends AppError {
  final String entityType;
  final int entityId;
  final double cachedValue;
  final double calculatedValue;

  ReconciliationError({
    required this.entityType,
    required this.entityId,
    required this.cachedValue,
    required this.calculatedValue,
  });

  @override
  String get messageAr =>
      tr('تم اكتشاف فرق في رصيد {entityType} (رقم {entityId}): القيمة المخزنة ({cachedValue}) ≠ المحسوبة ({calculatedValue})', {'entityType': entityType, 'entityId': entityId, 'cachedValue': cachedValue, 'calculatedValue': calculatedValue});

  @override
  String get messageTech =>
      'Reconciliation mismatch for $entityType[$entityId]: '
      'cached=$cachedValue, calculated=$calculatedValue';
}

// ═══════════════════════════════════════════════════════════════════════
// PERMISSION ERRORS
// ═══════════════════════════════════════════════════════════════════════

/// User lacks required permission
class PermissionDeniedError extends AppError {
  final String permissionCode;
  final String? permissionName;

  PermissionDeniedError({
    required this.permissionCode,
    this.permissionName,
  });

  @override
  String get messageAr => tr('ليس لديك صلاحية: {p0}', {'p0': permissionName ?? permissionCode});

  @override
  String get messageTech =>
      'Permission denied: $permissionCode';
}
