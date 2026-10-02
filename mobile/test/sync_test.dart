import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/sync/sync_scheduler.dart';

import 'support/fakes.dart';

class FakeConnectivity implements ConnectivitySource {
  FakeConnectivity(this.up);
  bool up;
  final _c = StreamController<bool>.broadcast(sync: true);
  void set(bool v) {
    up = v;
    _c.add(v);
  }

  @override
  Future<bool> isOnline() async => up;
  @override
  Stream<bool> get changes => _c.stream;
}

void main() {
  group('backoff', () {
    test('5 s ×3 per failure, capped at 15 min; jitter ±20 %', () {
      const b = Backoff();
      expect([for (var i = 1; i <= 7; i++) b.delay(i).inSeconds], [5, 15, 45, 135, 405, 900, 900]);
      expect(b.delay(1, 0).inMilliseconds, 4000);
      expect(b.delay(1, 0.9999).inMilliseconds, closeTo(6000, 1));
      expect(b.delay(9, 0.9999), const Duration(minutes: 15));
    });
  });

  group('scheduler', () {
    late List<bool> results;
    late int calls;
    Future<bool> sync() async {
      calls++;
      return results.isEmpty ? true : results.removeAt(0);
    }

    setUp(() {
      calls = 0;
      results = [];
    });

    test('retries with backoff after failures, then settles on the interval', () {
      fakeAsync((fa) {
        results = [false, false, false, true];
        final s = SyncScheduler(sync: sync, connectivity: FakeConnectivity(true), random: () => 0.5);
        s.start();
        fa.flushMicrotasks();
        fa.elapse(Duration.zero);
        expect(calls, 1);
        fa.elapse(const Duration(milliseconds: 4900));
        expect(calls, 1);
        fa.elapse(const Duration(milliseconds: 200)); // 5 s
        expect(calls, 2);
        fa.elapse(const Duration(seconds: 15));
        expect(calls, 3);
        fa.elapse(const Duration(seconds: 44));
        expect(calls, 3);
        fa.elapse(const Duration(seconds: 1)); // 45 s → success
        expect((calls, s.failures), (4, 0));
        fa.elapse(const Duration(minutes: 4, seconds: 59));
        expect(calls, 4);
        fa.elapse(const Duration(seconds: 1));
        expect(calls, 5);
        s.stop();
        fa.elapse(const Duration(hours: 1));
        expect(calls, 5);
      });
    });

    test('offline: no attempts; back online: immediate retry with backoff reset', () {
      fakeAsync((fa) {
        results = [false, false];
        final net = FakeConnectivity(false);
        final statuses = <bool>[];
        final s = SyncScheduler(
            sync: sync, connectivity: net, random: () => 0.5, onStatus: (online, _) => statuses.add(online));
        s.start();
        fa.flushMicrotasks();
        fa.elapse(const Duration(hours: 1));
        expect(calls, 0);
        net.set(true);
        fa.elapse(Duration.zero);
        expect(calls, 1);
        fa.elapse(const Duration(seconds: 5));
        expect((calls, s.failures), (2, 2));
        net.set(false);
        fa.elapse(const Duration(hours: 1));
        expect(calls, 2, reason: 'pending backoff timer cancelled while offline');
        net.set(true);
        fa.elapse(Duration.zero);
        expect((calls, s.failures), (3, 0));
        expect(statuses, containsAllInOrder([false, true, false, true]));
        s.stop();
      });
    });

    test('a queued document is pushed after the debounce, not at the next interval', () {
      fakeAsync((fa) {
        final s = SyncScheduler(sync: sync, connectivity: FakeConnectivity(true));
        s.start();
        fa.flushMicrotasks();
        fa.elapse(Duration.zero);
        expect(calls, 1);
        s.trigger();
        fa.elapse(const Duration(seconds: 2));
        expect(calls, 2);
        s.stop();
      });
    });
  });

  group('controller sync', () {
    CartLine bread() => CartLine(productGlobalId: 'p2', name: 'b', unitPrice: 1, taxRate: 0);

    test('offline: documents stay pending, failure reported; next sync sends them once', () async {
      final (c, api) = await readyController();
      await c.createSale(customerGlobalId: 'c2', lines: [bread()], paid: 1);
      api.offline = true;
      expect(await c.syncNow(), isFalse);
      expect(c.lastSyncError, isNotNull);
      expect((await c.pendingDocs()), hasLength(1));
      api.offline = false;
      expect(await c.syncNow(), isTrue);
      expect(c.lastSyncError, isNull);
      expect((await c.store.outbox()).single.status, OutboxStatus.accepted);
      expect(api.pushed, hasLength(1));
    });

    test('app killed mid-push (response lost): retry is a duplicate, accepted exactly once', () async {
      final (c, api) = await readyController();
      final e = await c.createSale(customerGlobalId: 'c2', lines: [bread()], paid: 1);
      api.dropPushResponse = true;
      expect(await c.syncNow(), isFalse);
      expect((await c.store.outbox()).single.status, OutboxStatus.pending);
      api.dropPushResponse = false;
      expect(await c.syncNow(), isTrue);
      expect(api.pushed.map((b) => b.single['globalId']), [e.globalId, e.globalId]);
      expect(api.serverDocs, {e.globalId});
      expect((await c.store.outbox()).single.status, OutboxStatus.accepted);
    });

    test('pull marks a pending document accepted when the server already has it', () async {
      final (c, api) = await readyController();
      final e = await c.createSale(customerGlobalId: 'c2', lines: [bread()], paid: 1);
      api.serverDocs.add(e.globalId);
      await c.applyServerPayload(await api.pull(c.creds!, 'session', 1000));
      expect((await c.store.outbox()).single.status, OutboxStatus.accepted);
    });

    test('device token is rotated after 30 days and the new token is kept', () async {
      var now = DateTime(2026, 5, 1, 10);
      final (c, api) = await readyController(clock: () => now);
      expect(api.rotations, 0);
      now = now.add(const Duration(days: 29));
      await c.syncNow();
      expect(api.rotations, 0);
      now = now.add(const Duration(days: 2));
      expect(await c.syncNow(), isTrue);
      expect((api.rotations, c.creds!.deviceToken), (1, 'tok-1'));
      expect(await c.store.getKv('creds'), contains('tok-1'));
      await c.syncNow();
      expect(api.rotations, 1);
    });

    test('revoked device is wiped (credentials, data, outbox)', () async {
      final (c, api) = await readyController();
      await c.createSale(customerGlobalId: 'c2', lines: [bread()], paid: 1);
      api.failWith = 'device_revoked';
      expect(await c.syncNow(), isFalse);
      expect((c.isPaired, c.loggedIn), (false, false));
      expect(await c.store.outbox(), isEmpty);
      expect(await c.routeCustomers(), isEmpty);
      expect(await c.store.getKv('creds'), isNull);
    });

    test('expired session asks for the PIN again instead of retrying blindly', () async {
      final (c, api) = await readyController();
      api.failWith = 'invalid_session';
      expect(await c.syncNow(), isFalse);
      expect((c.session, c.lastSyncError), (null, 'sessionRequired'));
      expect(await c.syncNow(), isFalse);
      c.signOut();
      expect(c.loggedIn, isFalse);
    });

    test('background sync runs while logged in and stops on sign-out', () async {
      final (c, _) = await readyController();
      final s = SyncScheduler(sync: () async => true, connectivity: FakeConnectivity(true));
      final bg = BackgroundSync(c, s);
      await Future<void>.delayed(Duration.zero);
      expect(s.started, isTrue);
      c.signOut();
      expect(s.started, isFalse);
      bg.dispose();
    });
  });
}
