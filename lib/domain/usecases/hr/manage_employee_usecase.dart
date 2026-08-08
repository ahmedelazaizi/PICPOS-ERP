import '../../repositories/hr_repository_interface.dart';

/// Input for employee operations
class EmployeeInput {
  final String name;
  final String? phone;
  final String role;
  final double salary;
  final String salaryType;

  /// H6 — فرعُ الموظف. `null` = مستوى الشركة (يظلّ مرئياً لكل نطاق).
  final int? branchId;

  EmployeeInput({
    required this.name,
    this.phone,
    this.role = 'staff',
    this.salary = 0,
    this.salaryType = 'monthly',
    this.branchId,
  });
}

/// Result of employee operations
class EmployeeResult {
  final bool isSuccess;
  final int? employeeId;
  final String? error;

  EmployeeResult.success([this.employeeId]) : isSuccess = true, error = null;
  EmployeeResult.failure(this.error) : isSuccess = false, employeeId = null;
}

/// Use case: Employee CRUD and attendance operations
class ManageEmployeeUseCase {
  final IHRRepository _hrRepo;

  ManageEmployeeUseCase(this._hrRepo);

  /// Create a new employee
  Future<EmployeeResult> addEmployee(EmployeeInput input) async {
    if (input.name.trim().isEmpty) {
      return EmployeeResult.failure('يجب إدخال اسم الموظف');
    }
    if (input.salary < 0) {
      return EmployeeResult.failure('الراتب لا يمكن أن يكون سالباً');
    }

    try {
      final id = await _hrRepo.addEmployee(
        name: input.name,
        phone: input.phone,
        role: input.role,
        salary: input.salary,
        salaryType: input.salaryType,
        branchId: input.branchId,
      );
      return EmployeeResult.success(id);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }

  /// Update existing employee
  Future<EmployeeResult> updateEmployee(int id, EmployeeInput input) async {
    if (input.name.trim().isEmpty) {
      return EmployeeResult.failure('يجب إدخال اسم الموظف');
    }

    try {
      await _hrRepo.updateEmployee(
        id: id,
        name: input.name,
        phone: input.phone,
        role: input.role,
        salary: input.salary,
        salaryType: input.salaryType,
        branchId: input.branchId,
      );
      return EmployeeResult.success(id);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }

  /// Record employee check-in
  Future<EmployeeResult> checkIn(int employeeId) async {
    try {
      await _hrRepo.checkInEmployee(employeeId);
      return EmployeeResult.success(employeeId);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }

  /// Record employee check-out
  Future<EmployeeResult> checkOut(int employeeId) async {
    try {
      await _hrRepo.checkOutEmployee(employeeId);
      return EmployeeResult.success(employeeId);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }

  /// Record employee advance (سلفة)
  Future<EmployeeResult> recordAdvance({
    required int employeeId,
    required double amount,
    required String description,
    required DateTime date,
    bool affectsTreasury = true,
  }) async {
    if (amount <= 0) return EmployeeResult.failure('مبلغ السلفة يجب أن يكون أكبر من صفر');

    try {
      await _hrRepo.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: amount,
        description: description,
        transactionDate: date,
        affectsTreasury: affectsTreasury,
      );
      return EmployeeResult.success(employeeId);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }

  /// Record employee deduction (خصم)
  Future<EmployeeResult> recordDeduction({
    required int employeeId,
    required double amount,
    required String description,
    required DateTime date,
  }) async {
    if (amount <= 0) return EmployeeResult.failure('مبلغ الخصم يجب أن يكون أكبر من صفر');

    try {
      await _hrRepo.recordEmployeeDeduction(
        employeeId: employeeId,
        amount: amount,
        description: description,
        transactionDate: date,
      );
      return EmployeeResult.success(employeeId);
    } catch (e) {
      return EmployeeResult.failure(e.toString());
    }
  }
}
