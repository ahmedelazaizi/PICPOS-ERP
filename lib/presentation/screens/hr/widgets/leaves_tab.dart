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

class LeavesTab extends ConsumerWidget {
  const LeavesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hrFormProvider);
    final notifier = ref.read(hrFormProvider.notifier);
    final hrRepo = ref.watch(hrRepositoryProvider);

    return Column(
      children: [
        // Pending Requests Horizontal List
        _PendingLeavesSection(db: hrRepo, notifier: notifier),

        const Divider(),

        // Employee Selection & Balances
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.user, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: ref.watch(hrEmployeesProvider).when(
                  data: (emps) => DropdownButtonFormField<int>(
                    initialValue: state.selectedEmployeeId,
                    decoration: const InputDecoration(
                      labelText: 'اختر موظف لعرض إجازاته',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: emps
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => notifier.selectEmployee(v),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Text('خطأ: $e', style: const TextStyle(color: AppColors.error)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _showLeaveRequestDialog(context, notifier, hrRepo, ref),
                icon: const Icon(PhosphorIconsBold.plus),
                style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),

        // Balances & History
        if (state.selectedEmployeeId != null)
          _EmployeeLeaveDetails(employeeId: state.selectedEmployeeId!, db: hrRepo)
        else
          const Expanded(
            child: Center(
              child: Text(
                'اختر موظفاً لعرض رصيد إجازاته',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
      ],
    );
  }

  void _showLeaveRequestDialog(
    BuildContext context,
    HRNotifier notifier,
    IHRRepository db,
    WidgetRef ref,
  ) {
    int? selectedEmpId;
    String leaveType = 'annual';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 1));
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final days = endDate.difference(startDate).inDays + 1;
            return AlertDialog(
              title: const Text('طلب إجازة جديد'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        return ref.watch(hrEmployeesProvider).when(
                          data: (emps) => DropdownButtonFormField<int>(
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
                            onChanged: (v) => setDialogState(() => selectedEmpId = v),
                          ),
                          loading: () => const CircularProgressIndicator(),
                          error: (e, s) => Text('خطأ: $e'),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: leaveType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الإجازة',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'annual', child: Text('سنوية')),
                        DropdownMenuItem(value: 'sick', child: Text('مرضية')),
                        DropdownMenuItem(
                          value: 'unpaid',
                          child: Text('بدون راتب'),
                        ),
                        DropdownMenuItem(
                          value: 'emergency',
                          child: Text('طارئة'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => leaveType = v!),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('من'),
                      subtitle: Text(
                        DateFormat('yyyy/MM/dd').format(startDate),
                      ),
                      leading: const Icon(PhosphorIconsBold.calendar),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => startDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('إلى'),
                      subtitle: Text(DateFormat('yyyy/MM/dd').format(endDate)),
                      leading: const Icon(PhosphorIconsBold.calendarCheck),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => endDate = picked);
                        }
                      },
                    ),
                    Text(
                      'المدة: $days يوم',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
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
                    if (selectedEmpId == null) return;
                    await notifier.requestLeave(
                      employeeId: selectedEmpId!,
                      leaveType: leaveType,
                      startDate: startDate,
                      endDate: endDate,
                      days: days,
                      notes: notesCtrl.text,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      AppToast.show(
                        context,
                        'تم تقديم طلب الإجازة بنجاح',
                        type: ToastType.success,
                      );
                    }
                  },
                  child: const Text('تقديم الطلب'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PendingLeavesSection extends StatelessWidget {
  final IHRRepository db;
  final HRNotifier notifier;

  const _PendingLeavesSection({required this.db, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'طلبات معلقة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: StreamBuilder<List<EmployeeLeave>>(
            stream: db.watchPendingLeaves(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? [];
              if (pending.isEmpty) {
                return const Center(
                  child: Text(
                    'لا توجد طلبات معلقة',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: pending.length,
                itemBuilder: (context, index) {
                  final leave = pending[index];
                  return _PendingLeaveCard(
                    leave: leave,
                    db: db,
                    notifier: notifier,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PendingLeaveCard extends ConsumerWidget {
  final EmployeeLeave leave;
  final IHRRepository db;
  final HRNotifier notifier;

  const _PendingLeaveCard({
    required this.leave,
    required this.db,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 250,
      child: Card(
        elevation: 3,
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ref.watch(hrEmployeeByIdProvider(leave.employeeId)).when(
                data: (emp) => Text(
                  emp?.name ?? '...',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                loading: () => const Text('جار التحميل...', style: TextStyle(fontWeight: FontWeight.bold)),
                error: (e, s) => const Text('خطأ', style: TextStyle(color: AppColors.error)),
              ),
              const SizedBox(height: 4),
              Text(
                '${_leaveTypeName(leave.leaveType)} — ${leave.days} يوم',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '${DateFormat('MM/dd').format(leave.startDate)} → ${DateFormat('MM/dd').format(leave.endDate)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          notifier.updateLeave(leave.id, 'approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      child: const Text(
                        'موافقة',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          notifier.updateLeave(leave.id, 'rejected'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      child: const Text('رفض', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeLeaveDetails extends ConsumerWidget {
  final int employeeId;
  final IHRRepository db;

  const _EmployeeLeaveDetails({required this.employeeId, required this.db});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    return Expanded(
      child: Column(
        children: [
          // Balances
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ref.watch(hrLeaveBalancesProvider(LeaveBalanceArgs(employeeId, year))).when(
              data: (balances) {
                if (balances.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: () async {
                        await db.initializeLeaveBalances(employeeId, year);
                        ref.invalidate(hrLeaveBalancesProvider);
                      },
                      child: const Text('تهيئة رصيد الإجازات لهذا العام'),
                    ),
                  );
                }
                return Row(
                  children: balances
                      .map(
                        (b) => Expanded(
                          child: Card(
                            color: _leaveTypeColor(b.leaveType).withValues(alpha: 0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Text(
                                    _leaveTypeName(b.leaveType),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _leaveTypeColor(b.leaveType),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${b.totalDays - b.usedDays}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _leaveTypeColor(b.leaveType),
                                    ),
                                  ),
                                  Text(
                                    'من ${b.totalDays} يوم',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('خطأ: $e', style: const TextStyle(color: AppColors.error))),
            ),
          ),
          const SizedBox(height: 8),
          // History
          Expanded(
            child: StreamBuilder<List<EmployeeLeave>>(
              stream: db.watchEmployeeLeaves(employeeId),
              builder: (context, snapshot) {
                final leaves = snapshot.data ?? [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ShimmerLoading.list(itemCount: 4);
                }
                if (leaves.isEmpty) {
                  return const Center(child: Text('لا توجد إجازات مسجلة'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: leaves.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final l = leaves[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          l.status == 'approved'
                              ? PhosphorIconsBold.checkCircle
                              : l.status == 'rejected'
                              ? PhosphorIconsBold.xCircle
                              : PhosphorIconsBold.hourglass,
                          color: l.status == 'approved'
                              ? Colors.green
                              : l.status == 'rejected'
                              ? AppColors.error
                              : Colors.orange,
                        ),
                        title: Text(
                          '${_leaveTypeName(l.leaveType)} — ${l.days} يوم',
                        ),
                        subtitle: Text(
                          '${DateFormat('MM/dd').format(l.startDate)} → ${DateFormat('MM/dd').format(l.endDate)}',
                        ),
                        trailing: Chip(
                          label: Text(
                            _statusName(l.status),
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: _statusColor(l.status),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _statusName(String status) => status == 'approved'
      ? 'موافق'
      : status == 'rejected'
      ? 'مرفوض'
      : 'معلق';
  Color _statusColor(String status) => status == 'approved'
      ? Colors.green[50]!
      : status == 'rejected'
      ? AppColors.errorLight
      : Colors.orange[50]!;
}

String _leaveTypeName(String type) {
  switch (type) {
    case 'annual':
      return 'سنوية';
    case 'sick':
      return 'مرضية';
    case 'unpaid':
      return 'بدون راتب';
    case 'emergency':
      return 'طارئة';
    default:
      return type;
  }
}

Color _leaveTypeColor(String type) {
  switch (type) {
    case 'annual':
      return Colors.blue;
    case 'sick':
      return AppColors.error;
    case 'unpaid':
      return Colors.grey;
    case 'emergency':
      return Colors.orange;
    default:
      return AppColors.primary;
  }
}
