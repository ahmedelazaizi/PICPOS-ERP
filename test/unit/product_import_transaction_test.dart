// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-11 — Excel import batches writes in ONE transaction
// ═══════════════════════════════════════════════════════════════════════════
//
// The bulk import inserted products row-by-row, so the `products` Drift stream
// (watchAllProducts → allProductsProvider) re-emitted on EVERY insert. Each
// emit re-mapped the growing list → O(N²) → "Not Responding". Wrapping the
// inserts in a single transaction makes Drift emit ONCE on commit.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';

void main() {
  late AppDatabase db;
  late DriftProductRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftProductRepository(db);
  });

  tearDown(() => db.close());

  test('runInWriteTransaction inserts atomically and emits the stream ONCE',
      () async {
    // Subscribe to the products stream and count emissions.
    var emits = 0;
    final sub = db.watchAllProducts().listen((_) => emits++);
    // Drain the initial (empty) emission deterministically. forTesting() uses
    // NativeDatabase.memory() (same isolate), so pumpEventQueue() settles every
    // pending Drift emission on the event loop — no flaky wall-clock delay.
    await pumpEventQueue();
    final baseline = emits;

    await repo.runInWriteTransaction(() async {
      for (var i = 0; i < 30; i++) {
        await repo.insertProduct(
          ProductsCompanion.insert(name: 'P$i', code: 'C$i'),
        );
      }
    });

    // Settle the single post-commit emission deterministically.
    await pumpEventQueue();
    await sub.cancel();

    // All 30 persisted.
    final all = await db.watchAllProducts().first;
    expect(all.where((p) => p.code.startsWith('C')).length, 30);

    // Exactly ONE emission for the whole batch (not 30).
    expect(emits - baseline, 1,
        reason: 'a 30-row import must emit the products stream once, not 30×');
  });

  test('a throw inside runInWriteTransaction rolls back the whole batch',
      () async {
    await expectLater(
      repo.runInWriteTransaction(() async {
        await repo.insertProduct(
          ProductsCompanion.insert(name: 'Keep?', code: 'K1'),
        );
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    final all = await db.watchAllProducts().first;
    expect(all.where((p) => p.code == 'K1'), isEmpty,
        reason: 'transaction rollback must drop the partial insert');
  });
}
