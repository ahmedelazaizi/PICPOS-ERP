// ═══════════════════════════════════════════════════════════════════════════
// The product cache must never outlive the truth it was read from.
// ═══════════════════════════════════════════════════════════════════════════
//
// `getProductById` / `getProductsByIds` memoise rows in `_productByIdCache`
// (product_crud_dao.dart) — a PROCESS-GLOBAL map, not an instance field, so it
// is shared by every AppDatabase in the process. Nothing about it is
// transaction-aware, which breaks the cache in two independent directions:
//
//  ROLLBACK — a read taken inside a transaction captures uncommitted state.
//    The transaction rolls back in the database; the cache keeps the value
//    that never existed, and every later read returns it. This is not a
//    display glitch: `updateProductWAC` (inventory_dao) reads currentStock and
//    costPrice THROUGH the cache, computes the weighted average from them, and
//    WRITES the result to disk — so a poisoned read becomes a stored, wrong
//    WAC, and every subsequent sale books COGS against it.
//
//  COMMIT — `updateProductStock` (product_crud_dao ~644) writes stock and does
//    NOT invalidate. Its own neighbour `adjustProductStockGlobal` does, with a
//    comment saying why, so this is an oversight rather than a design. It is
//    reached from `reconciliation_service` (the repair tool's own fix becomes
//    invisible) and from `inventory_balance_sync_strategy` (every client
//    balance sync — silently undoing the documented "zero stock in POS" fix).
//
// Field evidence for the rollback direction already exists but was found by
// accident: `landed_lifecycle_b8` PRET-1a asserts a failed purchase return
// rolls back completely, and read stock back as 5 instead of 10. Four tests
// written specifically for that bug all missed it, because they exercised
// SUCCESSFUL paths. There is no guard for this class today — this file is it.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    // The cache is process-global — clear it so a previous test's rows cannot
    // make this one pass or fail for the wrong reason.
    db.invalidateProductCache();

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'CACHE-TX-1',
        name: 'منتج',
        trackInventory: const Value(true),
        currentStock: const Value(10),
        costPrice: const Value(100),
      ),
    );
  });

  tearDown(() async {
    db.invalidateProductCache();
    await db.close();
  });

  Future<double> stockViaCache() async =>
      (await db.getProductById(productId))!.currentStock;

  Future<double> stockOnDisk() async {
    final row = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    return row.currentStock;
  }

  group('rollback — uncommitted state must not survive in the cache', () {
    test('a read taken inside a failed transaction is not served afterwards',
        () async {
      expect(await stockViaCache(), 10.0, reason: 'sanity');

      await expectLater(
        db.transaction(() async {
          await db.updateProductStock(productId, 5);
          // Force this read to reach the database. Without it the read is
          // served from the entry the sanity check left behind and the test
          // passes vacuously — it did, on the first draft: nothing was
          // poisoned because nothing was re-read. Being explicit also keeps
          // the test measuring cache-vs-rollback rather than whatever
          // updateProductStock happens to do about invalidation.
          db.invalidateProductCache(productId);
          // The poisoning read: legitimate application code does this all the
          // time (adjustStock, updateProductWAC, the purchase-invoice loop).
          await db.getProductById(productId);
          throw StateError('forced rollback');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await stockOnDisk(), 10.0,
          reason: 'sanity: the database itself rolled back correctly');
      expect(await stockViaCache(), 10.0,
          reason: 'the cache served 5 — a quantity that was never committed. '
              'updateProductWAC computes the weighted average from exactly '
              'this read and writes it to disk, so the wrong number stops '
              'being a cache artefact and becomes stored cost');
    });

    test('getProductsByIds does not poison the cache either', () async {
      // Same defect through the batch reader — it writes into the same map,
      // and the purchase-invoice loop uses it for every line at once.
      expect(await stockViaCache(), 10.0, reason: 'sanity');

      await expectLater(
        db.transaction(() async {
          await db.updateProductStock(productId, 7);
          await db.getProductsByIds([productId]);
          throw StateError('forced rollback');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await stockViaCache(), 10.0,
          reason: 'one poisoned batch read taints every line of the invoice '
              'that triggered it');
    });

    test('a COMMITTED transaction still shows its new value', () async {
      // Guard against "fix" by over-invalidating in a way that breaks reads,
      // and against a bypass that forgets to return fresh data.
      await db.transaction(() async {
        await db.updateProductStock(productId, 42);
      });

      expect(await stockOnDisk(), 42.0);
      expect(await stockViaCache(), 42.0,
          reason: 'a committed change must be visible to cached readers');
    });
  });

  group('commit — updateProductStock must invalidate', () {
    test('a cached reader sees a committed updateProductStock', () async {
      expect(await stockViaCache(), 10.0, reason: 'primes the cache');

      // No transaction here: this is the reconciliation / balance-sync shape.
      await db.updateProductStock(productId, 33);

      expect(await stockOnDisk(), 33.0);
      expect(await stockViaCache(), 33.0,
          reason: 'without invalidation the repair tool and every client '
              'balance sync write the right number to disk while all readers '
              'keep seeing the old one — which is the signature of the '
              '"wrong numbers that fix themselves after a restart" reports');
    });
  });
}
