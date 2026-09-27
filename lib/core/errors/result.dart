/// Result type for functional error handling
///
/// Usage:
/// ```dart
/// final result = await repository.getSomething();
/// switch (result) {
///   case Success(:final data): debugPrint(data);
///   case Failure(:final error): showError(error);
/// }
/// ```
library;

/// Base result type
sealed class Result<T> {
  const Result();

  /// Create a successful result
  factory Result.success(T data) = Success<T>;

  /// Create a failure result
  factory Result.failure(AppException error) = Failure<T>;

  /// Check if result is successful
  bool get isSuccess => this is Success<T>;

  /// Check if result is failure
  bool get isFailure => this is Failure<T>;

  /// Get data if success, throw if failure
  T get dataOrThrow {
    switch (this) {
      case Success(:final data):
        return data;
      case Failure(:final error):
        throw error;
    }
  }

  /// Get data if success, null if failure
  T? get dataOrNull {
    switch (this) {
      case Success(:final data):
        return data;
      case Failure():
        return null;
    }
  }

  /// Get error if failure, null if success
  AppException? get errorOrNull {
    switch (this) {
      case Success():
        return null;
      case Failure(:final error):
        return error;
    }
  }

  /// Map success value to another type
  Result<R> map<R>(R Function(T data) transform) {
    switch (this) {
      case Success(:final data):
        return Success(transform(data));
      case Failure(:final error):
        return Failure(error);
    }
  }

  /// Flat map for chaining operations
  Result<R> flatMap<R>(Result<R> Function(T data) transform) {
    switch (this) {
      case Success(:final data):
        return transform(data);
      case Failure(:final error):
        return Failure(error);
    }
  }

  /// Execute side effect on success
  Result<T> onSuccess(void Function(T data) action) {
    if (this is Success<T>) {
      action((this as Success<T>).data);
    }
    return this;
  }

  /// Execute side effect on failure
  Result<T> onFailure(void Function(AppException error) action) {
    if (this is Failure<T>) {
      action((this as Failure<T>).error);
    }
    return this;
  }
}

/// Successful result
final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

/// Failed result
final class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);
}

// ═══════════════════════════════════════════════════════════════════════════
// APP EXCEPTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Base application exception
sealed class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => code != null ? '[$code] $message' : message;
}

/// Validation exception
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.code = 'VALIDATION_ERROR'});
}

/// Not found exception
final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code = 'NOT_FOUND'});
}

/// Database exception
final class DatabaseException extends AppException {
  const DatabaseException(
    super.message, {
    super.code = 'DB_ERROR',
    super.originalError,
  });
}

/// Network exception
final class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    super.code = 'NETWORK_ERROR',
    super.originalError,
  });
}

/// Permission exception
final class PermissionException extends AppException {
  const PermissionException(super.message, {super.code = 'PERMISSION_DENIED'});
}

/// Business logic exception
final class BusinessException extends AppException {
  const BusinessException(super.message, {super.code = 'BUSINESS_ERROR'});
}

/// Insufficient stock exception
final class InsufficientStockException extends BusinessException {
  final int productId;
  final double available;
  final double requested;

  const InsufficientStockException({
    required this.productId,
    required this.available,
    required this.requested,
  }) : super('الكمية المتاحة ($available) أقل من المطلوبة ($requested)');
}

/// Credit limit exceeded exception
final class CreditLimitException extends BusinessException {
  final double limit;
  final double currentBalance;
  final double requestedAmount;

  const CreditLimitException({
    required this.limit,
    required this.currentBalance,
    required this.requestedAmount,
  }) : super('تجاوز الحد الائتماني');
}
