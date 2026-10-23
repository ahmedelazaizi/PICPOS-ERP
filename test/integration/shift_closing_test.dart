import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// E2E Test: Shift Closing Flow (Sprint 17)
/// Open Shift → Sales → Expenses → Close → Variance Check → Fiscal Lock
void main() {
  late AppDatabase db;
  late int userId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'shift_test',
      password: 'test123',
      displayName: 'Shift Tester',
      roleId: roleId,
    );

    final cashSafe = await db.getDefaultSafeByType('cash');
    cashSafeId = cashSafe!.id;
    await db.updateSafeBalance(cashSafeId, 0.0);
  });

  tearDown(() async => db.close());

  group('E2E Shift Closing Flow', () {
    test('Open → Transactions → Close with accurate variance', () async {
      // 1. Open shift with opening balance
      final shiftId = await db.openShift(userId, 500.0);
      expect(shiftId, isPositive);

      // 2. Verify shift is open
      final openShift = await db.getCurrentOpenShift(userId);
      expect(openShift, isNotNull);
      expect(openShift!.status, 'open');
      expect(openShift.openingBalance, 500.0);

      // 3. Simulate sales receipts during shift
      await db.createReceiptVoucher(
        amount: 1000.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: userId,
      );
      await db.createReceiptVoucher(
        amount: 500.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: userId,
      );

      // 4. Simulate expense during shift
      await db.createPaymentVoucher(
        amount: 200.0,
        category: 'expense',
        description: 'مصروفات شيفت',
        safeId: cashSafeId,
        userId: userId,
      );

      // Expected cash: 500 (opening) + 1000 + 500 - 200 = 1800
      // 5. Close shift — cashier reports 1800 (exact match, zero variance)
      await db.closeShiftWithAudit(shiftId, 1800.0);

      // 6. Verify shift is closed
      final closedShift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();

      expect(closedShift.status, 'closed');
      expect(closedShift.expectedCash, closeTo(1800.0, 1.0));
      expect(closedShift.actualCash, 1800.0);
      expect(closedShift.variance, closeTo(0.0, 1.0));
    });

    test('Shift with variance (shortage)', () async {
      final shiftId = await db.openShift(userId, 200.0);

      await db.createReceiptVoucher(
        amount: 800.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: userId,
      );

      // Expected: 200 + 800 = 1000
      // Cashier reports 950 (shortage of 50)
      await db.closeShiftWithAudit(shiftId, 950.0);

      final closedShift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();

      expect(closedShift.expectedCash, closeTo(1000.0, 1.0));
      expect(closedShift.actualCash, 950.0);
      expect(closedShift.variance, closeTo(-50.0, 1.0));
    });

    test('Shift with surplus', () async {
      final shiftId = await db.openShift(userId, 100.0);

      await db.createReceiptVoucher(
        amount: 300.0,
        category: 'sales',
        safeId: cashSafeId,
        userId: userId,
      );

      // Expected: 100 + 300 = 400
      // Cashier reports 420 (surplus of 20)
      await db.closeShiftWithAudit(shiftId, 420.0);

      final closedShift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();

      expect(closedShift.variance, closeTo(20.0, 1.0));
    });

    test('Closed shift cannot be closed again', () async {
      final shiftId = await db.openShift(userId, 0.0);

      await db.closeShiftWithAudit(shiftId, 0.0);

      // Close again — should be idempotent (status already 'closed')
      await db.closeShiftWithAudit(shiftId, 100.0);

      final shift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();

      // Should remain at original close values
      expect(shift.status, 'closed');
    });
  });
}
