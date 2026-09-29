import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

/// Approval Workflow Dashboard — لوحة الاعتمادات
class ApprovalDashboardScreen extends ConsumerStatefulWidget {
  const ApprovalDashboardScreen({super.key});

  @override
  ConsumerState<ApprovalDashboardScreen> createState() => _ApprovalDashboardScreenState();
}

class _ApprovalDashboardScreenState extends ConsumerState<ApprovalDashboardScreen> {
  int _selectedTab = 0; // 0=pending, 1=workflows

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            _buildTabBar(),
            Expanded(child: _selectedTab == 0 ? _buildPendingApprovals() : _buildWorkflowSettings()),
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
          colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
          begin: AlignmentDirectional.topEnd, end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(PhosphorIconsBold.checkSquare, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('الاعتمادات والموافقات'), style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Multi-Level Approval — Maker → Checker → Approver', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showNewWorkflowDialog(context),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text(tr('سير عمل جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFFE65100),
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
          _tab(tr('اعتمادات معلقة'), PhosphorIconsBold.hourglass, 0),
          _tab(tr('إعدادات سير العمل'), PhosphorIconsBold.gearSix, 1),
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
          border: Border(bottom: BorderSide(color: isActive ? AppColors.primary : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.cairo(fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppColors.primary : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingApprovals() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(PhosphorIconsBold.checkCircle, size: 48, color: AppColors.success),
          ),
          const SizedBox(height: 16),
          Text(tr('لا توجد اعتمادات معلقة'), style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(tr('جميع العمليات تمت الموافقة عليها'), style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildWorkflowSettings() {
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    return FutureBuilder<List<dynamic>>(
      future: (() async {
        try { return await accountingRepo.getActiveWorkflows(); } catch (_) { return <dynamic>[]; }
      })(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final workflows = snapshot.data!;
        if (workflows.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.flowArrow, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(tr('لا توجد إعدادات سير عمل'), style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Text(tr('أنشئ سير عمل لبدء تفعيل الاعتمادات المتعددة المستويات'),
                    style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workflows.length,
          itemBuilder: (context, index) => _buildWorkflowCard(workflows[index]),
        );
      },
    );
  }

  Widget _buildWorkflowCard(dynamic workflow) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(PhosphorIconsBold.flowArrow, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workflow.name, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      Text('${workflow.entityType}', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(tr('{p0} مستويات', {'p0': workflow.requiredLevels}), style: GoogleFonts.cairo(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Text(tr('الحد: {p0}', {'p0': workflow.amountThreshold}), style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            _buildLevelIndicator(workflow.requiredLevels),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelIndicator(int levels) {
    final labels = ['Maker', 'Checker', 'Approver'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(levels.clamp(1, 3), (i) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) const Icon(PhosphorIconsBold.arrowLeft, size: 10, color: AppColors.textMuted),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: [AppColors.primary, AppColors.warning, AppColors.success][i].withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(labels[i], style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w700,
                  color: [AppColors.primary, AppColors.warning, AppColors.success][i])),
            ),
          ],
        );
      }),
    );
  }

  void _showNewWorkflowDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.flowArrow, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(tr('سير عمل جديد'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 TextField(decoration: InputDecoration(labelText: tr('اسم سير العمل'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration:  InputDecoration(labelText: tr('نوع العملية')),
                  items:  [
                    DropdownMenuItem(value: 'journal_entry', child: Text(tr('قيد يومية'))),
                    DropdownMenuItem(value: 'sales_invoice', child: Text(tr('فاتورة مبيعات'))),
                    DropdownMenuItem(value: 'purchase_invoice', child: Text(tr('فاتورة مشتريات'))),
                    DropdownMenuItem(value: 'safe_transfer', child: Text(tr('تحويل خزنة'))),
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 12),
                 TextField(keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('الحد الأدنى لتفعيل الاعتماد'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration:  InputDecoration(labelText: tr('عدد المستويات')),
                  initialValue: 2,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 — Maker → Checker')),
                    DropdownMenuItem(value: 3, child: Text('3 — Maker → Checker → Approver')),
                  ],
                  onChanged: (_) {},
                ),
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