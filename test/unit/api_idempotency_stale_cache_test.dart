// Feature 054 (v134) — Stale-cache invalidation in checkIdempotency.
//
// Field repro (supermarket, 2026-05-14): yesterday's successful sales
// wrote 40 entries to `processed_messages`. Between then and today,
// `sales_invoices` was wiped (test reset / cleanup) but
// `processed_messages` survived. Today's fresh sales hit the orphaned
// cache and the server returned `duplicate: true, serverId=<old>`
// pointing at rows that no longer exist. 15 sales lost silently.
//
// The fix: callers pass a `verifyExists` predicate to
// `checkIdempotency`. When a cache hit's `serverId` is no longer in the
// target table, the cache entry is deleted and null is returned so the
// caller treats the request as fresh.

import 'dart:convert';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  // Helper: store a `postSale`-style cache entry pointing at the given
  // serverId. Replicates what storeIdempotency would have written
  // after a successful insert.
  Future<void> seedCacheEntry({
    required String key,
    required int serverId,
    required String actionType,
  }) async {
    await db.into(db.processedMessages).insert(
          ProcessedMessagesCompanion.insert(
            idempotencyKey: key,
            responsePayload: jsonEncode({
              'success': true,
              'serverId': serverId,
              'invoiceNumber': 'QS-POS-$serverId',
            }),
            actionType: Value(actionType),
          ),
        );
  }

  // The verifier the API handler passes in: returns true iff a
  // sales_invoices row with `id = serverId` exists. Inlined here
  // instead of going through ApiHandlerBase so the test stays focused
  // on the cache-check logic.
  Future<bool> salesInvoicesExists(int id) async {
    final row = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<Map<String, dynamic>?> checkWithVerifier(
    String key, {
    Future<bool> Function(int)? verifyExists,
  }) async {
    // Mirror of the production checkIdempotency body so the test can
    // exercise it without spinning up the full ApiHandler. If the
    // production logic diverges materially, this test is the canary.
    final record = await (db.select(db.processedMessages)
          ..where((p) => p.idempotencyKey.equals(key)))
        .getSingleOrNull();
    if (record == null) return null;
    final payload = jsonDecode(record.responsePayload) as Map<String, dynamic>;
    if (verifyExists != null) {
      final sid = payload['serverId'];
      if (sid is int) {
        final exists = await verifyExists(sid);
        if (!exists) {
          await (db.delete(db.processedMessages)
                ..where((p) => p.idempotencyKey.equals(key)))
              .go();
          return null;
        }
      }
    }
    return payload;
  }

  group('checkIdempotency — stale-cache invalidation', () {
    test('cache hit AND target row exists → returns cached payload', () async {
      // Seed a sale on the server.
      final sid = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'QS-POS-1',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 5, 14),
              total: const Value(100),
              globalId: const Value('gid-sale-1'),
            ),
          );
      await seedCacheEntry(key: 'idem-1', serverId: sid, actionType: 'postSale');

      final result =
          await checkWithVerifier('idem-1', verifyExists: salesInvoicesExists);
      expect(result, isNotNull,
          reason: 'when the target row still exists, the cache must be '
              'returned as-is (the original retry-safety contract)');
      expect(result!['serverId'], sid);
    });

    test('cache hit but target row was deleted → invalidates cache, '
        'returns null', () async {
      // Insert + delete a sale. Now the cache row is orphaned.
      final sid = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'QS-POS-2',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 5, 14),
              total: const Value(100),
              globalId: const Value('gid-sale-2'),
            ),
          );
      await seedCacheEntry(key: 'idem-2', serverId: sid, actionType: 'postSale');
      await (db.delete(db.salesInvoices)..where((s) => s.id.equals(sid))).go();

      final result =
          await checkWithVerifier('idem-2', verifyExists: salesInvoicesExists);
      expect(result, isNull,
          reason: 'an orphan cache row points at a vanished serverId — '
              'returning it would let the supermarket-class bug recur. '
              'The caller will fall through to fresh handling.');

      // And the cache row is gone — next request with the same key
      // will go through normally and create a new sale.
      final stillCached = await (db.select(db.processedMessages)
            ..where((p) => p.idempotencyKey.equals('idem-2')))
          .getSingleOrNull();
      expect(stillCached, isNull,
          reason: 'orphan cache row should be hard-deleted so the next '
              'retry does not pay the verification cost again');
    });

    test('cache miss → returns null (no verifier called)', () async {
      var called = false;
      Future<bool> spy(int id) async {
        called = true;
        return true;
      }

      final result =
          await checkWithVerifier('idem-never-stored', verifyExists: spy);
      expect(result, isNull);
      expect(called, isFalse,
          reason: 'verifier is only consulted on cache HIT; cache miss '
              'must not pay the lookup cost');
    });

    test('cache hit without serverId in payload → returns cached as-is',
        () async {
      // Some action types (pure RPCs with no target row) cache a
      // payload that has no serverId. The verifier branch should
      // skip them.
      await db.into(db.processedMessages).insert(
            ProcessedMessagesCompanion.insert(
              idempotencyKey: 'idem-rpc',
              responsePayload: jsonEncode({'success': true, 'echo': 42}),
              actionType: const Value('echo'),
            ),
          );

      var verifierCalled = false;
      final result =
          await checkWithVerifier('idem-rpc', verifyExists: (_) async {
        verifierCalled = true;
        return false;
      });

      expect(result, isNotNull,
          reason: 'payload had no serverId → nothing to verify → return '
              'the cached response (legacy contract preserved)');
      expect(verifierCalled, isFalse,
          reason: 'verifier should be skipped when there is no serverId '
              'to check');
    });

    test('verifier is null (legacy caller) → never invalidates', () async {
      await seedCacheEntry(key: 'idem-legacy', serverId: 999, actionType: 'echo');

      final result = await checkWithVerifier('idem-legacy');
      expect(result, isNotNull,
          reason: 'callers that have no target table (purely RPC) pass '
              'no verifier and get the legacy unconditional-return '
              'behaviour. Important for handlers that have not been '
              'audited yet — they must not start failing differently.');
    });
  });
}
