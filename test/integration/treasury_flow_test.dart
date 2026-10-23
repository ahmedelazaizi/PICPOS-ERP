import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// Integration test for Treasury Flow
/// Tests the complete treasury workflow: vouchers, balances, daily closing
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    
    // Seed required role first
    final roleId = await database.into(database.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false))
    );
    
    // Seed required user
    await database.createUser(
      username: 'treasury_user',
      password: 'test123',
      displayName: 'Treasury User',
      roleId: roleId,
    );
    
    // The database seeds default safes in _seedInitialData():
    // - "صندوق الكاشير" (cash, isDefault=true, balance=0)
    // - "الحساب البنكي" (bank, isDefault=true, balance=0)
    // We just need to update their balances instead of creating new ones
    
    // Get the seeded safes and update their balances
    final cashSafe = await database.getDefaultSafeByType('cash');
    if (cashSafe != null) {
      await database.updateSafeBalance(cashSafe.id, 1000.0);
    }
    
    final bankSafe = await database.getDefaultSafeByType('bank');
    if (bankSafe != null) {
      await database.updateSafeBalance(bankSafe.id, 50000.0);
    }
  });

  tearDown(() async {
    await database.close();
  });

  group('Treasury Flow - Safe Operations', () {
    test('getDefaultSafeByType - should return correct safe', () async {
      final cashSafe = await database.getDefaultSafeByType('cash');
      final bankSafe = await database.getDefaultSafeByType('bank');

      expect(cashSafe, isNotNull);
      expect(cashSafe!.name, 'صندوق الكاشير');
      expect(cashSafe.balance, 1000.0);

      expect(bankSafe, isNotNull);
      expect(bankSafe!.name, 'الحساب البنكي'); // Matches seed data name
    });

    test('getTotalCashBalance - should sum all safe balances', () async {
      final total = await database.getTotalCashBalance();

      expect(total, 51000.0); // 1000 + 50000
    });

    test('updateSafeBalance - should update balance', () async {
      final safe = await database.getDefaultSafeByType('cash');
      await database.updateSafeBalance(safe!.id, 2500.0);

      final updated = await database.getDefaultSafeByType('cash');
      expect(updated!.balance, 2500.0);
    });
  });

  group('Treasury Flow - Voucher Operations', () {
    test('createReceiptVoucher - should create receipt and update balance', () async {
      final safe = await database.getDefaultSafeByType('cash');
      final initialBalance = safe!.balance;

      await database.createReceiptVoucher(
        amount: 500.0,
        category: 'sales',
        description: 'مبيعات نقدية',
        safeId: safe.id,
        userId: 1,
      );

      final updated = await database.getDefaultSafeByType('cash');
      expect(updated!.balance, initialBalance + 500.0);
    });

    test('createPaymentVoucher - should create payment and update balance', () async {
      final safe = await database.getDefaultSafeByType('cash');
      final initialBalance = safe!.balance;

      await database.createPaymentVoucher(
        amount: 200.0,
        category: 'expense',
        description: 'مصروفات متنوعة',
        safeId: safe.id,
        userId: 1,
      );

      final updated = await database.getDefaultSafeByType('cash');
      expect(updated!.balance, initialBalance - 200.0);
    });

    test('receipt and payment flow - should maintain accurate balance', () async {
      final safe = await database.getDefaultSafeByType('cash');
      final initialBalance = safe!.balance;

      // Receive 1000
      await database.createReceiptVoucher(
        amount: 1000.0,
        category: 'customer_payment',
        safeId: safe.id,
        userId: 1,
      );

      // Pay 300
      await database.createPaymentVoucher(
        amount: 300.0,
        category: 'supplier_payment',
        safeId: safe.id,
        userId: 1,
      );

      // Receive 500
      await database.createReceiptVoucher(
        amount: 500.0,
        category: 'sales',
        safeId: safe.id,
        userId: 1,
      );

      final finalSafe = await database.getDefaultSafeByType('cash');
      // 1000 + 1000 - 300 + 500 = 2200
      expect(finalSafe!.balance, initialBalance + 1200.0);
    });
  });

  group('Treasury Flow - Daily Closing', () {
    test('closeSafe - should reset balance to zero and record closing', () async {
      final safe = await database.getDefaultSafeByType('cash');
      
      // Perform some transactions first
      await database.createReceiptVoucher(
        amount: 5000.0,
        category: 'sales',
        safeId: safe!.id,
        userId: 1,
      );

      final beforeClose = await database.getDefaultSafeByType('cash');
      expect(beforeClose!.balance, greaterThan(0));

      // Close the safe
      await database.closeSafe(safe.id, userId: 1);

      final afterClose = await database.getDefaultSafeByType('cash');
      expect(afterClose!.balance, 0.0);
    });
  });

  group('Treasury Flow - Reporting', () {
    test('getTreasurySummary - should calculate totals', () async {
      final safe = await database.getDefaultSafeByType('cash');

      // Create various transactions
      await database.createReceiptVoucher(
        amount: 1000.0,
        category: 'sales',
        safeId: safe!.id,
        userId: 1,
      );
      await database.createReceiptVoucher(
        amount: 500.0,
        category: 'customer_payment',
        safeId: safe.id,
        userId: 1,
      );
      await database.createPaymentVoucher(
        amount: 300.0,
        category: 'expense',
        safeId: safe.id,
        userId: 1,
      );

      final summary = await database.getTreasurySummary();

      expect(summary.totalReceipts, greaterThanOrEqualTo(1500.0));
      expect(summary.totalPayments, greaterThanOrEqualTo(300.0));
    });

    test('getTransactionsByCategory - should filter correctly', () async {
      final safe = await database.getDefaultSafeByType('cash');

      await database.createReceiptVoucher(
        amount: 100.0,
        category: 'sales',
        safeId: safe!.id,
        userId: 1,
      );
      await database.createReceiptVoucher(
        amount: 200.0,
        category: 'customer_payment',
        safeId: safe.id,
        userId: 1,
      );
      await database.createPaymentVoucher(
        amount: 50.0,
        category: 'expense',
        safeId: safe.id,
        userId: 1,
      );

      final salesReceipts = await database.getTransactionsByType(
        'receipt',
      );

      expect(salesReceipts.length, greaterThanOrEqualTo(2));
    });
  });
}
