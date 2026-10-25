// M2 (plan 2026-10-24, MIR-008): the console's link state, and the refusal of a
// write while the link is read-only.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/mirror_connectivity.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/write_router.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 25, 12);

  tearDown(() {
    SyncInterceptor.instance = null;
    MirrorConnectivity.debugReset();
    MirrorState.instance.debugSetForTests();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  test('classify: online <= 30 s, degraded <= 5 min, then read-only; never '
      'heard of = read-only', () {
    MirrorLinkState c(Duration age) =>
        MirrorConnectivity.classify(t0.subtract(age), t0);
    expect(c(const Duration(seconds: 5)), MirrorLinkState.online);
    expect(c(const Duration(seconds: 30)), MirrorLinkState.online);
    expect(c(const Duration(seconds: 31)), MirrorLinkState.degraded);
    expect(c(const Duration(minutes: 5)), MirrorLinkState.degraded);
    expect(c(const Duration(minutes: 5, seconds: 1)), MirrorLinkState.readOnly);
    expect(MirrorConnectivity.classify(null, t0), MirrorLinkState.readOnly);
  });

  test('off a mirror the link is always "online" (no console rules)', () {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    MirrorConnectivity.debugUseClock(() => t0.add(const Duration(days: 9)));
    MirrorState.instance.debugSetForTests(lastHandshakeAt: t0);
    expect(MirrorConnectivity.state, MirrorLinkState.online);
    expect(MirrorConnectivity.isReadOnly, isFalse);
    MirrorConnectivity.ensureWritable(); // no throw
  });

  group('on a mirror', () {
    void mirror({required Duration age}) {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      ClientWriteInterceptor.setup();
      MirrorConnectivity.debugUseClock(() => t0);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq:8080',
        lastHandshakeAt: t0.subtract(age),
      );
    }

    test('untilReadOnly counts down to the 5-minute threshold', () {
      mirror(age: const Duration(minutes: 2));
      expect(MirrorConnectivity.untilReadOnly, const Duration(minutes: 3));
      mirror(age: const Duration(minutes: 9));
      expect(MirrorConnectivity.untilReadOnly, Duration.zero);
    });

    test('a failed heartbeat is recorded and bumps the revision', () {
      mirror(age: const Duration(seconds: 1));
      final before = MirrorState.instance.revision.value;
      MirrorState.instance.markHandshakeFailed();
      expect(MirrorState.instance.revision.value, before + 1);
      expect(MirrorState.instance.lastFailureAt, isNotNull);
    });

    test('a write is REFUSED (not attempted) while the link is read-only',
        () async {
      mirror(age: const Duration(minutes: 6));
      var attempted = false;
      Object? error;
      try {
        await ClientWriteInterceptor.dispatchWrite(() async {
          attempted = true;
          return null;
        }, tag: 'test');
      } catch (e) {
        error = e;
      }
      expect(attempted, isFalse);
      expect(error, isA<MirrorOfflineException>());
      expect((error as MirrorOfflineException).isRefusal, isTrue);
      expect(error.toString(), contains('للقراءة فقط'));
    });

    test('a write on a live link is attempted and awaited', () async {
      mirror(age: const Duration(seconds: 3));
      var attempted = false;
      await ClientWriteInterceptor.dispatchWrite(() async {
        attempted = true;
        return null;
      }, tag: 'test');
      expect(attempted, isTrue);
    });
  });
}
