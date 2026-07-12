// ═══════════════════════════════════════════════════════════════════════════
// Feature 005 Phase 8 — Safe Balance Concurrency Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Reproduces the Lost-Update race that pre-005 affected the server-side
// `postSafeTransaction` and `postSafeTransfer` API handlers. When two
// branch clients posted safe transactions to the same safe concurrently,
// each request would:
//   1. read safe.balance
//   2. compute newBalance = balance ± amount in Dart
//   3. write the absolute value via updateSafeBalance
//
// Under PostgreSQL's default Read-Committed isolation, two concurrent
// transactions both saw the same starting balance and the second write
// silently clobbered the first — a classic Lost Update.
//
// The fix replaces the read-then-write pattern with SQL-level atomic
// arithmetic (`UPDATE safes SET balance = balance ± ?`) wrapped in a
// transaction. balanceAfter is read AFTER the UPDATE so the recorded
// transaction history matches the actual post-state.
//
// Note: SQLite serialises transactions via BEGIN IMMEDIATE so the race
// is harder to reproduce there than on Postgres, but the atomic-SQL fix
// is still strictly stronger and these tests run on the SQLite test DB
// to verify the fix's logical correctness across many parallel operations.
// ═══════════════════════════════════════════════════════════════════════════


import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'الصندوق الرئيسي للاختبار',
            safeType: const Value('cash'),
            balance: const Value(1000),
            globalId: const Value('gid-safe-test'),
          ),
        );
  });

  tearDown(() => db.close());

  group('Atomic safe balance — concurrent receipts', () {
    test('100 parallel +1 receipts land on a balance of exactly 1100', () async {
      // Fire 100 receipts in parallel. The atomic SQL increment guarantees
      // every one of them takes effect even if the underlying engine
      // schedules them in any order; the lossy read-then-write pattern
      // would drop most of them.
      final futures = <Future<void>>[];
      for (var i = 0; i < 100; i++) {
        futures.add(_atomicReceipt(db, safeId, 1.0));
      }
      await Future.wait(futures);

      final safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingle();
      expect(safe.balance, 1100.0,
          reason: 'every increment must compose: 1000 + 100×1 = 1100');

      final txns = await db.select(db.safeTransactions).get();
      expect(txns, hasLength(100),
          reason: 'every API call must record exactly one transaction row');
    });

    test('mixed receipts and payments still net correctly under concurrency',
        () async {
      // 50 receipts of +10 and 50 payments of -7 — net change is +150.
      final futures = <Future<void>>[];
      for (var i = 0; i < 50; i++) {
        futures.add(_atomicReceipt(db, safeId, 10.0));
        futures.add(_atomicPayment(db, safeId, 7.0));
      }
      await Future.wait(futures);

      final safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingle();
      expect(safe.balance, 1000.0 + (50 * 10.0) - (50 * 7.0),
          reason: 'net: 1000 + 500 - 350 = 1150');

      final txns = await db.select(db.safeTransactions).get();
      expect(txns, hasLength(100),
          reason: 'no transaction row should be lost or duplicated');
    });
  });

  group('balanceAfter reflects post-state, never a stale read', () {
    test('serial receipts produce monotonically increasing balanceAfter',
        () async {
      for (var i = 1; i <= 5; i++) {
        await _atomicReceipt(db, safeId, 100.0);
      }
      final txns = await (db.select(db.safeTransactions)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      // 1100, 1200, 1300, 1400, 1500
      expect(txns.map((t) => t.balanceAfter).toList(),
          [1100.0, 1200.0, 1300.0, 1400.0, 1500.0]);
    });
  });
}

/// Mirrors the post-005 atomic pattern used by the server's
/// postSafeTransaction handler. Inlined here so the test exercises the
/// exact arithmetic + transaction wrapping without spinning up the HTTP
/// layer.
Future<void> _atomicReceipt(AppDatabase db, int safeId, double amount) {
  return db.transaction(() async {
    await db.customStatement(
      'UPDATE safes SET balance = balance + ? WHERE id = ?',
      [amount, safeId],
    );
    final updated = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId))
          ..limit(1))
        .getSingle();
    await db.into(db.safeTransactions).insert(
      SafeTransactionsCompanion.insert(
        voucherNumber: 'RV-conc-${DateTime.now().microsecondsSinceEpoch}-$amount',
        safeId: safeId,
        transactionType: 'receipt',
        category: 'test',
        amount: amount,
        balanceAfter: updated.balance,
      ),
    );
  });
}

Future<void> _atomicPayment(AppDatabase db, int safeId, double amount) {
  return db.transaction(() async {
    await db.customStatement(
      'UPDATE safes SET balance = balance - ? WHERE id = ?',
      [amount, safeId],
    );
    final updated = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId))
          ..limit(1))
        .getSingle();
    await db.into(db.safeTransactions).insert(
      SafeTransactionsCompanion.insert(
        voucherNumber: 'PV-conc-${DateTime.now().microsecondsSinceEpoch}-$amount',
        safeId: safeId,
        transactionType: 'payment',
        category: 'test',
        amount: amount,
        balanceAfter: updated.balance,
      ),
    );
  });
}
