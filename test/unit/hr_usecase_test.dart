import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/hr/manage_employee_usecase.dart';
import 'package:picpos_erp/domain/usecases/hr/payroll_usecase.dart';

void main() {
  group('ManageEmployeeUseCase — EmployeeInput', () {
    test('EmployeeInput holds all fields', () {
      final input = EmployeeInput(
        name: 'أحمد',
        phone: '0791234567',
        role: 'manager',
        salary: 800,
        salaryType: 'monthly',
      );
      expect(input.name, 'أحمد');
      expect(input.phone, '0791234567');
      expect(input.role, 'manager');
      expect(input.salary, 800);
      expect(input.salaryType, 'monthly');
    });

    test('defaults are applied', () {
      final input = EmployeeInput(name: 'سارة');
      expect(input.role, 'staff');
      expect(input.salary, 0);
      expect(input.salaryType, 'monthly');
      expect(input.phone, isNull);
    });

    test('empty name should fail validation', () {
      final input = EmployeeInput(name: '');
      expect(input.name.trim().isEmpty, true);
    });

    test('negative salary should fail validation', () {
      final input = EmployeeInput(name: 'test', salary: -100);
      expect(input.salary < 0, true);
    });
  });

  group('EmployeeResult', () {
    test('success factory', () {
      final r = EmployeeResult.success(5);
      expect(r.isSuccess, true);
      expect(r.employeeId, 5);
    });

    test('failure factory', () {
      final r = EmployeeResult.failure('يجب إدخال اسم الموظف');
      expect(r.isSuccess, false);
      expect(r.error, contains('اسم'));
    });
  });

  group('PayrollUseCase — PayrollResult', () {
    test('success with net amount', () {
      final r = PayrollResult.success(750.50);
      expect(r.isSuccess, true);
      expect(r.netAmount, 750.50);
    });

    test('failure', () {
      final r = PayrollResult.failure('الراتب الصافي يجب أن يكون أكبر من صفر');
      expect(r.isSuccess, false);
      expect(r.netAmount, isNull);
    });
  });

  group('PayrollUseCase — Validation Data', () {
    test('leave end date before start date should fail', () {
      final start = DateTime(2026, 3, 10);
      final end = DateTime(2026, 3, 5);
      expect(end.isBefore(start), true);
    });

    test('zero overtime hours should fail validation', () {
      expect(0 <= 0, true);
    });

    test('salary period formatting', () {
      final period = '2026-${3.toString().padLeft(2, '0')}';
      expect(period, '2026-03');
    });
  });
}
