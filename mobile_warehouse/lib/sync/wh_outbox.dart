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

  /// Pending operations that belong to ANOTHER user (or another pairing): they
  /// wait, untouched, until their owner signs in again.
  int foreign = 0;
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

  void queue({required int pending, required int rejected, int foreign = 0}) {
    this.pending = pending;
    this.rejected = rejected;
    this.foreign = foreign;
    notifyListeners();
  }

  void synced(DateTime at) {
    lastSync = at;
    notifyListeners();
  }
}

/// What happened to a set of operations one screen just queued (W2.3c): the
/// screen shows "sent" only when the office ACCEPTED all of them.
class SendOutcome {
  const SendOutcome({required this.accepted, required this.rejectedCode, required this.waiting, this.rejectedIndex});

  /// Position (in the ids passed to drainFor) of the operation the office refused.
  final int? rejectedIndex;

  /// Every operation was accepted (or answered as a duplicate) by the office.
  final bool accepted;

  /// Reason code of the first operation the office refused, or null.
  final String? rejectedCode;

  /// Some operation is still queued (no connection, session ended, backoff).
  final bool waiting;
}

/// Offline outbox with replay (plan W5).
///
/// * Storage: the encrypted SQLCipher store (`WhLocalStore`), key in the
///   Android Keystore - the queue is never plain text on the phone.
/// * Every entry's `globalId` is the `x-idempotency-key` of its request, so a
///   replay after a lost answer is answered from the server's command log.
/// * **Owner (WH-004):** each entry records the user and the device that made
///   it. Only the signed-in owner's entries are sent, with his own session; the
///   others stay queued ("saved for user X") and are shown, never sent under
///   somebody else's identity.
/// * Conflict rules, applied by [send]:
///     - 2xx                                  -> accepted (`replayed` -> duplicate)
///     - no answer / 429                      -> stay pending, retry later (same id)
///     - 5xx (the office answered but failed) -> retry with backoff; after
///       [maxServerFailures] the entry is parked as `dead_letter` (needs the
///       manager) instead of blocking the whole queue forever (WH-005)
///     - 401 session expired                  -> stay pending, ask for sign-in
///     - 401 device revoked                   -> the phone is unpaired and the
///       user is told how many operations were discarded
///     - any other 4xx (stale, stock_changed, period_closed, ...) -> REJECTED,
///       terminal; the user sees the reason and decides.
///   Entries go out strictly in creation order. An entry queued with `after:`
///   is not sent if the entry it depends on was rejected.
class WhOutbox {
  WhOutbox(this.store, this.session, this.sync, {DateTime Function()? now, this.maxServerFailures = 5})
      : _now = now ?? DateTime.now {
    session.unsentCount = unsentCount;
  }
  final WhLocalStore store;
  final WhSession session;
  final WhSyncState sync;
  final int maxServerFailures;
  final DateTime Function() _now;

  String? get _deviceId => session.client?.credentials.deviceId;

  /// Queues `POST [path]` with [body]; [kind] is only the label shown to the
  /// user. [after] is the id of an earlier entry this one depends on.
  Future<String> enqueue(String kind, String path, Map<String, Object?> body, {String? after}) async {
    final info = session.info;
    final device = _deviceId;
    if (info == null || device == null) {
      throw const ApiError(kind: ApiErrorKind.unauthorized, code: 'unauthorized');
    }
    final id = newId('op');
    await store.outbox.enqueue(globalId: id, kind: kind, payload: {
      'path': path,
      'body': body,
      'userId': info.userId,
      'userName': info.username,
      'deviceId': device,
      'after': ?after,
    });
    await _count();
    return id;
  }

  bool _mine(OutboxEntry e) =>
      session.info != null && e.payload['userId'] == session.info!.userId && e.payload['deviceId'] == _deviceId;

  Future<int> unsentCount() async =>
      (await store.store.outbox()).where((e) => e.status == OutboxStatus.pending).length;

  Future<void> _count() async {
    final all = await store.store.outbox();
    // Before the office has said who is signed in, nothing is called foreign.
    bool owned(OutboxEntry e) => session.info == null || _mine(e);
    sync.queue(
      pending: all.where((e) => e.status == OutboxStatus.pending && owned(e)).length,
      rejected: all.where((e) => e.status == OutboxStatus.rejected && e.error != 'dismissed' && owned(e)).length,
      foreign: all.where((e) => e.status == OutboxStatus.pending && !owned(e)).length,
    );
  }

  Future<PushReply> send(OutboxEntry e) async {
    final client = session.client;
    if (client == null) throw const ApiError(kind: ApiErrorKind.network, code: 'network');
    final after = e.payload['after'];
    if (after is String) {
      final parent = await store.store.outboxEntry(after);
      if (parent != null && parent.status == OutboxStatus.rejected) {
        return const PushReply(PushOutcome.rejected, code: 'dependency_rejected');
      }
    }
    final retryAt = e.payload['retryAt'];
    if (retryAt is int && _now().millisecondsSinceEpoch < retryAt) {
      // Backoff after an office failure: wait, keeping the order.
      throw const ApiError(kind: ApiErrorKind.unavailable, code: 'backoff');
    }
    try {
      final r = await client.command(
        e.payload['path']! as String,
        (e.payload['body']! as Map).cast<String, Object?>(),
        commandId: e.globalId,
      );
      return PushReply(r.replayed ? PushOutcome.duplicate : PushOutcome.accepted);
    } on ApiError catch (err) {
      if (err.kind == ApiErrorKind.unauthorized || err.kind == ApiErrorKind.deviceRevoked) rethrow;
      if (err.kind == ApiErrorKind.unavailable && (err.status ?? 0) >= 500) {
        // NEW-03: "busy" (503: a locked database, a deadlock) is TRANSIENT and
        // says nothing about the entry. It has its own counter and never uses
        // the permanent-failure budget, so a rightful operation is not parked
        // as dead_letter by a few busy minutes at the office.
        if (err.status == 503 || err.code == 'busy') {
          final busy = ((e.payload['busyCount'] as num?)?.toInt() ?? 0) + 1;
          e.payload['busyCount'] = busy;
          e.payload['retryAt'] = _now().add(Backoff.lan.delay(busy)).millisecondsSinceEpoch;
          rethrow;
        }
        // The office answered and failed. Retry a bounded number of times with
        // backoff; then park it so the entries behind it are not held hostage.
        final failures = ((e.payload['serverFailures'] as num?)?.toInt() ?? 0) + 1;
        e.payload['serverFailures'] = failures;
        if (failures >= maxServerFailures) return const PushReply(PushOutcome.rejected, code: 'dead_letter');
        e.payload['retryAt'] = _now().add(Backoff.lan.delay(failures)).millisecondsSinceEpoch;
        rethrow;
      }
      if (err.retryable) rethrow;
      return PushReply(PushOutcome.rejected, code: err.code);
    }
  }

  /// Sends what is pending for the signed-in user. Never throws; returns null
  /// when nothing ran.
  Future<DrainReport?> drain() async {
    // After an app restart the session token is restored but not the user: ask
    // the office who it is before deciding whose entries may go out.
    if (session.info == null && session.loggedIn) {
      try {
        await session.refresh();
      } on Object {
        // Offline or refused: refresh() has already routed a revoked/expired session.
      }
    }
    if (session.client == null || session.info == null) {
      if (session.client != null) await _count();
      return null;
    }
    final report = await store.outbox.drain(send, where: _mine);
    final failure = report.failure;
    if (failure == null) {
      sync.reachable();
      sync.synced(_now());
    } else if (failure is ApiError && failure.kind == ApiErrorKind.deviceRevoked) {
      await session.handleRevoked();
    } else {
      sync.unreachable(login: failure is ApiError && failure.kind == ApiErrorKind.unauthorized);
    }
    await _count();
    return report;
  }

  /// [drain]s, then reports what happened to [ids] specifically.
  Future<SendOutcome> drainFor(List<String> ids) async {
    await drain();
    final byId = {for (final e in await store.store.outbox()) e.globalId: e};
    String? rejected;
    int? at;
    var waiting = false;
    for (var i = 0; i < ids.length; i++) {
      final e = byId[ids[i]];
      if (e == null || e.status == OutboxStatus.pending) {
        waiting = true;
      } else if (e.status == OutboxStatus.rejected && rejected == null) {
        rejected = e.error ?? 'rejected';
        at = i;
      }
    }
    // A dependent entry is rejected only because its parent was: show the
    // parent's reason, which is the real one.
    if (rejected == 'dependency_rejected') {
      for (var i = 0; i < ids.length; i++) {
        final e = byId[ids[i]];
        if (e != null && e.status == OutboxStatus.rejected && e.error != 'dependency_rejected') {
          rejected = e.error;
          at = i;
          break;
        }
      }
    }
    return SendOutcome(accepted: rejected == null && !waiting, rejectedCode: rejected, waiting: waiting, rejectedIndex: at);
  }

  /// Puts a dead-lettered entry (parked after repeated office failures) back in
  /// the queue under the SAME id: the office answers from its command log if it
  /// had in fact applied it, so retrying cannot apply it twice.
  Future<void> retry(OutboxEntry e) async {
    if (e.status != OutboxStatus.rejected || e.error != 'dead_letter') return;
    e
      ..status = OutboxStatus.pending
      ..error = null;
    e.payload
      ..remove('serverFailures')
      ..remove('busyCount')
      ..remove('retryAt');
    await store.store.updateOutbox(e);
    await _count();
  }

  /// Puts a rejected entry's reason in front of the user and lets him drop it.
  /// Dropping is the only way out: a rejected operation is never re-sent.
  Future<void> dismiss(OutboxEntry e) async {
    e
      ..status = OutboxStatus.rejected // history stays honest: it was NEVER accepted by the office
      ..error = 'dismissed';
    await store.store.updateOutbox(e);
    await _count();
  }
}
