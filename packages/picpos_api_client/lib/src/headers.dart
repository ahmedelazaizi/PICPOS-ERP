/// Request headers shared by the cloud `/manage/*` and LAN `/api/m1/*` APIs
/// (ARCHITECTURE-M §2 and ADR-M3). Header names follow the existing cloud
/// (`x-session-token`, `retry-after`) and LAN (`x-device-id`,
/// `x-idempotency-key`) servers; HTTP header names are case-insensitive.
library;

abstract final class ApiHeaderNames {
  static const authorization = 'authorization';
  static const deviceId = 'x-device-id';
  static const sessionToken = 'x-session-token';
  static const idempotencyKey = 'x-idempotency-key';
  static const stepUp = 'x-step-up';
  static const appVersion = 'x-app-version';
  static const acceptLanguage = 'accept-language';
  static const contentType = 'content-type';
}

/// Credentials of a paired device and (optionally) a logged-in user.
class ApiCredentials {
  const ApiCredentials({this.deviceId, this.deviceToken, this.sessionToken, this.stepUpToken});
  final String? deviceId;
  final String? deviceToken;
  final String? sessionToken;

  /// Short-lived token from `POST /manage/step-up` for `financial` commands.
  final String? stepUpToken;

  bool get isPaired => (deviceId ?? '').isNotEmpty && (deviceToken ?? '').isNotEmpty;

  ApiCredentials copyWith({String? deviceToken, String? sessionToken, String? stepUpToken}) => ApiCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken ?? this.deviceToken,
        sessionToken: sessionToken ?? this.sessionToken,
        stepUpToken: stepUpToken ?? this.stepUpToken,
      );

  /// Same device, no user session (sign-out).
  ApiCredentials signedOut() => ApiCredentials(deviceId: deviceId, deviceToken: deviceToken);
}

/// Builds the header map of one request.
class ApiHeaderBuilder {
  const ApiHeaderBuilder({required this.appVersion, this.locale = 'ar'});
  final String appVersion;
  final String locale;

  /// [idempotencyKey] is required by every write (the document `globalId`,
  /// the `commandId` or the `queryId`); [stepUp] adds `X-Step-Up`.
  /// Throws [ArgumentError] when a step-up is requested without a token or a
  /// session-level call is made on an unpaired device.
  Map<String, String> build(
    ApiCredentials c, {
    bool json = true,
    bool session = true,
    String? idempotencyKey,
    bool stepUp = false,
  }) {
    if (!c.isPaired) throw ArgumentError('device is not paired');
    if (session && (c.sessionToken ?? '').isEmpty) throw ArgumentError('no user session');
    if (stepUp && (c.stepUpToken ?? '').isEmpty) throw ArgumentError('step-up token required');
    return {
      ApiHeaderNames.authorization: 'Bearer ${c.deviceToken}',
      ApiHeaderNames.deviceId: c.deviceId!,
      if (session) ApiHeaderNames.sessionToken: c.sessionToken!,
      if (idempotencyKey != null) ApiHeaderNames.idempotencyKey: idempotencyKey,
      if (stepUp) ApiHeaderNames.stepUp: c.stepUpToken!,
      ApiHeaderNames.appVersion: appVersion,
      ApiHeaderNames.acceptLanguage: locale,
      if (json) ApiHeaderNames.contentType: 'application/json; charset=utf-8',
    };
  }

  /// Headers for unauthenticated calls (`/manage/pair`, `/api/m1/info`).
  Map<String, String> anonymous({bool json = true}) => {
        ApiHeaderNames.appVersion: appVersion,
        ApiHeaderNames.acceptLanguage: locale,
        if (json) ApiHeaderNames.contentType: 'application/json; charset=utf-8',
      };
}
