// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
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
                'رواتب: ${DateFormat('MMMM yyyy', 'ar').format(state.selectedMonth)}',
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
                return const Center(child: Text('لا يوجد موظفين حالياً'));
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
            error: (e, s) => Center(child: Text('خطأ: $e', style: const TextStyle(color: Colors.red))),
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
                _calcRow('الراتب الأساسي', calc.baseSalary),
                _calcRow('قيمة اليومية', calc.dailyRate, color: Colors.blueGrey),
                // B4 — «الأيام المدفوعة» لا «أيام الحضور»: العدد صار يضمّ
                // الإجازةَ المدفوعة المعتمدة، فالتسميةُ القديمة تجعل القسيمة
                // تُظهر حضوراً في أيامٍ كان الموظف فيها في إجازة.
                _calcRow('الأيام المدفوعة (${calc.daysAttended})', calc.dailyRate * calc.daysAttended, color: Colors.green),
                _calcRow('الإضافي', calc.overtimeAmount, color: Colors.green),
                // B3 — المسوَّى من هذه القسيمة لا المُصرَف كلَّه. سلفةُ ٥٠٠٠ على
                // مستحقٍّ ٢٨٠٠ تُسوّي ٢٨٠٠ فقط، وعرضُ ٥٠٠٠ خصماً بجانب صافٍ
                // بصفرٍ أرقامٌ لا تجتمع: ٢٨٠٠ − ٥٠٠٠ ≠ ٠.
                _calcRow('السلف المسوّاة', -calc.advancesSettled, color: Colors.red),
                if (calc.totalAdvances - calc.advancesSettled > 0.01)
                  _calcRow('سلف مؤجّلة للشهر القادم',
                      calc.totalAdvances - calc.advancesSettled,
                      color: Colors.orange),
                _calcRow('الخصومات', -calc.totalDeductions, color: Colors.red),
                const Divider(),
                _calcRow('الإجمالي المستحق', calc.grossPay, isBold: true, color: Colors.indigo),
                _calcRow('الصافي للصرف', calc.netSalary, isBold: true, color: Colors.blue),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: LinearProgressIndicator())),
      error: (e, s) => Card(child: ListTile(title: Text('خطأ: $e', style: const TextStyle(color: Colors.red)))),
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
      actionName: 'صرف الرواتب',
      child: ElevatedButton(
        onPressed: calc.netSalary <= 0 ? null : () => _confirmPayment(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text('صرف الراتب', style: TextStyle(fontSize: 12)),
      ),
    );
  }

  void _confirmPayment(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد صرف راتب'),
        content: Text(
          'هل أنت متأكد من صرف مبلغ ${calc.netSalary.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn} للموظف ${calc.employee.name}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              await notifier.paySalary(calc);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'تأكيد الصرف',
              style: TextStyle(color: Colors.green),
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
      label: const Text('تغيير الشهر'),
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
      actionName: 'تصدير مسير الرواتب',
      child: IconButton(
        icon: const Icon(PhosphorIconsBold.fileXls, size: 20, color: Color(0xFF059669)),
        tooltip: 'تصدير كشف الرواتب إلى Excel',
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
      'الموظف', 'الدور', 'الراتب الأساسي', 'الأيام المدفوعة',
      'إضافي', 'سُلف', 'خصومات', 'صافي المستحق',
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
    final path = await excelService.exportReport(
      title: 'كشف رواتب $period',
      headers: headers,
      rows: rows,
    );

    if (context.mounted) {
      if (path != null) {
        AppToast.show(context, 'تم تصدير كشف الرواتب بنجاح');
      } else {
        AppToast.show(context, 'فشل في تصدير كشف الرواتب', type: ToastType.error);
      }
    }
  }
}

// ── Salary Slip Dialog ───────────────────────────────────────
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
            Text('إيصال راتب — ${calc.employee.name}',
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _slipRow('الموظف', calc.employee.name),
                    _slipRow('الدور', calc.employee.role),
                    _slipRow('الفترة', '${calc.month}/${calc.year}'),
                    const Divider(),
                    _slipRow('الراتب الأساسي',
                        '${calc.baseSalary.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
                    _slipRow('الأيام المدفوعة', '${calc.daysAttended} يوم'),
                    _slipRow('بدل إضافي',
                        '${calc.overtimeAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFF059669)),
                    _slipRow('سُلف',
                        '-${calc.totalAdvances.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFFDC2626)),
                    _slipRow('خصومات',
                        '-${calc.totalDeductions.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        color: const Color(0xFFDC2626)),
                    const Divider(thickness: 2),
                    _slipRow('صافي المستحق',
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
            child: const Text('إغلاق'),
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