import '../core/i18n/tr.dart';
import '../web/web_session.dart';
import 'mirror_branch_context.dart';
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
  MirrorOfflineException(this.detail, {this.isNetworkIssue = true})
      : isRefusal = false;

  /// Convenience constructor for the unambiguous "we couldn't reach HQ"
  /// case (SocketException, TimeoutException, ClientException).
  MirrorOfflineException.network(this.detail)
      : isNetworkIssue = true,
        isRefusal = false;

  /// Convenience constructor for "HQ answered, but rejected the write"
  /// (HTTP 4xx/5xx). The user needs to see the actual server message,
  /// not a generic "connection lost".
  MirrorOfflineException.serverError(this.detail)
      : isNetworkIssue = false,
        isRefusal = false;

  /// The console REFUSES this operation outright (M3 / MIR-009): it would write
  /// locally before the main hears of it and the console has no outbox. [detail]
  /// is a user-facing sentence, shown as is.
  MirrorOfflineException.refused(this.detail)
      : isNetworkIssue = false,
        isRefusal = true;

  /// Local-first sales-invoice creation is not offered on the console.
  MirrorOfflineException.invoiceRefused()
      : detail = tr('إنشاء فاتورة بيع غير متاح على كونسول المدير — أنشئها من جهاز الفرع'),
        isNetworkIssue = false,
        isRefusal = true;

  /// Underlying error string. Surfaced as-is in debug builds and
  /// summarised in user-facing snackbars.
  final String detail;

  /// True when the failure was caused by an unreachable/timed-out server,
  /// false when the server responded with a non-2xx status.
  final bool isNetworkIssue;

  /// True for [MirrorOfflineException.refused].
  final bool isRefusal;

  @override
  String toString() => isRefusal
      ? detail
      : isNetworkIssue
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
///    the current branch (HQ takes the actor from the session), then
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

  /// M2 (MIR-012): the console works in ONE branch at a time. A write that
  /// carries no branch key at all gets `branchId` = the branch the manager is
  /// working in; the main checks it against his scope (`branch_access_denied`).
  /// A payload that already has the key (even null) is never touched - master
  /// data such as a warehouse owns its own branch.
  ///
  /// The acting user is NOT stamped here any more (MIR-004): the main takes it
  /// from the signed session alone and refuses a body naming somebody else.
  static void stampBranchContext(Map<String, dynamic> payload) {
    final branch = MirrorBranchContext.instance.currentBranchId;
    if (branch == null || payload.containsKey('branchId')) return;
    payload['branchId'] = branch;
  }
}
