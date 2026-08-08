part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HR & STAFF MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get phone => text().nullable()();
  TextColumn get role => text().withDefault(
    const Constant('staff'),
  )(); // cashier, waiter, manager, cleaner
  RealColumn get salary => real().withDefault(const Constant(0))();
  TextColumn get salaryType =>
      text().withDefault(const Constant('monthly'))(); // monthly, hourly, daily
  IntColumn get branchId => integer().nullable().references(Branches, #id)(); // الفرع
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get hiredAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deviceUserId =>
      text().nullable()(); // ZKTeco fingerprint device user ID
}

// ═══════════════════════════════════════════════════════════════════════════
// LEAVE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

class EmployeeLeaves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get leaveType => text()(); // annual, sick, unpaid, emergency
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get days => integer()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, approved, rejected
  TextColumn get notes => text().nullable()();
  IntColumn get approvedBy => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class LeaveBalances extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get leaveType => text()(); // annual, sick, emergency
  IntColumn get totalDays => integer()();
  IntColumn get usedDays => integer().withDefault(const Constant(0))();
  IntColumn get year => integer()();
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERTIME
// ═══════════════════════════════════════════════════════════════════════════

class OvertimeRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  DateTimeColumn get date => dateTime()();
  RealColumn get hours => real()();
  RealColumn get rate =>
      real().withDefault(const Constant(1.5))(); // multiplier (1.5x, 2x)
  RealColumn get amount => real()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ═══════════════════════════════════════════════════════════════════════════
// FINGERPRINT DEVICES
// ═══════════════════════════════════════════════════════════════════════════

class FingerprintDevices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // e.g. "جهاز بصمة الاستقبال"
  TextColumn get ipAddress => text()();
  IntColumn get port => integer().withDefault(const Constant(4370))();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get model => text().nullable()();
  DateTimeColumn get lastSync => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class EmployeeAttendance extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  DateTimeColumn get date => dateTime()(); // The working day
  DateTimeColumn get checkIn => dateTime().nullable()();
  DateTimeColumn get checkOut => dateTime().nullable()();
  TextColumn get status => text().withDefault(
    const Constant('present'),
  )(); // present, absent, leave, sick
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SalaryPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get period => text().nullable()(); // e.g. "January 2026"
  TextColumn get type => text().withDefault(
    const Constant('salary'),
  )(); // salary, bonus, deduction, advance
  TextColumn get notes => text().nullable()();
  IntColumn get treasuryTransactionId => integer().nullable().references(
    SafeTransactions,
    #id,
  )(); // Linked transaction
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Employee transactions for advances and deductions
///
/// Formula: Net Salary = (Base / أيام الشهر الحقيقية) * Days Attended
///                       - Advances - Deductions
/// المقام أيام الشهر الفعلية لا ٣٠ ثابتة (H1) — شوف `_daysInMonth` في
/// `hr_extensions.dart`.
class EmployeeTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get transactionType => text()(); // 'advance' | 'deduction'
  RealColumn get amount => real()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  BoolColumn get affectsTreasury => boolean().withDefault(
    const Constant(true),
  )(); // For advances: creates treasury transaction
  IntColumn get treasuryTransactionId =>
      integer().nullable().references(SafeTransactions, #id)();
  TextColumn get status => text().withDefault(
    const Constant('active'),
  )(); // active, cancelled, settled
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ═══════════════════════════════════════════════════════════════════════════
// PERFORMANCE EVALUATION
// ═══════════════════════════════════════════════════════════════════════════

class PerformanceReviews extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get period =>
      text()(); // e.g. "2026-Q1", "2026-01", "2026-annual"
  TextColumn get periodType => text().withDefault(
    const Constant('monthly'),
  )(); // monthly, quarterly, annual
  IntColumn get commitmentScore =>
      integer().withDefault(const Constant(0))(); // 0-100
  IntColumn get productivityScore =>
      integer().withDefault(const Constant(0))(); // 0-100
  IntColumn get qualityScore =>
      integer().withDefault(const Constant(0))(); // 0-100
  IntColumn get teamworkScore =>
      integer().withDefault(const Constant(0))(); // 0-100
  IntColumn get overallRating =>
      integer().withDefault(const Constant(0))(); // 0-100
  TextColumn get reviewerNotes => text().nullable()();
  IntColumn get reviewedBy => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class PerformanceGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get goalDescription => text()();
  DateTimeColumn get targetDate => dateTime()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, in_progress, completed, cancelled
  IntColumn get weight =>
      integer().withDefault(const Constant(1))(); // relative weight
  IntColumn get progressPercent =>
      integer().withDefault(const Constant(0))(); // 0-100
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPLOYMENT CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

class EmployeeContracts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id)();
  TextColumn get contractType => text().withDefault(
    const Constant('permanent'),
  )(); // permanent, temporary, part_time, freelance
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()(); // null for permanent
  RealColumn get salary => real()();
  TextColumn get benefits => text().nullable()(); // JSON or description
  TextColumn get terminationClause => text().nullable()();
  TextColumn get status => text().withDefault(
    const Constant('active'),
  )(); // active, expired, terminated, renewed
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
