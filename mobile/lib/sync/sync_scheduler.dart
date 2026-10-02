import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../state/app_controller.dart';

/// Network reachability as the scheduler needs it.
abstract class ConnectivitySource {
  Future<bool> isOnline();
  Stream<bool> get changes;
}

/// `connectivity_plus`: online when any transport other than `none` is up
/// (a captive or dead network still fails the sync and backs off).
class PlusConnectivity implements ConnectivitySource {
  PlusConnectivity([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;
  static bool _up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _up(await _c.checkConnectivity());
  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_up);
}

/// Exponential backoff 5 s → 15 min cap (ARCHITECTURE-I §5), ±20 % jitter so
/// a fleet of vans coming back online does not hit the server at once.
class Backoff {
  const Backoff({
    this.base = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 15),
    this.factor = 3,
    this.jitter = 0.2,
  });
  final Duration base, cap;
  final double factor, jitter;

  /// Delay after [failures] consecutive failures (≥ 1). [rnd] in [0, 1).
  Duration delay(int failures, [double rnd = 0.5]) {
    final raw = base.inMilliseconds * pow(factor, max(0, failures - 1));
    final capped = min(raw.toDouble(), cap.inMilliseconds.toDouble());
    final j = 1 + jitter * (2 * rnd - 1);
    return Duration(milliseconds: min(capped * j, cap.inMilliseconds.toDouble()).round());
  }
}

/// Runs [sync] in the background while the app is open: every [interval] when
/// healthy, with [Backoff] after failures, immediately when connectivity comes
/// back or a document is queued (debounced), never while offline.
class SyncScheduler {
  SyncScheduler({
    required this.sync,
    required this.connectivity,
    this.interval = const Duration(minutes: 5),
    this.backoff = const Backoff(),
    this.debounce = const Duration(seconds: 2),
    double Function()? random,
    this.onStatus,
  }) : _random = random ?? Random().nextDouble;

  final Future<bool> Function() sync;
  final ConnectivitySource connectivity;
  final Duration interval;
  final Backoff backoff;
  final Duration debounce;
  final double Function() _random;

  /// (online, next scheduled run) after every change.
  final void Function(bool online, DateTime? next)? onStatus;

  Timer? _timer;
  StreamSubscription<bool>? _sub;
  bool _online = true;
  bool _running = false;
  bool _started = false;
  int failures = 0;
  DateTime? nextRunAt;

  bool get started => _started;
  bool get online => _online;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    failures = 0;
    _sub = connectivity.changes.listen(_onConnectivity);
    _online = await connectivity.isOnline();
    if (_online) {
      _schedule(Duration.zero);
    } else {
      _report();
    }
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    nextRunAt = null;
    _sub?.cancel();
    _sub = null;
  }

  /// A document was queued: push soon (after [debounce]) unless offline.
  void trigger() {
    if (!_started || !_online) return;
    if (_running) {
      _triggered = true;
    } else {
      _schedule(debounce);
    }
  }

  bool _triggered = false;

  void _onConnectivity(bool online) {
    final cameBack = online && !_online;
    _online = online;
    if (!_started) return;
    if (!online) {
      _timer?.cancel();
      nextRunAt = null;
      _report();
    } else if (cameBack) {
      failures = 0;
      _schedule(Duration.zero);
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    nextRunAt = DateTime.now().add(d);
    _timer = Timer(d, _run);
    _report();
  }

  Future<void> _run() async {
    _timer = null;
    nextRunAt = null;
    if (!_started || !_online) return;
    if (_running) return;
    _running = true;
    bool ok;
    try {
      ok = await sync();
    } catch (_) {
      ok = false;
    } finally {
      _running = false;
    }
    if (!_started) return;
    final again = _triggered;
    _triggered = false;
    if (ok) {
      failures = 0;
      _schedule(again ? debounce : interval);
    } else {
      failures++;
      _schedule(backoff.delay(failures, _random()));
    }
  }

  void _report() => onStatus?.call(_online, nextRunAt);
}

/// Wires a scheduler to the controller: runs while logged in, stops on
/// sign-out / wipe, and pushes soon after each queued document.
class BackgroundSync {
  BackgroundSync(this.controller, this.scheduler) {
    controller.onOutboxChanged = scheduler.trigger;
    controller.addListener(_onChange);
    _onChange();
  }
  final AppController controller;
  final SyncScheduler scheduler;

  void _onChange() {
    if (controller.loggedIn && controller.isPaired && !scheduler.started) {
      scheduler.start();
    } else if ((!controller.loggedIn || !controller.isPaired) && scheduler.started) {
      scheduler.stop();
    }
  }

  void dispose() {
    controller.removeListener(_onChange);
    scheduler.stop();
  }
}
