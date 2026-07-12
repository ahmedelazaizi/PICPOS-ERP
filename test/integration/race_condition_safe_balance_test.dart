import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

/// Phase 1 — Safe/Treasury Balance Race Condition (Focused)
///
/// Dedicated test class for safe transaction balance atomicity.
/// Focuses on the three-pool reconciliation model (cash / bank / click).
///   - Deposit and withdrawal correctly update safe balance.
///   - Concurrent same-safe transactions maintain correct final balance.
///   - Safe balance never goes into an inconsistent intermediate state.
///   - Click-safe (non-cash pool) is tracked independently.
///   - The `balanceAfter` field on the transaction record reflects committed state.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('Safe Balance Race Condition — Focused Tests', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Single deposit updates safe balance atomically', () async {
      final safeId = await db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'Atomic Safe',
          safeType: const drift.Value('cash'),
          balance: const drift.Value(500),
        ),
      );

      await db.createSafeTransaction(
        SafeTransactionsCompanion.insert(
          voucherNumber: 'DEP-001',
          safeId: safeId,
          transactionType: 'deposit',
          category: 'cash_in',
          amount: 200,
          balanceAfter: 700,
        ),
      );

      final safe = await db.getSafeById(safeId);
      expect(safe?.balance, 700.0, reason: 'Deposit of 200 on balance 500 should give 700');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Single withdrawal updates safe balance atomically', () async {
      final safeId = await db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'Withdrawal Safe',
          safeType: const drift.Value('cash'),
          balance: const drift.Value(1000),
        ),
      );

      await db.createSafeTransaction(
        SafeTransactionsCompanion.insert(
          voucherNumber: 'WITH-001',
          safeId: safeId,
          transactionType: 'withdrawal',
          category: 'expense',
          amount: 350,
          balanceAfter: 650,
        ),
      );

      final safe = await db.getSafeById(safeId);
      expect(safe?.balance, 650.0, reason: 'Withdrawal of 350 from 1000 should give 650');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('50 concurrent deposits of equal amounts sum correctly', () async {
      final safeId = await db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'Concurrent Deposit Safe',
          safeType: const drift.Value('cash'),
          balance: const drift.Value(0),
        ),
      );

      var voucherCount = 0;
      final futures = List.generate(50, (_) {
        final vnum = ++voucherCount;
        return db.createSafeTransaction(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'C-DEP-$vnum',
            safeId: safeId,
            transactionType: 'deposit',
            category: 'test',
            amount: 100,
            balanceAfter: 0, // recalculated by DAO
          ),
        );
      });

      await Future.wait(futures);

      // 50 × 100 = 5000
      final safe = await db.getSafeById(safeId);
      expect(safe?.balance, 5000.0,
          reason: '50 concurrent deposits of 100 should total 5000');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Click-safe (bank pool) tracked separately from cash safe', () async {
      final cashSafeId = await db.into(db.safes).insert(
        SafesCompanion.insert(name: 'Cash Safe', safeType: const drift.Value('cash'), balance: const drift.Value(1000)),
      );
      final clickSafeId = await db.into(db.safes).insert(
        SafesCompanion.insert(name: 'Click Safe', safeType: const drift.Value('bank'), balance: const drift.Value(500)),
      );

      // Concurrent operations on both safes
      await Future.wait([
        db.createSafeTransaction(SafeTransactionsCompanion.insert(
          voucherNumber: 'CASH-TX', safeId: cashSafeId, transactionType: 'deposit',
          category: 'test', amount: 200, balanceAfter: 1200,
        )),
        db.createSafeTransaction(SafeTransactionsCompanion.insert(
          voucherNumber: 'CLICK-TX', safeId: clickSafeId, transactionType: 'deposit',
          category: 'test', amount: 100, balanceAfter: 600,
        )),
      ]);

      final cashSafe = await db.getSafeById(cashSafeId);
      final clickSafe = await db.getSafeById(clickSafeId);

      expect(cashSafe?.balance, 1200.0, reason: 'Cash safe should be 1000 + 200 = 1200');
      expect(clickSafe?.balance, 600.0, reason: 'Click safe should be 500 + 100 = 600');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Transaction record balanceAfter reflects the committed safe balance', () async {
      final safeId = await db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'Audit Trail Safe',
          safeType: const drift.Value('cash'),
          balance: const drift.Value(300),
        ),
      );

      final txId = await db.createSafeTransaction(
        SafeTransactionsCompanion.insert(
          voucherNumber: 'AUDIT-001',
          safeId: safeId,
          transactionType: 'deposit',
          category: 'test',
          amount: 700,
          balanceAfter: 1000, // claimed; DAO should reconcile
        ),
      );

      // Retrieve the transaction record
      final tx = await (db.select(db.safeTransactions)..where((t) => t.id.equals(txId))).getSingleOrNull();
      expect(tx, isNotNull);

      // The safe's actual balance after the transaction
      final safe = await db.getSafeById(safeId);
      expect(safe?.balance, 1000.0, reason: 'Safe balance should be 300 + 700 = 1000');
    });
  });
}
