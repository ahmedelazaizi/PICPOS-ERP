import '../../repositories/hr_repository_interface.dart';

/// Result of payroll operations
class PayrollResult {
  final bool isSuccess;
  final double? netAmount;
  final String? error;

  PayrollResult.success([this.netAmount]) : isSuccess = true, error = null;
  PayrollResult.failure(this.error) : isSuccess = false, netAmount = null;
}

/// Use case: Salary payment and leave management
class PayrollUseCase {
  final IHRRepository _hrRepo;

  PayrollUseCase(this._hrRepo);

  /// Process salary payment
  Future<PayrollResult> paySalary({
    required int employeeId,
    required double netSalary,
    required int year,
    required int month,
  }) async {
    if (netSalary <= 0) return PayrollResult.failure('الراتب الصافي يجب أن يكون أكبر من صفر');

    try {
      final period = '$year-${month.toString().padLeft(2, '0')}';
      await _hrRepo.recordSalaryPayment(
        employeeId: employeeId,
        amount: netSalary,
        period: period,
      );
      return PayrollResult.success(netSalary);
    } catch (e) {
      return PayrollResult.failure(e.toString());
    }
  }

  /// Request leave for an employee
  Future<PayrollResult> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) async {
    if (days <= 0) return PayrollResult.failure('عدد أيام الإجازة يجب أن يكون أكبر من صفر');
    if (endDate.isBefore(startDate)) return PayrollResult.failure('تاريخ نهاية الإجازة يجب أن يكون بعد تاريخ البداية');

    try {
      await _hrRepo.requestLeave(
        employeeId: employeeId,
        leaveType: leaveType,
        startDate: startDate,
        endDate: endDate,
        days: days,
        notes: notes,
      );
      return PayrollResult.success();
    } catch (e) {
      return PayrollResult.failure(e.toString());
    }
  }

  /// Record overtime hours
  Future<PayrollResult> addOvertime({
    required int employeeId,
    required DateTime date,
    required double hours,
    double rate = 1.5,
    String? notes,
  }) async {
    if (hours <= 0) return PayrollResult.failure('ساعات العمل الإضافي يجب أن تكون أكبر من صفر');

    try {
      await _hrRepo.addOvertimeRecord(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: rate,
        notes: notes,
      );
      return PayrollResult.success();
    } catch (e) {
      return PayrollResult.failure(e.toString());
    }
  }
}
