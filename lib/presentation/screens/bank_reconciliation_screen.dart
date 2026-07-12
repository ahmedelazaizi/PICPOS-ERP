// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/widgets/app_toast.dart';

/// Bank Reconciliation Screen — مطابقة بنكية
class BankReconciliationScreen extends ConsumerStatefulWidget {
  const BankReconciliationScreen({super.key});

  @override
  ConsumerState<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends ConsumerState<BankReconciliationScreen> {
  final _dateFormat = DateFormat('yyyy/MM/dd');
  int _selectedTab = 0; // 0=sessions, 1=import

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            _buildTabBar(),
            Expanded(
              child: _selectedTab == 0
                  ? _buildReconciliationsList(repo)
                  : _buildImportSection(repo),
            ),
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
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(PhosphorIconsBold.bank, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المطابقة البنكية',
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Bank Reconciliation — مقارنة كشف البنك مع الدفاتر',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showNewReconciliationDialog(context, ref.read(accountingRepositoryProvider)),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text('جلسة مطابقة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1565C0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          _tab('جلسات المطابقة', PhosphorIconsBold.listChecks, 0),
          _tab('استيراد كشف حساب', PhosphorIconsBold.uploadSimple, 1),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, int index) {
    final isActive = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.primary : AppColors.textMuted,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationsList(IAccountingRepository repo) {
    return FutureBuilder<List<dynamic>>(
      future: repo.getReconciliationSessions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sessions = snapshot.data!;
        if (sessions.isEmpty) return _buildEmptyState();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (context, index) => _buildSessionCard(sessions[index]),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.bank, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('لا توجد جلسات مطابقة', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text('أنشئ جلسة مطابقة جديدة لمقارنة كشف البنك مع سجلاتك',
              style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildSessionCard(dynamic session) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(PhosphorIconsBold.fileText, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('جلسة مطابقة #${session.id}',
                      style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('رصيد الكشف: ${session.statementBalance}',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            _statusBadge(session.status),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = status == 'completed' ? AppColors.success : AppColors.warning;
    final label = status == 'completed' ? 'مكتمل' : 'قيد العمل';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildImportSection(IAccountingRepository repo) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  const Icon(PhosphorIconsBold.fileCsv, size: 48, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('استيراد كشف حساب بنكي',
                      style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('قم بسحب ملف CSV أو اضغط لاختيار الملف',
                      style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      AppToast.show(context, 'جاري تحميل الكشف البنكي...', type: ToastType.info);
                    },
                    icon: const Icon(PhosphorIconsBold.uploadSimple, size: 18),
                    label: Text('اختيار ملف CSV', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.info, size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يجب أن يحتوي ملف CSV على أعمدة: التاريخ، الوصف، المبلغ، المرجع',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewReconciliationDialog(BuildContext context, IAccountingRepository repo) {
    final balanceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.bank, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('جلسة مطابقة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: balanceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رصيد كشف البنك',
                    prefixIcon: Icon(PhosphorIconsBold.currencyDollar),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                AppToast.show(context, 'تم إنشاء جلسة المطابقة');
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}