/// Outbox primitives (ARCHITECTURE-M ADR-M5 "Offline queue"; same
/// semantics as the rep app, ARCHITECTURE-I §5): documents are pushed one by
/// one in creation order with `X-Idempotency-Key = globalId`; `accepted` and
/// `duplicate` both finish an entry; `rejected` parks it in «تحتاج مراجعة»;
/// a transport failure stops the drain (order is preserved) and the same
/// entry is retried later with the same key.
library;

import 'dart:math';

import '../store/local_store.dart';

enum PushOutcome { accepted, duplicate, rejected }

class PushReply {
  const PushReply(this.outcome, {this.code});
  final PushOutcome outcome;

  /// Rejection code (`totals_mismatch`, `stock_negative`…).
  final String? code;
}

/// Sends one entry; throws on transport failure (no answer).
typedef OutboxSender = Future<PushReply> Function(OutboxEntry entry);

class DrainReport {
  const DrainReport({this.accepted = 0, this.rejected = 0, this.failure});
  final int accepted;
  final int rejected;

  /// The transport error that stopped the drain, if any.
  final Object? failure;
  bool get complete => failure == null;
}

class Outbox {
  Outbox(this.store, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final LocalStore store;
  final DateTime Function() _now;

  bool _draining = false;

  /// Queues a document. Calling it again with the same [globalId] (double
  /// tap, retry after a crash) does not create a second entry; returns
  /// whether a new entry was added.
  Future<bool> enqueue({required String globalId, required String kind, required Map<String, Object?> payload}) =>
      store.addOutbox(OutboxEntry(globalId: globalId, kind: kind, payload: payload, createdAt: _now()));

  Future<List<OutboxEntry>> pending() async =>
      [for (final e in await store.outbox()) if (e.status == OutboxStatus.pending) e];

  /// «تحتاج مراجعة»: rejected documents waiting for a manager decision.
  Future<List<OutboxEntry>> needsAttention() async =>
      [for (final e in await store.outbox()) if (e.status == OutboxStatus.rejected) e];

  /// Close-shift gate: nothing pending and nothing unresolved.
  Future<bool> isDrained() async => (await store.outbox()).every((e) => e.status == OutboxStatus.accepted);

  /// Pushes pending entries in order. Concurrent calls are ignored (the
  /// second returns an empty report) so one entry is never in flight twice.
  Future<DrainReport> drain(OutboxSender send) async {
    if (_draining) return const DrainReport();
    _draining = true;
    var accepted = 0, rejected = 0;
    try {
      for (final e in await pending()) {
        e.attempts++;
        PushReply reply;
        try {
          reply = await send(e);
        } catch (err) {
          e.error = 'transport';
          await store.updateOutbox(e);
          return DrainReport(accepted: accepted, rejected: rejected, failure: err);
        }
        if (reply.outcome == PushOutcome.rejected) {
          e
            ..status = OutboxStatus.rejected
            ..error = reply.code ?? 'rejected';
          rejected++;
        } else {
          e
            ..status = OutboxStatus.accepted
            ..error = null;
          accepted++;
        }
        await store.updateOutbox(e);
      }
      return DrainReport(accepted: accepted, rejected: rejected);
    } finally {
      _draining = false;
    }
  }
}

/// Exponential backoff with ±[jitter] (copied from
/// mobile/lib/sync/sync_scheduler.dart). M-B on the LAN uses a 5 min cap.
class Backoff {
  const Backoff({
    this.base = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 15),
    this.factor = 3,
    this.jitter = 0.2,
  });

  /// ADR-M5: 5 s → 5 min cap on the shop LAN.
  static const lan = Backoff(cap: Duration(minutes: 5));

  final Duration base, cap;
  final double factor, jitter;

  /// Delay after [failures] consecutive failures (≥ 1). [rnd] in [0, 1).
  Duration delay(int failures, [double rnd = 0.5]) {
    final raw = base.inMilliseconds * pow(factor, max(0, failures - 1));
    final capped = min(raw.toDouble(), cap.inMilliseconds.toDouble());
    final j = 1 + jitter * (2 * rnd - 1);
    return Duration(milliseconds: min(capped * j, cap.inMilliseconds.toDouble()).round());
  }
}
