import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../data/providers/providers.dart';
import '../hr_notifier.dart';

class AttendanceTab extends ConsumerWidget {
  const AttendanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrRepo = ref.watch(hrRepositoryProvider);
    final notifier = ref.read(hrFormProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.calendarCheck,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
               Text(
                tr('حضور وانصراف اليوم'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _ManualAttendanceButton(ref: ref),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<EmployeeAttendanceWithDetails>>(
            stream: hrRepo.watchTodayAttendance(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: ShimmerLoading.list(itemCount: 6),
                );
              }

              final records = snapshot.data ?? [];
              if (records.isEmpty) {
                return  Center(
                  child: Text(
                    tr('لم يتم تسجيل حضور لأي موظف اليوم'),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _AttendanceCard(record: record, notifier: notifier);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final EmployeeAttendanceWithDetails record;
  final HRNotifier notifier;

  const _AttendanceCard({required this.record, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final att = record.attendance;
    final emp = record.employee;
    final timeFormat = DateFormat('hh:mm a');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: att.checkOut != null
              ? Colors.grey[200]
              : Colors.green[50],
          child: Icon(
            att.checkOut != null
                ? PhosphorIconsBold.checkCircle
                : PhosphorIconsBold.clock,
            color: att.checkOut != null ? Colors.grey : Colors.green,
          ),
        ),
        title: Text(
          emp.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          children: [
            if (att.checkIn != null) ...[
              const Icon(
                PhosphorIconsBold.signIn,
                size: 14,
                color: Colors.green,
              ),
              const SizedBox(width: 4),
              Text(
                timeFormat.format(att.checkIn!),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (att.checkOut != null) ...[
              const SizedBox(width: 16),
              const Icon(
                PhosphorIconsBold.signOut,
                size: 14,
                color: Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                timeFormat.format(att.checkOut!),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: att.checkOut == null
            ? ElevatedButton(
                onPressed: () => notifier.checkOut(emp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child:  Text(tr('تسجيل خروج'), style: const TextStyle(fontSize: 12)),
              )
            :  Chip(
                label: Text(tr('مكتمل'), style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.grey,
              ),
      ),
    );
  }
}

class _ManualAttendanceButton extends StatelessWidget {
  final WidgetRef ref;
  const _ManualAttendanceButton({required this.ref});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showManualAttendance(context),
      icon: const Icon(PhosphorIconsBold.handPointing, size: 18),
      label:  Text(tr('تسجيل يدوي')),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
    );
  }

  void _showManualAttendance(BuildContext context) {
    final notifier = ref.read(hrFormProvider.notifier);

    // الغيابُ يُعلَّم بأثرٍ رجعيّ عادةً (يُكتشف بعد يومٍ أو يومين)، فاليومُ
    // قابلٌ للاختيار — بخلاف التحضير الذي هو دائماً «الآن».
    DateTime absenceDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title:  Text(tr('تسجيل يدوي')),
          content: SizedBox(
            width: 460,
            height: 380,
            child: Column(
              children: [
                // يومُ الغياب — لا يمسّ زرّ التحضير.
                Row(
                  children: [
                     Text(tr('يوم الغياب: ')),
                    Expanded(
                      child: Text(
                        DateFormat('yyyy/MM/dd').format(absenceDate),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(PhosphorIconsBold.calendar, size: 16),
                      label:  Text(tr('تغيير')),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: absenceDate,
                          firstDate: DateTime(absenceDate.year - 1),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => absenceDate = picked);
                        }
                      },
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<Employee>>(
                    // H6 — المزوّد المحصور لا القراءة المباشرة.
                    future: ref.read(hrEmployeesProvider.future),
                    builder: (context, snapshot) {
                      final emps = snapshot.data ?? [];
                      return ListView.builder(
                        itemCount: emps.length,
                        itemBuilder: (context, index) {
                          final e = emps[index];
                          return ListTile(
                            title: Text(e.name),
                            subtitle: Text(
                              e.salaryType == 'monthly'
                                  ? tr('شهري — الغياب المسجّل يُخصم')
                                  : tr('يومي — يُدفع بما عمل'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: tr('تسجيل حضور اليوم'),
                                  icon: const Icon(
                                    PhosphorIconsBold.plusCircle,
                                    color: Colors.green,
                                  ),
                                  onPressed: () async {
                                    await notifier.checkIn(e);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                ),
                                IconButton(
                                  tooltip: tr('تعليم غياب غير مدفوع'),
                                  icon: const Icon(
                                    PhosphorIconsBold.minusCircle,
                                    color: AppColors.error,
                                  ),
                                  onPressed: () =>
                                      _confirmAbsence(ctx, notifier, e,
                                          absenceDate),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// تأكيدٌ قبل تعليم الغياب: العمليةُ **تخصم مالاً** من راتبٍ شهري، وضغطةٌ
  /// بالخطأ على أيقونةٍ بجانب أيقونة التحضير عاقبتُها يومُ أجرٍ ضائع.
  void _confirmAbsence(
    BuildContext dialogCtx,
    HRNotifier notifier,
    Employee employee,
    DateTime date,
  ) {
    showDialog(
      context: dialogCtx,
      builder: (confirmCtx) => AlertDialog(
        title:  Text(tr('تأكيد تعليم غياب')),
        content: Text(
          'تعليم ${employee.name} غائباً يوم '
          '${DateFormat('yyyy/MM/dd').format(date)}؟'
          '${employee.salaryType == 'monthly' ? '\n\nسيُخصم يومٌ من راتبه الشهري.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx),
            child:  Text(tr('إلغاء')),
          ),
          TextButton(
            onPressed: () async {
              await notifier.markAbsent(employee, date);
              if (confirmCtx.mounted) Navigator.pop(confirmCtx);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child:  Text(tr('تأكيد'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
