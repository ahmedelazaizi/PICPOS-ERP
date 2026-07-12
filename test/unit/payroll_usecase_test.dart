// ═══════════════════════════════════════════════════════════════════════════
// PayrollUseCase — Unit Tests (coverage: payroll_usecase.dart)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/hr/payroll_usecase.dart';
import 'package:ural_erp/domain/repositories/hr_repository_interface.dart';
import 'package:ural_erp/data/database/database_barrel.dart';

class _MockHR implements IHRRepository {
  bool shouldFail = false;

  @override
  Future<void> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period,
  }) async {
    if (shouldFail) throw Exception('salary payment failed');
  }

  @override
  Future<void> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) async {
    if (shouldFail) throw Exception('leave request failed');
  }

  @override
  Future<void> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    required double rate,
    String? notes,
  }) async {
    if (shouldFail) throw Exception('overtime record failed');
  }

  // ── Unneeded methods ─────────────────────────────────────────────────────
  @override Stream<List<Employee>> watchAllEmployees() => throw UnimplementedError();
  @override Future<Employee?> getEmployeeById(int id) => throw UnimplementedError();
  @override Future<int> addEmployee({required String name, String? phone, required String role, required double salary, required String salaryType}) => throw UnimplementedError();
  @override Future<void> updateEmployee({required int id, String? name, String? phone, String? role, double? salary, String? salaryType, bool? isActive}) => throw UnimplementedError();
  @override Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance() => throw UnimplementedError();
  @override Future<void> checkInEmployee(int e) => throw UnimplementedError();
  @override Future<void> checkOutEmployee(int e) => throw UnimplementedError();
  @override Future<List<Employee>> getAllEmployees() => throw UnimplementedError();
  @override Stream<List<EmployeeTransaction>> watchEmployeeTransactions(int id) => throw UnimplementedError();
  @override Future<void> recordEmployeeAdvance({required int employeeId, required double amount, String? description, required DateTime transactionDate, bool affectsTreasury = true, int? safeId}) => throw UnimplementedError();
  @override Future<void> recordEmployeeDeduction({required int employeeId, required double amount, String? description, required DateTime transactionDate}) => throw UnimplementedError();
  @override Future<void> cancelEmployeeTransaction(int id) => throw UnimplementedError();
  @override Future<EmployeeSalaryCalculation> calculateNetSalary({required int employeeId, required int year, required int month}) => throw UnimplementedError();
  @override Stream<List<EmployeeLeave>> watchPendingLeaves() => throw UnimplementedError();
  @override Stream<List<EmployeeLeave>> watchEmployeeLeaves(int id) => throw UnimplementedError();
  @override Future<List<LeaveBalance>> getLeaveBalances(int id, int year) => throw UnimplementedError();
  @override Future<void> initializeLeaveBalances(int id, int year) => throw UnimplementedError();
  @override Future<void> updateLeaveStatus(int id, String s, int u) => throw UnimplementedError();
  @override Stream<List<OvertimeRecord>> watchEmployeeOvertime(int id, DateTime s, DateTime e) => throw UnimplementedError();
  @override Stream<List<PerformanceReview>> watchEmployeeReviews(int id) => throw UnimplementedError();
  @override Future<List<PerformanceReview>> getAllReviews() => throw UnimplementedError();
  @override Future<int> addPerformanceReview({required int employeeId, required String period, required String periodType, required int commitmentScore, required int productivityScore, required int qualityScore, required int teamworkScore, String? reviewerNotes, int? reviewedBy}) => throw UnimplementedError();
  @override Stream<List<EmployeeContract>> watchEmployeeContracts(int id) => throw UnimplementedError();
  @override Future<List<EmployeeContract>> getExpiringContracts(int d) => throw UnimplementedError();
  @override Future<int> addEmployeeContract({required int employeeId, required String contractType, required DateTime startDate, DateTime? endDate, required double salary, String? benefits, String? terminationClause, String? notes}) => throw UnimplementedError();
  @override Future<void> updateContractStatus(int id, String s) => throw UnimplementedError();
}

void main() {
  late _MockHR mock;
  late PayrollUseCase useCase;

  setUp(() {
    mock = _MockHR();
    useCase = PayrollUseCase(mock);
  });

  // ── paySalary ───────────────────────────────────────────────────────────────
  group('paySalary', () {
    test('fails when netSalary is zero', () async {
      final result = await useCase.paySalary(
        employeeId: 1,
        netSalary: 0,
        year: 2026,
        month: 4,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'الراتب الصافي يجب أن يكون أكبر من صفر');
    });

    test('fails when netSalary is negative', () async {
      final result = await useCase.paySalary(
        employeeId: 1,
        netSalary: -500,
        year: 2026,
        month: 4,
      );
      expect(result.isSuccess, isFalse);
    });

    test('succeeds and returns netSalary', () async {
      final result = await useCase.paySalary(
        employeeId: 3,
        netSalary: 3000,
        year: 2026,
        month: 4,
      );
      expect(result.isSuccess, isTrue);
      expect(result.netAmount, 3000);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.paySalary(
        employeeId: 1,
        netSalary: 1000,
        year: 2026,
        month: 1,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  // ── requestLeave ────────────────────────────────────────────────────────────
  group('requestLeave', () {
    final start = DateTime(2026, 5, 1);
    final end = DateTime(2026, 5, 10);

    test('fails when days is zero', () async {
      final result = await useCase.requestLeave(
        employeeId: 1,
        leaveType: 'annual',
        startDate: start,
        endDate: end,
        days: 0,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'عدد أيام الإجازة يجب أن يكون أكبر من صفر');
    });

    test('fails when endDate is before startDate', () async {
      final result = await useCase.requestLeave(
        employeeId: 1,
        leaveType: 'annual',
        startDate: end,   // reversed
        endDate: start,
        days: 5,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error,
          'تاريخ نهاية الإجازة يجب أن يكون بعد تاريخ البداية');
    });

    test('succeeds with valid leave request', () async {
      final result = await useCase.requestLeave(
        employeeId: 2,
        leaveType: 'annual',
        startDate: start,
        endDate: end,
        days: 10,
        notes: 'vacation',
      );
      expect(result.isSuccess, isTrue);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.requestLeave(
        employeeId: 1,
        leaveType: 'sick',
        startDate: start,
        endDate: end,
        days: 3,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  // ── addOvertime ─────────────────────────────────────────────────────────────
  group('addOvertime', () {
    test('fails when hours is zero', () async {
      final result = await useCase.addOvertime(
        employeeId: 1,
        date: DateTime(2026, 4, 15),
        hours: 0,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'ساعات العمل الإضافي يجب أن تكون أكبر من صفر');
    });

    test('succeeds with valid overtime record', () async {
      final result = await useCase.addOvertime(
        employeeId: 4,
        date: DateTime(2026, 4, 15),
        hours: 2.5,
        rate: 1.5,
      );
      expect(result.isSuccess, isTrue);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.addOvertime(
        employeeId: 1,
        date: DateTime.now(),
        hours: 3,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  // ── PayrollResult data class ─────────────────────────────────────────────────
  group('PayrollResult', () {
    test('success sets isSuccess=true and netAmount', () {
      final r = PayrollResult.success(1500.0);
      expect(r.isSuccess, isTrue);
      expect(r.netAmount, 1500.0);
      expect(r.error, isNull);
    });

    test('failure sets isSuccess=false and error', () {
      final r = PayrollResult.failure('failed');
      expect(r.isSuccess, isFalse);
      expect(r.error, 'failed');
      expect(r.netAmount, isNull);
    });

    test('success without amount has null netAmount', () {
      final r = PayrollResult.success();
      expect(r.isSuccess, isTrue);
      expect(r.netAmount, isNull);
    });
  });
}
