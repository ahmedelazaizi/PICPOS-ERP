class ApiError implements Exception {
  ApiError(this.status, this.code, [this.message, this.retryAfterSeconds]);
  final int status;
  final String code;
  final String? message;

  /// Sent as `Retry-After` (429 responses).
  final int? retryAfterSeconds;
  Map<String, Object?> toJson() => {'error': code, if (message != null) 'message': message};
  @override
  String toString() => 'ApiError($status, $code, $message)';
}

/// A business rejection of one pushed document (the batch continues).
class DocRejected implements Exception {
  DocRejected(this.code, [this.message, this.details]);
  final String code;
  final String? message;
  final Map<String, Object?>? details;
}

/// Authenticated device (+ optional rep session) context.
class DeviceContext {
  DeviceContext({
    required this.devicePk,
    required this.deviceId,
    required this.companyId,
    required this.employeeId,
    this.ip = 'unknown',
    this.tokenHash,
  });

  /// SHA-256 of the device token used on this request (current or the
  /// pre-rotation token during its grace period).
  final String? tokenHash;
  final int devicePk;
  final String deviceId;
  final int companyId;
  final int employeeId;
  final String ip;
}
