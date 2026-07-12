// Spec 069 / SC-001 — adjustSafeBalance atomic SQL arithmetic test.
//
// QA D5-003 (P1): the read-then-write pattern
//   final newBalance = safe.balance + amount;
//   await updateSafeBalance(safe.id, newBalance);
// loses one of two concurrent updates under PostgreSQL Read-Committed.
// The replacement helper adjustSafeBalance issues
//   UPDATE safes SET balance = balance + ? WHERE id = ?
// which is atomic on both SQLite and PostgreSQL.
//
// This test simulates two concurrent +100 calls against the same safe
// and asserts the final balance reflects BOTH adjustments (200 net,
// not 100 with one lost).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Safes balance atomic arithmetic (Spec 069 / D5-003)', () {
    late AppDatabase db;
    late int safeId;

    setUp(() async {
      db = AppDatabase.forTesting();
      // Insert a safe with a known starting balance.
      safeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'Test Cash',
              safeType: const Value('cash'),
              balance: const Value(1000.0),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    Future<double> readBalance() async {
      final s = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingle();
      return s.balance;
    }

    test('single adjustSafeBalance(+100) lands as +100', () async {
      await db.adjustSafeBalance(safeId, 100.0);
      expect(await readBalance(), equals(1100.0));
    });

    test('single adjustSafeBalance(-50) lands as -50', () async {
      await db.adjustSafeBalance(safeId, -50.0);
      expect(await readBalance(), equals(950.0));
    });

    test('two CONCURRENT adjustSafeBalance(+100) calls both apply (no lost update)',
        () async {
      // Kick off both at once. Even on SQLite (where this is implicitly
      // serialized) the test pins the contract; on PG this is the
      // critical case.
      await Future.wait([
        db.adjustSafeBalance(safeId, 100.0),
        db.adjustSafeBalance(safeId, 100.0),
      ]);
      expect(await readBalance(), equals(1200.0),
          reason: 'D5-003: two concurrent +100 must land as +200; '
              'a result of +100 means one update was silently lost.');
    });

    test('many sequential adjustments compose correctly', () async {
      for (var i = 0; i < 10; i++) {
        await db.adjustSafeBalance(safeId, 10.0);
      }
      expect(await readBalance(), equals(1100.0));
    });

    test('updateSafeBalance still works for absolute-value reconciliation',
        () async {
      // The legacy setter is preserved for reconciliation paths.
      await db.updateSafeBalance(safeId, 500.0);
      expect(await readBalance(), equals(500.0));
    });
  });
}
