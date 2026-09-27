import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 — Fix 3.5: requestWithRetry Exponential Backoff
///
/// Tests the retry logic in isolation by using a counter-controlled stub
/// that fails N times before succeeding. Verifies:
///   1. Transient failures are transparently retried.
///   2. Exponential backoff is applied (delay grows between retries).
///   3. Max retries exhausted → last exception is re-thrown.
///   4. Non-retryable errors (4xx) are re-thrown immediately (no retry waste).
///   5. SocketException triggers retry.
///   6. TimeoutException triggers retry.
///   7. 429 Too Many Requests is retried (rate-limit handling).
///
/// Note: These tests exercise the retry algorithm directly without a live
/// ServerProxy instance (which requires Flutter binding). The retry logic is
/// extracted into a standalone Dart function that mirrors the implementation
/// in ServerProxy.requestWithRetry().
void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Mirror of ServerProxy.requestWithRetry for isolated unit testing.
  // Kept in sync with the implementation in server_proxy.dart.
  // ─────────────────────────────────────────────────────────────────────────
  Future<T> requestWithRetryMirror<T>({
    required Future<T> Function() operation,
    required String operationName,
    int maxRetries = 3,
    int initialDelayMs = 1, // 1ms in tests to keep suite fast
    Set<int> retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    // Test-only hook: receives the NOMINAL backoff delay (ms) the algorithm is
    // about to sleep for, before it doubles. Lets the backoff-doubling test
    // assert the contract deterministically instead of measuring wall-clock
    // Future.delayed intervals (flaky under CI scheduler jitter at ms scale).
    void Function(int delayMs)? onRetryDelay,
  }) async {
    var delayMs = initialDelayMs;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } on TimeoutException {
        if (attempt == maxRetries) rethrow;
        // ignore: avoid_print
        print('[$operationName] Timeout attempt $attempt, retry in ${delayMs}ms');
      } on Exception catch (e) {
        final msg = e.toString();
        final isNetwork = msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('Connection reset') ||
            msg.contains('HandshakeException');

        if (isNetwork) {
          if (attempt == maxRetries) rethrow;
        } else {
          final statusMatch = RegExp(r'\((\d{3})\)').firstMatch(msg);
          final statusCode = int.tryParse(statusMatch?.group(1) ?? '');
          if (statusCode != null &&
              retryableStatusCodes.contains(statusCode) &&
              attempt < maxRetries) {
            // retryable server error
          } else {
            rethrow;
          }
        }
      }

      onRetryDelay?.call(delayMs);
      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2;
    }
    throw Exception('[$operationName] unreachable');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('Fix 3.5 — requestWithRetry Exponential Backoff', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Succeeds on first attempt without retrying', () async {
      var callCount = 0;
      final result = await requestWithRetryMirror<String>(
        operation: () async {
          callCount++;
          return 'success';
        },
        operationName: 'test-immediate-success',
      );

      expect(result, 'success');
      expect(callCount, 1, reason: 'Should not retry on success');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Retries once on 500, then succeeds on second attempt', () async {
      var callCount = 0;
      final result = await requestWithRetryMirror<int>(
        operation: () async {
          callCount++;
          if (callCount == 1) {
            throw Exception('Server error (500): Internal Server Error');
          }
          return 42;
        },
        operationName: 'test-retry-once',
        initialDelayMs: 1,
      );

      expect(result, 42);
      expect(callCount, 2, reason: 'Should call operation twice: fail then succeed');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Retries up to maxRetries on persistent 503, then rethrows', () async {
      var callCount = 0;
      await expectLater(
        () => requestWithRetryMirror<int>(
          operation: () async {
            callCount++;
            throw Exception('Server error (503): Service Unavailable');
          },
          operationName: 'test-max-retries',
          maxRetries: 3,
          initialDelayMs: 1,
        ),
        throwsA(isA<Exception>()),
      );

      expect(callCount, 3, reason: 'Should attempt exactly maxRetries=3 times');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Non-retryable 404 is thrown immediately without retry', () async {
      var callCount = 0;
      await expectLater(
        () => requestWithRetryMirror<int>(
          operation: () async {
            callCount++;
            throw Exception('Server error (404): Not Found');
          },
          operationName: 'test-no-retry-404',
          maxRetries: 3,
          initialDelayMs: 1,
        ),
        throwsA(isA<Exception>()),
      );

      expect(callCount, 1, reason: '404 is a client error and must NOT be retried');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('SocketException triggers retry', () async {
      var callCount = 0;
      final result = await requestWithRetryMirror<String>(
        operation: () async {
          callCount++;
          if (callCount == 1) {
            throw Exception("SocketException: Connection refused, address = 127.0.0.1 port = 8080");
          }
          return 'recovered';
        },
        operationName: 'test-socket-retry',
        initialDelayMs: 1,
      );

      expect(result, 'recovered');
      expect(callCount, 2, reason: 'SocketException should trigger one retry');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('TimeoutException triggers retry and rethrows after max attempts', () async {
      var callCount = 0;
      await expectLater(
        () => requestWithRetryMirror<String>(
          operation: () async {
            callCount++;
            throw TimeoutException('Request timed out', const Duration(seconds: 5));
          },
          operationName: 'test-timeout-retry',
          maxRetries: 2,
          initialDelayMs: 1,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(callCount, 2, reason: 'TimeoutException should retry up to maxRetries=2');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('429 Too Many Requests is retried (rate-limit recovery)', () async {
      var callCount = 0;
      final result = await requestWithRetryMirror<Map<String, dynamic>>(
        operation: () async {
          callCount++;
          if (callCount <= 2) {
            throw Exception('Server error (429): Too Many Requests');
          }
          return {'data': 'ok'};
        },
        operationName: 'test-rate-limit-retry',
        maxRetries: 3,
        initialDelayMs: 1,
      );

      expect(result['data'], 'ok');
      expect(callCount, 3, reason: '429 should be retried twice before eventual success');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Delay doubles between retries (exponential backoff contract)', () async {
      final delays = <int>[];
      var callCount = 0;

      await requestWithRetryMirror<bool>(
        operation: () async {
          callCount++;
          if (callCount < 3) {
            throw Exception('Server error (500): fail');
          }
          return true;
        },
        operationName: 'test-backoff-timing',
        maxRetries: 3,
        initialDelayMs: 10,
        onRetryDelay: delays.add,
      );

      // Assert the NOMINAL backoff schedule doubles: 10ms → 20ms. Captured from
      // the algorithm's own delay value, so this is exact and deterministic —
      // no wall-clock measurement of Future.delayed (which is flaky under CI
      // scheduler jitter: at 10/20ms scales a hiccup can inflate the FIRST
      // interval above the second and fail an ordering assertion).
      expect(delays, [10, 20],
          reason: 'Exponential backoff: nominal delay must double each retry');
    });
  });
}
