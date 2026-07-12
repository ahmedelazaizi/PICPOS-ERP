// ═══════════════════════════════════════════════════════════════════════════
// AdaptivePollTimer — Spec 129 F7 / FR-701..703
// ═══════════════════════════════════════════════════════════════════════════
//
// Wraps a single `Timer.periodic` that retunes its interval based on the
// WebSocket connection state. While the WS is connected, the safety-net poll
// runs every 5 minutes (300 s) because the WS already delivers real-time
// data_changed events. When the WS disconnects, the timer drops back to
// 30 s so a network blip doesn't strand a mirror at stale data.
//
// Why this matters: pre-Spec 129, the safety-net poll fired every 30 s
// unconditionally. On a healthy 24/7 mirror with a live WS, that's 2,880
// HTTP calls per day per mirror per branch slice — most of them empty. The
// new cadence drops the steady-state cost by 10× while preserving the
// catch-up latency on disconnect.
//
// Operator override (FR-703): if the persisted settings key
// `auto_sync_interval_seconds` is set (legacy / advanced operator), the
// explicit value wins over the auto-retune. This lets an admin force-cap
// the cadence on a slow LAN without re-deploying.
//
// Listens to: `WebSocketSyncClient.instance.connected` (`ValueNotifier<bool>`).
// Cancels and recreates the underlying Timer on every connect/disconnect
// transition so the new interval takes effect immediately (no waiting for
// the prior tick).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging/diagnostic_logger.dart';

/// Wraps a single periodic timer whose interval auto-retunes based on a
/// `ValueListenable<bool>` "WS connected" flag.
class AdaptivePollTimer {
  AdaptivePollTimer._({
    required ValueListenable<bool> connected,
    required Future<void> Function() onTick,
    required Duration connectedInterval,
    required Duration disconnectedInterval,
    required int? operatorOverrideSeconds,
  })  : _connected = connected,
        _onTick = onTick,
        _connectedInterval = connectedInterval,
        _disconnectedInterval = disconnectedInterval,
        _operatorOverrideSeconds = operatorOverrideSeconds;

  final ValueListenable<bool> _connected;
  final Future<void> Function() _onTick;
  final Duration _connectedInterval;
  final Duration _disconnectedInterval;
  final int? _operatorOverrideSeconds;

  Timer? _timer;
  bool _started = false;
  Duration _currentInterval = Duration.zero;

  /// Starts the adaptive timer. Picks the initial interval from the current
  /// value of [connected] and re-arms on every transition.
  ///
  /// [operatorOverrideSeconds]: explicit operator-chosen cadence from the
  /// settings key `auto_sync_interval_seconds`. When non-null and positive,
  /// this wins over the WS-driven auto-retune (FR-703).
  static AdaptivePollTimer start({
    required ValueListenable<bool> connected,
    required Future<void> Function() onTick,
    Duration connectedInterval = const Duration(seconds: 300),
    Duration disconnectedInterval = const Duration(seconds: 30),
    int? operatorOverrideSeconds,
  }) {
    final t = AdaptivePollTimer._(
      connected: connected,
      onTick: onTick,
      connectedInterval: connectedInterval,
      disconnectedInterval: disconnectedInterval,
      operatorOverrideSeconds: operatorOverrideSeconds,
    );
    t._start();
    return t;
  }

  void _start() {
    if (_started) return;
    _started = true;
    _connected.addListener(_onConnectedChanged);
    _arm();
  }

  /// Stop the timer and detach the listener. Safe to call multiple times.
  void stop() {
    if (!_started) return;
    _started = false;
    _connected.removeListener(_onConnectedChanged);
    _timer?.cancel();
    _timer = null;
  }

  /// Force the current value of the connected flag to be re-applied. Useful
  /// from tests that mutate the underlying notifier before checking the
  /// resulting interval.
  @visibleForTesting
  Duration get currentInterval => _currentInterval;

  void _onConnectedChanged() {
    _arm(trigger: _connected.value ? 'ws-connect' : 'ws-disconnect');
  }

  void _arm({String trigger = 'init'}) {
    final next = _pickInterval();
    if (next == _currentInterval && _timer != null) return;
    _currentInterval = next;
    _timer?.cancel();
    _timer = Timer.periodic(next, (_) async {
      try {
        await _onTick();
      } catch (e) {
        debugPrint('[AdaptivePoll] tick onTick threw: $e');
      }
    });
    DiagnosticLogger.log(
      DiagnosticLogger.pollCadence,
      'interval=${next.inSeconds}s trigger=$trigger '
      'wsConnected=${_connected.value} '
      'override=${_operatorOverrideSeconds ?? "none"}',
    );
  }

  Duration _pickInterval() {
    final override = _operatorOverrideSeconds;
    if (override != null && override > 0) {
      return Duration(seconds: override);
    }
    return _connected.value ? _connectedInterval : _disconnectedInterval;
  }
}
