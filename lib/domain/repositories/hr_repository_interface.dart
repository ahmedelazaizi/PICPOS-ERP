import '../../../data/database/database_barrel.dart';

abstract class IHRRepository {
  // Employee management
  Stream<List<Employee>> watchAllEmployees();
  Future<Employee?> getEmployeeById(int id);
  Future<int> addEmployee({
    required String name,
    String? phone,
    required String role,
    required double salary,
    required String salaryType,
  });
  Future<void> updateEmployee({
    required int id,
    String? name,
    String? phone,
    String? role,
    double? salary,
    String? salaryType,
    bool? isActive,
  });

  // Attendance
  Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance();
  Future<void> checkInEmployee(int employeeId);
  Future<void> checkOutEmployee(int employeeId);
  Future<List<Employee>> getAllEmployees();

  // Transactions
  Stream<List<EmployeeTransaction>> watchEmployeeTransactions(int employeeId);
  Future<void> recordEmployeeAdvance({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
    bool affectsTreasury = true,
    int? safeId,
  });
  Future<void> recordEmployeeDeduction({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
  });
  Future<void> cancelEmployeeTransaction(int transactionId);

  // Payroll
  Future<EmployeeSalaryCalculation> calculateNetSalary({
    required int employeeId,
    required int year,
    required int month,
  });
  Future<void> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period,
  });

  // Leaves
  Stream<List<EmployeeLeave>> watchPendingLeaves();
  Stream<List<EmployeeLeave>> watchEmployeeLeaves(int employeeId);
  Future<List<LeaveBalance>> getLeaveBalances(int employeeId, int year);
  Future<void> initializeLeaveBalances(int employeeId, int year);
  Future<void> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  });
  Future<void> updateLeaveStatus(int leaveId, String status, int userId);

  // Overtime
  Stream<List<OvertimeRecord>> watchEmployeeOvertime(
    int employeeId,
    DateTime start,
    DateTime end,
  );
  Future<void> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    required double rate,
    String? notes,
  });

  // Performance Reviews
  Stream<List<PerformanceReview>> watchEmployeeReviews(int employeeId);
  Future<List<PerformanceReview>> getAllReviews();
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
  });

  // Contracts
  Stream<List<EmployeeContract>> watchEmployeeContracts(int employeeId);
  Future<List<EmployeeContract>> getExpiringContracts(int withinDays);
  Future<int> addEmployeeContract({
    required int employeeId,
    required String contractType,
    required DateTime startDate,
    DateTime? endDate,
    required double salary,
    String? benefits,
    String? terminationClause,
    String? notes,
  });
  Future<void> updateContractStatus(int contractId, String status);
}
