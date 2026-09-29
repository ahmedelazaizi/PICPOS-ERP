import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../hr_notifier.dart';
import 'hr_dialogs.dart';
import '../../../../../../../core/constants/app_constants.dart';
import '../../../widgets/permission_guard.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../services/generators/vouchers_pdf_generator.dart';

class StaffListTab extends ConsumerWidget {
  const StaffListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  // ignore: unused_local_variable
    final hrRepo = ref.watch(hrRepositoryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.users, color: AppColors.primary),
              const SizedBox(width: 8),
               Text(
                tr('قائمة الموظفين'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              PermissionGuard(
                permission: PermissionCodes.hrManage,
                allowManagerOverride: true,
                actionName: tr('إضافة موظف جديد'),
                child: ElevatedButton.icon(
                  onPressed: () => HRDialogs.showEmployeeForm(context, ref),
                  icon: const Icon(PhosphorIconsBold.plus, size: 18),
                  label:  Text(tr('موظف جديد')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          // H6 — عبر `hrEmployeesStreamProvider` لا `hrRepo` مباشرةً: المزوّد
          // هو ما يحلّ نطاقَ الفروع، والقراءةُ المباشرة تتجاوزه فتُظهر موظفي
          // الشركة كلها لمدير فرع. (تحوّل من StreamBuilder إلى AsyncValue لأن
          // ‏Riverpod 3 أزال `.stream` على StreamProvider.)
          child: ref.watch(hrEmployeesStreamProvider).when(
            loading: () => Padding(
              padding: const EdgeInsets.all(16),
              child: ShimmerLoading.list(itemCount: 8),
            ),
            error: (e, _) => Center(
              child: Text(tr('خطأ في تحميل الموظفين: {e}', {'e': e}),
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (employees) {
              if (employees.isEmpty) {
                return  Center(child: Text(tr('لا يوجد موظفين حالياً')));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: employees.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  return _EmployeeCard(employee: emp);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmployeeCard extends ConsumerWidget {
  final Employee employee;

  const _EmployeeCard({required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Employee Info Row ───
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    employee.name[0],
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${_roleName(employee.role)} — ${employee.salary} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // ─── Edit / Delete ───
                PermissionGuard(
                  permission: PermissionCodes.hrManage,
                  allowManagerOverride: true,
                  actionName: tr('تعديل بيانات الموظف'),
                  child: IconButton(
                    icon: const Icon(PhosphorIconsBold.pencilSimple, size: 20, color: Colors.blue),
                    tooltip: tr('تعديل'),
                    onPressed: () => HRDialogs.showEmployeeForm(context, ref, employee: employee),
                  ),
                ),
                PermissionGuard(
                  permission: PermissionCodes.hrManage,
                  allowManagerOverride: true,
                  actionName: tr('حذف/تعطيل الموظف'),
                  child: IconButton(
                    icon: const Icon(PhosphorIconsBold.trash, size: 20, color: AppColors.error),
                    tooltip: tr('حذف'),
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // ─── Action Chips (always visible) ───
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PermissionGuard(
                  permission: PermissionCodes.hrAdvanceRecord,
                  allowManagerOverride: true,
                  actionName: tr('تسجيل سلفة'),
                  child: _ActionChip(
                    label: tr('سلفة'),
                    icon: PhosphorIconsBold.currencyCircleDollar,
                    color: AppColors.error,
                    onTap: () => HRDialogs.showTransactionDialog(context, ref, employee, 'advance'),
                  ),
                ),
                // Feature 013 / Issue EMP-ADVANCE-PRINT — print the most
                // recent سلفة (advance) for the employee. Reuses the
                // existing payment-voucher PDF generator with the
                // employee's name as the party and ADV-<id> as the
                // voucher number.
                PermissionGuard(
                  permission: PermissionCodes.hrView,
                  allowManagerOverride: false,
                  actionName: tr('طباعة سلفة'),
                  child: _ActionChip(
                    label: tr('طباعة سلفة'),
                    icon: PhosphorIconsBold.printer,
                    color: Colors.deepPurple,
                    onTap: () => _printLatestAdvance(context, ref, employee),
                  ),
                ),
                PermissionGuard(
                  permission: PermissionCodes.hrAdvanceRecord,
                  allowManagerOverride: true,
                  actionName: tr('تسجيل خصم'),
                  child: _ActionChip(
                    label: tr('خصم'),
                    icon: PhosphorIconsBold.minusCircle,
                    color: AppColors.warning,
                    onTap: () => HRDialogs.showTransactionDialog(context, ref, employee, 'deduction'),
                  ),
                ),
                PermissionGuard(
                  permission: PermissionCodes.hrView,
                  allowManagerOverride: false,
                  actionName: tr('سجل العمليات الإدارية'),
                  child: _ActionChip(
                    label: tr('السجل'),
                    icon: PhosphorIconsBold.clockCounterClockwise,
                    color: Colors.blue,
                    onTap: () => HRDialogs.showTransactionHistory(context, ref, employee),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Feature 013 / Issue EMP-ADVANCE-PRINT — fetch the most recent
  /// active 'advance' transaction for this employee and hand it to the
  /// existing payment-voucher PDF generator. Surfaces a toast when the
  /// employee has no advance recorded so the cashier never sees a blank
  /// preview.
  Future<void> _printLatestAdvance(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) async {
    final hrRepo = ref.read(hrRepositoryProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      final txns = await hrRepo.watchEmployeeTransactions(employee.id).first;
      final latestAdvance = txns
          .where((t) => t.transactionType == 'advance')
          .fold<EmployeeTransaction?>(null, (acc, t) {
        if (acc == null) return t;
        return t.transactionDate.isAfter(acc.transactionDate) ? t : acc;
      });

      if (latestAdvance == null) {
        if (context.mounted) {
          AppToast.show(
            context,
            tr('لا يوجد سلفة لهذا الموظف'),
            type: ToastType.warning,
          );
        }
        return;
      }

      final companyName = await settingsRepo.getSetting('company_name');
      final companyPhone = await settingsRepo.getSetting('company_phone');
      final companyAddress = await settingsRepo.getSetting('company_address');
      final companyTaxId = await settingsRepo.getSetting('company_tax_id');

      await VouchersPdfGenerator.printVoucher(
        voucherNumber: 'ADV-${latestAdvance.id}',
        voucherType: 'payment',
        date: latestAdvance.transactionDate,
        amount: latestAdvance.amount,
        partyName: employee.name,
        description: latestAdvance.description ?? tr('سلفة موظف'),
        employeeName: ref.read(authProvider).user?.displayName,
        companyName: companyName,
        companyPhone: companyPhone,
        companyAddress: companyAddress,
        companyTaxId: companyTaxId,
      );
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          tr('تعذّر طباعة السلفة: {e}', {'e': e}),
          type: ToastType.error,
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تعطيل موظف')),
        content: Text(tr('هل أنت متأكد من تعطيل ملف الموظف "{p0}"؟', {'p0': employee.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              await ref
                  .read(hrRepositoryProvider)
                  .updateEmployee(id: employee.id, isActive: false);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child:  Text(
              tr('تعطيل'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  String _roleName(String role) {
    switch (role) {
      case 'manager':
        return tr('مدير');
      case 'cashier':
        return tr('كاشير');
      case 'waiter':
        return tr('نادل');
      case 'chef':
        return tr('شيف');
      case 'cleaner':
        return tr('عامل');
      default:
        return 'موظف';
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
