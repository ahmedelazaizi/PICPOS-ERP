import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

import '../session/wh_session.dart';
import '../store/wh_local_store.dart';

/// Client-generated global id (the idempotency key of one operation).
String newId([String prefix = 'wh']) {
  final r = Random.secure();
  final hex = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$hex';
}

/// What the banner and the Outbox tab show: reachability and the queue.
class WhSyncState extends ChangeNotifier {
  bool online = true;
  bool needsLogin = false;
  int pending = 0;
  int rejected = 0;
  DateTime? lastSync;

  void reachable() {
    if (online && !needsLogin) return;
    online = true;
    needsLogin = false;
    notifyListeners();
  }

  void unreachable({bool login = false}) {
    if (!online && needsLogin == login) return;
    online = false;
    needsLogin = login;
    notifyListeners();
  }

  void queue({required int pending, required int rejected}) {
    this.pending = pending;
    this.rejected = rejected;
    notifyListeners();
  }

  void synced(DateTime at) {
    lastSync = at;
    notifyListeners();
  }
}

/// Offline outbox with replay (plan W5).
///
/// * Storage: the encrypted SQLCipher store (`WhLocalStore`), key in the
///   Android Keystore - the queue is never plain text on the phone.
/// * Every entry's `globalId` is the `x-idempotency-key` of its request, so a
///   replay after a lost answer is answered from the server's command log.
/// * Conflict rules, applied by [send]:
///     - 2xx                                  -> accepted (`replayed` -> duplicate)
///     - no answer / 429 / 5xx                -> stay pending, retry later (same id)
///     - 401 session expired                  -> stay pending, ask for sign-in
///     - 401 device revoked                   -> stay pending; the session wipes
///     - any other 4xx (stale, stock_changed,
///       invalid_transition, over_receipt,
///       idempotency_conflict, permission...) -> REJECTED, terminal. It is never
///       re-sent under a new identity; the user sees the reason and decides.
///   Entries go out strictly in creation order.
class WhOutbox {
  WhOutbox(this.store, this.session, this.sync);
  final WhLocalStore store;
  final WhSession session;
  final WhSyncState sync;

  /// Queues `POST [path]` with [body]; [kind] is only the label shown to the user.
  Future<String> enqueue(String kind, String path, Map<String, Object?> body) async {
    final id = newId('op');
    await store.outbox.enqueue(globalId: id, kind: kind, payload: {'path': path, 'body': body});
    await _count();
    return id;
  }

  Future<void> _count() async {
    final all = await store.store.outbox();
    sync.queue(
      pending: all.where((e) => e.status == OutboxStatus.pending).length,
      rejected: all.where((e) => e.status == OutboxStatus.rejected).length,
    );
  }

  Future<PushReply> send(OutboxEntry e) async {
    final client = session.client;
    if (client == null) throw const ApiError(kind: ApiErrorKind.network, code: 'network');
    try {
      final r = await client.command(
        e.payload['path']! as String,
        (e.payload['body']! as Map).cast<String, Object?>(),
        commandId: e.globalId,
      );
      return PushReply(r.replayed ? PushOutcome.duplicate : PushOutcome.accepted);
    } on ApiError catch (err) {
      if (err.retryable) rethrow;
      if (err.kind == ApiErrorKind.unauthorized || err.kind == ApiErrorKind.deviceRevoked) rethrow;
      return PushReply(PushOutcome.rejected, code: err.code);
    }
  }

  /// Sends what is pending. Never throws; returns null when nothing ran.
  Future<DrainReport?> drain() async {
    if (session.client == null) return null;
    final report = await store.outbox.drain(send);
    final failure = report.failure;
    if (failure == null) {
      sync.reachable();
      sync.synced(DateTime.now());
    } else {
      sync.unreachable(login: failure is ApiError && failure.kind == ApiErrorKind.unauthorized);
    }
    await _count();
    return report;
  }

  /// Puts a rejected entry's reason in front of the user and lets him drop it.
  /// Dropping is the only way out: a rejected operation is never re-sent.
  Future<void> dismiss(OutboxEntry e) async {
    e
      ..status = OutboxStatus.accepted
      ..error = 'dismissed';
    await store.store.updateOutbox(e);
    await _count();
  }
}
