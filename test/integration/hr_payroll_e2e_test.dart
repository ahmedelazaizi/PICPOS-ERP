import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

/// E2E Test: HR Payroll Lifecycle
/// Employee → Salary Payment → Overtime → Treasury Integration
void main() {
  late AppDatabase db;
  late int employeeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Create employee
    employeeId = await db.into(db.employees).insert(
      EmployeesCompanion.insert(
        name: 'أحمد محمد',
        phone: const Value('0791234567'),
        salary: const Value(1500.0),
      ),
    );
  });

  tearDown(() async => db.close());

  group('HR Payroll E2E', () {
    test('Salary Payment records correctly', () async {
      // 1. Record salary payment
      final paymentId = await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: 1500.0,
        period: '2026-01',
      );

      expect(paymentId, isPositive);

      // 2. Verify salary record exists
      final salaryRecords = await (db.select(db.salaryPayments)
            ..where((s) => s.employeeId.equals(employeeId)))
          .get();
      expect(salaryRecords.length, 1);
      expect(salaryRecords.first.amount, 1500.0);
    });

    test('Leave request records correctly', () async {
      // 1. Request leave
      final leaveId = await db.into(db.employeeLeaves).insert(
        EmployeeLeavesCompanion.insert(
          employeeId: employeeId,
          leaveType: 'annual',
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 3),
          days: 3,
        ),
      );

      expect(leaveId, isPositive);

      // 2. Verify leave record
      final leaves = await (db.select(db.employeeLeaves)
            ..where((l) => l.employeeId.equals(employeeId)))
          .get();
      expect(leaves.length, 1);
      expect(leaves.first.days, 3);
      expect(leaves.first.leaveType, 'annual');
    });

    test('Overtime records accumulate correctly', () async {
      // 1. Record overtime: 3 hours at 1.5x rate
      await db.into(db.overtimeRecords).insert(
        OvertimeRecordsCompanion.insert(
          employeeId: employeeId,
          date: DateTime(2026, 3, 5),
          hours: 3.0,
          amount: 45.0,
          rate: const Value(1.5),
        ),
      );

      // 2. Record more overtime
      await db.into(db.overtimeRecords).insert(
        OvertimeRecordsCompanion.insert(
          employeeId: employeeId,
          date: DateTime(2026, 3, 6),
          hours: 2.0,
          amount: 30.0,
          rate: const Value(1.5),
        ),
      );

      // 3. Verify total overtime hours
      final records = await (db.select(db.overtimeRecords)
            ..where((o) => o.employeeId.equals(employeeId)))
          .get();
      expect(records.length, 2);
      final totalHours = records.fold<double>(0, (sum, r) => sum + r.hours);
      expect(totalHours, 5.0);
    });
  });
}
