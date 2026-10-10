import '../web/web_session.dart';
import 'mirror_state.dart';
import 'network_service.dart';

/// Thrown by the write path when an HTTP call fails while the device is in
/// `NetworkMode.mirror`. Mirror mode has no outbox by design — the operator
/// is acting as an HQ admin from a remote laptop, and silently queueing
/// writes would let HQ data drift out of sync without anyone noticing.
///
/// Caught at UI boundaries to show an Arabic-localised error and revert
/// the optimistic UI state, mirroring how `MutationDeniedException` is
/// surfaced for the cross-branch elevation guard.
///
/// [isNetworkIssue] differentiates a real connection failure (Socket/Timeout)
/// from a server-side rejection (HTTP 4xx/5xx). Lumping both under "فقد
/// الاتصال" hid genuine server bugs from operators in the field — they kept
/// reporting "connection lost" while the device was clearly online and only
/// the write itself was failing for a different reason.
class MirrorOfflineException implements Exception {
  MirrorOfflineException(this.detail, {this.isNetworkIssue = true});

  /// Convenience constructor for the unambiguous "we couldn't reach HQ"
  /// case (SocketException, TimeoutException, ClientException).
  MirrorOfflineException.network(this.detail) : isNetworkIssue = true;

  /// Convenience constructor for "HQ answered, but rejected the write"
  /// (HTTP 4xx/5xx). The user needs to see the actual server message,
  /// not a generic "connection lost".
  MirrorOfflineException.serverError(this.detail) : isNetworkIssue = false;

  /// Underlying error string. Surfaced as-is in debug builds and
  /// summarised in user-facing snackbars.
  final String detail;

  /// True when the failure was caused by an unreachable/timed-out server,
  /// false when the server responded with a non-2xx status.
  final bool isNetworkIssue;

  @override
  String toString() => isNetworkIssue
      ? 'فقد الاتصال بـ HQ-Server — تأكد من الاتصال ثم أعد المحاولة ($detail)'
      : 'تعذّر التعديل — رد السيرفر: $detail';
}

/// Centralises the routing decision for writes that originate in the
/// shared `_tryOrQueue` infrastructure inside `ClientWriteInterceptor`.
///
/// Three behaviour tiers, picked by current network mode:
///
/// 1. **standalone / server modes** — interceptor is not installed; this
///    helper is never consulted.
/// 2. **client mode** — preserve the legacy behaviour: try the server
///    once, fall back to the local outbox on failure (offline-first).
/// 3. **mirror mode** (Feature 006 / MM.C) — no outbox. Inject
///    `adminUserId` so HQ attributes the write to the remote admin, then
///    throw [MirrorOfflineException] if the call fails. The UI layer
///    surfaces the error, the operator sees that nothing was saved, and
///    the next attempt happens after they reconnect.
///
/// Kept as a top-level utility (not a method on `ClientWriteInterceptor`)
/// so the test suite can exercise the routing decision without standing
/// up the full interceptor + DB stack.
class WriteRouter {
  WriteRouter._();

  /// True when the device is in `NetworkMode.mirror` AND a successful
  /// wizard pairing has happened (server identity captured + at least
  /// one handshake recorded). Defensive against the intermediate state
  /// where the user picked mirror but never finished the wizard.
  ///
  /// م3-7: وعلى الويب (`kIsWeb`) تكون **دائماً** صحيحةً ما دامت جلسة ويب نشطة
  /// — المتصفّح عميلٌ بلا كاش محلي ولا صندوق صادر، فتمرّ كلُّ كتابةٍ عبر HTTP
  /// وفشلُ الاتصال يُرمى [MirrorOfflineException].
  static bool get isMirrorActive =>
      isWebClient ||
      (NetworkService.instance.isMirror && MirrorState.instance.isConfigured);

  /// هل هذا متصفّح ويب بجلسة نشطة؟ (لا كاش محلي: يُتخطّى سحب الدلتا والصندوق.)
  static bool get isWebClient => WebSession.activeWebClient != null;

  /// Stamps the mirror admin's HQ-side userId into [payload] so the
  /// server's `_resolveUserId` resolves writes to that user instead of
  /// the local cashier. Adds:
  ///
  ///   • `userId` — only when the caller didn't already provide one.
  ///     This avoids overriding a deliberate userId on writes that need
  ///     to retain a different actor (e.g. shift-reconstruct flows).
  ///   • `actorUserId` — always set, regardless of the legacy `userId`
  ///     field, so a future server-side audit handler can prefer this
  ///     dedicated channel and ignore `userId` (which is also used for
  ///     domain semantics like "who opened the shift").
  ///
  /// No-op when the mirror admin id has not yet been verified — the
  /// server's existing admin fallback in `_resolveUserId` will still
  /// preserve the record.
  static void stampAdminAttribution(Map<String, dynamic> payload) {
    final adminId = MirrorState.instance.adminUserId;
    if (adminId == null) return;
    payload['actorUserId'] = adminId;
    payload['userId'] ??= adminId;
  }
}
