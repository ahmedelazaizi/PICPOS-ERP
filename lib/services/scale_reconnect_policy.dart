/// When — and how often — to retry connecting to the scale after a failure.
///
/// `ScaleService.autoConnect()` is the app's only automatic connection path and
/// it runs exactly once, from `MainScreen.initState`. Before this policy
/// existed, any failure (scale still powering up, USB adapter not enumerated
/// yet, port briefly claimed by a previous worker isolate) left the scale dead
/// for the entire session. Nothing surfaced the failure, and a cashier — whose
/// allowed screens contain no settings entry — had no way to reconnect. Only
/// restarting the app helped.
///
/// The one case that must *not* retry is an operator who pressed "disconnect"
/// in the hardware settings; [suppress] holds the policy down until an explicit
/// connect calls [resume].
class ScaleReconnectPolicy {
  /// Delay before each successive attempt. The last entry repeats forever, so
  /// a permanently absent scale settles into a cheap 30s poll rather than
  /// either giving up or growing without bound.
  static const List<Duration> backoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  int _attempt = 0;
  bool _suppressed = false;

  /// False only while the operator has deliberately disconnected.
  bool get shouldRetry => !_suppressed;

  /// How many attempts have been handed out since the last [reset].
  int get attempt => _attempt;

  /// Delay for the next attempt, advancing the schedule.
  Duration nextDelay() {
    final delay = backoff[_attempt.clamp(0, backoff.length - 1)];
    if (_attempt < backoff.length) _attempt++;
    return delay;
  }

  /// Rewind the schedule — call after a successful connect so the next outage
  /// recovers in 2s instead of inheriting the previous 30s cap.
  void reset() {
    _attempt = 0;
  }

  /// Operator disconnected: stop retrying and rewind.
  void suppress() {
    _suppressed = true;
    _attempt = 0;
  }

  /// Something explicitly asked to connect: retries are allowed again.
  ///
  /// Deliberately does NOT rewind the schedule. Every connect attempt — including
  /// the ones this policy itself triggers — passes through here, so rewinding
  /// would pin the backoff at its first step and turn a 30s poll into a 2s one
  /// against a scale that is simply absent. Only [reset] (on success) and
  /// [suppress] rewind.
  void resume() {
    _suppressed = false;
  }
}
