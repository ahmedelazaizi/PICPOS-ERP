// ═══════════════════════════════════════════════════════════════════════════
// HR VALIDATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════
//
// This service provides HR-level validations and business rules
// for employee management, attendance, salary, and compliance.
//
// Features:
// - Attendance validation
// - Salary calculation with deductions/additions
// - Leave/vacation tracking
// - Overtime calculation
// - Employee transaction validation (advances, loans)

import '../core/constants/app_constants.dart';
import '../data/database/database_barrel.dart';

/// HR validation result
class HRValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final Map<String, dynamic>? data;

  const HRValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.data,
  });

  factory HRValidationResult.success({Map<String, dynamic>? data}) =>
      HRValidationResult(isValid: true, data: data);

  factory HRValidationResult.failure(List<String> errors) =>
      HRValidationResult(isValid: false, errors: errors);
}

/// HR validation and business rules service
class HRService {
  final AppDatabase _db;

  HRService(this._db);

  // ═══════════════════════════════════════════════════════════════════════
  // ATTENDANCE VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate check-in time
  Future<HRValidationResult> validateCheckIn({
    required int employeeId,
    required DateTime checkInTime,
  }) async {
    try {
      final employee = await _db.getEmployeeById(employeeId);
      if (employee == null) {
        return HRValidationResult.failure(['الموظف غير موجود']);
      }

      // Check if employee is active
      if (!employee.isActive) {
        return HRValidationResult.failure(['الموظف غير نشط']);
      }

      // Check for duplicate attendance today
      final todayStart = DateTime(
        checkInTime.year,
        checkInTime.month,
        checkInTime.day,
      );
      final todayEnd = todayStart.add(const Duration(days: 1));
      final existing = await _db.getEmployeeAttendanceForDateRange(
        employeeId,
        todayStart,
        todayEnd,
      );

      if (existing.isNotEmpty) {
        return HRValidationResult.failure(['تم تسجيل الحضور اليوم بالفعل']);
      }

      final warnings = <String>[];

      // Check for late arrival (after 9:00 AM by default)
      final expectedTime = DateTime(
        checkInTime.year,
        checkInTime.month,
        checkInTime.day,
        9,
        0,
      );
      if (checkInTime.isAfter(expectedTime)) {
        final lateMinutes = checkInTime.difference(expectedTime).inMinutes;
        warnings.add('تسجيل متأخر بـ $lateMinutes دقيقة');
      }

      return HRValidationResult(
        isValid: true,
        warnings: warnings,
        data: {
          'expectedTime': expectedTime,
          'lateMinutes': checkInTime.isAfter(expectedTime)
              ? checkInTime.difference(expectedTime).inMinutes
              : 0,
        },
      );
    } catch (e) {
      return HRValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }

  /// Validate check-out time
  Future<HRValidationResult> validateCheckOut({
    required int employeeId,
    required DateTime checkOutTime,
  }) async {
    try {
      final todayStart = DateTime(
        checkOutTime.year,
        checkOutTime.month,
        checkOutTime.day,
      );
      final todayEnd = todayStart.add(const Duration(days: 1));
      final attendance = await _db.getEmployeeAttendanceForDateRange(
        employeeId,
        todayStart,
        todayEnd,
      );

      if (attendance.isEmpty) {
        return HRValidationResult.failure(['لم يتم تسجيل الحضور اليوم']);
      }

      final record = attendance.first;
      if (record.checkOut != null) {
        return HRValidationResult.failure(['تم تسجيل الانصراف اليوم بالفعل']);
      }

      final warnings = <String>[];

      // Calculate work hours
      if (record.checkIn == null) {
        return HRValidationResult.failure(['لا يوجد وقت تسجيل حضور']);
      }
      final duration = checkOutTime.difference(record.checkIn!);
      final workHours = duration.inMinutes / 60.0;

      // Check for overtime (after 8 hours)
      if (workHours > 8) {
        final overtimeHours = workHours - 8;
        warnings.add('ساعات إضافية: ${overtimeHours.toStringAsFixed(1)} ساعة');
      }

      // Check for early leave (before 5:00 PM)
      final expectedEnd = DateTime(
        checkOutTime.year,
        checkOutTime.month,
        checkOutTime.day,
        17,
        0,
      );
      if (checkOutTime.isBefore(expectedEnd) && workHours < 8) {
        warnings.add('انصراف مبكر قبل الوقت المحدد');
      }

      return HRValidationResult(
        isValid: true,
        warnings: warnings,
        data: {
          'workHours': workHours,
          'overtimeHours': workHours > 8 ? workHours - 8 : 0,
        },
      );
    } catch (e) {
      return HRValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALARY CALCULATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Calculate monthly salary with all adjustments
  Future<SalaryCalculation> calculateMonthlySalary({
    required int employeeId,
    required int year,
    required int month,
  }) async {
    final employee = await _db.getEmployeeById(employeeId);
    if (employee == null) {
      return SalaryCalculation.error('الموظف غير موجود');
    }

    final baseSalary = employee.salary;

    // Get attendance for the month
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

    final attendanceRecords = await _db.getEmployeeAttendanceForDateRange(
      employeeId,
      startDate,
      endDate,
    );

    // Calculate working days
    final workingDays = _calculateWorkingDays(year, month);
    final attendedDays = attendanceRecords
        .where((a) => a.checkOut != null)
        .length;
    final absentDays = workingDays - attendedDays;

    // Calculate overtime hours
    double totalOvertimeHours = 0;
    for (final record in attendanceRecords) {
      if (record.checkOut != null && record.checkIn != null) {
        final duration = record.checkOut!.difference(record.checkIn!);
        final workHours = duration.inMinutes / 60.0;
        if (workHours > 8) {
          totalOvertimeHours += workHours - 8;
        }
      }
    }

    // Get transactions (advances, deductions, bonuses)
    final transactions = await _db.getEmployeeTransactionsForMonth(
      employeeId,
      year,
      month,
    );

    double totalAdvances = 0;
    double totalDeductions = 0;
    double totalBonuses = 0;

    for (final tx in transactions) {
      switch (tx.transactionType) {
        case 'advance':
        case 'loan':
          totalAdvances += tx.amount;
          break;
        case 'deduction':
        case 'penalty':
          totalDeductions += tx.amount;
          break;
        case 'bonus':
        case 'incentive':
          totalBonuses += tx.amount;
          break;
      }
    }

    // Calculate salary per day
    final salaryPerDay = baseSalary / workingDays;

    // Calculate absence deduction
    final absenceDeduction = absentDays * salaryPerDay;

    // Calculate overtime payment (1.5x hourly rate)
    final hourlyRate = salaryPerDay / 8;
    final overtimePayment = totalOvertimeHours * hourlyRate * 1.5;

    // Calculate net salary
    final netSalary =
        baseSalary -
        absenceDeduction -
        totalAdvances -
        totalDeductions +
        totalBonuses +
        overtimePayment;

    return SalaryCalculation(
      baseSalary: baseSalary,
      workingDays: workingDays,
      attendedDays: attendedDays,
      absentDays: absentDays,
      overtimeHours: totalOvertimeHours,
      overtimePayment: overtimePayment,
      advances: totalAdvances,
      deductions: totalDeductions,
      bonuses: totalBonuses,
      absenceDeduction: absenceDeduction,
      netSalary: netSalary,
    );
  }

  /// Calculate working days in a month (excluding Fridays)
  int _calculateWorkingDays(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0);

    int workingDays = 0;
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(year, month, day);
      // Exclude Fridays (weekday 5)
      if (date.weekday != 5) {
        workingDays++;
      }
    }
    return workingDays;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ADVANCE/LOAN VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate advance request
  Future<HRValidationResult> validateAdvanceRequest({
    required int employeeId,
    required double amount,
  }) async {
    try {
      final employee = await _db.getEmployeeById(employeeId);
      if (employee == null) {
        return HRValidationResult.failure(['الموظف غير موجود']);
      }

      final errors = <String>[];
      final warnings = <String>[];

      // Check if employee is active
      if (!employee.isActive) {
        errors.add('الموظف غير نشط');
      }

      // Check if advance exceeds 50% of salary
      final maxAdvance = employee.salary * 0.5;
      if (amount > maxAdvance) {
        errors.add(
          'السلفة لا يمكن أن تتجاوز 50% من الراتب (${maxAdvance.toStringAsFixed(AppConstants.decimalPlaces)})',
        );
      }

      // Check for existing unpaid advances this month
      final now = DateTime.now();
      final existingAdvances = await _db.getEmployeeTransactionsForMonth(
        employeeId,
        now.year,
        now.month,
      );
      final unpaidAdvances = existingAdvances
          .where((t) => t.transactionType == 'advance' && t.status != 'settled')
          .fold<double>(0, (sum, t) => sum + t.amount);

      if (unpaidAdvances + amount > employee.salary) {
        errors.add('إجمالي السلف يتجاوز الراتب الأساسي');
      }

      if (unpaidAdvances > 0 && errors.isEmpty) {
        warnings.add(
          'يوجد سلف سابقة غير مسددة: ${unpaidAdvances.toStringAsFixed(AppConstants.decimalPlaces)}',
        );
      }

      return HRValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
        data: {'maxAdvance': maxAdvance, 'existingAdvances': unpaidAdvances},
      );
    } catch (e) {
      return HRValidationResult.failure(['خطأ في التحقق: $e']);
    }
  }
}

/// Salary calculation result
class SalaryCalculation {
  final double baseSalary;
  final int workingDays;
  final int attendedDays;
  final int absentDays;
  final double overtimeHours;
  final double overtimePayment;
  final double advances;
  final double deductions;
  final double bonuses;
  final double absenceDeduction;
  final double netSalary;
  final String? error;

  bool get isValid => error == null;

  SalaryCalculation({
    required this.baseSalary,
    required this.workingDays,
    required this.attendedDays,
    required this.absentDays,
    required this.overtimeHours,
    required this.overtimePayment,
    required this.advances,
    required this.deductions,
    required this.bonuses,
    required this.absenceDeduction,
    required this.netSalary,
    this.error,
  });

  factory SalaryCalculation.error(String message) => SalaryCalculation(
    baseSalary: 0,
    workingDays: 0,
    attendedDays: 0,
    absentDays: 0,
    overtimeHours: 0,
    overtimePayment: 0,
    advances: 0,
    deductions: 0,
    bonuses: 0,
    absenceDeduction: 0,
    netSalary: 0,
    error: message,
  );
}
