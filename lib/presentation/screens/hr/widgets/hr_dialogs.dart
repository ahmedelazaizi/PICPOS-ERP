import 'package:picpos_erp/core/i18n/tr.dart';
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
    final hoursPerDayCtrl = TextEditingController(
      text: employee?.hoursPerDay?.toString() ?? '',
    );
    String role = employee?.role ?? 'staff';
    String salaryType = employee?.salaryType ?? 'monthly';

    // H6 — فرعُ الموظف. خياراتُ القائمة **متقاطعةٌ مع نطاق المستخدم** فلا يقدر
    // مديرُ فرعٍ أن يُنشئ موظفاً في فرعٍ لا يراه، ويُبذَر للموظف الجديد بفرعه
    // هو (‏`primaryBranchId`) — وإلا وُلد بلا فرعٍ فصار مرئياً لكل الفروع، وهو
    // بالضبط الحالُ الذي أُصلح.
    final scope = ref.watch(branchScopeProvider).value;
    final allBranches = ref.watch(allBranchesProvider).value ?? const [];
    final visibleBranches = (scope == null || scope.hasFullAccess)
        ? allBranches
        : allBranches.where((b) => scope.isAllowed(b.id)).toList();
    int? branchId = employee?.branchId ?? scope?.primaryBranchId;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(employee == null ? tr('إضافة موظف') : tr('تعديل موظف')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration:  InputDecoration(labelText: tr('الاسم رباعي')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration:  InputDecoration(labelText: tr('رقم الهاتف')),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration:  InputDecoration(labelText: tr('المسمى الوظيفي')),
                    items:  [
                      DropdownMenuItem(value: 'manager', child: Text(tr('مدير'))),
                      DropdownMenuItem(value: 'cashier', child: Text(tr('كاشير'))),
                      DropdownMenuItem(
                        value: 'waiter',
                        child: Text(tr('نادل (ويتر)')),
                      ),
                      DropdownMenuItem(value: 'chef', child: Text(tr('شيف'))),
                      DropdownMenuItem(
                        value: 'cleaner',
                        child: Text(tr('عامل نظافة')),
                      ),
                      DropdownMenuItem(value: 'staff', child: Text(tr('موظف عام'))),
                    ],
                    onChanged: (v) => setState(() => role = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: salaryCtrl,
                          decoration:  InputDecoration(labelText: tr('الراتب')),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: salaryType,
                          decoration:  InputDecoration(labelText: tr('نظام الراتب')),
                          items:  [
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text(tr('شهري')),
                            ),
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text(tr('يومي')),
                            ),
                            DropdownMenuItem(
                              value: 'hourly',
                              child: Text(tr('بالساعة')),
                            ),
                          ],
                          onChanged: (v) => setState(() => salaryType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: hoursPerDayCtrl,
                    decoration:  InputDecoration(
                      labelText: tr('ساعات العمل اليومية'),
                      helperText:
                          tr('مطلوب لأجر الساعة، ويُستعمل لاحتساب الوقت الإضافي تلقائياً'),
                      helperMaxLines: 2,
                      prefixIcon: const Icon(PhosphorIconsBold.timer),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: branchId,
                    decoration:  InputDecoration(labelText: tr('الفرع')),
                    items: [
                      // «بلا فرع» = موظفٌ على مستوى الشركة، يراه كلُّ الفروع.
                      // مقصورٌ على من له وصولٌ كامل: مديرُ فرعٍ يختاره كان
                      // يُنشئ موظفاً مرئياً لكل الفروع من داخل نطاقه.
                      if (scope == null || scope.hasFullAccess)
                         DropdownMenuItem<int?>(
                          value: null,
                          child: Text(tr('بلا فرع (مستوى الشركة)')),
                        ),
                      ...visibleBranches.map(
                        (b) => DropdownMenuItem<int?>(
                          value: b.id,
                          child: Text(b.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => branchId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  final salary = double.tryParse(salaryCtrl.text) ?? 0;
                  final hoursPerDay = hoursPerDayCtrl.text.trim().isEmpty
                      ? null
                      : double.tryParse(hoursPerDayCtrl.text.trim());

                  // الحقلُ يظهر لكلّ الأنواع، ويُلزَم لـ`hourly` وحدَه: بدونه
                  // يفشل حسابُ راتبه لاحقاً بصمت — والمنعُ هنا أرخصُ وأوضحُ.
                  if (salaryType == kHourlySalaryType &&
                      (hoursPerDay == null || hoursPerDay <= 0)) {
                    AppToast.show(
                      context,
                      tr('ساعاتُ العمل اليومية مطلوبةٌ لموظفٍ بأجر الساعة'),
                      type: ToastType.error,
                    );
                    return;
                  }

                  await notifier.saveEmployee(
                    existingEmployee: employee,
                    name: nameCtrl.text,
                    phone: phoneCtrl.text,
                    role: role,
                    salary: salary,
                    salaryType: salaryType,
                    branchId: branchId,
                    hoursPerDay: hoursPerDay,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child:  Text(tr('حفظ')),
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
                  ? tr('تسجيل سلفة - {p0}', {'p0': employee.name})
                  : tr('تسجيل خصم - {p0}', {'p0': employee.name}),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    decoration:  InputDecoration(
                      labelText: tr('المبلغ'),
                      prefixIcon: const Icon(PhosphorIconsBold.money),
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration:  InputDecoration(
                      labelText: tr('ملاحظات / السبب'),
                      prefixIcon: const Icon(PhosphorIconsBold.textT),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:  Text(tr('التاريخ')),
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
                      title:  Text(tr('يؤثر على الخزينة (صرف نقدي)')),
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
                            return  Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(tr('لا توجد صناديق متاحة'), style: const TextStyle(color: AppColors.error)),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: DropdownButtonFormField<int>(
                              initialValue: selectedSafeId,
                              decoration:  InputDecoration(
                                labelText: tr('الصندوق'),
                                prefixIcon: const Icon(PhosphorIconsBold.vault),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              hint:  Text(tr('اختيار الصندوق (اختياري)')),
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
                child:  Text(tr('إلغاء')),
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
                          ? tr('تم تسجيل السلفة بنجاح')
                          : tr('تم تسجيل الخصم بنجاح'),
                      type: ToastType.success,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: type == 'advance'
                      ? AppColors.error
                      : AppColors.warning,
                ),
                child: Text(type == 'advance' ? tr('تسجيل سلفة') : tr('تسجيل خصم')),
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
          title: Text(tr('سجل معاملات: {p0}', {'p0': employee.name})),
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
                  return  Center(child: Text(tr('لا توجد معاملات مسجلة')));
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
                        tr('{p0}: {p1} {p2}', {'p0': isAdvance ? tr('سلفة') : tr('خصم'), 'p1': t.amount.toStringAsFixed(AppConstants.decimalPlaces), 'p2': AppConstants.currencySymbolEn}),
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
                              title:  Text(tr('تأكيد الحذف')),
                              content:  Text(
                                tr('هل أنت متأكد من حذف هذه المعاملة؟'),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child:  Text(tr('إلغاء')),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child:  Text(tr('حذف')),
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
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }
}
