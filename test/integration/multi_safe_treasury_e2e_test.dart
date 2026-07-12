import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// E2E Test: Multi-Safe Treasury Operations
/// Create Safes → Deposit → Withdraw → Verify Balances → Receipt/Payment Vouchers
void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'أمين صندوق', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'treasury_test',
      password: 'test123',
      displayName: 'Treasury Tester',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  group('Multi-Safe Treasury E2E', () {
    test('Receipt voucher increases safe balance', () async {
      // 1. Get default cash safe
      final cashSafe = await db.getDefaultSafeByType('cash');
      expect(cashSafe, isNotNull);
      final initialBalance = cashSafe!.balance;

      // 2. Create receipt voucher
      final txnId = await db.createReceiptVoucher(
        amount: 500.0,
        category: 'عائد مبيعات',
        safeId: cashSafe.id,
        userId: userId,
        description: 'إيداع نقدي',
      );

      expect(txnId, isPositive);

      // 3. Verify balance increased
      final afterReceipt = await db.getDefaultSafeByType('cash');
      expect(afterReceipt!.balance, initialBalance + 500.0);
    });

    test('Payment voucher decreases safe balance', () async {
      // 1. First deposit money
      final cashSafe = await db.getDefaultSafeByType('cash');
      await db.createReceiptVoucher(
        amount: 1000.0,
        category: 'إيداع',
        safeId: cashSafe!.id,
        userId: userId,
      );

      final balanceAfterDeposit = (await db.getDefaultSafeByType('cash'))!.balance;

      // 2. Create payment voucher
      await db.createPaymentVoucher(
        amount: 300.0,
        category: 'مصروفات تشغيلية',
        safeId: cashSafe.id,
        userId: userId,
        description: 'دفع إيجار',
      );

      // 3. Verify balance decreased
      final afterPayment = await db.getDefaultSafeByType('cash');
      expect(afterPayment!.balance, balanceAfterDeposit - 300.0);
    });

    test('Bank and cash safe balances are independent', () async {
      final cashSafe = await db.getDefaultSafeByType('cash');
      final bankSafe = await db.getDefaultSafeByType('bank');

      expect(cashSafe, isNotNull);
      expect(bankSafe, isNotNull);

      final initialCash = cashSafe!.balance;
      final initialBank = bankSafe!.balance;

      // Deposit to cash only
      await db.createReceiptVoucher(
        amount: 1000.0,
        category: 'نقدي',
        safeId: cashSafe.id,
        userId: userId,
      );

      // Bank should be unchanged
      final afterCashDeposit = await db.getDefaultSafeByType('bank');
      expect(afterCashDeposit!.balance, initialBank);

      // Cash should increase
      final afterCash = await db.getDefaultSafeByType('cash');
      expect(afterCash!.balance, initialCash + 1000.0);
    });

    test('Transaction history is recorded', () async {
      final cashSafe = await db.getDefaultSafeByType('cash');

      // Create multiple transactions
      await db.createReceiptVoucher(
        amount: 200.0,
        category: 'sales',
        safeId: cashSafe!.id,
        userId: userId,
      );

      await db.createReceiptVoucher(
        amount: 350.0,
        category: 'returns',
        safeId: cashSafe.id,
        userId: userId,
      );

      await db.createPaymentVoucher(
        amount: 100.0,
        category: 'expenses',
        safeId: cashSafe.id,
        userId: userId,
      );

      // Verify transaction count
      final txns = await (db.select(db.safeTransactions)
            ..where((t) => t.safeId.equals(cashSafe.id)))
          .get();
      expect(txns.length, greaterThanOrEqualTo(3));
    });
  });
}
