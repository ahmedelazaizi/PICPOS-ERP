import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/hr_repository_interface.dart';
import '../../../domain/repositories/audit_repository_interface.dart';
import '../../../../../../core/constants/app_constants.dart';

class HRState {
  final int? selectedEmployeeId;
  final DateTime selectedMonth;
  final bool isLoading;

  HRState({
    this.selectedEmployeeId,
    required this.selectedMonth,
    this.isLoading = false,
  });

  HRState copyWith({
    int? selectedEmployeeId,
    DateTime? selectedMonth,
    bool? isLoading,
  }) {
    return HRState(
      selectedEmployeeId: selectedEmployeeId ?? this.selectedEmployeeId,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HRNotifier extends Notifier<HRState> {
  @override
  HRState build() {
    return HRState(selectedMonth: DateTime.now());
  }

  IHRRepository get _hrRepo => ref.read(hrRepositoryProvider);
  IAuditRepository get _auditRepo => ref.read(auditRepositoryProvider);

  void selectEmployee(int? id) {
    state = state.copyWith(selectedEmployeeId: id);
  }

  void selectMonth(DateTime date) {
    state = state.copyWith(selectedMonth: date);
  }

  Future<void> saveEmployee({
    Employee? existingEmployee,
    required String name,
    String? phone,
    String role = 'staff',
    double salary = 0,
    String salaryType = 'monthly',
    int? branchId,
    double? hoursPerDay,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      if (existingEmployee == null) {
        final id = await _hrRepo.addEmployee(
          name: name,
          phone: phone,
          role: role,
          salary: salary,
          salaryType: salaryType,
          branchId: branchId,
          hoursPerDay: hoursPerDay,
        );
        await _log('add_employee', tr('إضافة موظف: {name} ({role})', {'name': name, 'role': role}), entityId: id);
      } else {
        await _hrRepo.updateEmployee(
          id: existingEmployee.id,
          name: name,
          phone: phone,
          role: role,
          salary: salary,
          salaryType: salaryType,
          branchId: branchId,
          hoursPerDay: hoursPerDay,
        );
        await _log(
          'update_employee',
          tr('تعديل موظف: {name}', {'name': name}),
          entityId: existingEmployee.id,
          oldValue: existingEmployee.name,
          newValue: name,
        );
      }
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> checkIn(Employee employee) async {
    await _hrRepo.checkInEmployee(employee.id);
    await _log(
      'employee_checkin',
      tr('تسجيل حضور: {p0}', {'p0': employee.name}),
      entityId: employee.id,
    );
  }

  /// يعلّم يوماً غياباً. يُسجَّل في سجلّ التدقيق لأنه **يخصم مالاً** من راتبٍ
  /// شهري — فمن علّمه ومتى سؤالٌ سيُطرح.
  Future<void> markAbsent(Employee employee, DateTime date) async {
    await _hrRepo.markEmployeeAbsent(employee.id, date);
    await _log(
      'employee_absent',
      tr('تعليم غياب: {p0} — {p1}/{p2}/{p3}', {'p0': employee.name, 'p1': date.year, 'p2': date.month.toString().padLeft(2, '0'), 'p3': date.day.toString().padLeft(2, '0')}),
      entityId: employee.id,
    );
  }

  Future<void> checkOut(Employee employee) async {
    await _hrRepo.checkOutEmployee(employee.id);
    await _log(
      'employee_checkout',
      tr('تسجيل انصراف: {p0}', {'p0': employee.name}),
      entityId: employee.id,
    );
  }

  Future<void> recordAdvance(
    Employee employee,
    double amount,
    String description,
    DateTime date,
    bool affectsTreasury, {
    int? safeId,
  }) async {
    await _hrRepo.recordEmployeeAdvance(
      employeeId: employee.id,
      amount: amount,
      description: description,
      transactionDate: date,
      affectsTreasury: affectsTreasury,
      safeId: safeId,
    );
    await _log(
      'employee_advance',
      tr('سلفة: {p0} - {p1} {p2}', {'p0': employee.name, 'p1': amount.toStringAsFixed(AppConstants.decimalPlaces), 'p2': AppConstants.currencySymbolEn}),
      entityId: employee.id,
      newValue: amount.toStringAsFixed(AppConstants.decimalPlaces),
    );
  }

  Future<void> recordDeduction(
    Employee employee,
    double amount,
    String description,
    DateTime date,
  ) async {
    await _hrRepo.recordEmployeeDeduction(
      employeeId: employee.id,
      amount: amount,
      description: description,
      transactionDate: date,
    );
    await _log(
      'employee_deduction',
      tr('خصم: {p0} - {p1} {p2}', {'p0': employee.name, 'p1': amount.toStringAsFixed(AppConstants.decimalPlaces), 'p2': AppConstants.currencySymbolEn}),
      entityId: employee.id,
      newValue: amount.toStringAsFixed(AppConstants.decimalPlaces),
    );
  }

  Future<void> paySalary(EmployeeSalaryCalculation calc) async {
    // B3 — الأرقامُ الثلاثة من `calc` نفسه لا مُعادةَ الحساب هنا: كانت الدالةُ
    // تستقبل الحسابَ كاملاً وتمرّر الصافيَ وحده، فيُقيَّد المصروفُ مُبخَّساً
    // و١١٤٦ لا يُقيَّد عليه دائنٌ قطّ.
    await _hrRepo.recordSalaryPayment(
      employeeId: calc.employee.id,
      amount: calc.netSalary,
      period: '${calc.year}-${calc.month.toString().padLeft(2, '0')}',
      payableAmount: calc.payableAmount,
      advancesSettled: calc.advancesSettled,
    );
    await _log(
      'salary_payment',
      tr('صرف راتب: {p0} - {p1} {p2}', {'p0': calc.employee.name, 'p1': calc.netSalary.toStringAsFixed(AppConstants.decimalPlaces), 'p2': AppConstants.currencySymbolEn}),
      entityId: calc.employee.id,
      newValue: calc.netSalary.toStringAsFixed(AppConstants.decimalPlaces),
    );
  }

  Future<void> requestLeave({
    required int employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int days,
    String? notes,
  }) async {
    await _hrRepo.requestLeave(
      employeeId: employeeId,
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      days: days,
      notes: notes,
    );
  }

  Future<void> updateLeave(int leaveId, String status) async {
    final user = ref.read(authProvider).user;
    await _hrRepo.updateLeaveStatus(leaveId, status, user?.id ?? 0);
  }

  /// يُعيد `null` عند النجاح، أو رسالةَ خطأٍ للعرض.
  ///
  /// كان النداءُ عارياً، و`HRNotifier` ليس `AsyncNotifier` فلا تغليفَ تلقائي:
  /// أيُّ استثناءٍ يهبط في `PlatformDispatcher.onError` الذي يسجّله ويُعيد
  /// `true` — فلا التطبيقُ يسقط ولا المستخدمُ يرى شيئاً. الزرُّ يبدو أنه لم
  /// يفعل شيئاً، والسجلُّ لا يُحفظ، ولا رسالة. **الفشلُ الصامت أسوأ من
  /// الانهيار**: الانهيارُ يُبلَّغ عنه.
  Future<String?> addOvertime({
    required int employeeId,
    required DateTime date,
    required double hours,
    double rate = 1.5,
    String? notes,
    double? manualAmount,
  }) async {
    try {
      await _hrRepo.addOvertimeRecord(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: rate,
        notes: notes,
        manualAmount: manualAmount,
      );
      return null;
    } on StateError catch (e) {
      return tr('تعذّر احتسابُ المبلغ تلقائياً: {p0}. أدخِل ساعاتِ العمل اليومية للموظف، أو أدخِل المبلغَ يدوياً.', {'p0': e.message});
    } catch (e) {
      return tr('تعذّر تسجيلُ الوقت الإضافي: {e}', {'e': e});
    }
  }

  Future<void> _log(
    String action,
    String description, {
    int? entityId,
    String? oldValue,
    String? newValue,
  }) async {
    final auth = ref.read(authProvider);
    final user = auth.user;
    await _auditRepo.logActivity(
      userId: user?.id,
      userName: user?.displayName ?? tr('مجهول'),
      action: action,
      entityType: 'employee',
      entityId: entityId,
      description: description,
      oldValue: oldValue,
      newValue: newValue,
    );
  }
}

final hrFormProvider = NotifierProvider<HRNotifier, HRState>(() {
  return HRNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// H6 — قوائمُ الموظفين محصورةٌ بفروع المستخدم.
// ═══════════════════════════════════════════════════════════════════════════
//
// كانت شاشاتُ HR تقرأ `getAllEmployees()` بلا نطاق، وليس في مجلد `hr/` ذكرٌ
// واحدٌ لـ`branchId`. فمديرُ فرعٍ يفتح تبويبَ الرواتب فيقرأ **رواتبَ الشركة
// كاملة** — أسماءها وأدوارها ومبالغها وسلفها.
//
// وحتى تستقرّ الشاشةُ لم يُمرَّر النطاق في كلِّ شاشةٍ على حِدة، بل يُحَلّ هنا
// مرةً واحدة: الشاشةُ تراقب المزوّد فقط، ونسيانُ شاشةٍ جديدة للحصر يصير
// مستحيلاً لأن لا مسارَ غيرَ محصورٍ متاحاً لها.
//
// ريثما يُحَلّ النطاق (الإطارُ الأولُ بعد الدخول) يُعاد **صفرُ صفوف** لا القائمة
// غيرَ المحصورة — نفسُ اختيار `parties_providers.dart`: وميضُ صفوفِ فرعٍ آخر
// لعشراتِ الميلي ثانية تسريبٌ كامل.

/// نطاقُ الفروع للمستخدم الحالي، أو `null` ريثما لم يُحَلّ بعد.
///
/// `hasFullAccess` يُترجَم إلى `null` في نداءِ المستودع (بلا فلتر)، وغيرُه إلى
/// المجموعةِ المغلقة.
Set<int>? _scopeFilter(BranchScope scope) =>
    scope.hasFullAccess ? null : scope.allowedBranchIds;

final hrEmployeesProvider = FutureProvider.autoDispose<List<Employee>>((
  ref,
) async {
  final hrRepo = ref.watch(hrRepositoryProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  return hrRepo.getAllEmployees(allowedBranchIds: _scopeFilter(scope));
});

/// نسخةُ التدفّق — `staff_list_tab` يحتاج تحديثاً حياً عند الإضافة والتعطيل.
final hrEmployeesStreamProvider =
    StreamProvider.autoDispose<List<Employee>>((ref) {
  final hrRepo = ref.watch(hrRepositoryProvider);
  final scope = ref.watch(branchScopeProvider.select((s) => s.value));
  if (scope == null) return Stream<List<Employee>>.value(const []);
  return hrRepo.watchAllEmployees(allowedBranchIds: _scopeFilter(scope));
});

class LeaveBalanceArgs {
  final int employeeId;
  final int year;
  const LeaveBalanceArgs(this.employeeId, this.year);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaveBalanceArgs &&
          runtimeType == other.runtimeType &&
          employeeId == other.employeeId &&
          year == other.year;

  @override
  int get hashCode => employeeId.hashCode ^ year.hashCode;
}

final hrLeaveBalancesProvider = FutureProvider.autoDispose.family<List<LeaveBalance>, LeaveBalanceArgs>((ref, args) {
  final hrRepo = ref.watch(hrRepositoryProvider);
  return hrRepo.getLeaveBalances(args.employeeId, args.year);
});

class NetSalaryArgs {
  final int employeeId;
  final int year;
  final int month;
  const NetSalaryArgs(this.employeeId, this.year, this.month);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetSalaryArgs &&
          runtimeType == other.runtimeType &&
          employeeId == other.employeeId &&
          year == other.year &&
          month == other.month;

  @override
  int get hashCode => employeeId.hashCode ^ year.hashCode ^ month.hashCode;
}

final hrNetSalaryProvider = FutureProvider.autoDispose.family<EmployeeSalaryCalculation, NetSalaryArgs>((ref, args) {
  final hrRepo = ref.watch(hrRepositoryProvider);
  return hrRepo.calculateNetSalary(
    employeeId: args.employeeId,
    year: args.year,
    month: args.month,
  );
});

final hrEmployeeByIdProvider = FutureProvider.autoDispose.family<Employee?, int>((ref, id) {
  final hrRepo = ref.watch(hrRepositoryProvider);
  return hrRepo.getEmployeeById(id);
});
