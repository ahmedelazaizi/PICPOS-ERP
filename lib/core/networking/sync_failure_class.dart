import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// SYNC FAILURE CLASSIFICATION — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Types consumed by `SyncRetryPolicy.withSyncRetry(...)` — kept separate so
// callers can `import` just the classification enum without pulling in the
// retry policy implementation.
//
// Per Spec 125 contracts/sync-retry-policy.md.
// ═══════════════════════════════════════════════════════════════════════════

/// Outcome classification for a single `withSyncRetry` call.
enum SyncFailureClass {
  /// Succeeded on attempt 1 in ≤ slowThreshold. No log entry, no toast.
  immediate,

  /// Succeeded on attempt 1 but took > slowThreshold. Log `SYNC-SLOW`,
  /// no toast.
  slow,

  /// Succeeded on attempt 2 or 3 (one or more transient failures). Log
  /// `SYNC-RETRY`, no toast.
  transient,

  /// All 3 attempts failed. Log `SYNC-FAIL`, caller shows ONE toast for
  /// the whole login session (aggregated across all sync tables).
  persistent,
}

/// Thrown by `SyncRetryPolicy.withSyncRetry(...)` when all retries fail.
/// Preserves the error from each attempt for diagnostics.
class SyncPersistentFailure implements Exception {
  const SyncPersistentFailure({
    required this.tag,
    required this.attemptErrors,
    required this.totalDuration,
  });

  final String tag;
  final List<Object> attemptErrors;
  final Duration totalDuration;

  /// Arabic user-facing message for the aggregated login toast.
  String toUserMessageAr() =>
      tr('فقد الاتصال بالسيرفر أثناء مزامنة "{tag}". تحقق من الشبكة وأعد المحاولة.', {'tag': tag});

  @override
  String toString() =>
      'SyncPersistentFailure(tag=$tag, attempts=${attemptErrors.length}, '
      'duration=${totalDuration.inMilliseconds}ms, '
      'errors=$attemptErrors)';
}
