/// Decides when a serial/TCP scale has actually gone away.
///
/// The read loops in [ScaleService] are event-driven: they call
/// `readBytes(..., timeout: 25-30ms)` in a tight loop, so a read that returns
/// no bytes is the ordinary state for any scale transmitting slower than
/// ~33 Hz. The previous policy counted those empty reads and declared the
/// cable disconnected after 10 — as little as 300 ms of silence, and often far
/// less when the port returns empty immediately instead of blocking for the
/// full timeout. Scales that idle between frames, USB-serial latency spikes,
/// and ordinary Windows scheduling stalls all tripped it, and the verdict was
/// permanent for the session because nothing reconnects.
///
/// This separates the two signals the old counter conflated:
///
///  * **Silence** is measured in *time*, not in reads. Only a gap longer than
///    [silenceThreshold] since the last byte counts as a disconnection.
///  * **I/O errors** are direct evidence from the driver and keep their own
///    consecutive counter, [ioErrorThreshold], so a genuinely broken port is
///    still caught quickly.
///
/// The detector holds no clock of its own — callers pass `now`. That keeps it
/// deterministic under test and lets the read loop reuse a timestamp it has
/// already taken.
class ScaleDisconnectDetector {
  /// The default silence window is deliberately generous. A cable that is
  /// actually pulled makes the port handle invalid, so reads *throw* and
  /// [ioErrorThreshold] catches it within a few cycles; silence alone is the
  /// weaker signal, produced just as easily by a scale that stops transmitting
  /// while the weight is unchanged. Erring long here costs a few seconds of
  /// stale reading, while erring short resurrects the very bug this class
  /// exists to kill — and now also churns the reconnect loop.
  ScaleDisconnectDetector({
    this.silenceThreshold = const Duration(seconds: 10),
    this.ioErrorThreshold = 10,
  });

  /// How long the link may stay silent before it is considered gone.
  final Duration silenceThreshold;

  /// How many consecutive read exceptions mean the port is broken.
  final int ioErrorThreshold;

  DateTime? _lastAliveAt;
  int _consecutiveIoErrors = 0;

  /// Bytes arrived — the link is demonstrably alive.
  void onData(DateTime now) {
    _lastAliveAt = now;
    _consecutiveIoErrors = 0;
  }

  /// A read completed but returned nothing. Expected while the scale is idle;
  /// it only starts the silence clock, it is never evidence on its own.
  void onEmptyRead(DateTime now) {
    _lastAliveAt ??= now;
  }

  /// A read threw. Counts toward [ioErrorThreshold] and also starts the
  /// silence clock if no byte has ever arrived.
  void onIoError(DateTime now) {
    _lastAliveAt ??= now;
    _consecutiveIoErrors++;
  }

  /// True once either signal says the scale is gone.
  bool shouldDisconnect(DateTime now) {
    if (_consecutiveIoErrors >= ioErrorThreshold) return true;
    final last = _lastAliveAt;
    if (last == null) return false;
    return now.difference(last) >= silenceThreshold;
  }

  /// Seconds of silence accumulated so far — for diagnostics.
  Duration silenceFor(DateTime now) {
    final last = _lastAliveAt;
    return last == null ? Duration.zero : now.difference(last);
  }

  /// Clear all state and restart the silence clock at [now]. Call on connect
  /// and after a successful reconnect.
  void reset(DateTime now) {
    _lastAliveAt = now;
    _consecutiveIoErrors = 0;
  }
}
