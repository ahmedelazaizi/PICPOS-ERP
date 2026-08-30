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

/// B4 — أنواعُ الإجازات المدفوعة: تُحتسب حضوراً في حساب الراتب.
///
/// المجالُ المدعوم لـ`EmployeeLeaves.leaveType` هو `annual` · `sick` ·
/// `unpaid` · `emergency`. المدفوعُ منها ثلاثة، و`unpaid` مستثنى بحكم اسمه:
/// يومٌ بلا أجر. فلا يصحّ تعميمُ «كلُّ إجازةٍ معتمدة مدفوعة» — التعميم يدفع
/// أجراً عن أيامٍ اتُّفق صراحةً على ألّا تُدفَع.
const Set<String> kPaidLeaveTypes = {'annual', 'sick', 'emergency'};

/// حالةُ صفِّ الحضور لإجازةٍ مدفوعة معتمدة.
const String kAttendanceStatusPaidLeave = 'leave';

/// أقصى امتدادٍ زمنيٍّ تُعدُّ فيه بصمةُ انصرافٍ **تابعةً** لتحضيرٍ سابق.
///
/// تُستعمل في [HrExtensions.importDeviceCheckOut] لضمِّ ورديةٍ تعبر منتصفَ
/// الليل في صفٍّ واحد. وهي **حدٌّ أعلى لا تعريفُ ورديّة**: ما تجاوزها ليس
/// ورديّةً ممتدّةً بل بصمةُ انصرافٍ ضاع تحضيرُها — وضمُّها كان سيلصق يومَين
/// لا علاقةَ بينهما ويُنتج «ورديّةً» بطول ثلاثين ساعة.
///
/// ستَّ عشرةَ ساعةً تغطّي أطولَ ورديّةٍ واقعيّةٍ (‏١٢ ساعة + تأخّرُ انصراف)
/// وتقصر دون أقصرِ فجوةٍ بين ورديّتَين مستقلّتَين.
const Duration kMaxShiftSpan = Duration(hours: 16);

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

/// غيابٌ يعلّمه المدير — يومٌ غيرُ مدفوعٍ **مسجَّل**.
const String kAttendanceStatusAbsent = 'absent';

/// حالاتُ صفِّ الحضور التي تُخصم من **الراتب الشهري**.
///
/// `unpaid_leave` معها لا وحدَها `absent`: لو خُصم الغيابُ وحده لصارت الإجازةُ
/// غيرُ المدفوعةِ المعتمدة مدفوعةً بحكم الأمر الواقع، لأن الشهريَّ يُدفَع كاملاً
/// ما لم يُخصَم صراحةً.
const Set<String> kUnpaidAttendanceStatuses = {
  kAttendanceStatusAbsent,
  kAttendanceStatusUnpaidLeave,
};

/// نوعُ الراتب الذي يُدفَع كاملاً ويُخصم منه الغيابُ المسجَّل.
///
/// قرار المالك 2026-08-09. المجالُ المدعوم لـ`employees.salaryType` هو
/// `monthly` · `daily` · `hourly`، وكان المحرّكُ **لا يقرأ العمود إطلاقاً**
/// فيطبّق موديلَ الأجر اليومي على الثلاثة: `daysAttended × dailyRate`. ويومُ
/// الراحة لا صفَّ حضورٍ له، فكان الشهريُّ يُخصَم عن أيام راحته.
///
/// ⚠️ `hourly` باقٍ على موديل اليوم ولم يُحسَم بعد: `employees.salary` نفسه
/// غامضٌ لهذا النوع (شهريٌّ مكافئ أم أجرُ ساعة؟) ولا شيء في السكيما يحسمه،
/// و`checkIn`/`checkOut` موجودان فالساعاتُ مشتقّةٌ لو تقرّر ذلك.
const String kMonthlySalaryType = 'monthly';

/// نوعُ الأجر بالساعة — الأساسيُّ = ساعاتُ الحضور الفعلية × أجرُ الساعة
/// ([hourlyRateFor])، لا يومٌ كاملٌ بصرف النظر عن طول الحضور.
///
/// قرار المالك 2026-08-09. صفُّ حضورٍ بلا `checkOut` لا يحتسب ساعات: المدةُ
/// مجهولة، والاتجاهُ الآمن أن تُوثَّق لا أن تُخمَّن.
const String kHourlySalaryType = 'hourly';

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
    double? hoursPerDay,
  }) {
    // ساعاتُ اليوم مقامُ أجر الساعة. وموظفُ `hourly` بدونها تجهيزةٌ ناقصة
    // تُفشل حسابَ راتبه، والمنعُ عند الإدخال أرخصُ وأوضحُ من اكتشافه في كشف.
    if (salaryType == kHourlySalaryType &&
        (hoursPerDay == null || hoursPerDay <= 0)) {
      throw ArgumentError('ساعاتُ العمل اليومية مطلوبةٌ لموظفٍ بأجر الساعة');
    }
    return into(employees).insert(
      EmployeesCompanion.insert(
        name: name,
        phone: Value(phone),
        role: Value(role),
        salary: Value(salary),
        salaryType: Value(salaryType),
        branchId: Value(branchId),
        hoursPerDay: Value(hoursPerDay),
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
    double? hoursPerDay,
  }) async {
    // نفسُ حارسِ `addEmployee`، لكن `salaryType` هنا معاملٌ اختياريّ:
    // `null` يعني «النوعُ لم يتغيّر» لا «ليس hourly». فالحكمُ على النوع
    // **الفعليّ** بعد هذا التحديث — ولو لم يُمرَّر فمصدرُه الصفُّ القائم، لا
    // افتراضٌ. وكذلك [hoursPerDay]: غيابُه هنا يعني «لم يتغيّر» فقد تكفي
    // الساعاتُ المخزَّنةُ سلفاً.
    Employee? current;
    Future<Employee> loadCurrent() async =>
        current ??= await (select(employees)..where((e) => e.id.equals(id)))
            .getSingle();

    final effectiveSalaryType = salaryType ?? (await loadCurrent()).salaryType;
    if (effectiveSalaryType == kHourlySalaryType) {
      final effectiveHours = hoursPerDay ?? (await loadCurrent()).hoursPerDay;
      if (effectiveHours == null || effectiveHours <= 0) {
        throw ArgumentError('ساعاتُ العمل اليومية مطلوبةٌ لموظفٍ بأجر الساعة');
      }
    }

    await (update(employees)..where((e) => e.id.equals(id))).write(
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
        hoursPerDay:
            hoursPerDay != null ? Value(hoursPerDay) : const Value.absent(),
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

  /// يعلّم يوماً غياباً غيرَ مدفوع.
  ///
  /// المدخلُ الوحيدُ للخصم من الراتب الشهري: الشهريُّ يُدفَع كاملاً ما لم
  /// يُسجَّل غيابُه هنا. فالعبءُ على من يريد الخصمَ أن يوثّقه — لا على الموظف
  /// أن يُثبت أنه حضر.
  ///
  /// **upsert لا insert** لقيد v152 `idx_employee_attendance_day_dedup`: اليومُ
  /// قد يكون فيه صفُّ بصمةٍ سابق، فالإدراجُ يُرفَض. وتعليمُ المدير هو الأحدث
  /// فهو الحاكم — لكن التحضيرَ والانصرافَ المسجَّلَين يبقيان: إن كان الغيابُ
  /// خطأً فالإثباتُ لم يضِع.
  Future<void> markEmployeeAbsent(
    int employeeId,
    DateTime date, {
    String? notes,
  }) async {
    final day = DateTime(date.year, date.month, date.day);

    final existing =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.equals(day)))
            .getSingleOrNull();

    if (existing == null) {
      await into(employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: employeeId,
          date: day,
          status: const Value(kAttendanceStatusAbsent),
          notes: Value(notes),
        ),
      );
    } else {
      await (update(
        employeeAttendance,
      )..where((a) => a.id.equals(existing.id))).write(
        EmployeeAttendanceCompanion(
          status: const Value(kAttendanceStatusAbsent),
          notes: notes != null ? Value(notes) : const Value.absent(),
        ),
      );
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

  /// أجرُ الساعة لموظفٍ في شهرٍ بعينه — **المصدرُ الوحيد**.
  ///
  ///     الراتب الشهري ÷ (ساعاتُ اليوم × أيامِ العمل في ذلك الشهر)
  ///
  /// يستعمله مسارُ الراتب ومسارُ الإضافي معاً. وكان الإضافيُّ يشتقّه محلياً
  /// بمقامٍ خاطئ — `_daysInMonth` (أيامُ التقويم) و٨ ساعاتٍ مثبّتة — فساعةُ
  /// الموظف الإضافية كانت أرخص مما تستحق بنحو ١٥٪ في شهرٍ بأربع عطلات.
  ///
  /// **لا يُقرَّب الناتج**: التقريبُ هنا يتراكم على عشرات الساعات، والتقريبُ
  /// موضعُه الناتجُ النهائيّ وحده.
  Future<double> hourlyRateFor(Employee employee, int year, int month) async {
    final hours = employee.hoursPerDay;
    if (hours == null || hours <= 0) {
      throw StateError(
          'ساعاتُ العمل اليومية غيرُ محدَّدة للموظف ${employee.id} — '
          'لا يمكن اشتقاقُ أجر الساعة');
    }
    final days = await workingDaysInMonth(year, month,
        branchId: employee.branchId);
    if (days <= 0) {
      throw StateError(
          'لا أيامَ عملٍ في $month/$year لفرع الموظف ${employee.id} — '
          'راجع تقويمَ العطلات');
    }
    return employee.salary / (hours * days);
  }

  /// Record salary payment
  Future<int> recordSalaryPayment({
    required int employeeId,
    required double amount,
    required String period, // e.g., "2023-10"
    String type = 'salary',
    String? notes,
    double? payableAmount,
    double advancesSettled = 0,
  }) async {
    // ── B3 — حارسُ الثابت، **قبل** فتحِ المعاملة ────────────────────────────
    // قيدُ اليومية ملفوفٌ في `try/catch` يبتلع الفشل بـ`debugPrint`. فقيدٌ
    // مختلٌّ يرفضه حارسُ التوازن، ويُبتلَع الرفض، ويُصرَف الراتبُ **بلا قيدٍ
    // إطلاقاً** بصمت — والخزنةُ تنقص والدفاترُ لا تعلم. فلا يجوز الاتّكال على
    // حارسِ التوازن هنا؛ الثابتُ يُفحَص صراحةً وقبل أيّ كتابة.
    if (advancesSettled < 0) {
      throw ArgumentError.value(
        advancesSettled,
        'advancesSettled',
        'السلفُ المسوّاة لا تكون سالبة',
      );
    }
    if (payableAmount == null && advancesSettled > 0) {
      throw ArgumentError(
        'تسويةُ سلفٍ بلا `payableAmount` — المصروفُ المُعترَف به غيرُ معلوم '
        'فالقيدُ لا يمكن أن يتوازن.',
      );
    }
    if (payableAmount != null &&
        (payableAmount - (amount + advancesSettled)).abs() > 0.01) {
      throw ArgumentError(
        'أرقامُ الراتب غيرُ متّسقة: المستحقُّ ($payableAmount) لا يساوي '
        'الصافي ($amount) + السلفَ المسوّاة ($advancesSettled). '
        'مصدرُ الأرقام الوحيدُ هو `calculateNetSalary`.',
      );
    }

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
      //
      // ── المخرجُ الصامتُ الأوّل: بلا خزنة ────────────────────────────────
      //
      // 🔴 كان `if (safe != null) { … }` يلفّ **كلَّ** الأثر الماليّ: سندَ
      // الخزنة، وخصمَ الرصيد، والقيدَ المحاسبيّ. فحين لا تُحلّ خزنةٌ نقديّةٌ
      // نشِطة كان الصفُّ في `salary_payments` يُكتَب ويُرجَع مُعرِّفُه —
      // «مدفوع» في شاشة الرواتب، وصفرٌ في الخزنة، وصفرٌ في الأستاذ.
      //
      // والأسوأُ أنّ الحالةَ **لا تُصلَح**: فهرسٌ فريدٌ
      // (`idx_salary_payments_period_dedup` على موظف+فترة+نوع) وحارسٌ في
      // الكود يمنعان إعادةَ الصرف، ولا مسارَ إلغاءٍ لسندِ راتبٍ في المستودع
      // كلِّه — فالفترةُ تصير غيرَ قابلةٍ للدفع ولا للتقييد إلى الأبد، ثمّ
      // تُقفَل على هذا الخطأ (‏`closeAccountingPeriod` لا تفحص رواتبَ بلا
      // قيد).
      //
      // فالفشلُ صريحٌ الآن، والدالّةُ كلُّها داخل معاملةٍ واحدة ⇒ الصفُّ
      // يُلغى والإعادةُ ممكنة. وهذا عينُ ما يفعله
      // `operational_expenses_dao` للحالة نفسِها منذ B7.
      final safe = await getDefaultSafeByType('cash');
      if (safe == null) {
        throw StateError(
          'لا توجد خزنة نقدية نشطة — لا يمكن صرفُ الراتب بلا حركةِ خزنة '
          'ولا قيدٍ محاسبيّ. أنشئ خزنةً نقديّةً وأعِد المحاولة.',
        );
      }
      {
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

        // H15 — خصمٌ ذرّيّ. (مسارُ الأجور خارجَ نطاق PicPos lite ومسيَّجٌ
        // بـ`features.hrEnabled`؛ صُحِّح الحسابُ ولم يُفعَّل شيء.)
        await adjustSafeBalance(safe.id, -amount);

        // Link transaction to salary payment
        await (update(salaryPayments)..where((p) => p.id.equals(id))).write(
          SalaryPaymentsCompanion(treasuryTransactionId: Value(transId)),
        );

        // ── B3 — حسابُ سلف الموظفين، **قبل** الـtry الذي يبتلع الفشل ────────
        // لو احتاج القيدُ سطرَ تسويةٍ وتعذّر الحسابُ، فإسقاطُ السطر يُنتج قيداً
        // مختلاًّ يرفضه الحارسُ ويُبتلَع الرفض ⇒ لا قيدَ إطلاقاً و١١٤٦ لا
        // يُقيَّد عليه دائنٌ — أي العطلُ نفسه يعود من بابٍ آخر. فالفشلُ صريح.
        Account? advanceAcc;
        if (advancesSettled > 0) {
          final advanceCode = await getMappedAccountCode(
            'employee_advances',
            AccountingDao.accountPurposes['employee_advances']!,
          );
          advanceAcc = await getAccountByCode(advanceCode);
          if (advanceAcc == null) {
            throw StateError(
              'حساب سلف الموظفين ($advanceCode) غير موجود، وتسويةُ '
              '$advancesSettled لا يمكن تقييدُها. صحّح شجرةَ الحسابات أولاً.',
            );
          }
        }

        // GAP-HR-JE: Auto-post GL journal entry for salary disbursement
        //
        // B3 — القيدُ ثلاثيّ لا ثنائيّ:
        //   مدين  مصروف الرواتب ٦٢١  = المستحقّ (الإجمالي − الجزاءات)
        //   دائن  النقدية ١١١١       = الصافي (ما خرج من الخزنة فعلاً)
        //   دائن  سلف الموظفين ١١٤٦  = السلفُ المسوّاة
        //
        // كان يُدَبِّن **الصافي**، فيُبلَّغ المصروفُ أقلَّ من حقيقته بقيمة السلف،
        // و١١٤٦ لا يُقيَّد عليه دائنٌ قطّ فيتضخّم للأبد: السلفةُ تُدَبَّن حين
        // تُصرَف ولا تُدَيَّن حين تُسدَّد، فتظلّ ظاهرةً أصلاً بعد سدادها.
        //
        // وسطرُ الصفر يُحجَب: صافٍ بصفرٍ (سلفةٌ استوعبت المستحقَّ كلَّه) لا يعني
        // حركةَ نقدٍ، وسطرٌ بصفرٍ يشوّش سجلَّ الحساب بلا معنى.
        final expenseAmount = payableAmount ?? amount;
        {
          final salaryAccCode = await getMappedAccountCode(
            'salary_expense',
            AccountingDao.accountPurposes['salary_expense']!,
          );
          final cashAccCode = await getMappedAccountCode(
            'cash',
            AccountingDao.accountPurposes['cash']!,
          );
          final salaryAcc = await getAccountByCode(salaryAccCode);
          final cashAcc = await getAccountByCode(cashAccCode);

          // ── المخرجان الصامتان الثاني والثالث ─────────────────────────────
          //
          // 🔴 (٢) كان `if (salaryAcc != null && cashAcc != null)` **بلا
          // `else`**. و`getMappedAccountCode` لا تُرجع null أبداً (‏تسقط إلى
          // `621`/`1111`)، فالفرعُ يقع حين يغيب ذلك الكودُ من شجرة الحسابات —
          // محاسبٌ أعاد هيكلةَ الشجرة، أو بذرةٌ ناقصة. والنقدُ **كان قد خرج
          // بالفعل** قبل عشرين سطراً (`adjustSafeBalance`)، فالنتيجةُ خزنةٌ
          // ناقصةٌ وأستاذٌ صامت.
          //
          // 🔴 (٣) وكان الكلُّ ملفوفاً بـ`try { … } catch (e) { debugPrint }`.
          // و`createJournalEntry` ترمي على: فترةٍ ماليّةٍ مقفلة، أو سنةٍ
          // ماليّةٍ غائبة، أو قيدٍ غيرِ متوازن، أو حسابٍ غيرِ قابلٍ للترحيل —
          // وكلُّها كانت تصير سطرَ `debugPrint` بينما النقدُ خرج. أي أنّ
          // أكثرَ أسبابِ الفشل شيوعاً (‏صرفُ راتبِ فبراير في مارس بعد إقفال
          // مارس) كان يُنتج بالضبط: نقصٌ في الخزنة، وصفرٌ في الأستاذ، وفترةٌ
          // لا تقبل إعادةَ الصرف.
          //
          // كلاهما صريحٌ الآن. والمعاملةُ الواحدةُ تُرجِع كلَّ شيءٍ عند الرمي:
          // لا صفَّ راتبٍ، ولا حركةَ خزنة، ولا رصيدَ منقوص — والإعادةُ ممكنة.
          if (salaryAcc == null || cashAcc == null) {
            final missing = [
              if (salaryAcc == null) 'مصروف الرواتب ($salaryAccCode)',
              if (cashAcc == null) 'النقدية ($cashAccCode)',
            ].join(' و');
            throw StateError(
              'حساب $missing غير موجود في شجرة الحسابات — لا يمكن تقييدُ '
              'صرفِ الراتب. صحّح شجرةَ الحسابات وأعِد المحاولة.',
            );
          }

          {
            await createJournalEntry(
              description: 'صرف راتب — فترة $period',
              date: DateTime.now(),
              lines: [
                JournalLine(
                  accountId: salaryAcc.id,
                  debit: expenseAmount,
                  description: 'مصروف الرواتب',
                ),
                if (amount > 0)
                  JournalLine(
                    accountId: cashAcc.id,
                    credit: amount,
                    description: 'صرف نقدي من الصندوق',
                  ),
                if (advanceAcc != null)
                  JournalLine(
                    accountId: advanceAcc.id,
                    credit: advancesSettled,
                    description: 'تسوية سلف الموظف من راتب $period',
                  ),
              ],
              referenceType: 'salary_payment',
              referenceId: id,
              isAutoPosted: true,
            );
          }
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
          // H15 — خصمُ سلفةٍ ذرّيّ. (خارجَ نطاق lite، مسيَّجٌ بـhrEnabled.)
          await adjustSafeBalance(targetSafe.id, -amount);
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

    // (‏`daysAttended` يُحسَب بعد جلب العطلات — يرشّحها كما يرشّحها المقام.)

    // الأيامُ غيرُ المدفوعة **المسجَّلة** — أساسُ خصمِ الراتب الشهري.
    // تُقرأ من الجدول لا تُستنتج من غياب الصفوف: يومُ الراحة لا صفَّ له كذلك،
    // والاستنتاجُ كان يخصمه.
    final unpaidRecords =
        await (select(employeeAttendance)
              ..where((a) => a.employeeId.equals(employeeId))
              ..where((a) => a.date.isBiggerOrEqual(Variable(startOfMonth)))
              ..where((a) => a.date.isSmallerThan(Variable(endOfMonth)))
              ..where(
                (a) => a.status.isIn(kUnpaidAttendanceStatuses.toList()),
              ))
            .get();

    // التقويمُ يسري على الجميع (قرار المالك 2026-08-09، مواصفة الأجر
    // بالساعة): يومُ العطلة لا يُعدّ غياباً — حتى لو سُجِّل له صفُّ «absent»
    // خطأً أو بأثرٍ رجعي.
    final holidays = await holidaysInMonth(year, month,
        branchId: employee.branchId);
    final unpaidDays = unpaidRecords
        .where((r) => !holidays.contains(
            DateTime(r.date.year, r.date.month, r.date.day)))
        .length;

    // ── البسطُ يُرشَّح كما يُرشَّح المقام ────────────────────────────────────
    //
    // ⚠️ كان `daysAttended = attendanceRecords.length` — عدَّ صفوفٍ خام.
    // و`_writeLeaveAttendance` توثِّق نفسَها بأنّها تكتب صفّاً **لكلِّ يومٍ
    // تقويميّ** في الإجازة المعتمدة، فتشمل العطلاتِ الواقعةَ داخلها. فما
    // دام المقامُ صار أيّامَ عملٍ (‏تستثني العطلات) وجب أن يستثنيَها البسطُ
    // كذلك، وإلّا زاد الراتبُ عن نفسه: إجازةُ ٧ أيّامٍ تعبر جمعةً واحدةً
    // تُنتج ٢٨ صفّاً على مقامِ ٢٧ ⇒ **١٠٣٫٧٪** من الراتب.
    //
    // و`unpaidDays` أعلاه يرشّح العطلاتِ منذ 2026-08-09 — فالطرفان الآن
    // متماثلان، وهذا شرطُ صحّةِ إصلاح المقام لا تحسينٌ مستقلّ.
    final daysAttended = attendanceRecords
        .where((r) => !holidays.contains(
            DateTime(r.date.year, r.date.month, r.date.day)))
        .length;

    // Get advances and deductions
    final advances = await getMonthlyAdvances(employeeId, year, month);
    final deductions = await getMonthlyDeductions(employeeId, year, month);

    // Get overtime total
    final overtimeAmount = await getMonthlyOvertimeAmount(
      employeeId,
      year,
      month,
    );

    // ── مقامٌ واحدٌ صحيح: أيّامُ العمل ─────────────────────────────────────
    //
    // 🔴 كان `employee.salary / _daysInMonth(year, month)` — **أيّامُ
    // التقويم**. والبسطُ في كلِّ استعمالاته أيّامُ عمل: `daysAttended` يأتي
    // من بصمةٍ أو تحضيرٍ (‏ولا أحدَ يبصم في العطلة)، و`unpaidDays` يستثني
    // العطلاتِ صراحةً. فخلطُ مقامٍ تقويميٍّ ببسطٍ عمليٍّ ينقص الراتبَ بنسبة
    // العطلات في كلِّ شهر:
    //
    //   • يوميّ، راتب ٣٠٠٠، شهرٌ ٣١ يوماً بأربع عطلاتٍ أسبوعيّة، حضورٌ كامل:
    //     ٣٠٠٠ ÷ ٣١ × ٢٧ = **٢٦١٢٫٩٠** — نقصُ ١٢٫٩٪ بلا غيابٍ واحد.
    //   • شهريّ، غيابٌ كاملُ الشهر: ٣٠٠٠ − ٩٦٫٧٧×٢٧ = **٣٨٧٫١٠** بدل صفر.
    //
    // و`hourlyRateFor` كانت على المقام الصحيح (`workingDaysInMonth`) منذ
    // البداية — فالمحرّكُ كان يحمل مقامَين متناقضَين في دالّتَين متجاورتين.
    //
    // ويُشتقّ العددُ من `holidays` المحسوبة أعلاه بدل استعلامٍ ثانٍ:
    // `workingDaysInMonth` تحسبها بنفس الطريقة (‏أيّامُ الشهر − العطلات).
    final calendarDays = _daysInMonth(year, month);
    final workingDays = calendarDays - holidays.length;
    if (workingDays <= 0) {
      // حارسُ صفرٍ على شاكلة [hourlyRateFor]: بدونه يصير الأجرُ اليوميُّ
      // `Infinity` أو `NaN` ويُطبَع على قسيمة الراتب.
      throw StateError(
        'لا أيامَ عملٍ في $month/$year لفرع الموظف $employeeId — '
        'راجِع جدولَ العطلات قبل احتساب الراتب',
      );
    }
    final dailyRate = employee.salary / workingDays;

    // ساعاتُ الحضور الفعلية — صفٌّ بلا انصرافٍ لا يُحتسب: مدةٌ مجهولة
    // تُوثَّق ولا تُخمَّن.
    //
    // ── قرار المالك 2026-08-09 — سدُّ فجوة B4 لموظف الساعة ─────────────────
    // إجازةٌ مدفوعةٌ معتمدة (‏[kAttendanceStatusPaidLeave]) لا تحمل بصمةً
    // عادةً، فكانت تُسهم بصفر ساعات ⇒ موظفُ الساعة لا يُدفَع عن إجازةٍ وافق
    // عليها مديرُه — يناقض B4 الموثَّق أعلاه لـ[kPaidAttendanceStatuses].
    // فيومُ الإجازة المدفوعة يُحتسب [Employee.hoursPerDay] ساعةً كاملة، **لا**
    // مجموعاً مع أيّ بصمةٍ مسجَّلة على نفس الصف (فلا ازدواج). والغيابُ
    // والإجازةُ غيرُ المدفوعة أصلاً خارج `attendanceRecords` — الاستعلامُ
    // أعلاه يحصرها بـ[kPaidAttendanceStatuses] — فتُسهم بصفرٍ بالبناء بلا
    // حاجةٍ لفرعٍ صريح هنا.
    final hoursWorked = attendanceRecords.fold<double>(0, (sum, a) {
      if (a.status == kAttendanceStatusPaidLeave) {
        return sum + (employee.hoursPerDay ?? 0);
      }
      final inAt = a.checkIn, outAt = a.checkOut;
      if (inAt == null || outAt == null) return sum;
      // ⚠️ **مدّةٌ سالبةٌ لا تُجمَع.** صفٌّ انصرافُه قبل تحضيره ليس عملاً
      // بالسالب — هو صفٌّ مشوَّه (‏وردية ليلٍ سُجِّل طرفاها على نفس اليوم
      // التقويميّ). وجمعُه كان يطرح ١٦ ساعةً من إجماليّ الشهر، فعشرون ليلةً
      // متتاليةً تُنتج **−٣٠٤ ساعة** ⇒ صافياً سالباً يُقصَر إلى صفر، وزرُّ
      // الصرف يُعطَّل (`payroll_tab` يشترط `netSalary > 0`) — فموظفُ
      // الساعة لا يمكن دفعُه أصلاً.
      // وهذه طبقةٌ ثانيةٌ لا علاجٌ للجذر: الجذرُ في `importDeviceCheckOut`.
      if (!outAt.isAfter(inAt)) return sum;
      return sum + outAt.difference(inAt).inMinutes / 60.0;
    });

    // ── الموديلُ بحسب `salaryType` (قرار المالك 2026-08-09) ─────────────────
    // كان موديلٌ واحد — أجرٌ يومي — يُطبَّق على الأنواع الثلاثة، و`salaryType`
    // لا يُقرأ إطلاقاً. فالشهريُّ كان يُخصَم عن أيام راحته: أيامُ العمل تأتي من
    // بصمةٍ أو تحضيرٍ يدوي، ويومُ الراحة لا أحد يبصم فيه ⇒ لا صفَّ ⇒ لا أجر.
    // موظفٌ بـ٢٨٠٠ وأسبوعُ عملٍ من خمسة أيام كان يأخذ ٢٢٠٠ — خصمُ ٢١٪ بلا
    // غيابٍ واحد، وصفراً في فرعٍ بلا جهاز بصمة.
    //
    //   شهري : الراتبُ كاملاً − (الأجرُ اليومي × الأيامِ غيرِ المدفوعةِ المسجَّلة)
    //   بالساعة : ساعاتُ الحضور الفعلية × أجرُ الساعة (‏[hourlyRateFor]) — لا
    //             يومٌ كاملٌ بصرف النظر عن طول الحضور.
    //   غيرُه (يومي) : الأجرُ اليومي × الأيامِ المدفوعة   ← كما كان
    //
    // والاتجاهُ الآمن مقصود: غيابٌ لم يُسجَّل = لا خصم. فلا يُخصَم من موظفٍ
    // لأن أحداً نسي أن يبصم له، والعبءُ على من يريد الخصمَ أن يوثّقه.
    //
    // وقيدُ v152 يمنع أكثرَ من صفٍّ لليوم، فـ`unpaidDays ≤ أيام الشهر` ⇒
    // الأساسُ لا يهبط تحت الصفر بالبناء.
    final basePay = switch (employee.salaryType) {
      kMonthlySalaryType => employee.salary - dailyRate * unpaidDays,
      kHourlySalaryType =>
        hoursWorked * await hourlyRateFor(employee, year, month),
      _ => dailyRate * daysAttended,
    };

    final grossPay = basePay + overtimeAmount;

    // ── B3 — الاشتقاقُ هنا وحده، فلا يُعاد حسابه في طبقةٍ أخرى ──────────────
    // ثلاثةُ أرقامٍ يحتاجها قيدُ اليومية، وحسابُها في مكانَين يعني انحرافَهما
    // عند أول تعديل — والانحرافُ في قيدٍ يعني دفاترَ مختلّة.
    //
    // `payableAmount` هو ما استحقّه الموظف بعد الجزاءات، وهو **المصروفُ
    // المُعترَف به** (قرار المالك 2026-08-08: الجزاءُ يُنقص المصروف لا يُقيَّد
    // إيراداً — فالموظف استحقّ أقلَّ، وتكلفةُ الأجر انخفضت فعلاً).
    final payableAmount = grossPay - deductions;

    // لا تُسوَّى سلفةٌ أكثر من المستحقّ: سلفةُ ٥٠٠٠ على مستحقٍّ ٢٨٠٠ تُسوّي
    // ٢٨٠٠ ويبقى ٢٢٠٠ أصلاً قائماً في ١١٤٦ — لأنه فعلاً لم يُسدَّد بعد.
    // وبهذا يتحقّق الثابت `payableAmount == netSalary + advancesSettled`
    // **بالبناء**، فحارسُ توازن القيد يمرّ دائماً بلا حسابٍ إضافي.
    final settleable = payableAmount > 0 ? payableAmount : 0.0;
    final advancesSettled = advances < settleable ? advances : settleable;

    // القصُّ يبقى لحالةٍ واحدة فقط: جزاءاتٌ تتجاوز الإجمالي (‏payable سالب).
    // السلفُ لم تعد تُسلِّب الصافي لأن المسوَّى منها محدودٌ بالمستحقّ.
    final netSalary = payableAmount - advancesSettled;

    return EmployeeSalaryCalculation(
      employee: employee,
      baseSalary: employee.salary,
      dailyRate: dailyRate,
      daysAttended: daysAttended,
      grossPay: grossPay,
      totalAdvances: advances,
      totalDeductions: deductions,
      overtimeAmount: overtimeAmount,
      unpaidDays: unpaidDays,
      hoursWorked: hoursWorked,
      payableAmount: payableAmount,
      advancesSettled: advancesSettled,
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
      //
      // ⚠️ **ولا يُكتَب تحضيرٌ بعد انصرافِ نفسِ الصفّ.** الصفوفُ اليتيمةُ
      // التي خلّفها العطلُ القديم (‏انصرافٌ بلا تحضير، من وردياتِ ليلٍ
      // سابقة) كانت تُملأ ببصمةِ الليلة التالية: تحضيرٌ ٢٢:٠٠ فوق انصرافٍ
      // ٠٦:٠٠ على **نفس** اليوم ⇒ مدّةٌ سالبةٌ بستّ عشرةَ ساعة. الصفُّ
      // اليتيمُ لا يُصلَح بلصقِ بصمةٍ لا تخصّه؛ يُترَك كما هو ليُراجَع.
      if (existing.checkIn == null &&
          (existing.checkOut == null ||
              existing.checkOut!.isAfter(timestamp))) {
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
      return;
    }

    // ── وردية تعبر منتصف الليل: صفٌّ واحدٌ لا صفّان ─────────────────────────
    //
    // 🔴 كلُّ بصمةٍ كانت تشتقّ يومَها من طابعها الزمنيّ وحدَه: تحضيرُ ٢٢:٠٠
    // يقع على اليوم «د»، وانصرافُ ٠٦:٠٠ على «د+١». فلا يجد الانصرافُ صفّاً
    // ليومه فيُنشئ **صفّاً ثانياً** بحالة `present` — وردية واحدة، صفّان.
    // وقيدُ v152 الفريدُ على (موظف، يوم) لا يمنعها: اليومان مختلفان.
    //
    // والأثرُ المقيسُ يختلف باختلاف نموذج الأجر، وكلاهما خطأ:
    //   • **يوميّ**: `daysAttended` يعدّ صفّين ⇒ يُدفَع **مرّتين** لوردية.
    //   • **بالساعة**: كلا الصفَّين نصفُ بصمة (‏أحدُهما بلا انصراف والآخرُ
    //     بلا تحضير) فيُسهمان بـ**صفر** ساعة ⇒ لا يُدفَع شيءٌ عن ثماني ساعات.
    //   • وليالٍ متتالية: بصمةُ الليلة التالية تملأ الصفَّ اليتيم، فيصير
    //     التحضيرُ والانصرافُ على **نفس** اليوم بفارقٍ سالب — ٢٠ ليلةً
    //     تُنتج −٣٠٤ ساعة.
    //
    // فالانصرافُ يبحث أوّلاً عن **ورديةٍ مفتوحة**: صفٌّ سابقٌ له تحضيرٌ بلا
    // انصراف، وفارقُه عن هذا الطابع داخل نافذةِ ورديةٍ معقولة. ويُقيَّد
    // الانصرافُ عليه بدل إنشاء صفٍّ جديد.
    //
    // النافذةُ حدٌّ أعلى لا تعريفٌ لوردية: أيُّ فارقٍ أكبرَ منها ليس ورديةً
    // بل بصمةٌ منسيّة، وضمُّها كان سيلصق يومَين لا علاقةَ بينهما.
    final openShiftCutoff = timestamp.subtract(kMaxShiftSpan);
    final openShift = await (select(employeeAttendance)
          ..where((a) => a.employeeId.equals(employeeId))
          ..where((a) => a.date.isSmallerThanValue(day))
          ..where((a) => a.checkIn.isNotNull())
          ..where((a) => a.checkOut.isNull())
          ..where((a) => a.checkIn.isBiggerOrEqualValue(openShiftCutoff))
          ..orderBy([(a) => OrderingTerm.desc(a.date)])
          ..limit(1))
        .getSingleOrNull();

    if (openShift != null) {
      await (update(employeeAttendance)
            ..where((a) => a.id.equals(openShift.id)))
          .write(EmployeeAttendanceCompanion(checkOut: Value(timestamp)));
      return;
    }

    // Create record with just check-out (unusual but possible) — بصمةُ
    // انصرافٍ بلا تحضيرٍ يقابلها في نافذة الوردية. تُوثَّق ولا تُخمَّن.
    await into(employeeAttendance).insert(
      EmployeeAttendanceCompanion.insert(
        employeeId: employeeId,
        date: day,
        checkOut: Value(timestamp),
        status: const Value('present'),
      ),
    );
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
        // كتابةُ الحضور بـupsert على (موظف، يوم) فإعادتُها تُحدّث الصفَّ
        // نفسَه — تُعاد بلا ضرر.
        await _writeLeaveAttendance(leave);

        // 🔴 الخصمُ **تراكميّ**، فلا يُعاد لطلبٍ معتمدٍ سلفاً.
        //
        // كان يُنفَّذ كلَّما نُودِيت الدالةُ بـ`approved` بلا نظرٍ إلى الحالة
        // السابقة، فاعتمادُ طلبٍ معتمدٍ ثانيةً (نقرةٌ مزدوجة · إعادةُ محاولةٍ
        // بعد خطأِ شبكة · مزامنةٌ تُعيد تطبيق الأمر) يخصم ضعفَ أيامه —
        // مقيس: ١٠ أيامٍ بدل ٥. والرصيدُ هو ما يحدّ إجازاتِ الموظف لاحقاً،
        // فالخصمُ المضاعَف يحرمه أياماً يستحقها ولا سجلَّ يقول لماذا.
        //
        // والشرطُ على الحالة **السابقة** لا على الجديدة: طلبٌ مرفوضٌ ثم
        // معتمَدٌ يُخصم مرةً واحدة، وطلبان مستقلّان يُخصمان كلاهما.
        if (leave.status != 'approved') {
          await _deductLeaveBalance(
            leave.employeeId,
            leave.leaveType,
            leave.days,
            leave.startDate.year,
          );
        }
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
    double? manualAmount,
  }) async {
    final employee = await (select(
      employees,
    )..where((e) => e.id.equals(employeeId))).getSingle();

    // المبلغُ مُشتقٌّ من [hourlyRateFor] — المصدرِ الوحيد. وكان يُشتقّ هنا
    // محلياً بمقام `_daysInMonth` (أيامِ التقويم) و٨ ساعاتٍ مثبّتة، فساعةُ
    // الموظف الإضافية أرخصُ ممّا تستحق بنحو ١٥٪ في شهرٍ بأربع عطلات.
    //
    // الفحصُ هنا **قبل** أيّ نداءٍ لـ[hourlyRateFor]: هي ترمي لو `hoursPerDay`
    // معدومٌ، وموظفٌ بلا `hoursPerDay` مع تجاوزٍ يدويّ يجب أن يمرّ بلا رمي —
    // فنداءها في المسار اليدويّ يكسر ذلك حتى لو أُهمِلت نتيجته.
    final double amount;
    if (manualAmount != null) {
      amount = manualAmount;
    } else {
      amount =
          hours * rate * await hourlyRateFor(employee, date.year, date.month);
    }

    return into(overtimeRecords).insert(
      OvertimeRecordsCompanion.insert(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: Value(rate),
        amount: amount,
        isManualAmount: Value(manualAmount != null),
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

  /// عددُ الأيام غيرِ المدفوعةِ **المسجَّلة** في الشهر — غيابٌ أو إجازةٌ غيرُ
  /// مدفوعةٍ معتمدة.
  ///
  /// هو أساسُ الخصم للراتب الشهري. ولليومي لا معنى له في الحساب (يُدفَع بما
  /// عمل)، لكنه يبقى مُبلَّغاً لأن سجلَّ الغياب معلومةٌ إدارية بذاتها.
  final int unpaidDays;

  /// ساعاتُ الحضور الفعلية في الشهر — أساسُ الأجر لموظف [kHourlySalaryType].
  ///
  /// إجازةٌ مدفوعةٌ معتمدة تُسهم بـ`hoursPerDay` (قرار المالك 2026-08-09،
  /// سدُّ فجوة B4 لموظف الساعة)، وصفٌّ بلا انصرافٍ يُسهم بصفر. ولغير الساعة
  /// لا معنى له في الحساب لكنه يبقى مُبلَّغاً لعرضه في واجهة الرواتب.
  final double hoursWorked;

  /// B3 — المستحقُّ بعد الجزاءات = [grossPay] − [totalDeductions]، وهو المبلغُ
  /// الذي يُقيَّد **مديناً** على مصروف الرواتب.
  ///
  /// كان القيدُ يُدَبِّن الصافي، فيُبلَّغ المصروفُ أقلَّ من حقيقته بقيمة السلف
  /// المخصومة.
  final double payableAmount;

  /// B3 — ما تُسوّيه هذه القسيمةُ من السلف = min([totalAdvances], المستحقّ).
  ///
  /// ليس [totalAdvances] نفسه: سلفةٌ أكبر من المستحقّ لا تُسوّى كاملةً، والباقي
  /// يظلّ أصلاً قائماً في ١١٤٦ لأنه فعلاً لم يُسدَّد.
  ///
  /// والثابت `payableAmount == netSalary + advancesSettled` محقَّقٌ بالبناء —
  /// وهو بعينه شرطُ توازنِ قيدِ اليومية.
  final double advancesSettled;

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
    this.unpaidDays = 0,
    this.hoursWorked = 0,
    required this.payableAmount,
    this.advancesSettled = 0,
    required this.netSalary,
    required this.month,
    required this.year,
  });
}
