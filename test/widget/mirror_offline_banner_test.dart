import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/mirror_offline_banner.dart';
import 'package:picpos_erp/services/network_service.dart';

/// MM.D unit tests for the offline-banner visibility decision. The
/// classifier is a pure function of (mode, lastHandshakeAt, now), so we
/// can pin its behaviour without driving the real ticker + clock.
void main() {
  // A fixed "now" so the threshold maths is deterministic across CI clocks.
  final now = DateTime.utc(2026, 5, 4, 12, 0, 0);

  group('MirrorOfflineBanner.shouldShow', () {
    test('false in standalone mode regardless of handshake age', () {
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.standalone,
          lastHandshakeAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.standalone,
          lastHandshakeAt: now.subtract(const Duration(hours: 2)),
          now: now,
        ),
        isFalse,
      );
    });

    test('false in client mode (client mode owns its outbox)', () {
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.client,
          lastHandshakeAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('true in mirror mode when handshake has never been recorded', () {
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.mirror,
          lastHandshakeAt: null,
          now: now,
        ),
        isTrue,
        reason: 'never-handshook mirror is offline by definition',
      );
    });

    test('false in mirror mode within the 5-minute window', () {
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.mirror,
          lastHandshakeAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isFalse,
      );
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.mirror,
          // exactly at 5 minutes — the predicate uses strict greater-than,
          // so this case is still "fresh enough" and the banner stays hidden.
          lastHandshakeAt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('true in mirror mode when the threshold is crossed', () {
      expect(
        MirrorOfflineBanner.shouldShow(
          mode: NetworkMode.mirror,
          lastHandshakeAt:
              now.subtract(const Duration(minutes: 5, seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
