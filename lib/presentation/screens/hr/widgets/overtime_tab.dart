import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/repositories/hr_repository_interface.dart';
import '../hr_notifier.dart';
import 'dart:ui' as ui;
import '../../../../../../../core/constants/app_constants.dart';

class OvertimeTab extends ConsumerWidget {
  const OvertimeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hrFormProvider);
    final notifier = ref.read(hrFormProvider.notifier);
    final hrRepo = ref.watch(hrRepositoryProvider);

    final startOfMonth = DateTime(
      state.selectedMonth.year,
      state.selectedMonth.month,
      1,
    );
    final endOfMonth = DateTime(
      state.selectedMonth.year,
      state.selectedMonth.month + 1,
      1,
    );

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.timer, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'العمل الإضافي: ${DateFormat('MMMM yyyy', 'ar').format(state.selectedMonth)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _MonthSelector(state: state, notifier: notifier),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () =>
                    _showAddOvertimeDialog(context, ref, notifier, hrRepo),
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label: const Text('تسجيل إضافي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),

        // Employee list with overtime summary
        Expanded(
          child: FutureBuilder<List<Employee>>(
            // H6 — المزوّد المحصور لا القراءة المباشرة.
            future: ref.watch(hrEmployeesProvider.future),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: ShimmerLoading.list(itemCount: 6),
                );
              }

              final employees = snapshot.data ?? [];
              if (employees.isEmpty) {
                return const Center(child: Text('لا يوجد موظفين'));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: employees.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  return _OvertimeEmployeeExpansionTile(
                    emp: emp,
                    db: hrRepo,
                    start: startOfMonth,
                    end: endOfMonth,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddOvertimeDialog(
    BuildContext context,
    WidgetRef ref,
    HRNotifier notifier,
    IHRRepository db,
  ) {
    int? selectedEmpId;
    final hoursCtrl = TextEditingController();
    double rate = 1.5;
    DateTime date = DateTime.now();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('تسجيل عمل إضافي'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<List<Employee>>(
                    // H6 — منتقي الموظف محصور كذلك: بدونه يُسجَّل عملٌ إضافي
                    // (‏= أجرٌ) على موظف فرعٍ آخر.
                    future: ref.read(hrEmployeesProvider.future),
                    builder: (_, snap) {
                      final emps = snap.data ?? [];
                      return DropdownButtonFormField<int>(
                        initialValue: selectedEmpId,
                        decoration: const InputDecoration(labelText: 'الموظف'),
                        items: emps
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedEmpId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: hoursCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عدد الساعات',
                      prefixIcon: Icon(PhosphorIconsBold.timer),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<double>(
                    initialValue: rate,
                    decoration: const InputDecoration(labelText: 'المضاعف'),
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('عادي (1x)')),
                      DropdownMenuItem(value: 1.5, child: Text('إضافي (1.5x)')),
                      DropdownMenuItem(value: 2.0, child: Text('مضاعف (2x)')),
                      DropdownMenuItem(value: 3.0, child: Text('ثلاثي (3x)')),
                    ],
                    onChanged: (v) => setDialogState(() => rate = v!),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('التاريخ'),
                    subtitle: Text(DateFormat('yyyy/MM/dd').format(date)),
                    leading: const Icon(PhosphorIconsBold.calendar),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 60),
                        ),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
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
                  final hours = double.tryParse(hoursCtrl.text) ?? 0;
                  if (selectedEmpId == null || hours <= 0) return;
                  await notifier.addOvertime(
                    employeeId: selectedEmpId!,
                    date: date,
                    hours: hours,
                    rate: rate,
                    notes: notesCtrl.text,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    AppToast.show(
                      context,
                      'تم تسجيل العمل الإضافي بنجاح',
                      type: ToastType.success,
                    );
                  }
                },
                child: const Text('تسجيل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OvertimeEmployeeExpansionTile extends StatelessWidget {
  final Employee emp;
  final IHRRepository db;
  final DateTime start;
  final DateTime end;

  const _OvertimeEmployeeExpansionTile({
    required this.emp,
    required this.db,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OvertimeRecord>>(
      stream: db.watchEmployeeOvertime(emp.id, start, end),
      builder: (context, otSnap) {
        final records = otSnap.data ?? [];
        final totalHours = records.fold<double>(0, (sum, r) => sum + r.hours);
        final totalAmount = records.fold<double>(0, (sum, r) => sum + r.amount);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: totalHours > 0
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              child: Icon(
                PhosphorIconsBold.timer,
                color: totalHours > 0 ? Colors.orange : Colors.grey,
                size: 20,
              ),
            ),
            title: Text(
              emp.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              totalHours > 0
                  ? '${totalHours.toStringAsFixed(1)} ساعة — ${totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'
                  : 'لا يوجد عمل إضافي هذا الشهر',
              style: TextStyle(
                color: totalHours > 0
                    ? Colors.orange[700]
                    : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            children: records.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'لا توجد سجلات',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ]
                : records
                      .map(
                        (r) => ListTile(
                          dense: true,
                          leading: const Icon(
                            PhosphorIconsBold.clockAfternoon,
                            size: 18,
                          ),
                          title: Text(
                            '${r.hours.toStringAsFixed(1)} ساعة × ${r.rate}x = ${r.amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          ),
                          subtitle: Text(
                            DateFormat('yyyy/MM/dd').format(r.date),
                          ),
                        ),
                      )
                      .toList(),
          ),
        );
      },
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
