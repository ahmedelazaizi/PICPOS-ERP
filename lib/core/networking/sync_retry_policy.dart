// ═══════════════════════════════════════════════════════════════════════════
// SYNC RETRY POLICY — Spec 125 Mirror Foundation (FR-016 → FR-019)
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ CRITICAL: التزامن اللحظى مُقدّس (FR-015). This utility exists ONLY to
// improve error display layer for login pulls. It MUST NOT be used in any
// write path, outbox push, or periodic sync — that would introduce timing
// changes that break the real-time-sync contract.
//
// Bounded exponential backoff: 3 attempts, delays [0, 250ms, 500ms],
// total ≤ 750ms before throwing. Classifies outcomes as immediate / slow /
// transient / persistent for smart toast suppression.
//
// Per Spec 125 contracts/sync-retry-policy.md + research.md R1.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import '../logging/diagnostic_logger.dart';
import 'sync_failure_class.dart';

/// Retry policy for sync read pulls. Static-only — stateless by design.
///
/// Use ONLY in login table-sync loop. Do NOT use in write paths.
abstract class SyncRetryPolicy {
  /// Maximum attempts (1 original + 2 retries).
  static const int maxAttempts = 3;

  /// Delay BEFORE each attempt. backoffs[0]=0 means attempt 1 is immediate.
  static const List<Duration> backoffs = [
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
  ];

  /// If attempt 1 succeeds but takes longer than this, classified as `slow`
  /// (still success, but logged for visibility).
  static const Duration slowThreshold = Duration(seconds: 3);

  /// Wraps a sync request with bounded exponential backoff retry.
  ///
  /// On success (any attempt): returns the request's result, fires
  /// [onClassification] with `immediate`, `slow`, or `transient`.
  ///
  /// On all-attempts failure: fires [onClassification] with `persistent`,
  /// logs `SYNC-FAIL`, and throws [SyncPersistentFailure].
  ///
  /// [tag] is used for log entries (e.g. `'USERS-SYNC'`, `'PERMS-SYNC'`).
  static Future<T> withSyncRetry<T>(
    Future<T> Function() request, {
    required String tag,
    void Function(SyncFailureClass classification)? onClassification,
  }) async {
    final overallStopwatch = Stopwatch()..start();
    final errors = <Object>[];

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final delay = backoffs[attempt];
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      final attemptStopwatch = Stopwatch()..start();
      try {
        final result = await request();
        attemptStopwatch.stop();
        overallStopwatch.stop();

        // Classify success.
        final SyncFailureClass cls;
        if (attempt == 0) {
          // First attempt succeeded — immediate or slow.
          cls = (attemptStopwatch.elapsed > slowThreshold)
              ? SyncFailureClass.slow
              : SyncFailureClass.immediate;
        } else {
          // Recovered after one or more failures.
          cls = SyncFailureClass.transient;
        }

        // Log only non-immediate outcomes.
        if (cls == SyncFailureClass.slow) {
          unawaited(DiagnosticLogger.log(
            'SYNC-SLOW',
            'tag=$tag duration=${attemptStopwatch.elapsedMilliseconds}ms',
          ));
        } else if (cls == SyncFailureClass.transient) {
          unawaited(DiagnosticLogger.log(
            'SYNC-RETRY',
            'tag=$tag succeeded_attempt=${attempt + 1} '
                'prev_errors_count=${errors.length}',
          ));
        }

        onClassification?.call(cls);
        return result;
      } catch (e) {
        attemptStopwatch.stop();
        errors.add(e);
        // Continue to next attempt (if any).
      }
    }

    // All attempts failed.
    overallStopwatch.stop();
    unawaited(DiagnosticLogger.log(
      'SYNC-FAIL',
      'tag=$tag total_duration=${overallStopwatch.elapsedMilliseconds}ms '
          'attempts=$maxAttempts errors=$errors',
    ));
    onClassification?.call(SyncFailureClass.persistent);
    throw SyncPersistentFailure(
      tag: tag,
      attemptErrors: List.unmodifiable(errors),
      totalDuration: overallStopwatch.elapsed,
    );
  }
}
