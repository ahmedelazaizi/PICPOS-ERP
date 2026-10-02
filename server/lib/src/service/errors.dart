class ApiError implements Exception {
  ApiError(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;
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
  });
  final int devicePk;
  final String deviceId;
  final int companyId;
  final int employeeId;
}
