// ═══════════════════════════════════════════════════════════════════════════
// ManageEmployeeUseCase — Unit Tests (coverage: manage_employee_usecase.dart)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/hr/manage_employee_usecase.dart';
import 'package:ural_erp/domain/repositories/hr_repository_interface.dart';
import 'package:ural_erp/data/database/database_barrel.dart';

class _MockHRRepository implements IHRRepository {
  bool shouldFail = false;
  int nextEmployeeId = 55;

  /// H6 — يُلتقط لا يُتجاهل: تمريرُ `branchId` من `EmployeeInput` إلى المستودع
  /// هو الحلقةُ التي لو انقطعت وُلد كلُّ موظفٍ بلا فرع، وهو العطلُ نفسه.
  int? capturedAddBranchId;
  int? capturedUpdateBranchId;

  @override
  Future<int> addEmployee({
    required String name,
    String? phone,
    required String role,
    required double salary,
    required String salaryType,
    int? branchId,
  }) async {
    if (shouldFail) throw Exception('DB error');
    capturedAddBranchId = branchId;
    return nextEmployeeId;
  }

  @override
  Future<void> updateEmployee({
    required int id,
    String? name,
    String? phone,
    String? role,
    double? salary,
    String? salaryType,
    bool? isActive,
    int? branchId,
  }) async {
    capturedUpdateBranchId = branchId;
    if (shouldFail) throw Exception('DB error');
  }

  @override
  Future<void> checkInEmployee(int employeeId) async {
    if (shouldFail) throw Exception('check-in failed');
  }

  @override
  Future<void> checkOutEmployee(int employeeId) async {
    if (shouldFail) throw Exception('check-out failed');
  }

  @override
  Future<void> recordEmployeeAdvance({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
    bool affectsTreasury = true,
    int? safeId,
  }) async {
    if (shouldFail) throw Exception('advance failed');
  }

  @override
  Future<void> recordEmployeeDeduction({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
  }) async {
    if (shouldFail) throw Exception('deduction failed');
  }

  @override
  Future<void> cancelEmployeeTransaction(int transactionId) async {}

  // ── Unneeded methods — throw so we notice if they're accidentally called
  @override
  Stream<List<Employee>> watchAllEmployees({Set<int>? allowedBranchIds}) =>
      throw UnimplementedError();
  @override
  Future<Employee?> getEmployeeById(int id) => throw UnimplementedError();
  @override
  Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance() =>
      throw UnimplementedError();
  @override
  Future<List<Employee>> getAllEmployees({Set<int>? allowedBranchIds}) =>
      throw UnimplementedError();
  @override
  Stream<List<EmployeeTransaction>> watchEmployeeTransactions(int id) =>
      throw UnimplementedError();
  @override
  Future<EmployeeSalaryCalculation> calculateNetSalary({
    required int employeeId,
    required int year,
    required int month,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period,
  }) =>
      throw UnimplementedError();
  @override
  Stream<List<EmployeeLeave>> watchPendingLeaves() => throw UnimplementedError();
  @override
  Stream<List<EmployeeLeave>> watchEmployeeLeaves(int id) =>
      throw UnimplementedError();
  @override
  Future<List<LeaveBalance>> getLeaveBalances(int id, int year) =>
      throw UnimplementedError();
  @override
  Future<void> initializeLeaveBalances(int id, int year) =>
      throw UnimplementedError();
  @override
  Future<void> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> updateLeaveStatus(int leaveId, String status, int userId) =>
      throw UnimplementedError();
  @override
  Stream<List<OvertimeRecord>> watchEmployeeOvertime(
    int id,
    DateTime start,
    DateTime end,
  ) =>
      throw UnimplementedError();
  @override
  Future<void> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    required double rate,
    String? notes,
  }) =>
      throw UnimplementedError();
  @override
  Stream<List<PerformanceReview>> watchEmployeeReviews(int id) =>
      throw UnimplementedError();
  @override
  Future<List<PerformanceReview>> getAllReviews() => throw UnimplementedError();
  @override
  Future<int> addPerformanceReview({
    required int employeeId,
    required String period,
    required String periodType,
    required int commitmentScore,
    required int productivityScore,
    required int qualityScore,
    required int teamworkScore,
    String? reviewerNotes,
    int? reviewedBy,
  }) =>
      throw UnimplementedError();
  @override
  Stream<List<EmployeeContract>> watchEmployeeContracts(int id) =>
      throw UnimplementedError();
  @override
  Future<List<EmployeeContract>> getExpiringContracts(int withinDays) =>
      throw UnimplementedError();
  @override
  Future<int> addEmployeeContract({
    required int employeeId,
    required String contractType,
    required DateTime startDate,
    DateTime? endDate,
    required double salary,
    String? benefits,
    String? terminationClause,
    String? notes,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> updateContractStatus(int contractId, String status) =>
      throw UnimplementedError();
}

void main() {
  late _MockHRRepository mock;
  late ManageEmployeeUseCase useCase;

  setUp(() {
    mock = _MockHRRepository();
    useCase = ManageEmployeeUseCase(mock);
  });

  // ── addEmployee ─────────────────────────────────────────────────────────────
  group('addEmployee', () {
    test('fails when name is empty', () async {
      final input = EmployeeInput(name: '', role: 'staff', salary: 1000);
      final result = await useCase.addEmployee(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'يجب إدخال اسم الموظف');
    });

    test('fails when name is blank whitespace', () async {
      final input = EmployeeInput(name: '   ', role: 'staff', salary: 1000);
      final result = await useCase.addEmployee(input);
      expect(result.isSuccess, isFalse);
    });

    test('fails when salary is negative', () async {
      final input =
          EmployeeInput(name: 'Ahmed', role: 'staff', salary: -500);
      final result = await useCase.addEmployee(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'الراتب لا يمكن أن يكون سالباً');
    });

    test('succeeds and returns employeeId', () async {
      mock.nextEmployeeId = 42;
      final input =
          EmployeeInput(name: 'Ahmed Ali', role: 'cashier', salary: 2000);
      final result = await useCase.addEmployee(input);
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 42);
    });

    test('returns failure when repository throws', () async {
      mock.shouldFail = true;
      final input =
          EmployeeInput(name: 'Test', role: 'staff', salary: 0);
      final result = await useCase.addEmployee(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    // H6 — الحلقةُ التي لو انقطعت وُلد كلُّ موظفٍ بلا فرعٍ فسقط الحصر كلُّه.
    test('branchId يُمرَّر إلى المستودع', () async {
      final input = EmployeeInput(
        name: 'Ahmed Ali',
        role: 'cashier',
        salary: 2000,
        branchId: 3,
      );
      await useCase.addEmployee(input);
      expect(mock.capturedAddBranchId, 3);
    });

    test('غيابُ branchId يُمرَّر null — موظفٌ على مستوى الشركة', () async {
      final input =
          EmployeeInput(name: 'Ahmed Ali', role: 'manager', salary: 9000);
      await useCase.addEmployee(input);
      expect(mock.capturedAddBranchId, isNull);
    });
  });

  // ── updateEmployee ──────────────────────────────────────────────────────────
  group('updateEmployee', () {
    test('fails when name is empty', () async {
      final input = EmployeeInput(name: '', role: 'staff', salary: 1000);
      final result = await useCase.updateEmployee(1, input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'يجب إدخال اسم الموظف');
    });

    test('branchId يُمرَّر إلى المستودع — نقلُ موظفٍ بين الفروع', () async {
      final input = EmployeeInput(
        name: 'Ahmed Ali',
        role: 'cashier',
        salary: 2000,
        branchId: 8,
      );
      await useCase.updateEmployee(11, input);
      expect(mock.capturedUpdateBranchId, 8);
    });

    test('succeeds and returns same employee id', () async {
      final input = EmployeeInput(name: 'Omar', role: 'manager', salary: 5000);
      final result = await useCase.updateEmployee(7, input);
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 7);
    });

    test('returns failure when repository throws', () async {
      mock.shouldFail = true;
      final input = EmployeeInput(name: 'Test', role: 'staff', salary: 0);
      final result = await useCase.updateEmployee(1, input);
      expect(result.isSuccess, isFalse);
    });
  });

  // ── checkIn / checkOut ──────────────────────────────────────────────────────
  group('checkIn', () {
    test('succeeds and returns employeeId', () async {
      final result = await useCase.checkIn(10);
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 10);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.checkIn(1);
      expect(result.isSuccess, isFalse);
    });
  });

  group('checkOut', () {
    test('succeeds and returns employeeId', () async {
      final result = await useCase.checkOut(3);
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 3);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.checkOut(3);
      expect(result.isSuccess, isFalse);
    });
  });

  // ── recordAdvance ───────────────────────────────────────────────────────────
  group('recordAdvance', () {
    test('fails when amount is zero', () async {
      final result = await useCase.recordAdvance(
        employeeId: 1,
        amount: 0,
        description: 'advance',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'مبلغ السلفة يجب أن يكون أكبر من صفر');
    });

    test('fails when amount is negative', () async {
      final result = await useCase.recordAdvance(
        employeeId: 1,
        amount: -100,
        description: 'advance',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isFalse);
    });

    test('succeeds and returns employeeId', () async {
      final result = await useCase.recordAdvance(
        employeeId: 5,
        amount: 500,
        description: 'emergency',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 5);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.recordAdvance(
        employeeId: 1,
        amount: 100,
        description: '',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isFalse);
    });
  });

  // ── recordDeduction ─────────────────────────────────────────────────────────
  group('recordDeduction', () {
    test('fails when amount is zero', () async {
      final result = await useCase.recordDeduction(
        employeeId: 1,
        amount: 0,
        description: 'late',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'مبلغ الخصم يجب أن يكون أكبر من صفر');
    });

    test('succeeds and returns employeeId', () async {
      final result = await useCase.recordDeduction(
        employeeId: 2,
        amount: 50,
        description: 'lateness',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 2);
    });

    test('returns failure when repo throws', () async {
      mock.shouldFail = true;
      final result = await useCase.recordDeduction(
        employeeId: 1,
        amount: 50,
        description: '',
        date: DateTime.now(),
      );
      expect(result.isSuccess, isFalse);
    });
  });

  // ── Data classes ─────────────────────────────────────────────────────────────
  group('EmployeeInput defaults', () {
    test('role defaults to staff and salaryType to monthly', () {
      final input = EmployeeInput(name: 'Ali', salary: 1000);
      expect(input.role, 'staff');
      expect(input.salaryType, 'monthly');
    });
  });

  group('EmployeeResult', () {
    test('success sets isSuccess=true and employeeId', () {
      final r = EmployeeResult.success(7);
      expect(r.isSuccess, isTrue);
      expect(r.employeeId, 7);
      expect(r.error, isNull);
    });

    test('failure sets isSuccess=false and error', () {
      final r = EmployeeResult.failure('bad');
      expect(r.isSuccess, isFalse);
      expect(r.error, 'bad');
      expect(r.employeeId, isNull);
    });

    test('success without id has null employeeId', () {
      final r = EmployeeResult.success();
      expect(r.isSuccess, isTrue);
      expect(r.employeeId, isNull);
    });
  });
}
