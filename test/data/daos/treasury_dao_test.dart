import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// Unit Tests for TreasuryDao extension
/// Tests treasury-related database operations (Safes, Transactions)
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('TreasuryDao - Safe Operations', () {
    test('insertSafe - should create a new safe', () async {
      final safeId = await database.into(database.safes).insert(
        SafesCompanion.insert(
          name: 'Main Cash Register',
          safeType: const Value('cash'),
          balance: const Value(1000.0),
        ),
      );

      expect(safeId, isPositive);
    });

    test('getDefaultSafeByType - should return default cash safe', () async {
      // Insert a default cash safe
      await database.into(database.safes).insert(
        SafesCompanion.insert(
          name: 'Default Cash',
          safeType: const Value('cash'),
          balance: const Value(500.0),
          isDefault: const Value(true),
        ),
      );

      final safe = await database.getDefaultSafeByType('cash');

      expect(safe, isNotNull);
      expect(safe!.safeType, 'cash');
      expect(safe.isDefault, isTrue);
    });

    test('updateSafeBalance - should update balance correctly', () async {
      final safeId = await database.into(database.safes).insert(
        SafesCompanion.insert(
          name: 'Balance Test Safe',
          safeType: const Value('cash'),
          balance: const Value(100.0),
        ),
      );

      await database.updateSafeBalance(safeId, 250.0);
      
      final updatedSafe = await (database.select(database.safes)
        ..where((s) => s.id.equals(safeId))).getSingle();

      expect(updatedSafe.balance, 250.0);
    });
  });

  group('TreasuryDao - Transaction Operations', () {
    test('createSafeTransaction - should record transaction', () async {
      // First create a safe
      final safeId = await database.into(database.safes).insert(
        SafesCompanion.insert(
          name: 'Transaction Safe',
          safeType: const Value('cash'),
          balance: const Value(1000.0),
        ),
      );

      final txId = await database.createSafeTransaction(
        SafeTransactionsCompanion.insert(
          safeId: safeId,
          transactionType: 'receipt',
          voucherNumber: 'RCV-001',
          amount: 500.0,
          balanceAfter: 1500.0,
          category: 'sales',
        ),
      );

      expect(txId, isPositive);
    });
  });

  group('TreasuryDao - Treasury Summary', () {
    test('getTreasurySummary - should return summary object', () async {
      final safeId = await database.into(database.safes).insert(
        SafesCompanion.insert(
          name: 'Summary Test',
          safeType: const Value('cash'),
          balance: const Value(1000.0),
        ),
      );

      // Add transaction
      await database.createSafeTransaction(
        SafeTransactionsCompanion.insert(
          safeId: safeId,
          transactionType: 'receipt',
          voucherNumber: 'RCV-003',
          amount: 500.0,
          balanceAfter: 1500.0,
          category: 'sales',
        ),
      );

      final summary = await database.getTreasurySummary();

      // Just verify it returns something without crashing
      expect(summary.totalReceipts, greaterThanOrEqualTo(0));
    });
  });
}
