import '../../domain/repositories/hr_repository_interface.dart';
import '../database/database.dart';
import '../database/extensions/hr_extensions.dart';

class HRRepositoryImpl implements IHRRepository {
  final AppDatabase _db;

  HRRepositoryImpl(this._db);

  @override
  Stream<List<Employee>> watchAllEmployees({Set<int>? allowedBranchIds}) =>
      _db.watchAllEmployees(allowedBranchIds: allowedBranchIds);

  @override
  Future<Employee?> getEmployeeById(int id) => _db.getEmployeeById(id);

  @override
  Future<int> addEmployee({
    required String name,
    String? phone,
    required String role,
    required double salary,
    required String salaryType,
    int? branchId,
  }) => _db.addEmployee(
    name: name,
    phone: phone,
    role: role,
    salary: salary,
    salaryType: salaryType,
    branchId: branchId,
  );

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
  }) => _db.updateEmployee(
    id: id,
    name: name,
    phone: phone,
    role: role,
    salary: salary,
    salaryType: salaryType,
    isActive: isActive,
    branchId: branchId,
  );

  @override
  Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance() =>
      _db.watchTodayAttendance();

  @override
  Future<void> checkInEmployee(int employeeId) =>
      _db.checkInEmployee(employeeId);

  @override
  Future<void> checkOutEmployee(int employeeId) =>
      _db.checkOutEmployee(employeeId);

  @override
  Future<List<Employee>> getAllEmployees({Set<int>? allowedBranchIds}) =>
      _db.getAllEmployees(allowedBranchIds: allowedBranchIds);

  @override
  Stream<List<EmployeeTransaction>> watchEmployeeTransactions(int employeeId) =>
      _db.watchEmployeeTransactions(employeeId);

  @override
  Future<void> recordEmployeeAdvance({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
    bool affectsTreasury = true,
    int? safeId,
  }) => _db.recordEmployeeAdvance(
    employeeId: employeeId,
    amount: amount,
    description: description,
    transactionDate: transactionDate,
    affectsTreasury: affectsTreasury,
    safeId: safeId,
  );

  @override
  Future<void> recordEmployeeDeduction({
    required int employeeId,
    required double amount,
    String? description,
    required DateTime transactionDate,
  }) => _db.recordEmployeeDeduction(
    employeeId: employeeId,
    amount: amount,
    description: description,
    transactionDate: transactionDate,
  );

  @override
  Future<void> cancelEmployeeTransaction(int transactionId) =>
      _db.cancelEmployeeTransaction(transactionId);

  @override
  Future<EmployeeSalaryCalculation> calculateNetSalary({
    required int employeeId,
    required int year,
    required int month,
  }) =>
      _db.calculateNetSalary(employeeId: employeeId, year: year, month: month);

  @override
  Future<void> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period,
    double? payableAmount,
    double advancesSettled = 0,
  }) => _db.recordSalaryPayment(
    employeeId: employeeId,
    amount: amount,
    period: period,
    payableAmount: payableAmount,
    advancesSettled: advancesSettled,
  );

  @override
  Stream<List<EmployeeLeave>> watchPendingLeaves() => _db.watchPendingLeaves();

  @override
  Stream<List<EmployeeLeave>> watchEmployeeLeaves(int employeeId) =>
      _db.watchEmployeeLeaves(employeeId);

  @override
  Future<List<LeaveBalance>> getLeaveBalances(int employeeId, int year) =>
      _db.getLeaveBalances(employeeId, year);

  @override
  Future<void> initializeLeaveBalances(int employeeId, int year) =>
      _db.initializeLeaveBalances(employeeId, year);

  @override
  Future<void> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) => _db.requestLeave(
    employeeId: employeeId,
    leaveType: leaveType,
    startDate: startDate,
    endDate: endDate,
    days: days,
    notes: notes,
  );

  @override
  Future<void> updateLeaveStatus(int leaveId, String status, int userId) =>
      _db.updateLeaveStatus(leaveId, status, userId);

  @override
  Stream<List<OvertimeRecord>> watchEmployeeOvertime(
    int employeeId,
    DateTime start,
    DateTime end,
  ) => _db.watchEmployeeOvertime(employeeId, start, end);

  @override
  Future<void> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    required double rate,
    String? notes,
  }) => _db.addOvertimeRecord(
    employeeId: employeeId,
    date: date,
    hours: hours,
    rate: rate,
    notes: notes,
  );

  @override
  Stream<List<PerformanceReview>> watchEmployeeReviews(int employeeId) =>
      _db.watchEmployeeReviews(employeeId);

  @override
  Future<List<PerformanceReview>> getAllReviews() => _db.getAllReviews();

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
  }) => _db.addPerformanceReview(
        employeeId: employeeId,
        period: period,
        periodType: periodType,
        commitmentScore: commitmentScore,
        productivityScore: productivityScore,
        qualityScore: qualityScore,
        teamworkScore: teamworkScore,
        reviewerNotes: reviewerNotes,
        reviewedBy: reviewedBy,
      );

  @override
  Stream<List<EmployeeContract>> watchEmployeeContracts(int employeeId) =>
      _db.watchEmployeeContracts(employeeId);

  @override
  Future<List<EmployeeContract>> getExpiringContracts(int withinDays) =>
      _db.getExpiringContracts(withinDays);

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
  }) => _db.addEmployeeContract(
        employeeId: employeeId,
        contractType: contractType,
        startDate: startDate,
        endDate: endDate,
        salary: salary,
        benefits: benefits,
        terminationClause: terminationClause,
        notes: notes,
      );

  @override
  Future<void> updateContractStatus(int contractId, String status) =>
      _db.updateContractStatus(contractId, status);
}
