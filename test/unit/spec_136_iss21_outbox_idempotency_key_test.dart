import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/offline_sync_worker.dart';

/// Spec 136 ISS-21 — the offline outbox drain must reuse the globally-unique
/// UUIDv7 idempotency key minted by ClientWriteInterceptor._tryOrQueue
/// (payload['idempotency_key']), NOT regenerate `'SyncOutbox_<localId>'`.
///
/// The local outbox id restarts after a wipe/reinstall and repeats across
/// devices, while the server's processed_messages cache is persistent + global,
/// so 'SyncOutbox_3' collided with an unrelated earlier invoice and the server
/// returned that stale cached response — silently dropping the new offline
/// invoice and causing a shift variance.
void main() {
  test('uses the stored UUIDv7 idempotency_key when present', () {
    const gid = '019e91f6-988b-7851-b2ae-6a9c6f5a3a78';
    final key = OfflineSyncWorker.idempotencyKeyFor(
      {'invoiceNumber': 'POS-32', 'idempotency_key': gid},
      3, // local outbox id that previously collided
    );
    expect(key, gid,
        reason: 'must reuse the globally-unique stored key, not SyncOutbox_3');
    expect(key, isNot(startsWith('SyncOutbox_')));
  });

  test('two offline sales never share a key even on the same local outbox id',
      () {
    // Simulates the cross-session/cross-device collision: same local outbox id
    // (3) but two distinct economic events → must yield distinct keys.
    final a = OfflineSyncWorker.idempotencyKeyFor(
        {'idempotency_key': 'gid-A'}, 3);
    final b = OfflineSyncWorker.idempotencyKeyFor(
        {'idempotency_key': 'gid-B'}, 3);
    expect(a, isNot(b));
  });

  test('falls back to SyncOutbox_<id> only for legacy rows without a key', () {
    expect(OfflineSyncWorker.idempotencyKeyFor({'invoiceNumber': 'X'}, 7),
        'SyncOutbox_7');
    expect(OfflineSyncWorker.idempotencyKeyFor({'idempotency_key': ''}, 7),
        'SyncOutbox_7');
  });
}
