/// Error mapping for both servers (ARCHITECTURE-M §2 conventions).
///
/// Accepts the documented `{error:{code,message}}` body and the shape the
/// cloud returns today (`{error:'code', message?}`, `server/lib/src/service/
/// errors.dart`), plus the `retry-after` header (seconds).
library;

import 'dart:convert';

/// What the app should do with an error, independent of the exact code.
enum ApiErrorKind {
  /// No response (socket, DNS, TLS, timeout). Retry later / try other transport.
  network,

  /// 401 other than revocation: session expired → log in again.
  unauthorized,

  /// 401 `device_revoked`: wipe local data and return to pairing.
  deviceRevoked,

  /// 403 (`permission_denied`, `totp_required` is [unauthorized]).
  forbidden,
  notFound,

  /// 409 (`stale`, duplicate state…).
  conflict,

  /// 400 / 422 (`validation_failed`, `totals_mismatch`, `period_closed`…).
  rejected,

  /// 429: wait [ApiError.retryAfter].
  rateLimited,

  /// 503 `desktop_offline` (relay) or any 5xx: retry later.
  unavailable,

  /// The payload did not verify against the pinned desktop key.
  invalidSignature,
  unknown,
}

class ApiError implements Exception {
  const ApiError({required this.kind, required this.code, this.status, this.message, this.retryAfter, this.field});

  final ApiErrorKind kind;
  final String code;
  final int? status;
  final String? message;
  final Duration? retryAfter;

  /// `validation_failed{field}`.
  final String? field;

  /// Worth retrying the same request later (same idempotency key).
  bool get retryable =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.rateLimited || kind == ApiErrorKind.unavailable;

  /// No HTTP answer at all: justifies trying the other transport.
  bool get transportFailure => kind == ApiErrorKind.network;

  factory ApiError.network(Object cause) =>
      ApiError(kind: ApiErrorKind.network, code: 'network', message: cause.toString());

  factory ApiError.invalidSignature() =>
      const ApiError(kind: ApiErrorKind.invalidSignature, code: 'invalid_signature');

  /// Maps an HTTP response. [headers] keys are expected lower-case (as
  /// `package:http` delivers them).
  factory ApiError.fromResponse(int status, String body, [Map<String, String> headers = const {}]) {
    String? code;
    String? message;
    String? field;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final e = decoded['error'];
        if (e is Map) {
          code = e['code']?.toString();
          message = e['message']?.toString();
          field = e['field']?.toString();
        } else if (e is String) {
          code = e;
          message = decoded['message']?.toString();
          field = decoded['field']?.toString();
        }
      }
    } on FormatException {
      // Non-JSON body (proxy page): fall back to the status.
    }
    final retry = int.tryParse(headers['retry-after'] ?? '');
    final c = code ?? _defaultCode(status);
    return ApiError(
      kind: _kind(status, c),
      code: c,
      status: status,
      message: message,
      field: field,
      retryAfter: retry == null ? null : Duration(seconds: retry),
    );
  }

  static String _defaultCode(int status) => switch (status) {
        400 => 'bad_request',
        401 => 'unauthorized',
        403 => 'permission_denied',
        404 => 'not_found',
        409 => 'conflict',
        422 => 'validation_failed',
        429 => 'rate_limited',
        503 => 'unavailable',
        _ => 'http_$status',
      };

  static ApiErrorKind _kind(int status, String code) {
    if (status == 401) return code == 'device_revoked' ? ApiErrorKind.deviceRevoked : ApiErrorKind.unauthorized;
    return switch (status) {
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      409 => ApiErrorKind.conflict,
      400 || 422 => ApiErrorKind.rejected,
      429 => ApiErrorKind.rateLimited,
      >= 500 && < 600 => ApiErrorKind.unavailable,
      _ => ApiErrorKind.unknown,
    };
  }

  @override
  String toString() => 'ApiError($code${status == null ? '' : ', $status'}${message == null ? '' : ': $message'})';
}
