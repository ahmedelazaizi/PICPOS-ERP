// Feature 010 / Cluster C — ActivityLogger 429-cooldown helpers.
//
// Field-collected logs from a beta restaurant showed a single mirror device
// hammering the server's per-IP rate limiter (api_rate_limiter.dart, 120 req
// / 60s) with activity-log pushes. Once the bucket was exhausted, EVERY
// write (sales, purchases, settings, shifts) got 429'd for the rest of the
// minute — including a purchase invoice, which then caused the subsequent
// purchase return to fail with 404 ("Purchase invoice not found").
//
// The fix in lib/services/activity_logger.dart parses the server's
// `retryAfterSeconds` from a 429 response and pauses subsequent activity-
// log pushes for that window. These tests pin the parser shape and the
// boundary conditions — the cooldown is a load-bearing piece of the fix
// and needs a regression guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/activity_logger.dart';

void main() {
  group('ActivityLogger.parseRateLimitCooldown', () {
    test('returns the server-requested duration on a real 429 response', () {
      // The exact wire format from api_rate_limiter.dart:121 — what
      // ServerProxy._postWithRetry surfaces to the caller.
      const msg = 'Server error (429): {"error":"Too many requests",'
          '"retryAfterSeconds":60}';
      expect(
        ActivityLogger.parseRateLimitCooldown(msg),
        const Duration(seconds: 60),
      );
    });

    test('honours a non-default retryAfterSeconds (e.g. 30s)', () {
      const msg = 'Server error (429): {"error":"Too many requests",'
          '"retryAfterSeconds":30}';
      expect(
        ActivityLogger.parseRateLimitCooldown(msg),
        const Duration(seconds: 30),
      );
    });

    test('falls back to 60s when the body is malformed but the code is 429',
        () {
      // Defensive: any 429 we cannot parse still triggers a sensible
      // cooldown. Better to back off than to keep hammering.
      const msg = 'Server error (429): unexpected body shape';
      expect(
        ActivityLogger.parseRateLimitCooldown(msg),
        const Duration(seconds: 60),
      );
    });

    test('returns null for a 500 (NOT a back-pressure signal)', () {
      // Other server errors must not pause activity-log pushes — they
      // could be transient and unrelated to load.
      expect(
        ActivityLogger.parseRateLimitCooldown(
            'Server error (500): internal server error'),
        isNull,
      );
    });

    test('returns null for a network exception', () {
      expect(
        ActivityLogger.parseRateLimitCooldown(
            'SocketException: connection refused'),
        isNull,
      );
      expect(
        ActivityLogger.parseRateLimitCooldown('TimeoutException after 30s'),
        isNull,
      );
    });

    test('returns null for an empty / unrelated message', () {
      expect(ActivityLogger.parseRateLimitCooldown(''), isNull);
      expect(
        ActivityLogger.parseRateLimitCooldown(
            'Exception: some unrelated business error'),
        isNull,
      );
    });

    test('also recognises a 429 surfaced as plain "Too many requests" text',
        () {
      // Defensive — some intermediaries may strip the numeric code from
      // the prefix. As long as the body is recognisable we still pause.
      const msg = '{"error":"Too many requests","retryAfterSeconds":45}';
      expect(
        ActivityLogger.parseRateLimitCooldown(msg),
        const Duration(seconds: 45),
      );
    });
  });

  group('ActivityLogger cooldown state', () {
    setUp(ActivityLogger.resetPushCooldownForTest);

    test('isInPushCooldown is false by default', () {
      expect(ActivityLogger.isInPushCooldown, isFalse);
    });

    test('resetPushCooldownForTest clears any prior cooldown', () {
      // Sanity: this hook is what other tests rely on between runs.
      ActivityLogger.resetPushCooldownForTest();
      expect(ActivityLogger.isInPushCooldown, isFalse);
    });
  });
}
