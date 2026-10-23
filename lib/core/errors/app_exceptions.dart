import 'package:picpos_erp/core/i18n/tr.dart';
/// Base exception class for UralCash application
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final Object? originalError;
  final StackTrace? stackTrace;

  AppException(this.message, {this.code, this.originalError, this.stackTrace});

  @override
  String toString() => 'AppException($code): $message';
}

/// Database-related exceptions
class DatabaseException extends AppException {
  DatabaseException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  factory DatabaseException.queryFailed(String query, Object error) {
    return DatabaseException(
      'Query failed: $query',
      code: 'DB_QUERY_FAILED',
      originalError: error,
    );
  }

  factory DatabaseException.connectionFailed(Object error) {
    return DatabaseException(
      'Database connection failed',
      code: 'DB_CONNECTION_FAILED',
      originalError: error,
    );
  }

  factory DatabaseException.transactionFailed(Object error) {
    return DatabaseException(
      'Transaction failed and was rolled back',
      code: 'DB_TRANSACTION_FAILED',
      originalError: error,
    );
  }
}

/// Validation exceptions
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException(super.message, {super.code, this.fieldErrors});

  factory ValidationException.required(String field) {
    return ValidationException(
      'Field "$field" is required',
      code: 'VALIDATION_REQUIRED',
      fieldErrors: {field: tr('مطلوب')},
    );
  }

  factory ValidationException.invalid(String field, String reason) {
    return ValidationException(
      'Field "$field" is invalid: $reason',
      code: 'VALIDATION_INVALID',
      fieldErrors: {field: reason},
    );
  }

  factory ValidationException.multiple(Map<String, String> errors) {
    return ValidationException(
      'Multiple validation errors',
      code: 'VALIDATION_MULTIPLE',
      fieldErrors: errors,
    );
  }
}

/// Business logic exceptions
class BusinessException extends AppException {
  BusinessException(super.message, {super.code});

  factory BusinessException.insufficientStock(
    String productName,
    double available,
    double requested,
  ) {
    return BusinessException(
      'Insufficient stock for "$productName": available=$available, requested=$requested',
      code: 'BUSINESS_INSUFFICIENT_STOCK',
    );
  }

  factory BusinessException.insufficientFunds(
    double available,
    double requested,
  ) {
    return BusinessException(
      'Insufficient funds: available=$available, requested=$requested',
      code: 'BUSINESS_INSUFFICIENT_FUNDS',
    );
  }

  factory BusinessException.invoiceAlreadyPaid(String invoiceNumber) {
    return BusinessException(
      'Invoice "$invoiceNumber" is already fully paid',
      code: 'BUSINESS_INVOICE_PAID',
    );
  }

  factory BusinessException.operationNotAllowed(String reason) {
    return BusinessException(
      'Operation not allowed: $reason',
      code: 'BUSINESS_NOT_ALLOWED',
    );
  }
}

/// Authentication/Authorization exceptions
class AuthException extends AppException {
  AuthException(super.message, {super.code});

  factory AuthException.invalidCredentials() {
    return AuthException(
      'Invalid username or password',
      code: 'AUTH_INVALID_CREDENTIALS',
    );
  }

  factory AuthException.sessionExpired() {
    return AuthException('Session has expired', code: 'AUTH_SESSION_EXPIRED');
  }

  factory AuthException.unauthorized(String action) {
    return AuthException(
      'Not authorized to perform: $action',
      code: 'AUTH_UNAUTHORIZED',
    );
  }
}

/// Hardware-related exceptions
class HardwareException extends AppException {
  HardwareException(super.message, {super.code, super.originalError});

  factory HardwareException.printerNotFound() {
    return HardwareException(
      'Printer not found or not connected',
      code: 'HW_PRINTER_NOT_FOUND',
    );
  }

  factory HardwareException.printFailed(Object error) {
    return HardwareException(
      'Print operation failed',
      code: 'HW_PRINT_FAILED',
      originalError: error,
    );
  }

  factory HardwareException.scaleNotConnected() {
    return HardwareException(
      'Scale not connected',
      code: 'HW_SCALE_NOT_CONNECTED',
    );
  }

  factory HardwareException.scaleReadFailed(Object error) {
    return HardwareException(
      'Failed to read from scale',
      code: 'HW_SCALE_READ_FAILED',
      originalError: error,
    );
  }
}

/// Network exceptions (for future cloud sync)
class NetworkException extends AppException {
  NetworkException(super.message, {super.code, super.originalError});

  factory NetworkException.noConnection() {
    return NetworkException(
      'No internet connection',
      code: 'NET_NO_CONNECTION',
    );
  }

  factory NetworkException.timeout() {
    return NetworkException('Request timed out', code: 'NET_TIMEOUT');
  }

  factory NetworkException.serverError(int statusCode) {
    return NetworkException(
      'Server error: $statusCode',
      code: 'NET_SERVER_ERROR',
    );
  }
}

/// عمليّةٌ تُخرِج نقداً من درجٍ طُلبت ولا ورديّةَ مفتوحةً لصاحبها.
///
/// **ليست عطلاً — بل طلبُ إجراء.** نوعٌ مستقلٌّ عن `Exception` العامّ كي تميّز
/// الواجهةُ «اعرض على الكاشير فتحَ ورديّة ثمّ أعد المحاولة» عن خطأٍ حقيقيٍّ
/// يُعرَض نصّاً أحمر.
///
/// ولماذا يُرفَض أصلاً (مواصفة 2026-08-18 §١، ح‑١): نسبةُ حركةِ الخزنة إلى
/// ورديّةٍ تتمّ بالنافذة الزمنيّة وحدَها (`safe_transactions` بلا `shift_id`).
/// فحركةٌ تقع بين إقفالِ ورديّةٍ وفتحِ التالية لا تنتمي لأيّ نافذة: النقدُ
/// يخرج من الدرج ولا `expectedCash` لأحدٍ يعرف به، فيعدّ الكاشيرُ التالي
/// درجَه ناقصاً ويُقيَّد العجزُ في ذمّته وهو بريء.
class ShiftRequiredException extends AppException {
  /// ما كان سيخرج نقداً لو مضت العمليّة — يُعرَض في نصّ الطلب.
  final double cashAmount;

  ShiftRequiredException({
    required this.cashAmount,
    String? message,
  }) : super(
          // عامّةٌ عمداً: يستعملها البيعُ (نقدٌ يدخل) والمرتجعُ (نقدٌ يخرج).
          // كانت تقول «المرتجع» فصارت تكذب على الكاشير في نصف الحالات.
          message ?? tr('لا توجد وردية مفتوحة، والعملية تحرّك نقداً في الدرج. افتح وردية أولاً لتُسجَّل الحركة على درجها.'),
          code: 'SHIFT_REQUIRED_FOR_CASH_REFUND',
        );
}
