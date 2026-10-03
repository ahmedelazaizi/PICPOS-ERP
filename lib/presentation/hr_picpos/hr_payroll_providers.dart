// J4 (الجزء ٣) — مزوّداتُ الرواتب والسلف والعمولات. كلُّ قراءةٍ عبر
// `databaseProvider`، والسطورُ محصورةٌ بفروع المستخدم (H6) كسجلّ الموظفين.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../../domain/models/hr_payroll.dart';
import '../../domain/models/voucher_book.dart';
import 'hr_picpos_providers.dart';

final payrollRunsProvider = FutureProvider.autoDispose<List<PayrollRun>>(
    (ref) => ref.watch(databaseProvider).listPayrollRuns());

final payrollRunProvider = FutureProvider.autoDispose
    .family<PayrollRun, int>(
        (ref, id) => ref.watch(databaseProvider).getPayrollRun(id));

/// سطورُ مسيّرٍ محصورةٌ بنطاق المستخدم.
final payrollLinesProvider = FutureProvider.autoDispose
    .family<List<PayrollLine>, int>((ref, runId) async {
  final scope = await ref.watch(branchScopeProvider.future);
  final lines = await ref.watch(databaseProvider).listPayrollLines(runId: runId);
  return [for (final l in lines) if (scope.isAllowed(l.branchId)) l];
});

final payrollRulesProvider = FutureProvider.autoDispose<PayrollRules>(
    (ref) => ref.watch(databaseProvider).payrollRules());

final payrollAccountsProvider = FutureProvider.autoDispose<PayrollAccounts>(
    (ref) => ref.watch(databaseProvider).payrollAccounts());

final payrollAccountOptionsProvider =
    FutureProvider.autoDispose<List<PayrollAccountOption>>(
        (ref) => ref.watch(databaseProvider).payrollAccountOptions());

final payrollCostCentersProvider = FutureProvider.autoDispose<List<(int, String)>>(
    (ref) => ref.watch(databaseProvider).payrollCostCenterOptions());

final payrollDeptCostCentersProvider = FutureProvider.autoDispose<Map<int, int>>(
    (ref) => ref.watch(databaseProvider).departmentCostCenters());

final salaryComponentsProvider =
    FutureProvider.autoDispose<List<SalaryComponent>>(
        (ref) => ref.watch(databaseProvider).listSalaryComponents());

final payrollSafesProvider = FutureProvider.autoDispose<List<PayrollSafe>>(
    (ref) async {
  final scope = await ref.watch(branchScopeProvider.future);
  final safes = await ref.watch(databaseProvider).payrollSafes();
  return [for (final s in safes) if (scope.isAllowed(s.branchId)) s];
});

/// دفاترُ سندات الصرف الفعّالة.
final paymentBooksProvider = FutureProvider.autoDispose<List<VoucherBook>>(
    (ref) => ref
        .watch(databaseProvider)
        .listVoucherBooks(type: 'payment', activeOnly: true));

/// السلفُ (موظف أو الكلّ) محصورةٌ بنطاق المستخدم.
final employeeAdvancesProvider = FutureProvider.autoDispose
    .family<List<EmployeeAdvance>, int?>((ref, employeeId) async {
  final allowed = {
    for (final p in await ref.watch(hrProfilesProvider.future)) p.id,
  };
  final rows = await ref
      .watch(databaseProvider)
      .listEmployeeAdvances(employeeId: employeeId);
  return [for (final a in rows) if (allowed.contains(a.employeeId)) a];
});

final payrollAdjustmentsProvider = FutureProvider.autoDispose
    .family<List<PayrollAdjustment>, int?>((ref, employeeId) async {
  final allowed = {
    for (final p in await ref.watch(hrProfilesProvider.future)) p.id,
  };
  final rows = await ref
      .watch(databaseProvider)
      .listPayrollAdjustments(employeeId: employeeId);
  return [for (final a in rows) if (allowed.contains(a.employeeId)) a];
});

final commissionPlansProvider =
    FutureProvider.autoDispose<List<CommissionPlan>>(
        (ref) => ref.watch(databaseProvider).listCommissionPlans());

final commissionCategoriesProvider =
    FutureProvider.autoDispose<List<(int, String)>>(
        (ref) => ref.watch(databaseProvider).commissionCategoryOptions());

/// كشفُ عمولة (موظف، سنة، شهر).
final commissionStatementProvider = FutureProvider.autoDispose
    .family<CommissionStatement, (int, int, int)>((ref, q) => ref
        .watch(databaseProvider)
        .commissionStatement(
            q.$1, DateTime(q.$2, q.$3), DateTime(q.$2, q.$3 + 1, 0)));

final employeePayslipsProvider = FutureProvider.autoDispose
    .family<List<PayslipEntry>, int>(
        (ref, id) => ref.watch(databaseProvider).employeePayslips(id));

/// يُعيد قراءةَ كلِّ ما يتغيّر بعد كتابةٍ في الرواتب.
void refreshPayroll(WidgetRef ref) {
  ref.invalidate(payrollRunsProvider);
  ref.invalidate(payrollRunProvider);
  ref.invalidate(payrollLinesProvider);
  ref.invalidate(payrollRulesProvider);
  ref.invalidate(payrollAccountsProvider);
  ref.invalidate(payrollDeptCostCentersProvider);
  ref.invalidate(salaryComponentsProvider);
  ref.invalidate(employeeAdvancesProvider);
  ref.invalidate(payrollAdjustmentsProvider);
  ref.invalidate(commissionPlansProvider);
  ref.invalidate(commissionStatementProvider);
  ref.invalidate(employeePayslipsProvider);
  ref.invalidate(paymentBooksProvider);
  ref.invalidate(hrHistoryProvider);
}
