import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database.dart';
import '../../../domain/entities/accounting_entities.dart';

/// H1 — عدد أيام الشهر الحقيقي، أساس الأجر اليومي.
///
/// القسمة على ٣٠ ثابتة كانت تكسر ثابتاً بسيطاً: **شهرٌ كامل الحضور يجب أن
/// يُعطي الراتب**. فبراير (٢٨ يوماً) كان يُعطي `salary/30*28` = خصمَ ٦٫٦٧٪ على
/// موظف لم يغب يوماً، ويناير (٣١) كان يُعطي أكثر من الراتب.
///
/// `DateTime(y, m + 1, 0)` يُرجع آخر يوم في الشهر `m` لأن Dart يطبّع اليوم صفر
/// إلى آخر يوم في الشهر السابق — ويصحّ على ديسمبر كذلك (الشهر ١٣ يُطبَّع إلى
/// يناير السنة التالية) وعلى فبراير الكبيسة بلا حالة خاصة.
int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// ساعات اليوم القياسية — مقام الأجر بالساعة للوقت الإضافي.
///
/// ليس في المستودع أيّ إعداد لساعات العمل أو الورديات (فُحص 2026-08-08)، فهذا
/// الرقم افتراضٌ **معلَن** لا قيمةٌ مشتقّة. إن أُضيف إعداد ورديات يوماً، فهذا
/// هو الموضع الوحيد الذي يقرأ منه.
const int kStandardWorkHoursPerDay = 8;

/// B4 — أنواعُ الإجازات المدفوعة: تُحتسب حضوراً في حساب الراتب.
///
/// المجالُ المدعوم لـ`EmployeeLeaves.leaveType` هو `annual` · `sick` ·
/// `unpaid` · `emergency`. المدفوعُ منها ثلاثة، و`unpaid` مستثنى بحكم اسمه:
/// يومٌ بلا أجر. فلا يصحّ تعميمُ «كلُّ إجازةٍ معتمدة مدفوعة» — التعميم يدفع
/// أجراً عن أيامٍ اتُّفق صراحةً على ألّا تُدفَع.
const Set<String> kPaidLeaveTypes = {'annual', 'sick', 'emergency'};

/// حالةُ صفِّ الحضور لإجازةٍ مدفوعة معتمدة.
const String kAttendanceStatusPaidLeave = 'leave';

/// حالةُ صفِّ الحضور لإجازةٍ غير مدفوعة معتمدة.
///
/// الصفُّ يُكتب ولا يُحتسب: الغيابُ مصرَّحٌ به لا مجهول، فيظهر في سجلِّ الحضور
/// مميَّزاً. ولهذا لم تُستعمل `absent` — دلالتُها «لم يحضر بلا إذن»، وطمسُ
/// الفرق يُخفي أنّ المدير وافق.
const String kAttendanceStatusUnpaidLeave = 'unpaid_leave';

/// حالاتُ صفِّ الحضور التي تُعَدّ يوماً **مدفوعاً** في حساب الراتب.
const Set<String> kPaidAttendanceStatuses = {
  'present',
  kAttendanceStatusPaidLeave,
};

/// حدٌّ أعلى لعدد الأيام التي يكتبها اعتمادُ إجازةٍ واحدة.
///
/// ليس قاعدةَ عمل بل حاجزَ بيانات: `endDate` يأتي من منتقي تواريخ، وخطأُ
/// إدخالٍ بسنةٍ كاملة كان سيكتب آلافَ الصفوف داخل معاملةٍ واحدة.
const int kMaxLeaveDaysPerRequest = 366;

/// H6 — شرطُ حصر الموظفين بالفرع.
///
/// `branch_id IS NULL` تعني موظفاً على مستوى الشركة (مديرٌ عام · محاسبٌ مركزي)
/// فيظلّ مرئياً لكل نطاق — نفسُ قاعدة `BranchScope.isAllowed` بالحرف، فلا يفترق
/// حصرُ الـSQL عن الصنف الذي يولّد النطاق.
///
/// ومجموعةٌ **فارغة** ليست «بلا حصر»: هي مستخدمٌ لا يرى شيئاً ⇒ صفرُ صفوف،
/// فشلٌ مقفول مطابقٌ لكلِّ تقريرٍ محصور في المستودع (‏`_buildAuthScopeFilter`
/// و`_buildReportQuery` كلاهما `1 = 0`). و«بلا حصر» يُعبَّر عنه بـ`null` عند
/// الاستدعاء فلا يُستدعى هذا الشرطُ أصلاً.
Expression<bool> _employeeBranchScope($EmployeesTable e, Set<int> ids) =>
    ids.isEmpty
        ? const Constant(false)
        : e.branchId.isIn(ids.toList()) | e.branchId.isNull();

/// Extensions for HR/Employee management
extension HRExtensions on AppDatabase {
  // -----------------------------------------------------------------------
  // EMPLOYEES
  // -----------------------------------------------------------------------

  /// Get all active employees
  Stream<List<Employee>> watchAllEmployees({Set<int>? allowedBranchIds}) {
    final q = select(employees)
      ..where((e) => e.isActive.equals(true))
      ..orderBy([(e) => OrderingTerm.asc(e.name)]);
    if (allowedBranchIds != null) {
      q.where((e) => _employeeBranchScope(e, allowedBranchIds));
    }
    return q.watch();
  }

  /// Get all employees including inactive
  Future<List<Employee>> getAllEmployees({Set<int>? allowedBranchIds}) {
    final q = select(employees)
      ..orderBy([(e) => OrderingTerm.asc(e.name)]);
    if (allowedBranchIds != null) {
      q.where((e) => _employeeBranchScope(e, allowedBranchIds));
    }
    return q.get();
  }

  /// Get employee by ID
  Future<Employee?> getEmployeeById(int id) {
    return (select(employees)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  /// Get employee attendance for date range
  Future<List<EmployeeAttendanceData>> getEmployeeAttendanceForDateRange(
    int employeeId,
    DateTime start,
    DateTime end,
  ) {
    return (select(employeeAttendance)
          ..where((a) => a.employeeId.equals(employeeId))
          ..where((a) => a.date.isBiggerOrEqual(Variable(start)))
          ..where((a) => a.date.isSmallerThan(Variable(end)))
          ..orderBy([(a) => OrderingTerm.desc(a.date)]))
        .get();
  }

  /// Get employee transactions for a specific month
  Future<List<EmployeeTransaction>> getEmployeeTransactionsForMonth(
    int employeeId,
    int year,
    int month,
  ) {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    return (select(employeeTransactions)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.status.equals('active'))
          ..where(
            (t) => t.transactionDate.isBiggerOrEqual(Variable(startOfMonth)),
          )
          ..where((t) => t.transactionDate.isSmallerThan(Variable(endOfMonth))))
        .get();
  }

  /// Add new employee
  ///
  /// H6 — [branchId] يُكتب. كان العمودُ موجوداً في السكيما ولا يُكتب قطّ، فكلُّ
  /// موظفٍ يُولَد بلا فرعٍ ⇒ لا حصرَ ممكن على الرواتب.
  /// `null` = موظفٌ على مستوى الشركة، يظلّ مرئياً لكل نطاق.
  Future<int> addEmployee({
    required String name,
    String? phone,
    String role = 'staff',
    double salary = 0,
    String salaryType = 'monthly',
    int? branchId,
  }) {
    return into(employees).insert(
      EmployeesCompanion.insert(
        name: name,
        phone: Value(phone),
        role: Value(role),
        salary: Value(salary),
        salaryType: Value(salaryType),
        branchId: Value(branchId),
        hiredAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update employee
  ///
  /// H6 — [branchId] بـ`null` تعني «لا تلمس الفرع» لا «انقله إلى بلا فرع»،
  /// مطابقةً لبقيةِ الحقول هنا: تعديلُ الاسم وحده لا يجوز أن يُخرج الموظف من
  /// فرعه. (نقلُه إلى «بلا فرع» يحتاج مساراً صريحاً، وليس مطلوباً بعد.)
  Future<void> updateEmployee({
    required int id,
    String? name,
    String? phone,
    String? role,
    double? salary,
    String? salaryType,
    bool? isActive,
    int? branchId,
  }) {
    return (update(employees)..where((e) => e.id.equals(id))).write(
      EmployeesCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        phone: phone != null ? Value(phone) : const Value.absent(),
        role: role != null ? Value(role) : const Value.absent(),
        salary: salary != null ? Value(salary) : const Value.absent(),
        salaryType: salaryType != null
            ? Value(salaryType)
            : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        branchId: branchId != null ? Value(branchId) : const Value.absent(),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // ATTENDANCE
  // -----------------------------------------------------------------------

  /// Check in employee
  Future<int> checkInEmployee(int employeeId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Check if already checked in today
    final existing =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.equals(today)))
            .getSingleOrNull();

    if (existing != null) {
      // Already has record
      if (existing.checkIn == null) {
        await (update(
          employeeAttendance,
        )..where((a) => a.id.equals(existing.id))).write(
          EmployeeAttendanceCompanion(
            checkIn: Value(now),
            status: const Value('present'),
          ),
        );
        return existing.id;
      }
      return existing.id;
    }

    return into(employeeAttendance).insert(
      EmployeeAttendanceCompanion.insert(
        employeeId: employeeId,
        date: today,
        checkIn: Value(now),
        status: const Value('present'),
      ),
    );
  }

  /// Check out employee
  Future<void> checkOutEmployee(int employeeId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final existing =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.equals(today)))
            .getSingleOrNull();

    if (existing != null) {
      await (update(employeeAttendance)..where((a) => a.id.equals(existing.id)))
          .write(EmployeeAttendanceCompanion(checkOut: Value(now)));
    }
  }

  /// Get today's attendance
  Stream<List<EmployeeAttendanceWithDetails>> watchTodayAttendance() {
    final today = DateTime.now();
    // Just simple date match. Drift might compare full DateTime.
    // Need range query for "today".
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    // Join with Employee table to get names
    final query = select(employeeAttendance).join(
      [
        innerJoin(
          employees,
          employees.id.equalsExp(employeeAttendance.employeeId),
        ),
      ],
    )..where(employeeAttendance.date.isBetween(Variable(start), Variable(end)));

    return query.watch().map((rows) {
      return rows.map((row) {
        return EmployeeAttendanceWithDetails(
          attendance: row.readTable(employeeAttendance),
          employee: row.readTable(employees),
        );
      }).toList();
    });
  }

  // -----------------------------------------------------------------------
  // PAYROLL
  // -----------------------------------------------------------------------

  /// Record salary payment
  Future<int> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period, // e.g., "2023-10"
    String type = 'salary',
    String? notes,
  }) async {
    return transaction(() async {
      // B1 — idempotency guard. The «صرف الراتب» button stays enabled, and
      // every press used to create a fresh salary row, a fresh cash voucher
      // (debiting the safe again) and a fresh journal entry. Two presses paid
      // the salary twice.
      //
      // createJournalEntry's own duplicate guard could not help: it keys on
      // referenceId = salaryPayments.id, which is a NEW id on every press, so
      // each press looked like a brand-new business event.
      //
      // `type` is part of the key on purpose — a bonus or an advance for the
      // same period is a different obligation, not a repeat of the salary.
      //
      // TODO(owner): this belongs in the schema as UNIQUE(employee_id, period,
      // type). Adding it needs a migration + build_runner, which is frozen in
      // agent sessions; until then this is the only layer enforcing it, so a
      // concurrent writer on another device could still slip a duplicate past.
      final existing = await (select(salaryPayments)
            ..where((p) =>
                p.employeeId.equals(employeeId) &
                p.period.equals(period) &
                p.type.equals(type))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        throw StateError(
          'تم صرف $type الفترة $period لهذا الموظف بالفعل '
          '(سند #${existing.id} بمبلغ ${existing.amount}). '
          'لو محتاج تعديل، الغِ الصرف السابق الأول.',
        );
      }

      // Create payment record
      final id = await into(salaryPayments).insert(
        SalaryPaymentsCompanion.insert(
          employeeId: employeeId,
          amount: amount,
          paymentDate: DateTime.now(),
          period: Value(period),
          type: Value(type),
          notes: Value(notes),
        ),
      );

      // Create Treasury Transaction (Expense)
      // Assuming 'expense' category and default cash safe
      final safe = await getDefaultSafeByType('cash');
      if (safe != null) {
        final newBalance = safe.balance - amount;
        final voucher = await generateInvoiceNumber('PV');

        final transId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safe.id,
            transactionType: 'payment',
            category: 'salaries',
            amount: amount,
            balanceAfter: newBalance,
            referenceType: const Value('salary_payment'),
            referenceId: Value(id),
          ),
        );

        await updateSafeBalance(safe.id, newBalance);

        // Link transaction to salary payment
        await (update(salaryPayments)..where((p) => p.id.equals(id))).write(
          SalaryPaymentsCompanion(treasuryTransactionId: Value(transId)),
        );

        // GAP-HR-JE: Auto-post GL journal entry for salary disbursement
        // Dr مصروف الرواتب (621) / Cr الصندوق (1111)
        try {
          final salaryAccCode = await getMappedAccountCode(
            'salary_expense',
            AccountingDao.accountPurposes['salary_expense']!,
          );
          final cashAccCode = await getMappedAccountCode(
            'cash',
            AccountingDao.accountPurposes['cash']!,
          );
          final salaryAcc = await getAccountByCode(salaryAccCode);
          final cashAcc   = await getAccountByCode(cashAccCode);
          if (salaryAcc != null && cashAcc != null) {
            await createJournalEntry(
              description: 'صرف راتب — فترة $period',
              date: DateTime.now(),
              lines: [
                JournalLine(
                  accountId: salaryAcc.id,
                  debit: amount,
                  description: 'مصروف الرواتب',
                ),
                JournalLine(
                  accountId: cashAcc.id,
                  credit: amount,
                  description: 'صرف نقدي من الصندوق',
                ),
              ],
              referenceType: 'salary_payment',
              referenceId: id,
              isAutoPosted: true,
            );
          }
        } catch (e) {
          debugPrint('[HR-AUTOPOST] Salary GL entry failed for period $period: $e');
        }
      }

      return id;
    });
  }

  // -----------------------------------------------------------------------
  // EMPLOYEE TRANSACTIONS (ADVANCES & DEDUCTIONS)
  // -----------------------------------------------------------------------

  /// Watch all transactions for an employee
  Stream<List<EmployeeTransaction>> watchEmployeeTransactions(int employeeId) {
    return (select(employeeTransactions)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
        .watch();
  }

  /// Watch all active transactions for a specific month
  Stream<List<EmployeeTransaction>> watchMonthlyTransactions(
    int employeeId,
    int year,
    int month,
  ) {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    return (select(employeeTransactions)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.status.equals('active'))
          ..where(
            (t) => t.transactionDate.isBiggerOrEqual(Variable(startOfMonth)),
          )
          ..where((t) => t.transactionDate.isSmallerThan(Variable(endOfMonth)))
          ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
        .watch();
  }

  /// Get total advances for employee in a specific month
  Future<double> getMonthlyAdvances(int employeeId, int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final result =
        await (select(employeeTransactions)
              ..where((t) => t.employeeId.equals(employeeId))
              ..where((t) => t.transactionType.equals('advance'))
              ..where((t) => t.status.equals('active'))
              ..where(
                (t) =>
                    t.transactionDate.isBiggerOrEqual(Variable(startOfMonth)),
              )
              ..where(
                (t) => t.transactionDate.isSmallerThan(Variable(endOfMonth)),
              ))
            .get();

    return result.fold<double>(0, (sum, t) => sum + t.amount);
  }

  /// Get total deductions for employee in a specific month
  Future<double> getMonthlyDeductions(
    int employeeId,
    int year,
    int month,
  ) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final result =
        await (select(employeeTransactions)
              ..where((t) => t.employeeId.equals(employeeId))
              ..where((t) => t.transactionType.equals('deduction'))
              ..where((t) => t.status.equals('active'))
              ..where(
                (t) =>
                    t.transactionDate.isBiggerOrEqual(Variable(startOfMonth)),
              )
              ..where(
                (t) => t.transactionDate.isSmallerThan(Variable(endOfMonth)),
              ))
            .get();

    return result.fold<double>(0, (sum, t) => sum + t.amount);
  }

  /// Record an advance (سلفة) - affects treasury
  Future<int> recordEmployeeAdvance({
    required int employeeId,
    required double amount,
    String? description,
    DateTime? transactionDate,
    bool affectsTreasury = true,
    int? safeId,
  }) async {
    return transaction(() async {
      int? treasuryTransactionId;

      // Create treasury/accounting transaction if needed
      if (affectsTreasury) {
        final voucher = await generateInvoiceNumber('ADV');

        final employee = await (select(
          employees,
        )..where((e) => e.id.equals(employeeId))).getSingle();

        // Determine credit account (Cash/Bank) from safe's linked account
        int creditAccountId;
        Safe? targetSafe;

        if (safeId != null) {
          targetSafe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
        }
        // If no safe specified, try to get default cash safe
        targetSafe ??= await getDefaultSafeByType('cash');

        if (targetSafe != null && targetSafe.linkedAccountId != null) {
          // Use the safe's linked account
          creditAccountId = targetSafe.linkedAccountId!;
        } else {
          // Fallback to account mapping
          final cashMapping = await (select(accountMappings)
                ..where((m) => m.purpose.equals('cash')))
              .getSingleOrNull();
          if (cashMapping != null) {
            creditAccountId = cashMapping.accountId;
          } else {
            // Hard fallback to seeded cash account ('1111' الصندوق الرئيسي).
            // The earlier '1101' code was never present in the seeded chart.
            final fallbackCash = await (select(accounts)
                  ..where((a) => a.code.equals(
                      AccountingDao.accountPurposes['cash']!)))
                .getSingleOrNull();
            if (fallbackCash == null) throw Exception('لا يوجد حساب نقدية افتراضي.');
            creditAccountId = fallbackCash.id;
          }
        }

        // Create safe transaction to deduct from safe balance
        if (targetSafe != null) {
          final newBalance = targetSafe.balance - amount;
          treasuryTransactionId = await into(safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucher,
              safeId: targetSafe.id,
              transactionType: 'payment',
              category: 'employee_advance',
              amount: amount,
              balanceAfter: newBalance,
              referenceType: const Value('employee_advance'),
              referenceId: Value(employeeId),
              description: Value('سلفة موظف: ${employee.name}'),
            ),
          );
          await updateSafeBalance(targetSafe.id, newBalance);
        }

        // Determine debit account (Employee Advances)
        final advanceMapping = await (select(accountMappings)
              ..where((m) => m.purpose.equals('employee_advances')))
            .getSingleOrNull();
        int debitAccountId;
        if (advanceMapping != null) {
          debitAccountId = advanceMapping.accountId;
        } else {
          final fallbackAdvance = await (select(accounts)
                ..where((a) => a.code.equals('1146')))
              .getSingleOrNull();
          if (fallbackAdvance == null) throw Exception('حساب سلف الموظفين غير موجود.');
          debitAccountId = fallbackAdvance.id;
        }

        // Create Journal Entry — use accountingDao.createJournalEntry for proper posting
        await accountingDao.createJournalEntry(
          description: 'سلفة موظف: ${employee.name} - ${description ?? ""}',
          date: transactionDate ?? DateTime.now(),
          lines: [
            JournalLine(
              accountId: debitAccountId,
              debit: amount,
              description: 'سلفة موظف: ${employee.name}',
            ),
            JournalLine(
              accountId: creditAccountId,
              credit: amount,
              description: 'صرف سلفة لموظف: ${employee.name}',
            ),
          ],
          referenceType: 'employee_advance',
          referenceId: employeeId,
          isAutoPosted: true,
        );
      }

      // Create employee transaction
      return into(employeeTransactions).insert(
        EmployeeTransactionsCompanion.insert(
          employeeId: employeeId,
          transactionType: 'advance',
          amount: amount,
          description: Value(description ?? 'سلفة'),
          transactionDate: transactionDate ?? DateTime.now(),
          affectsTreasury: Value(affectsTreasury),
          treasuryTransactionId: Value(treasuryTransactionId),
        ),
      );
    });
  }

  /// Record a deduction (???)
  Future<int> recordEmployeeDeduction({
    required int employeeId,
    required double amount,
    String? description,
    DateTime? transactionDate,
  }) async {
    return into(employeeTransactions).insert(
      EmployeeTransactionsCompanion.insert(
        employeeId: employeeId,
        transactionType: 'deduction',
        amount: amount,
        description: Value(description ?? '???'),
        transactionDate: transactionDate ?? DateTime.now(),
        affectsTreasury: const Value(
          false,
        ), // Deductions don't affect treasury directly
      ),
    );
  }

  /// Cancel a transaction
  Future<void> cancelEmployeeTransaction(int transactionId) async {
    await (update(employeeTransactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(const EmployeeTransactionsCompanion(status: Value('cancelled')));

    // Note: If treasury transaction exists, it should be handled separately
    // (e.g., create a reversal transaction)
  }

  /// Calculate net salary for an employee
  ///
  /// Formula: (Base Salary / أيام الشهر الحقيقية) * Days Attended
  ///          + Overtime - Advances - Deductions
  ///
  /// المقام هو [_daysInMonth] لا ٣٠ ثابتة — شوف تعليقه لسبب ذلك.
  Future<EmployeeSalaryCalculation> calculateNetSalary({
    required int employeeId,
    required int year,
    required int month,
  }) async {
    // Get employee
    final employee = await (select(
      employees,
    )..where((e) => e.id.equals(employeeId))).getSingle();

    // Get days attended
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final attendanceRecords =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.isBiggerOrEqual(Variable(startOfMonth)))
              ..where((a) => a.date.isSmallerThan(Variable(endOfMonth)))
              // B4 — الأيامُ **المدفوعة** لا الحاضرةُ وحدها. الإجازةُ المدفوعة
              // المعتمدة يومٌ مستحَقُّ الأجر، فاستثناؤها كان يخصم إجازةً وافق
              // عليها المدير. شوف [kPaidAttendanceStatuses].
              ..where(
                (a) => a.status.isIn(kPaidAttendanceStatuses.toList()),
              ))
            .get();

    final daysAttended = attendanceRecords.length;

    // Get advances and deductions
    final advances = await getMonthlyAdvances(employeeId, year, month);
    final deductions = await getMonthlyDeductions(employeeId, year, month);

    // Get overtime total
    final overtimeAmount = await getMonthlyOvertimeAmount(
      employeeId,
      year,
      month,
    );

    // Calculate
    final dailyRate = employee.salary / _daysInMonth(year, month);
    final grossPay = dailyRate * daysAttended + overtimeAmount;
    final netSalary = grossPay - advances - deductions;

    return EmployeeSalaryCalculation(
      employee: employee,
      baseSalary: employee.salary,
      dailyRate: dailyRate,
      daysAttended: daysAttended,
      grossPay: grossPay,
      totalAdvances: advances,
      totalDeductions: deductions,
      overtimeAmount: overtimeAmount,
      netSalary: netSalary < 0 ? 0 : netSalary,
      month: month,
      year: year,
    );
  }

  // -----------------------------------------------------------------------
  // FINGERPRINT DEVICE SYNC
  // -----------------------------------------------------------------------

  /// Find employee by their fingerprint device user ID
  Future<Employee?> getEmployeeByDeviceUserId(String deviceUserId) {
    return (select(
      employees,
    )..where((e) => e.deviceUserId.equals(deviceUserId))).getSingleOrNull();
  }

  /// Import a check-in record from the fingerprint device
  Future<void> importDeviceCheckIn(int employeeId, DateTime timestamp) async {
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);

    // Check if attendance record exists for this day
    final existing =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.equals(day)))
            .getSingleOrNull();

    if (existing != null) {
      // Update only if no check-in yet
      if (existing.checkIn == null) {
        await (update(
          employeeAttendance,
        )..where((a) => a.id.equals(existing.id))).write(
          EmployeeAttendanceCompanion(
            checkIn: Value(timestamp),
            status: const Value('present'),
          ),
        );
      }
    } else {
      await into(employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: employeeId,
          date: day,
          checkIn: Value(timestamp),
          status: const Value('present'),
        ),
      );
    }
  }

  /// Import a check-out record from the fingerprint device
  Future<void> importDeviceCheckOut(int employeeId, DateTime timestamp) async {
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final existing =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.equals(day)))
            .getSingleOrNull();

    if (existing != null) {
      await (update(employeeAttendance)..where((a) => a.id.equals(existing.id)))
          .write(EmployeeAttendanceCompanion(checkOut: Value(timestamp)));
    } else {
      // Create record with just check-out (unusual but possible)
      await into(employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: employeeId,
          date: day,
          checkOut: Value(timestamp),
          status: const Value('present'),
        ),
      );
    }
  }

  // -----------------------------------------------------------------------
  // LEAVE MANAGEMENT
  // -----------------------------------------------------------------------

  /// Watch all leave requests for an employee
  Stream<List<EmployeeLeave>> watchEmployeeLeaves(int employeeId) {
    return (select(employeeLeaves)
          ..where((l) => l.employeeId.equals(employeeId))
          ..orderBy([(l) => OrderingTerm.desc(l.startDate)]))
        .watch();
  }

  /// Watch all pending leave requests (for managers)
  Stream<List<EmployeeLeave>> watchPendingLeaves() {
    return (select(employeeLeaves)
          ..where((l) => l.status.equals('pending'))
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
        .watch();
  }

  /// Request a new leave
  Future<int> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) {
    return into(employeeLeaves).insert(
      EmployeeLeavesCompanion.insert(
        employeeId: employeeId,
        leaveType: leaveType,
        startDate: startDate,
        endDate: endDate,
        days: days,
        notes: Value(notes),
      ),
    );
  }

  /// Approve or reject a leave request
  ///
  /// B4 — الاعتمادُ يكتب **صفوفَ حضورٍ** للفترة، لا يغيّر حالةَ الطلب وحدها.
  /// قبل ذلك كان حسابُ الراتب يعدّ صفوفَ الحضور ولا صفَّ مكتوب، فإجازةٌ سنوية
  /// **معتمدة** سبعةَ أيامٍ تُخصم سبعةَ أيامٍ من الراتب: الموظف يطلب، والمديرُ
  /// يوافق، والنظامُ يعاقبه على موافقةٍ حصل عليها.
  ///
  /// والثلاثة في معاملةٍ واحدة: حالةُ الطلب وصفوفُ الحضور وخصمُ الرصيد. كانت
  /// الحالةُ والرصيدُ منفصلَين، وإضافةُ كتابةٍ ثالثة بلا معاملة تجعل السقوطَ في
  /// الوسط يترك رصيداً مخصوماً بلا أيامٍ مدفوعة — أو العكس.
  Future<void> updateLeaveStatus(
    int leaveId,
    String status,
    int approvedBy,
  ) async {
    return transaction(() async {
      final leave = await (select(
        employeeLeaves,
      )..where((l) => l.id.equals(leaveId))).getSingle();

      await (update(employeeLeaves)..where((l) => l.id.equals(leaveId))).write(
        EmployeeLeavesCompanion(
          status: Value(status),
          approvedBy: Value(approvedBy),
        ),
      );

      // Update leave balance if approved
      if (status == 'approved') {
        await _writeLeaveAttendance(leave);
        await _deductLeaveBalance(
          leave.employeeId,
          leave.leaveType,
          leave.days,
          leave.startDate.year,
        );
      }
    });
  }

  /// B4 — يكتب صفَّ حضورٍ لكلِّ يومٍ تقويميّ في [leave] شاملاً الطرفين.
  ///
  /// **الفترةُ بالتقويم لا بعدّاد `days`**: العدّادُ يخصم الرصيد، والتقويمُ
  /// يحدّد أيَّ أيامٍ تُدفَع. وهما رقمان مختلفان قد يفترقان.
  ///
  /// **upsert لا insert**: قيدُ v152 `idx_employee_attendance_day_dedup` فريدٌ
  /// على (موظف، يوم)، فموظفٌ بصم صباحَ يومٍ ثم اعتُمدت إجازتُه عليه كان إدراجُه
  /// يُرفَض فتسقط المعاملةُ كلُّها. والتحديثُ يمسّ الحالةَ والملاحظة **فقط**،
  /// فيبقى التحضيرُ والانصرافُ المسجَّلان: إثباتُ أنه حضر فعلاً لا يجوز أن يضيع
  /// لأن إجازةً اعتُمدت على نفس اليوم.
  ///
  /// **العدُّ باليوم لا بـ`add(Duration(days: 1))`**: إضافةُ ٢٤ ساعةً عبر حدِّ
  /// التوقيت الصيفي تُنتج الساعةَ ٢٣ من **نفس** اليوم، فيتكرّر يومٌ ويُفقَد
  /// آخر. و`DateTime(y, m, d + i)` يطبّع تجاوزَ الشهر والسنة من نفسه.
  Future<void> _writeLeaveAttendance(EmployeeLeave leave) async {
    final attendanceStatus = kPaidLeaveTypes.contains(leave.leaveType)
        ? kAttendanceStatusPaidLeave
        : kAttendanceStatusUnpaidLeave;
    final note = 'إجازة ${leave.leaveType} معتمدة — طلب #${leave.id}';

    final first = DateTime(
      leave.startDate.year,
      leave.startDate.month,
      leave.startDate.day,
    );
    final last = DateTime(
      leave.endDate.year,
      leave.endDate.month,
      leave.endDate.day,
    );

    for (var i = 0; i < kMaxLeaveDaysPerRequest; i++) {
      final day = DateTime(first.year, first.month, first.day + i);
      if (day.isAfter(last)) break;

      final existing =
          await (select(employeeAttendance)
                ..where((a) => a.employeeId.equals(leave.employeeId))
                ..where((a) => a.date.equals(day)))
              .getSingleOrNull();

      if (existing == null) {
        await into(employeeAttendance).insert(
          EmployeeAttendanceCompanion.insert(
            employeeId: leave.employeeId,
            date: day,
            status: Value(attendanceStatus),
            notes: Value(note),
          ),
        );
      } else {
        await (update(
          employeeAttendance,
        )..where((a) => a.id.equals(existing.id))).write(
          EmployeeAttendanceCompanion(
            status: Value(attendanceStatus),
            notes: Value(note),
          ),
        );
      }
    }
  }

  /// Get leave balance for an employee for a specific year
  Future<List<LeaveBalance>> getLeaveBalances(int employeeId, int year) {
    return (select(leaveBalances)
          ..where((b) => b.employeeId.equals(employeeId))
          ..where((b) => b.year.equals(year)))
        .get();
  }

  /// Initialize leave balance for a new year
  Future<void> initializeLeaveBalances(
    int employeeId,
    int year, {
    int annualDays = 21,
    int sickDays = 15,
    int emergencyDays = 3,
  }) async {
    for (final entry in [
      {'type': 'annual', 'days': annualDays},
      {'type': 'sick', 'days': sickDays},
      {'type': 'emergency', 'days': emergencyDays},
    ]) {
      final existing =
          await (select(leaveBalances)
                ..where((b) => b.employeeId.equals(employeeId))
                ..where((b) => b.leaveType.equals(entry['type'] as String))
                ..where((b) => b.year.equals(year)))
              .getSingleOrNull();

      if (existing == null) {
        await into(leaveBalances).insert(
          LeaveBalancesCompanion.insert(
            employeeId: employeeId,
            leaveType: entry['type'] as String,
            totalDays: entry['days'] as int,
            year: year,
          ),
        );
      }
    }
  }

  Future<void> _deductLeaveBalance(
    int employeeId,
    String leaveType,
    int days,
    int year,
  ) async {
    final balance =
        await (select(leaveBalances)
              ..where((b) => b.employeeId.equals(employeeId))
              ..where((b) => b.leaveType.equals(leaveType))
              ..where((b) => b.year.equals(year)))
            .getSingleOrNull();

    if (balance != null) {
      await (update(
        leaveBalances,
      )..where((b) => b.id.equals(balance.id))).write(
        LeaveBalancesCompanion(usedDays: Value(balance.usedDays + days)),
      );
    }
  }

  // -----------------------------------------------------------------------
  // OVERTIME
  // -----------------------------------------------------------------------

  /// Watch overtime records for an employee in a date range
  Stream<List<OvertimeRecord>> watchEmployeeOvertime(
    int employeeId,
    DateTime start,
    DateTime end,
  ) {
    return (select(overtimeRecords)
          ..where((o) => o.employeeId.equals(employeeId))
          ..where((o) => o.date.isBiggerOrEqual(Variable(start)))
          ..where((o) => o.date.isSmallerThan(Variable(end)))
          ..orderBy([(o) => OrderingTerm.desc(o.date)]))
        .watch();
  }

  /// Add overtime record
  Future<int> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    double rate = 1.5,
    String? notes,
  }) async {
    final employee = await (select(
      employees,
    )..where((e) => e.id.equals(employeeId))).getSingle();
    // الأجر بالساعة مشتقٌّ من الأجر اليومي **لشهر السجل نفسه**، فساعةٌ إضافية
    // في فبراير تُقاس على ٢٨ يوماً لا ٣٠. لو ظلّ المقام ٣٠ هنا بعد إصلاح الأجر
    // اليومي، لصارت ساعة الموظف الإضافية أرخص من ساعته العادية في كل شهر أقصر
    // من ٣٠ يوماً — تناقضٌ داخلي بين مسارَي الأجر نفسه.
    final hourlyRate = employee.salary /
        _daysInMonth(date.year, date.month) /
        kStandardWorkHoursPerDay;
    final amount = hours * hourlyRate * rate;

    return into(overtimeRecords).insert(
      OvertimeRecordsCompanion.insert(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: Value(rate),
        amount: amount,
        notes: Value(notes),
      ),
    );
  }

  /// Get total overtime amount for a month
  Future<double> getMonthlyOvertimeAmount(
    int employeeId,
    int year,
    int month,
  ) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final records =
        await (select(overtimeRecords)
              ..where((o) => o.employeeId.equals(employeeId))
              ..where((o) => o.date.isBiggerOrEqual(Variable(startOfMonth)))
              ..where((o) => o.date.isSmallerThan(Variable(endOfMonth))))
            .get();

    return records.fold<double>(0, (sum, r) => sum + r.amount);
  }

  // -----------------------------------------------------------------------
  // FINGERPRINT DEVICES CRUD
  // -----------------------------------------------------------------------

  /// Watch all registered fingerprint devices
  Stream<List<FingerprintDevice>> watchFingerprintDevices() {
    return (select(fingerprintDevices)
          ..where((d) => d.isActive.equals(true))
          ..orderBy([(d) => OrderingTerm.asc(d.name)]))
        .watch();
  }

  /// Add a new fingerprint device
  Future<int> addFingerprintDevice({
    required String name,
    required String ipAddress,
    int port = 4370,
    String? serialNumber,
    String? model,
  }) {
    return into(fingerprintDevices).insert(
      FingerprintDevicesCompanion.insert(
        name: name,
        ipAddress: ipAddress,
        port: Value(port),
        serialNumber: Value(serialNumber),
        model: Value(model),
      ),
    );
  }

  /// Update fingerprint device last sync time
  Future<void> updateDeviceLastSync(int deviceId) {
    return (update(fingerprintDevices)..where((d) => d.id.equals(deviceId)))
        .write(FingerprintDevicesCompanion(lastSync: Value(DateTime.now())));
  }

  // -----------------------------------------------------------------------
  // PERFORMANCE REVIEWS
  // -----------------------------------------------------------------------

  /// Watch all performance reviews for an employee
  Stream<List<PerformanceReview>> watchEmployeeReviews(int employeeId) {
    return (select(performanceReviews)
          ..where((r) => r.employeeId.equals(employeeId))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .watch();
  }

  /// Get all performance reviews
  Future<List<PerformanceReview>> getAllReviews() {
    return (select(performanceReviews)
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }

  /// Add a performance review
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
  }) {
    final overall =
        ((commitmentScore + productivityScore + qualityScore + teamworkScore) /
                4)
            .round();
    return into(performanceReviews).insert(
      PerformanceReviewsCompanion.insert(
        employeeId: employeeId,
        period: period,
        periodType: Value(periodType),
        commitmentScore: Value(commitmentScore),
        productivityScore: Value(productivityScore),
        qualityScore: Value(qualityScore),
        teamworkScore: Value(teamworkScore),
        overallRating: Value(overall),
        reviewerNotes: Value(reviewerNotes),
        reviewedBy: Value(reviewedBy),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // PERFORMANCE GOALS
  // -----------------------------------------------------------------------

  /// Watch goals for an employee
  Stream<List<PerformanceGoal>> watchEmployeeGoals(int employeeId) {
    return (select(performanceGoals)
          ..where((g) => g.employeeId.equals(employeeId))
          ..orderBy([(g) => OrderingTerm.desc(g.createdAt)]))
        .watch();
  }

  /// Add a performance goal
  Future<int> addPerformanceGoal({
    required int employeeId,
    required String goalDescription,
    required DateTime targetDate,
    int weight = 1,
    String? notes,
  }) {
    return into(performanceGoals).insert(
      PerformanceGoalsCompanion.insert(
        employeeId: employeeId,
        goalDescription: goalDescription,
        targetDate: targetDate,
        weight: Value(weight),
        notes: Value(notes),
      ),
    );
  }

  /// Update goal progress
  Future<void> updateGoalProgress(int goalId, int progress, String status) {
    return (update(performanceGoals)..where((g) => g.id.equals(goalId))).write(
      PerformanceGoalsCompanion(
        progressPercent: Value(progress),
        status: Value(status),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // EMPLOYEE CONTRACTS
  // -----------------------------------------------------------------------

  /// Watch all contracts for an employee
  Stream<List<EmployeeContract>> watchEmployeeContracts(int employeeId) {
    return (select(employeeContracts)
          ..where((c) => c.employeeId.equals(employeeId))
          ..orderBy([(c) => OrderingTerm.desc(c.startDate)]))
        .watch();
  }

  /// Get active contract for an employee
  Future<EmployeeContract?> getActiveContract(int employeeId) {
    return (select(employeeContracts)
          ..where((c) => c.employeeId.equals(employeeId))
          ..where((c) => c.status.equals('active'))
          ..orderBy([(c) => OrderingTerm.desc(c.startDate)]))
        .getSingleOrNull();
  }

  /// Get contracts expiring within N days
  Future<List<EmployeeContract>> getExpiringContracts(int withinDays) async {
    final now = DateTime.now();
    final deadline = now.add(Duration(days: withinDays));
    return (select(employeeContracts)
          ..where((c) => c.status.equals('active'))
          ..where((c) => c.endDate.isSmallerOrEqual(Variable(deadline)))
          ..where((c) => c.endDate.isBiggerOrEqual(Variable(now)))
          ..orderBy([(c) => OrderingTerm.asc(c.endDate)]))
        .get();
  }

  /// Add a new contract
  Future<int> addEmployeeContract({
    required int employeeId,
    required String contractType,
    required DateTime startDate,
    DateTime? endDate,
    required double salary,
    String? benefits,
    String? terminationClause,
    String? notes,
  }) {
    return into(employeeContracts).insert(
      EmployeeContractsCompanion.insert(
        employeeId: employeeId,
        contractType: Value(contractType),
        startDate: startDate,
        endDate: Value(endDate),
        salary: salary,
        benefits: Value(benefits),
        terminationClause: Value(terminationClause),
        notes: Value(notes),
      ),
    );
  }

  /// Terminate/expire a contract
  Future<void> updateContractStatus(int contractId, String status) {
    return (update(employeeContracts)
          ..where((c) => c.id.equals(contractId)))
        .write(EmployeeContractsCompanion(status: Value(status)));
  }
}

class EmployeeAttendanceWithDetails {
  final EmployeeAttendanceData attendance;
  final Employee employee;

  EmployeeAttendanceWithDetails({
    required this.attendance,
    required this.employee,
  });
}

/// Salary calculation result
class EmployeeSalaryCalculation {
  final Employee employee;
  final double baseSalary;
  final double dailyRate;
  final int daysAttended;
  final double grossPay;
  final double totalAdvances;
  final double totalDeductions;
  final double overtimeAmount;
  final double netSalary;
  final int month;
  final int year;

  EmployeeSalaryCalculation({
    required this.employee,
    required this.baseSalary,
    required this.dailyRate,
    required this.daysAttended,
    required this.grossPay,
    required this.totalAdvances,
    required this.totalDeductions,
    this.overtimeAmount = 0,
    required this.netSalary,
    required this.month,
    required this.year,
  });
}
