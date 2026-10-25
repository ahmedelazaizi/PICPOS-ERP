import 'dart:async';
import 'package:flutter/foundation.dart';

import 'mirror_state.dart';
import 'network_service.dart';
import 'server_proxy.dart';

/// Mirror-mode heartbeat ticker (Feature 006 / MM.B + MM.E hot-fix).
///
/// Pings the cheap `/api/sync/time` endpoint every 10 seconds and stamps
/// `MirrorState.lastHandshakeAt` on success. Powers the badge's
/// staleness dot and the offline banner / mutation guard threshold.
///
/// Lifecycle:
///   • [start] is idempotent — calling it twice with mirror still active
///     keeps the existing timer; calling it when not in mirror mode is a
///     no-op (returns immediately).
///   • [stop] cancels the timer if running. Safe to call multiple times.
///   • [start] also stamps an immediate handshake before the first tick
///     fires, so the badge doesn't show stale-by-default for the first
///     10 seconds after a fresh pairing.
///
/// Why a static service rather than inline timer in `initPlatform()`:
/// the wizard finalises mirror pairing AFTER `initPlatform()` already
/// ran (boot found `mode = standalone`, so the inline `if (isMirror)`
/// guard skipped the timer). Without re-triggering the heartbeat on
/// `setMode(NetworkMode.mirror)`, the badge would stay red until the
/// next app restart even though the connection is fine. This service
/// can be called from BOTH boot and `setMode`.
class MirrorHeartbeatService {
  MirrorHeartbeatService._();

  static Timer? _timer;
  static const Duration _tickInterval = Duration(seconds: 10);

  /// True when the timer is currently running. Test seam.
  static bool get isRunning => _timer?.isActive ?? false;

  /// Start the 10-second heartbeat ticker. No-op if not in mirror mode
  /// or already running. Stamps an immediate handshake so the badge
  /// reflects current connectivity before the first tick fires.
  static void start() {
    if (!NetworkService.instance.isMirror) return;
    if (isRunning) return;

    // Immediate handshake — without this, a fresh-paired mirror would
    // start with `lastHandshakeAt` from setPaired and only update at the
    // 10s mark, giving the user a brief "is the connection actually
    // alive?" moment of doubt on the badge.
    unawaited(_tick());

    _timer = Timer.periodic(_tickInterval, (timer) {
      if (!NetworkService.instance.isMirror) {
        timer.cancel();
        _timer = null;
        return;
      }
      unawaited(_tick());
    });
    if (kDebugMode) {
      debugPrint(
        '[MirrorHeartbeat] started — '
        '${_tickInterval.inSeconds}s tick → /api/sync/time',
      );
    }
  }

  /// Ping right now (the status strip's refresh button, M2).
  static Future<void> checkNow() => _tick();

  /// Cancel the timer. Safe to call when not running.
  static void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    if (kDebugMode) {
      debugPrint('[MirrorHeartbeat] stopped');
    }
  }

  /// Single ping → markHandshake on success. Failures are swallowed —
  /// the next tick will retry, and the badge consults `lastHandshakeAt`
  /// to surface staleness directly. We intentionally don't log every
  /// miss, only the first start/stop transition above.
  static Future<void> _tick() async {
    try {
      final t = await ServerProxy.instance.fetchServerTime();
      if (t != null) {
        await MirrorState.instance.markHandshake();
      } else {
        MirrorState.instance.markHandshakeFailed();
      }
    } catch (_) {
      MirrorState.instance.markHandshakeFailed(); // staleness stays observable
    }
  }
}
