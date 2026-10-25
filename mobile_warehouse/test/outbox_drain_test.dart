// Offline outbox (plan W5): encrypted-store-backed queue, strict order, the
// entry id IS the idempotency key, conflict rules (retry / reject / ask login).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import 'docs_flow_test.dart' show signedIn;
import 'fake_office.dart';

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
    final a = await outbox.enqueue('receipt_lines', '/api/m1/wh/po/PO1/receipts', {'globalId': 'r1'});
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
}
