// ═══════════════════════════════════════════════════════════════════════════
// SYNC RETRY POLICY TESTS — Spec 125 (T020)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/core/networking/sync_failure_class.dart';
import 'package:ural_erp/core/networking/sync_retry_policy.dart';

void main() {
  setUp(() {
    DiagnosticLogger.enableTestMode();
  });

  group('SyncRetryPolicy.withSyncRetry', () {
    test('attempt 1 succeeds immediately → immediate classification, no logs',
        () async {
      SyncFailureClass? observed;
      final result = await SyncRetryPolicy.withSyncRetry(
        () async => 'value',
        tag: 'T1',
        onClassification: (c) => observed = c,
      );
      expect(result, 'value');
      expect(observed, SyncFailureClass.immediate);
      expect(DiagnosticLogger.testLog.any((l) => l.contains('SYNC-SLOW')),
          isFalse);
      expect(DiagnosticLogger.testLog.any((l) => l.contains('SYNC-RETRY')),
          isFalse);
      expect(DiagnosticLogger.testLog.any((l) => l.contains('SYNC-FAIL')),
          isFalse);
    });

    test('attempt 2 succeeds after 1 failure → transient + SYNC-RETRY log',
        () async {
      var attempts = 0;
      SyncFailureClass? observed;
      final result = await SyncRetryPolicy.withSyncRetry(
        () async {
          attempts++;
          if (attempts == 1) throw Exception('transient');
          return 'recovered';
        },
        tag: 'T2',
        onClassification: (c) => observed = c,
      );
      expect(result, 'recovered');
      expect(attempts, 2);
      expect(observed, SyncFailureClass.transient);
      expect(DiagnosticLogger.testLog.any((l) => l.contains('SYNC-RETRY')),
          isTrue);
    });

    test('attempt 3 succeeds after 2 failures → transient', () async {
      var attempts = 0;
      SyncFailureClass? observed;
      final result = await SyncRetryPolicy.withSyncRetry(
        () async {
          attempts++;
          if (attempts < 3) throw Exception('flaky');
          return 42;
        },
        tag: 'T3',
        onClassification: (c) => observed = c,
      );
      expect(result, 42);
      expect(attempts, 3);
      expect(observed, SyncFailureClass.transient);
    });

    test('all 3 attempts fail → throws SyncPersistentFailure + persistent',
        () async {
      var attempts = 0;
      SyncFailureClass? observed;
      await expectLater(
        SyncRetryPolicy.withSyncRetry<String>(
          () async {
            attempts++;
            throw Exception('always_fails_$attempts');
          },
          tag: 'T4',
          onClassification: (c) => observed = c,
        ),
        throwsA(isA<SyncPersistentFailure>()),
      );
      expect(attempts, 3);
      expect(observed, SyncFailureClass.persistent);
      expect(DiagnosticLogger.testLog.any((l) => l.contains('SYNC-FAIL')),
          isTrue);
    });

    test('SyncPersistentFailure preserves all 3 errors', () async {
      try {
        await SyncRetryPolicy.withSyncRetry<void>(
          () async => throw Exception('boom'),
          tag: 'T5',
        );
        fail('should have thrown');
      } on SyncPersistentFailure catch (e) {
        expect(e.tag, 'T5');
        expect(e.attemptErrors.length, 3);
      }
    });

    test('total delay before throw is bounded by ~750ms (excluding request time)',
        () async {
      final sw = Stopwatch()..start();
      try {
        await SyncRetryPolicy.withSyncRetry<void>(
          () async => throw Exception('boom'),
          tag: 'T6',
        );
      } on SyncPersistentFailure {
        // expected
      }
      sw.stop();
      // backoffs are 0 + 250 + 500 = 750ms minimum. Allow generous upper
      // bound for CI slowness, but it MUST be < 3 seconds (no cooldown).
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(700));
    });

    test('SyncPersistentFailure.toUserMessageAr contains the tag', () {
      const e = SyncPersistentFailure(
        tag: 'USERS-SYNC',
        attemptErrors: [],
        totalDuration: Duration.zero,
      );
      final msg = e.toUserMessageAr();
      expect(msg.contains('فقد الاتصال'), isTrue);
      expect(msg.contains('USERS-SYNC'), isTrue);
    });

    test('exactly N invocations of the wrapped request', () async {
      var count = 0;
      try {
        await SyncRetryPolicy.withSyncRetry<int>(
          () async {
            count++;
            throw Exception('fail');
          },
          tag: 'T7',
        );
      } on SyncPersistentFailure {
        // expected
      }
      expect(count, SyncRetryPolicy.maxAttempts);
    });
  });
}
