import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme/app_colors.dart';
import '../../data/providers/repository_providers.dart';
import '../../core/widgets/app_toast.dart';

/// Deferred Revenue / Expense Management Screen — الإيرادات والمصروفات المؤجلة
class DeferredScheduleScreen extends ConsumerStatefulWidget {
  const DeferredScheduleScreen({super.key});

  @override
  ConsumerState<DeferredScheduleScreen> createState() => _DeferredScheduleScreenState();
}

class _DeferredScheduleScreenState extends ConsumerState<DeferredScheduleScreen> {
  final _dateFormat = DateFormat('yyyy/MM/dd');
  bool _processingRecognitions = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildSchedulesList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF37474F), Color(0xFF546E7A)],
          begin: AlignmentDirectional.topEnd, end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(PhosphorIconsBold.calendarCheck, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('الإيرادات والمصروفات المؤجلة'), style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(tr('IAS 18 / IAS 38 — الاستحقاق والترحيل التلقائي'), style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text(tr('جدول جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF37474F),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _processingRecognitions ? null : () async {
              setState(() => _processingRecognitions = true);
              final repo = ref.read(accountingRepositoryProvider);
              try {
                final count = await repo.processDueRecognitions();
                if (context.mounted) {
                  AppToast.show(context, tr('تم ترحيل {count} فترة استحقاق', {'count': count}));
                  setState(() {});
                }
              } catch (e) {
                if (context.mounted) {
                  AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              } finally {
                if (mounted) setState(() => _processingRecognitions = false);
              }
            },
            icon: const Icon(PhosphorIconsBold.play, size: 18, color: Colors.white),
            label: Text(tr('ترحيل الفترات المستحقة'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulesList() {
    final repo = ref.watch(accountingRepositoryProvider);
    return FutureBuilder<List<dynamic>>(
      future: (() async {
        try { return await repo.getActiveSchedules(); } catch (_) { return <dynamic>[]; }
      })(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final schedules = snapshot.data!;
        if (schedules.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.calendarCheck, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(tr('لا توجد جداول استحقاق نشطة'), style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Text(tr('أضف إيراداً مؤجلاً أو مصروفاً مدفوعاً مقدماً لبدء الترحيل التلقائي'),
                    style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: schedules.length,
          itemBuilder: (context, index) => _buildScheduleCard(schedules[index]),
        );
      },
    );
  }

  Widget _buildScheduleCard(dynamic schedule) {
    final isRevenue = schedule.type == 'deferred_revenue';
    final progress = schedule.totalPeriods > 0
        ? schedule.completedPeriods / schedule.totalPeriods : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isRevenue ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isRevenue ? PhosphorIconsBold.arrowCircleDown : PhosphorIconsBold.arrowCircleUp,
                    color: isRevenue ? AppColors.success : AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(schedule.description, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(isRevenue ? tr('إيراد مؤجل') : tr('مصروف مدفوع مقدماً'),
                          style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${schedule.totalAmount}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(tr('متبقي: {p0}', {'p0': schedule.remainingAmount}),
                        style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(isRevenue ? AppColors.success : AppColors.warning),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(tr('{p0}/{p1} فترة', {'p0': schedule.completedPeriods, 'p1': schedule.totalPeriods}),
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.calendarPlus, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(tr('جدول استحقاق جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration:  InputDecoration(labelText: tr('النوع')),
                  initialValue: 'deferred_revenue',
                  items:  [
                    DropdownMenuItem(value: 'deferred_revenue', child: Text(tr('إيراد مؤجل'))),
                    DropdownMenuItem(value: 'prepaid_expense', child: Text(tr('مصروف مدفوع مقدماً'))),
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 12),
                 TextField(decoration: InputDecoration(labelText: tr('الوصف'))),
                const SizedBox(height: 12),
                 TextField(keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('المبلغ الإجمالي'))),
                const SizedBox(height: 12),
                 TextField(keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('عدد فترات الاستحقاق'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إنشاء'))),
          ],
        ),
      ),
    );
  }
}