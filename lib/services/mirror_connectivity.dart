// Branch-manager console connectivity (plan 2026-10-24, M2 / MIR-008).
//
// The console is ONLINE-only for writes. Its link to the main is judged by the
// last successful heartbeat:
//   online    - answered within [onlineWithin];
//   degraded  - older, but not yet [readOnlyAfter]: reconnecting, writes still
//               attempted (the main decides);
//   readOnly  - nothing for [readOnlyAfter] (or never): the console is a
//               read-only view of its local copy and a write is REFUSED with a
//               clear message instead of being attempted and lost.
// The same threshold feeds the mutation guard, the status strip and the write
// path (`ClientWriteInterceptor`), so they can never disagree.
import '../core/i18n/tr.dart';
import 'mirror_state.dart';
import 'network_service.dart';
import 'write_router.dart';

enum MirrorLinkState { online, degraded, readOnly }

class MirrorConnectivity {
  MirrorConnectivity._();

  static const Duration onlineWithin = Duration(seconds: 30);
  static const Duration readOnlyAfter = Duration(minutes: 5);

  /// Injectable clock (tests).
  static DateTime Function() clock = DateTime.now;

  static MirrorLinkState classify(DateTime? lastHandshakeAt, DateTime now) {
    if (lastHandshakeAt == null) return MirrorLinkState.readOnly;
    final age = now.toUtc().difference(lastHandshakeAt.toUtc());
    if (age > readOnlyAfter) return MirrorLinkState.readOnly;
    if (age <= onlineWithin) return MirrorLinkState.online;
    return MirrorLinkState.degraded;
  }

  /// The link state right now (always [MirrorLinkState.online] off a mirror).
  static MirrorLinkState get state {
    if (!NetworkService.instance.isMirror) return MirrorLinkState.online;
    return classify(MirrorState.instance.lastHandshakeAt, clock());
  }

  static bool get isReadOnly => state == MirrorLinkState.readOnly;

  /// Time left before a degraded link turns read-only (null when not applicable).
  static Duration? get untilReadOnly {
    if (!NetworkService.instance.isMirror) return null;
    final stamp = MirrorState.instance.lastHandshakeAt;
    if (stamp == null) return null;
    final left = readOnlyAfter - clock().toUtc().difference(stamp.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Throws [MirrorOfflineException] when a console write must not be attempted.
  static void ensureWritable() {
    if (isReadOnly) {
      throw MirrorOfflineException.refused(
          tr('فقد الاتصال بالسيرفر الرئيسي — المرآة للقراءة فقط حتى يعود الاتصال.'));
    }
  }

  static void debugUseClock(DateTime Function() c) => clock = c;
  static void debugReset() => clock = DateTime.now;
}
