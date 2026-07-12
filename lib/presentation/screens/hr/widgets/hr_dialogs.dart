import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../hr_notifier.dart';
import 'dart:ui' as ui;
import '../../../../core/constants/app_constants.dart';

/// Provider for active safes (cash boxes) — used in advance dialog
final _activeSafesProvider = StreamProvider.autoDispose<List<SafeData>>((ref) {
  final repo = ref.watch(treasuryRepositoryProvider);
  return repo.watchSafes();
});

class HRDialogs {
  static void showEmployeeForm(
    BuildContext context,
    WidgetRef ref, {
    Employee? employee,
  }) {
    final notifier = ref.read(hrFormProvider.notifier);
    final nameCtrl = TextEditingController(text: employee?.name);
    final phoneCtrl = TextEditingController(text: employee?.phone);
    final salaryCtrl = TextEditingController(
      text: employee?.salary.toString() ?? '0',
    );
    String role = employee?.role ?? 'staff';
    String salaryType = employee?.salaryType ?? 'monthly';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(employee == null ? 'إضافة موظف' : 'تعديل موظف'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'الاسم رباعي'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'المسمى الوظيفي'),
                    items: const [
                      DropdownMenuItem(value: 'manager', child: Text('مدير')),
                      DropdownMenuItem(value: 'cashier', child: Text('كاشير')),
                      DropdownMenuItem(
                        value: 'waiter',
                        child: Text('نادل (ويتر)'),
                      ),
                      DropdownMenuItem(value: 'chef', child: Text('شيف')),
                      DropdownMenuItem(
                        value: 'cleaner',
                        child: Text('عامل نظافة'),
                      ),
                      DropdownMenuItem(value: 'staff', child: Text('موظف عام')),
                    ],
                    onChanged: (v) => setState(() => role = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: salaryCtrl,
                          decoration: const InputDecoration(labelText: 'الراتب'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: salaryType,
                          decoration: const InputDecoration(labelText: 'نظام الراتب'),
                          items: const [
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text('شهري'),
                            ),
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('يومي'),
                            ),
                            DropdownMenuItem(
                              value: 'hourly',
                              child: Text('بالساعة'),
                            ),
                          ],
                          onChanged: (v) => setState(() => salaryType = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  final salary = double.tryParse(salaryCtrl.text) ?? 0;

                  await notifier.saveEmployee(
                    existingEmployee: employee,
                    name: nameCtrl.text,
                    phone: phoneCtrl.text,
                    role: role,
                    salary: salary,
                    salaryType: salaryType,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showTransactionDialog(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
    String type,
  ) {
    final notifier = ref.read(hrFormProvider.notifier);
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool affectsTreasury = type == 'advance';
    DateTime transactionDate = DateTime.now();
    int? selectedSafeId;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              type == 'advance'
                  ? 'تسجيل سلفة - ${employee.name}'
                  : 'تسجيل خصم - ${employee.name}',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      prefixIcon: Icon(PhosphorIconsBold.money),
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات / السبب',
                      prefixIcon: Icon(PhosphorIconsBold.textT),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('التاريخ'),
                    subtitle: Text(
                      DateFormat('yyyy/MM/dd').format(transactionDate),
                    ),
                    leading: const Icon(PhosphorIconsBold.calendar),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: transactionDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() => transactionDate = picked);
                      }
                    },
                  ),
                  if (type == 'advance')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('يؤثر على الخزينة (صرف نقدي)'),
                      value: affectsTreasury,
                      onChanged: (v) => setState(() => affectsTreasury = v!),
                    ),
                  // Safe selector (only for advances that affect treasury)
                  if (type == 'advance' && affectsTreasury)
                    Consumer(builder: (context, cRef, _) {
                      final safesAsync = cRef.watch(_activeSafesProvider);
                      return safesAsync.when(
                        data: (safes) {
                          if (safes.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('لا توجد صناديق متاحة', style: TextStyle(color: AppColors.error)),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: DropdownButtonFormField<int>(
                              initialValue: selectedSafeId,
                              decoration: const InputDecoration(
                                labelText: 'الصندوق',
                                prefixIcon: Icon(PhosphorIconsBold.vault),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              hint: const Text('اختيار الصندوق (اختياري)'),
                              items: safes
                                  .map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text('${s.name} (${s.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn})')))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => selectedSafeId = v),
                            ),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (amount <= 0) return;

                  if (type == 'advance') {
                    await notifier.recordAdvance(
                      employee,
                      amount,
                      descCtrl.text,
                      transactionDate,
                      affectsTreasury,
                      safeId: selectedSafeId,
                    );
                  } else {
                    await notifier.recordDeduction(
                      employee,
                      amount,
                      descCtrl.text,
                      transactionDate,
                    );
                  }

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    AppToast.show(
                      context,
                      type == 'advance'
                          ? 'تم تسجيل السلفة بنجاح'
                          : 'تم تسجيل الخصم بنجاح',
                      type: ToastType.success,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: type == 'advance'
                      ? AppColors.error
                      : AppColors.warning,
                ),
                child: Text(type == 'advance' ? 'تسجيل سلفة' : 'تسجيل خصم'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showTransactionHistory(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) {
    final hrRepo = ref.read(hrRepositoryProvider);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('سجل معاملات: ${employee.name}'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: StreamBuilder<List<EmployeeTransaction>>(
              stream: hrRepo.watchEmployeeTransactions(employee.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: ShimmerLoading.list(itemCount: 4),
                  );
                }

                final transactions = snapshot.data ?? [];
                if (transactions.isEmpty) {
                  return const Center(child: Text('لا توجد معاملات مسجلة'));
                }

                return ListView.separated(
                  itemCount: transactions.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final t = transactions[index];
                    final isAdvance = t.transactionType == 'advance';

                    return ListTile(
                      leading: Icon(
                        isAdvance
                            ? PhosphorIconsBold.currencyCircleDollar
                            : PhosphorIconsBold.minusCircle,
                        color: isAdvance ? AppColors.error : AppColors.warning,
                      ),
                      title: Text(
                        '${isAdvance ? "سلفة" : "خصم"}: ${t.amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('yyyy/MM/dd').format(t.transactionDate),
                          ),
                          if (t.description != null)
                            Text(
                              t.description!,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          PhosphorIconsBold.trash,
                          color: AppColors.error,
                          size: 20,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('تأكيد الحذف'),
                              content: const Text(
                                'هل أنت متأكد من حذف هذه المعاملة؟',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('إلغاء'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await hrRepo.cancelEmployeeTransaction(t.id);
                          }
                        },
                      ),
                    );
                  },
                );
              },
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
}
