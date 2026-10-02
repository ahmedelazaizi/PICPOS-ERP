import 'errors.dart';

/// In-memory sliding-window limiter (one API instance; a shared store such as
/// Postgres/Redis is needed once the API runs as several replicas — I-6).
class RateLimiter {
  RateLimiter({required this.max, required this.window, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final int max;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, List<DateTime>> _hits = {};

  /// Records a hit for [key]; throws 429 `rate_limited` (with Retry-After)
  /// when the key already used [max] hits inside [window].
  void hit(String key, {String code = 'rate_limited'}) {
    final now = _clock();
    final list = _hits.putIfAbsent(key, () => [])..removeWhere((t) => now.difference(t) >= window);
    if (list.length >= max) {
      final retry = window - now.difference(list.first);
      throw ApiError(429, code, null, retry.inSeconds < 1 ? 1 : retry.inSeconds);
    }
    list.add(now);
  }
}
