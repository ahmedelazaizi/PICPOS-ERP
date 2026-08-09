import '../../../data/database/database_barrel.dart';

abstract class IHRRepository {
  // Employee management
  //
  // H6 — `allowedBranchIds` هو نطاق `branchScopeProvider`: `null` = وصولٌ كامل،
  // ومجموعةٌ فارغة = صفرُ صفوف (فشلٌ مقفول). والموظفُ بلا فرعٍ على مستوى
  // الشركة فيبقى مرئياً لكل نطاق.
  Stream<List<Employee>> watchAllEmployees({required Set<int>? allowedBranchIds});
  Future<Employee?> getEmployeeById(int id);
  Future<int> addEmployee({
    required String name,
    String? phone,
    required String role,
    required double salary,
    required String salaryType,
    int? branchId,
  });
  Future<void> updateEmployee({
    required int id,
    String? name,
    String? phone,
    String? role,
    double? salary,
    String? salaryType,
    bool? isActive,
    int? branchId,
  });

  // Attendance
  Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance();
  Future<void> checkInEmployee(int employeeId);
  Future<void> checkOutEmployee(int employeeId);

  /// يعلّم يوماً غياباً غيرَ مدفوع — المدخلُ الوحيدُ للخصم من الراتب الشهري.
  Future<void> markEmployeeAbsent(
    int employeeId,
    DateTime date, {
    String? notes,
  });
  Future<List<Employee>> getAllEmployees({required Set<int>? allowedBranchIds});

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
  /// B3 — [amount] هو الصافي المدفوع نقداً، و[payableAmount] هو المستحقُّ بعد
  /// الجزاءات (المصروفُ المُعترَف به)، و[advancesSettled] ما تُسوّيه هذه
  /// القسيمةُ من السلف. مصدرُ الثلاثة الوحيد هو `calculateNetSalary`.
  ///
  /// إغفالُ الأخيرَين يعني «لا تسويةَ سلفٍ» — وهو الصحيح للمكافآت وما شابه.
  Future<void> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period,
    double? payableAmount,
    double advancesSettled,
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
