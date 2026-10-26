// Offline outbox (plan W5): encrypted-store-backed queue, strict order, the
// entry id IS the idempotency key, conflict rules (retry / reject / ask login).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import 'docs_flow_test.dart' show signedIn;
import 'fake_office.dart';

Map<String, Object?> _receiptBody(String gid) => {
      'globalId': gid,
      'lines': [
        {'lineGlobalId': 'line-$gid', 'productId': 5, 'quantity': '1', 'condition': 'ok'},
      ],
    };

void main() {
  late FakeOffice office;
  late WhLocalStore store;
  late WhOutbox outbox;
  late WhSyncState sync;

  setUp(() async {
    office = FakeOffice();
    store = WhLocalStore.memory();
    sync = WhSyncState();
    outbox = WhOutbox(store, await signedIn(office), sync);
  });

  void fail(ApiError e) {
    for (final t in office.transports) {
      t.failWith = e;
    }
  }

  Future<List<OutboxEntry>> entries() => store.store.outbox();

  test('entries are sent in creation order, each under its own id as the idempotency key', () async {
    final a = await outbox.enqueue('receipt_lines', '/api/m1/wh/po/PO1/receipts', _receiptBody('r1'));
    final b = await outbox.enqueue('receipt_submit', '/api/m1/wh/receipts/r1/submit', const {});
    final report = await outbox.drain();
    expect(report!.accepted, 2);
    expect(office.posts.map((p) => p.key), [a, b]);
    expect((await entries()).every((e) => e.status == OutboxStatus.accepted), isTrue);
    expect(sync.pending, 0);
    expect(sync.lastSync, isNotNull);
  });

  test('no connection: everything stays pending, the banner state is offline, nothing is lost', () async {
    await outbox.enqueue('count_submit', '/api/m1/wh/counts/T1/submit', {'globalId': 'c1'});
    fail(const ApiError(kind: ApiErrorKind.network, code: 'network'));
    final report = await outbox.drain();
    expect(report!.complete, isFalse);
    expect(sync.online, isFalse);
    expect(sync.pending, 1);
    expect((await entries()).single.status, OutboxStatus.pending);

    fail(const ApiError(kind: ApiErrorKind.network, code: 'x'));
    for (final t in office.transports) {
      t.failWith = null;
    }
    await outbox.drain();
    expect(office.applied, 1);
    expect(sync.online, isTrue);
    expect(sync.pending, 0);
  });

  test('a crash after the office applied the command but before the phone noted it replays safely', () async {
    await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
    await outbox.drain();
    expect(office.applied, 1);
    // Simulate the crash: the phone believes the entry is still pending.
    final e = (await entries()).single
      ..status = OutboxStatus.pending
      ..error = null;
    await store.store.updateOutbox(e);
    final report = await outbox.drain();
    expect(report!.accepted, 1);
    expect(office.applied, 1, reason: 'the office answered from its command log; nothing was applied twice');
    expect(office.posts, hasLength(1));
  });

  test('a refusal (stock_changed, self_approval, stale...) is final: never re-sent, reason kept', () async {
    await outbox.enqueue('transfer_dispatch', '/api/m1/wh/transfers/t1/dispatch', const {});
    office.rejectWith = 'stock_changed';
    final report = await outbox.drain();
    expect(report!.rejected, 1);
    final e = (await entries()).single;
    expect(e.status, OutboxStatus.rejected);
    expect(e.error, 'stock_changed');
    expect(sync.rejected, 1);

    office.rejectWith = null;
    await outbox.drain();
    expect(office.posts, isEmpty, reason: 'a rejected operation is not retried under any identity');
    await outbox.dismiss(e);
    expect(sync.rejected, 0);
    final kept = (await entries()).single;
    expect((kept.status, kept.error), (OutboxStatus.rejected, 'dismissed'), reason: 'a dropped operation is NOT recorded as accepted');
    expect(await store.outbox.isDrained(), isTrue, reason: 'a dismissed entry does not hold back unpairing');
  });

  test('an expired session keeps the queue and asks for sign-in; a rejected entry does not block the next', () async {
    await outbox.enqueue('a', '/api/m1/wh/vouchers', {'globalId': 'v1'});
    fail(const ApiError(kind: ApiErrorKind.unauthorized, code: 'unauthorized', status: 401));
    await outbox.drain();
    expect(sync.needsLogin, isTrue);
    expect((await entries()).single.status, OutboxStatus.pending);

    for (final t in office.transports) {
      t.failWith = null;
    }
    office.rejectWith = 'over_receipt';
    await outbox.enqueue('b', '/api/m1/wh/vouchers', {'globalId': 'v2'});
    await outbox.drain();
    final es = await entries();
    expect(es.map((e) => e.status), [OutboxStatus.rejected, OutboxStatus.rejected]);
  });

  test('queued payloads are stored in the local store, not in memory only', () async {
    final id = await outbox.enqueue('receipt_lines', '/api/m1/wh/po/PO1/receipts', {'globalId': 'r1'});
    final stored = await store.store.outboxEntry(id);
    expect(stored!.payload['path'], '/api/m1/wh/po/PO1/receipts');
    expect(stored.payload['body'], {'globalId': 'r1'});
  });

  group('WH-004 an operation belongs to the user who made it', () {
    test('A queues, signs out; B signs in: nothing goes out under B; A returns and it goes out as A', () async {
      final session = await signedIn(office);
      outbox = WhOutbox(store, session, sync);
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});

      session.signOut();
      office
        ..userId = 9
        ..username = 'bob';
      await session.login('bob', 'pw');
      await outbox.drain();
      expect(office.posts, isEmpty, reason: 'ali\'s operation is not sent with bob\'s session');
      expect((await entries()).single.status, OutboxStatus.pending);
      expect(sync.foreign, 1);
      expect(sync.pending, 0);

      // Bob's own operation goes out under bob; ali's still waits behind it.
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v2'});
      await outbox.drain();
      expect(office.posts.map((p) => p.user), ['9']);
      expect(sync.foreign, 1);

      session.signOut();
      office
        ..userId = 7
        ..username = 'ali';
      await session.login('ali', 'pw');
      await outbox.drain();
      expect(office.posts.map((p) => p.user), ['9', '7'], reason: 'ali\'s operation is created by ali');
      expect(sync.foreign, 0);
    });

    test('an entry without an owner (written by an older build) is never sent', () async {
      final session = await signedIn(office);
      outbox = WhOutbox(store, session, sync);
      await store.outbox.enqueue(globalId: 'op-legacy-1', kind: 'x', payload: {'path': '/api/m1/wh/vouchers', 'body': {'globalId': 'v1'}});
      await outbox.drain();
      expect(office.posts, isEmpty);
    });
  });

  group('WH-005 a failing operation cannot block the queue forever', () {
    late DateTime clock;
    setUp(() async {
      clock = DateTime(2026, 10, 25, 9);
      outbox = WhOutbox(store, await signedIn(office), sync, now: () => clock);
    });

    test('a period closed at the office rejects the entry with its reason; the next one still goes', () async {
      office.periodClosed = true;
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      await outbox.enqueue('count_submit', '/api/m1/wh/counts/T1/submit', {'globalId': 'c1'});
      final report = await outbox.drain();
      expect(report!.rejected, 1);
      expect(report.accepted, 1, reason: 'the entry behind the refused one is sent');
      final es = await entries();
      expect(es.first.status, OutboxStatus.rejected);
      expect(es.first.error, 'period_closed');
      expect(es.last.status, OutboxStatus.accepted);
    });

    test('repeated 500s back off, then park the entry as dead_letter so the next one flows', () async {
      office.serverErrors = 5;
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      await outbox.enqueue('count_submit', '/api/m1/wh/counts/T1/submit', {'globalId': 'c1'});

      await outbox.drain();
      expect(office.serverErrors, 4);
      await outbox.drain(); // same instant: the backoff gate holds, the office is not hammered
      expect(office.serverErrors, 4);
      expect((await entries()).first.status, OutboxStatus.pending);

      for (var i = 0; i < 4; i++) {
        clock = clock.add(const Duration(hours: 1));
        await outbox.drain();
      }
      final es = await entries();
      expect(es.first.status, OutboxStatus.rejected);
      expect(es.first.error, 'dead_letter');
      expect(office.serverErrors, 0, reason: 'exactly five attempts were made');
      expect(es.last.status, OutboxStatus.accepted, reason: 'the queue is no longer blocked: the entry behind it went out');
    });

    test('NEW-03: a run of 503 busy answers never consumes the dead_letter budget and the entry is still sent when the office recovers', () async {
      office.busyReplies = 12; // more than twice maxServerFailures
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      for (var i = 0; i < 12; i++) {
        clock = clock.add(const Duration(hours: 1));
        await outbox.drain();
      }
      expect(office.busyReplies, 0, reason: 'twelve attempts were made');
      var e = (await entries()).single;
      expect(e.status, OutboxStatus.pending, reason: 'busy is not a permanent failure');
      expect(e.payload['serverFailures'], isNull);
      expect(e.payload['busyCount'], 12);
      clock = clock.add(const Duration(hours: 1));
      await outbox.drain();
      e = (await entries()).single;
      expect(e.status, OutboxStatus.accepted);
      expect(office.applied, 1);
    });

    test('NEW-03: retry puts a dead_letter entry back in the queue under the SAME id; discarding is the other exit', () async {
      office.serverErrors = 5;
      final id = await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(hours: 1));
        await outbox.drain();
      }
      var e = (await entries()).single;
      expect((e.status, e.error), (OutboxStatus.rejected, 'dead_letter'));
      expect(sync.rejected, 1);

      await outbox.retry(e);
      e = (await entries()).single;
      expect((e.status, e.globalId), (OutboxStatus.pending, id));
      expect(e.payload['serverFailures'], isNull);
      expect(sync.rejected, 0);
      await outbox.drain();
      expect((await entries()).single.status, OutboxStatus.accepted);
      expect(office.posts.last.key, id);

      // an ordinary refusal is NOT retryable
      office.rejectWith = 'stock_changed';
      await outbox.enqueue('transfer_dispatch', '/api/m1/wh/transfers/t1/dispatch', const {});
      await outbox.drain();
      final refused = (await entries()).last;
      await outbox.retry(refused);
      expect((await entries()).last.status, OutboxStatus.rejected);
    });

    test('an operation that depends on a rejected one is not sent', () async {
      office.rejectWith = 'po_not_receivable';
      final a = await outbox.enqueue('receipt_lines', '/api/m1/wh/po/PO1/receipts', _receiptBody('r1'));
      await outbox.enqueue('receipt_submit', '/api/m1/wh/receipts/r1/submit', const {}, after: a);
      await outbox.drain();
      final es = await entries();
      expect(es.map((e) => e.error), ['po_not_receivable', 'dependency_rejected']);
      expect(office.posts, isEmpty);
    });
  });

  group('W5.4b a revoked phone says so and what it threw away', () {
    test('2 unsent operations: the wipe leaves a notice with the count', () async {
      final session = await signedIn(office);
      outbox = WhOutbox(store, session, sync);
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v2'});
      office.revoked = true;
      await outbox.drain();
      expect(session.paired, isFalse);
      expect(session.unpairNotice, isNotNull);
      expect(session.unpairNotice!.discardedOperations, 2);
    });

    test('a user-requested unpair leaves no notice', () async {
      final session = await signedIn(office);
      await session.wipe();
      expect(session.unpairNotice, isNull);
    });
  });}
