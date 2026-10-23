import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/scale_reconnect_policy.dart';

/// Cover for the scale reconnection schedule.
///
/// `autoConnect()` runs once from `MainScreen.initState` and nothing else ever
/// retried it, so a scale that was powered off, still enumerating, or unplugged
/// mid-shift stayed dead until the app restarted — invisible, because the
/// failure was swallowed, and unrecoverable for a cashier, who has no settings
/// screen to reconnect from. These tests pin the retry schedule and the one
/// case that must NOT retry: an operator who deliberately disconnected.
void main() {
  group('ScaleReconnectPolicy — backoff schedule', () {
    test('backs off 2s, 4s, 8s, 16s then holds at 30s', () {
      final p = ScaleReconnectPolicy();
      expect(p.nextDelay(), const Duration(seconds: 2));
      expect(p.nextDelay(), const Duration(seconds: 4));
      expect(p.nextDelay(), const Duration(seconds: 8));
      expect(p.nextDelay(), const Duration(seconds: 16));
      expect(p.nextDelay(), const Duration(seconds: 30));
    });

    test('holds at the cap indefinitely rather than growing unbounded', () {
      final p = ScaleReconnectPolicy();
      for (var i = 0; i < 4; i++) {
        p.nextDelay();
      }
      for (var i = 0; i < 500; i++) {
        expect(p.nextDelay(), const Duration(seconds: 30));
      }
    });

    test('reset returns to the front of the schedule', () {
      final p = ScaleReconnectPolicy();
      p.nextDelay();
      p.nextDelay();
      p.nextDelay();
      p.reset();
      expect(p.nextDelay(), const Duration(seconds: 2),
          reason: 'a successful connect must not leave the next outage '
              'waiting 30s to recover');
    });
  });

  group('ScaleReconnectPolicy — operator intent', () {
    test('retries are allowed by default', () {
      expect(ScaleReconnectPolicy().shouldRetry, isTrue);
    });

    test('an explicit disconnect suppresses retries', () {
      final p = ScaleReconnectPolicy();
      p.suppress();
      expect(p.shouldRetry, isFalse,
          reason: 'pressing disconnect in hardware settings must not be '
              'undone by the retry loop two seconds later');
    });

    test('suppressing also rewinds the schedule', () {
      final p = ScaleReconnectPolicy();
      p.nextDelay();
      p.nextDelay();
      p.suppress();
      p.resume();
      expect(p.nextDelay(), const Duration(seconds: 2));
    });

    test('resume re-arms retries', () {
      final p = ScaleReconnectPolicy();
      p.suppress();
      p.resume();
      expect(p.shouldRetry, isTrue);
    });

    test('resume alone does not rewind the schedule', () {
      // Every connect attempt clears operator intent, including the ones the
      // retry loop itself makes. If that rewound the backoff, a permanently
      // absent scale would be probed every 2s forever instead of every 30s.
      final p = ScaleReconnectPolicy();
      p.nextDelay();
      p.nextDelay();
      p.resume();
      expect(p.nextDelay(), const Duration(seconds: 8));
    });

    test('reset does not silently re-arm a suppressed policy', () {
      final p = ScaleReconnectPolicy();
      p.suppress();
      p.reset();
      expect(p.shouldRetry, isFalse,
          reason: 'only an explicit connect (resume) clears operator intent');
    });
  });
}
