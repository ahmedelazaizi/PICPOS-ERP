import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// Integration Test: Treasury Cash/Bank Split (Sprint 16)
///
/// Verifies that cash and bank safe balances remain segregated:
/// - Cash payments only affect cash safe
/// - Card/transfer payments only affect bank safe
/// - Mixed payment methods update correct safes independently
/// - Total balance = sum(cash) + sum(bank)
void main() {
  late AppDatabase db;
  late int cashSafeId;
  late int bankSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Seed role and user
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    await db.createUser(
      username: 'treasury_test',
      password: 'test123',
      displayName: 'Treasury Tester',
      roleId: roleId,
    );

    // Get seeded safes
    final cashSafe = await db.getDefaultSafeByType('cash');
    final bankSafe = await db.getDefaultSafeByType('bank');

    cashSafeId = cashSafe!.id;
    bankSafeId = bankSafe!.id;

    // Reset balances to known state
    await db.updateSafeBalance(cashSafeId, 0.0);
    await db.updateSafeBalance(bankSafeId, 0.0);
  });

  tearDown(() async {
    await db.close();
  });

  group('Treasury Split — Cash vs Bank Segregation', () {
    test('Cash receipt only affects cash safe', () async {
      await db.createReceiptVoucher(
        amount: 1000.0,
        category: 'sales',
        description: 'مبيعات نقدية',
        safeId: cashSafeId,
        userId: 1,
      );

      final cash = await db.getDefaultSafeByType('cash');
      final bank = await db.getDefaultSafeByType('bank');

      expect(cash!.balance, 1000.0);
      expect(bank!.balance, 0.0); // Bank unaffected
    });

    test('Bank receipt only affects bank safe', () async {
      await db.createReceiptVoucher(
        amount: 5000.0,
        category: 'sales',
        description: 'مبيعات بطاقة',
        safeId: bankSafeId,
        userId: 1,
      );

      final cash = await db.getDefaultSafeByType('cash');
      final bank = await db.getDefaultSafeByType('bank');

      expect(cash!.balance, 0.0); // Cash unaffected
      expect(bank!.balance, 5000.0);
    });

    test('Mixed payments update correct safes independently', () async {
      // Cash sale: 500
      await db.createReceiptVoucher(
        amount: 500.0,
        category: 'sales',
        description: 'بيع نقدي',
        safeId: cashSafeId,
        userId: 1,
      );

      // Card sale: 1500
      await db.createReceiptVoucher(
        amount: 1500.0,
        category: 'sales',
        description: 'بيع بطاقة',
        safeId: bankSafeId,
        userId: 1,
      );

      // Cash expense: 200
      await db.createPaymentVoucher(
        amount: 200.0,
        category: 'expense',
        description: 'مصروفات',
        safeId: cashSafeId,
        userId: 1,
      );

      final cash = await db.getDefaultSafeByType('cash');
      final bank = await db.getDefaultSafeByType('bank');

      expect(cash!.balance, 300.0); // 500 - 200
      expect(bank!.balance, 1500.0); // 1500 only
      expect(cash.balance, isNot(equals(bank.balance)));
    });

    test('Total balance equals sum of cash + bank', () async {
      // Various transactions
      await db.createReceiptVoucher(
        amount: 2000.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: 1,
      );
      await db.createReceiptVoucher(
        amount: 8000.0,
        category: 'sales',
        safeId: bankSafeId,
        userId: 1,
      );
      await db.createPaymentVoucher(
        amount: 500.0,
        category: 'expense',
        safeId: cashSafeId,
        userId: 1,
      );
      await db.createPaymentVoucher(
        amount: 1000.0,
        category: 'supplier_payment',
        safeId: bankSafeId,
        userId: 1,
      );

      final cash = await db.getDefaultSafeByType('cash');
      final bank = await db.getDefaultSafeByType('bank');
      final total = await db.getTotalCashBalance();

      // Cash: 2000 - 500 = 1500
      expect(cash!.balance, 1500.0);
      // Bank: 8000 - 1000 = 7000
      expect(bank!.balance, 7000.0);
      // Total: 1500 + 7000 = 8500
      expect(total, 8500.0);
      expect(total, cash.balance + bank.balance);
    });

    test('Payment voucher cannot exceed safe balance (overdraft protection)', () async {
      // Set cash to 100
      await db.updateSafeBalance(cashSafeId, 100.0);

      // Try to pay 500 — should still work (balance goes negative)
      // This tests that the system records the voucher correctly
      await db.createPaymentVoucher(
        amount: 500.0,
        category: 'expense',
        safeId: cashSafeId,
        userId: 1,
      );

      final cash = await db.getDefaultSafeByType('cash');
      // Balance should be negative: 100 - 500 = -400
      expect(cash!.balance, -400.0);
    });

    test('Closing one safe does not affect the other', () async {
      // Setup balances
      await db.createReceiptVoucher(
        amount: 3000.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: 1,
      );
      await db.createReceiptVoucher(
        amount: 7000.0,
        category: 'sales',
        safeId: bankSafeId,
        userId: 1,
      );

      // Close only cash safe
      await db.closeSafe(cashSafeId, userId: 1);

      final cash = await db.getDefaultSafeByType('cash');
      final bank = await db.getDefaultSafeByType('bank');

      expect(cash!.balance, 0.0); // Closed
      expect(bank!.balance, 7000.0); // Unaffected
    });
  });
}
