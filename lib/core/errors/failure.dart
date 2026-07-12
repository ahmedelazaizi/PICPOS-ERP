/// Failure class for functional error handling (Either pattern)
///
/// Use this when you want to return errors as values instead of throwing exceptions.
/// Commonly used with packages like dartz or fpdart.
abstract class Failure {
  final String message;
  final String? code;

  const Failure(this.message, {this.code});

  @override
  String toString() => 'Failure($code): $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => message.hashCode ^ (code?.hashCode ?? 0);
}

/// Database operation failure
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.code});
}

/// Validation failure
class ValidationFailure extends Failure {
  final Map<String, String>? fieldErrors;

  const ValidationFailure(super.message, {super.code, this.fieldErrors});
}

/// Business logic failure
class BusinessFailure extends Failure {
  const BusinessFailure(super.message, {super.code});
}

/// Cache/Storage failure
class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.code});
}

/// Server/Network failure
class ServerFailure extends Failure {
  final int? statusCode;

  const ServerFailure(super.message, {super.code, this.statusCode});
}
