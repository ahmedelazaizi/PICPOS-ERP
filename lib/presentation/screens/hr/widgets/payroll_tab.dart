import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/repositories/hr_repository_interface.dart';
import '../hr_notifier.dart';
import '../../../../../../../core/constants/app_constants.dart';
import '../../../widgets/permission_guard.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../core/widgets/app_toast.dart';

class PayrollTab extends ConsumerWidget {
  const PayrollTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hrFormProvider);
    final notifier = ref.read(hrFormProvider.notifier);
    final hrRepo = ref.watch(hrRepositoryProvider);

    return Column(
      children: [
        // Header with Month Selector
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.wallet, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                tr('رواتب: {p0}', {'p0': DateFormat('MMMM yyyy', 'ar').format(state.selectedMonth)}),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Excel Export Button
              _ExportPayrollButton(
                state: state,
                hrRepo: hrRepo,
              ),
              const SizedBox(width: 8),
              _MonthSelector(state: state, notifier: notifier),
            ],
          ),
        ),

        // Employee Payroll List
        Expanded(
          child: ref.watch(hrEmployeesProvider).when(
            data: (employees) {
              if (employees.isEmpty) {
                return  Center(child: Text(tr('لا يوجد موظفين حالياً')));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: employees.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  return _PayrollCard(
                    employee: emp,
                    state: state,
                    db: hrRepo,
                    notifier: notifier,
                  );
                },
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.all(16),
              child: ShimmerLoading.list(itemCount: 6),
            ),
            error: (e, s) => Center(child: Text(tr('خطأ: {e}', {'e': e}), style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }
}

class _PayrollCard extends ConsumerWidget {
  final Employee employee;
  final HRState state;
  final IHRRepository db;
  final HRNotifier notifier;

  const _PayrollCard({
    required this.employee,
    required this.state,
    required this.db,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(hrNetSalaryProvider(NetSalaryArgs(employee.id, state.selectedMonth.year, state.selectedMonth.month))).when(
      data: (calc) {
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    _PayButton(calc: calc, notifier: notifier),
                  ],
                ),
                const Divider(),
                _calcRow(tr('الراتب الأساسي'), calc.baseSalary),
                _calcRow(tr('قيمة اليومية'), calc.dailyRate, color: Colors.blueGrey),
                // الصفُّ يتبع الموديل. للشهري: الراتبُ هو الأساس ويُخصم منه
                // الغيابُ المسجَّل، فعرضُ «الأيام المدفوعة × الأجر اليومي» كان
                // يشرح حساباً لا يجري.
                //
                // B4 — «الأيام المدفوعة» لا «أيام الحضور» لليومي: العدد يضمّ
                // الإجازةَ المدفوعة المعتمدة.
                if (calc.employee.salaryType == 'monthly')
                  ...[
                    if (calc.unpaidDays > 0)
                      _calcRow(tr('خصم غياب ({p0} يوم)', {'p0': calc.unpaidDays}),
                          -calc.dailyRate * calc.unpaidDays,
                          color: AppColors.error),
                  ]
                else if (calc.employee.salaryType == 'hourly')
                  // موظفُ الساعة: الأساسيُّ = ساعاتُ الحضور × أجرُ الساعة، لا
                  // «الأيام × الأجر اليومي» — `dailyRate` لا معنى له هنا.
                  // `grossPay - overtimeAmount` يساوي الأساسيَّ بالبناء
                  // (‏`grossPay = basePay + overtimeAmount` في
                  // `calculateNetSalary`)، فلا حاجةَ لتعريض أجر الساعة حقلاً
                  // مستقلاً.
                  _calcRow(
                      tr('الساعات ({p0}) × أجر الساعة', {'p0': calc.hoursWorked.toStringAsFixed(1)}),
                      calc.grossPay - calc.overtimeAmount,
                      color: Colors.green)
                else
                  _calcRow(tr('الأيام المدفوعة ({p0})', {'p0': calc.daysAttended}),
                      calc.dailyRate * calc.daysAttended,
                      color: Colors.green),
                _calcRow(tr('الإضافي'), calc.overtimeAmount, color: Colors.green),
                // B3 — المسوَّى من هذه القسيمة لا المُصرَف كلَّه. سلفةُ ٥٠٠٠ على
                // مستحقٍّ ٢٨٠٠ تُسوّي ٢٨٠٠ فقط، وعرضُ ٥٠٠٠ خصماً بجانب صافٍ
                // بصفرٍ أرقامٌ لا تجتمع: ٢٨٠٠ − ٥٠٠٠ ≠ ٠.
                _calcRow(tr('السلف المسوّاة'), -calc.advancesSettled, color: AppColors.error),
                if (calc.totalAdvances - calc.advancesSettled > 0.01)
                  _calcRow(tr('سلف مؤجّلة للشهر القادم'),
                      calc.totalAdvances - calc.advancesSettled,
                      color: Colors.orange),
                _calcRow(tr('الخصومات'), -calc.totalDeductions, color: AppColors.error),
                const Divider(),
                _calcRow(tr('الإجمالي المستحق'), calc.grossPay, isBold: true, color: Colors.indigo),
                _calcRow(tr('الصافي للصرف'), calc.netSalary, isBold: true, color: Colors.blue),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: LinearProgressIndicator())),
      error: (e, s) => Card(child: ListTile(title: Text(tr('خطأ: {e}', {'e': e}), style: const TextStyle(color: AppColors.error)))),
    );
  }

  Widget _calcRow(
    String label,
    double amount, {
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final EmployeeSalaryCalculation calc;
  final HRNotifier notifier;

  const _PayButton({required this.calc, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: PermissionCodes.hrPayrollProcess,
      allowManagerOverride: true,
      actionName: tr('صرف الرواتب'),
      child: ElevatedButton(
        onPressed: calc.netSalary <= 0 ? null : () => _confirmPayment(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child:  Text(tr('صرف الراتب'), style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  void _confirmPayment(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تأكيد صرف راتب')),
        content: Text(
          tr('هل أنت متأكد من صرف مبلغ {p0} {p1} للموظف {p2}؟', {'p0': calc.netSalary.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn, 'p2': calc.employee.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              await notifier.paySalary(calc);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child:  Text(
              tr('تأكيد الصرف'),
              style: const TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final HRState state;
  final HRNotifier notifier;

  const _MonthSelector({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: state.selectedMonth,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 30)),
        );
        if (picked != null) notifier.selectMonth(picked);
      },
      icon: const Icon(PhosphorIconsBold.calendar, size: 18),
      label:  Text(tr('تغيير الشهر')),
    );
  }
}

// ── Excel Export Button ───────────────────────────────────────
class _ExportPayrollButton extends ConsumerWidget {
  final HRState state;
  final IHRRepository hrRepo;

  const _ExportPayrollButton({required this.state, required this.hrRepo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGuard(
      permission: PermissionCodes.hrPayrollProcess,
      allowManagerOverride: true,
      actionName: tr('تصدير مسير الرواتب'),
      child: IconButton(
        icon: const Icon(PhosphorIconsBold.fileXls, size: 20, color: Color(0xFF059669)),
        tooltip: tr('تصدير كشف الرواتب إلى Excel'),
        onPressed: () => _exportPayroll(context, ref),
      ),
    );
  }

  Future<void> _exportPayroll(BuildContext context, WidgetRef ref) async {
    // H6 — التصديرُ محصورٌ كذلك. كشفُ رواتب Excel أخطرُ من الشاشة: ملفٌ يُرسَل
    // ويُحفَظ، فتسريبُه أثرٌ باقٍ لا عرضٌ عابر.
    final employees = await ref.read(hrEmployeesProvider.future);
    final calcs = await Future.wait(
      employees.map((e) => hrRepo.calculateNetSalary(
        employeeId: e.id,
        year: state.selectedMonth.year,
        month: state.selectedMonth.month,
      )),
    );

    final headers = [
      tr('الموظف'), tr('الدور'), tr('الراتب الأساسي'), tr('الأيام المدفوعة'),
      tr('إضافي'), tr('سُلف'), tr('خصومات'), tr('صافي المستحق'),
    ];

    final rows = calcs.map((c) => [
      c.employee.name,
      c.employee.role,
      c.baseSalary,
      c.daysAttended,
      c.overtimeAmount,
      c.totalAdvances,
      c.totalDeductions,
      c.netSalary,
    ]).toList();

    final excelService = ref.read(excelServiceProvider);
    final period = DateFormat('yyyy-MM').format(state.selectedMonth);
    // فترةُ الكشف شهرٌ كامل: أوّلُه إلى آخرِ يومٍ فيه. والفرعُ من نطاق
    // المستخدم لا من فلترٍ — تبويبُ الرواتب لا يملك منسدلةَ فرع، والقائمةُ
    // محصورةٌ بالنطاق (H6)، فالنطاقُ هو ما يصف الملفَّ بصدق.
    final monthStart = DateTime(
      state.selectedMonth.year,
      state.selectedMonth.month,
      1,
    );
    final monthEnd = DateTime(
      state.selectedMonth.year,
      state.selectedMonth.month + 1,
      0,
    );
    final path = await excelService.exportReport(
      title: tr('كشف رواتب {period}', {'period': period}),
      headers: headers,
      rows: rows,
      periodFrom: monthStart,
      periodTo: monthEnd,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
    );

    if (context.mounted) {
      if (path != null) {
        AppToast.show(context, tr('تم تصدير كشف الرواتب بنجاح'));
      } else {
        AppToast.show(context, tr('فشل في تصدير كشف الرواتب'), type: ToastType.error);
      }
    }
  }
}

// ── Salary Slip Dialog ───────────────────────────────────────
  // ignore: unused_element
void _showSalarySlip(BuildContext context, EmployeeSalaryCalculation calc) {
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.receipt, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr('إيصال راتب — {p0}', {'p0': calc.employee.name}),
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ctx.picposField,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ctx.picposHairline),
                ),
                child: Column(
                  children: [
                    _slipRow(tr('الموظف'), calc.employee.name),
                    _slipRow(tr('الدور'), calc.employee.role),
                    _slipRow(tr('الفترة'), '${calc.month}/${calc.year}'),
                    const Divider(),
                    _slipRow(tr('الراتب الأساسي'),
                        '${calc.baseSalary.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
                    if (calc.employee.salaryType == 'monthly')
                      _slipRow(tr('أيام غياب غير مدفوعة'),
                          tr('{p0} يوم', {'p0': calc.unpaidDays}))
                    else if (calc.employee.salaryType == 'hourly')
                      _slipRow(tr('الساعات المدفوعة'),
                          tr('{p0} ساعة', {'p0': calc.hoursWorked.toStringAsFixed(1)}))
                    else
                      _slipRow(tr('الأيام المدفوعة'), tr('{p0} يوم', {'p0': calc.daysAttended})),
                    _slipRow(tr('بدل إضافي'),
                        '${calc.overtimeAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFF059669)),
                    _slipRow(tr('سُلف'),
                        '-${calc.totalAdvances.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFFDC2626)),
                    _slipRow(tr('خصومات'),
                        '-${calc.totalDeductions.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFFDC2626)),
                    const Divider(thickness: 2),
                    _slipRow(tr('صافي المستحق'),
                        '${calc.netSalary.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        isBold: true, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    ),
  );
}

Widget _slipRow(String label, String value,
    {Color? color, bool isBold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                color: color)),
      ],
    ),
  );
}
