import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/login_rate_limiter.dart';

void main() {
  setUp(() {
    LoginRateLimiter.reset();
  });

  group('LoginRateLimiter', () {
    test('allows login when no previous attempts', () {
      expect(LoginRateLimiter.isAllowed('testuser'), true);
      expect(LoginRateLimiter.remainingAttempts('testuser'), 5);
    });

    test('decrements remaining attempts on failure', () {
      expect(LoginRateLimiter.recordFailure('testuser'), 4);
      expect(LoginRateLimiter.remainingAttempts('testuser'), 4);

      expect(LoginRateLimiter.recordFailure('testuser'), 3);
      expect(LoginRateLimiter.remainingAttempts('testuser'), 3);
    });

    test('locks out after 5 failed attempts', () {
      for (int i = 0; i < 5; i++) {
        LoginRateLimiter.recordFailure('testuser');
      }

      expect(LoginRateLimiter.isAllowed('testuser'), false);
      expect(LoginRateLimiter.remainingAttempts('testuser'), 0);
      expect(LoginRateLimiter.getLockoutRemaining('testuser'), isNotNull);
    });

    test('resets on successful login', () {
      LoginRateLimiter.recordFailure('testuser');
      LoginRateLimiter.recordFailure('testuser');
      LoginRateLimiter.recordFailure('testuser');

      LoginRateLimiter.recordSuccess('testuser');

      expect(LoginRateLimiter.isAllowed('testuser'), true);
      expect(LoginRateLimiter.remainingAttempts('testuser'), 5);
    });

    test('is case-insensitive for usernames', () {
      LoginRateLimiter.recordFailure('Admin');
      expect(LoginRateLimiter.remainingAttempts('admin'), 4);
      expect(LoginRateLimiter.remainingAttempts('ADMIN'), 4);
    });

    test('tracks different users independently', () {
      LoginRateLimiter.recordFailure('user1');
      LoginRateLimiter.recordFailure('user1');

      expect(LoginRateLimiter.remainingAttempts('user1'), 3);
      expect(LoginRateLimiter.remainingAttempts('user2'), 5);
    });

    test('returns remaining attempts as 0 when locked', () {
      for (int i = 0; i < 5; i++) {
        LoginRateLimiter.recordFailure('locktest');
      }
      expect(LoginRateLimiter.remainingAttempts('locktest'), 0);
    });

    test('lockout duration is approximately 15 minutes', () {
      for (int i = 0; i < 5; i++) {
        LoginRateLimiter.recordFailure('durationtest');
      }
      final remaining = LoginRateLimiter.getLockoutRemaining('durationtest');
      expect(remaining, isNotNull);
      expect(remaining!.inMinutes, lessThanOrEqualTo(15));
      expect(remaining.inMinutes, greaterThanOrEqualTo(14));
    });

    test('reset clears all records', () {
      LoginRateLimiter.recordFailure('user1');
      LoginRateLimiter.recordFailure('user2');

      LoginRateLimiter.reset();

      expect(LoginRateLimiter.remainingAttempts('user1'), 5);
      expect(LoginRateLimiter.remainingAttempts('user2'), 5);
    });

    test('returns correct remaining on each failure', () {
      expect(LoginRateLimiter.recordFailure('seq'), 4);
      expect(LoginRateLimiter.recordFailure('seq'), 3);
      expect(LoginRateLimiter.recordFailure('seq'), 2);
      expect(LoginRateLimiter.recordFailure('seq'), 1);
      expect(LoginRateLimiter.recordFailure('seq'), 0);
    });
  });
}
