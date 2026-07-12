// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/widgets/app_toast.dart';

/// SOD Matrix Screen — مصفوفة فصل المهام
class SodMatrixScreen extends ConsumerStatefulWidget {
  const SodMatrixScreen({super.key});

  @override
  ConsumerState<SodMatrixScreen> createState() => _SodMatrixScreenState();
}

class _SodMatrixScreenState extends ConsumerState<SodMatrixScreen> {
  int _selectedTab = 0; // 0=matrix, 1=violations

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
            Expanded(child: _selectedTab == 0 ? _buildMatrix() : _buildViolations()),
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
          colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(PhosphorIconsBold.shieldCheck, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('مصفوفة فصل المهام', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('ISA 315 / COSO — Segregation of Duties', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () async {
              final accountingRepo = ref.read(accountingRepositoryProvider);
              try {
                await accountingRepo.seedDefaultSodConflicts();
                if (context.mounted) {
                  AppToast.show(context, 'تم إنشاء قواعد SOD الافتراضية');
                  setState(() {});
                }
              } catch (e) {
                if (context.mounted) {
                  AppToast.show(context, 'خطأ: $e', type: ToastType.error);
                }
              }
            },
            icon: const Icon(PhosphorIconsBold.shieldPlus, size: 18),
            label: Text('تحميل القواعد الافتراضية', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFFB71C1C),
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
          _tab('قواعد التعارض', PhosphorIconsBold.table, 0),
          _tab('سجل المخالفات', PhosphorIconsBold.warning, 1),
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

  Widget _buildMatrix() {
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    return FutureBuilder<List<dynamic>>(
      future: (() async {
        try { return await accountingRepo.getActiveSodConflicts(); } catch (_) { return <dynamic>[]; }
      })(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final conflicts = snapshot.data!;
        if (conflicts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.shieldCheck, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('لا توجد قواعد تعارض', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Text('اضغط "تحميل القواعد الافتراضية" لإنشاء 7 قواعد ISA 315',
                    style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: conflicts.length,
          itemBuilder: (context, index) => _buildConflictCard(conflicts[index]),
        );
      },
    );
  }

  Widget _buildConflictCard(dynamic conflict) {
    final isHard = conflict.conflictType == 'hard';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isHard ? AppColors.error.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isHard ? AppColors.error : AppColors.warning).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isHard ? PhosphorIconsBold.prohibit : PhosphorIconsBold.warning,
                color: isHard ? AppColors.error : AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _permBadge(conflict.permission1),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(PhosphorIconsBold.x, size: 12, color: AppColors.error),
                      ),
                      _permBadge(conflict.permission2),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isHard ? AppColors.error : AppColors.warning).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isHard ? 'منع إلزامي' : 'تحذير',
                          style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w700,
                              color: isHard ? AppColors.error : AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(conflict.description, style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permBadge(String perm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(perm, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
    );
  }

  Widget _buildViolations() {
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    return FutureBuilder<List<dynamic>>(
      future: (() async {
        try { return await accountingRepo.getSodViolationReport(); } catch (_) { return <dynamic>[]; }
      })(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final violations = snapshot.data!;
        if (violations.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(PhosphorIconsBold.checkCircle, size: 48, color: AppColors.success),
                ),
                const SizedBox(height: 16),
                Text('لا توجد مخالفات SOD', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('النظام متوافق مع متطلبات فصل المهام', style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: violations.length,
          itemBuilder: (context, index) {
            final v = violations[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  v.wasBlocked ? PhosphorIconsBold.prohibit : PhosphorIconsBold.warning,
                  color: v.wasBlocked ? AppColors.error : AppColors.warning,
                ),
                title: Text(v.detectedAction, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                subtitle: Text('مستخدم #${v.userId}', style: GoogleFonts.cairo(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (v.wasBlocked ? AppColors.error : AppColors.warning).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    v.wasBlocked ? 'تم المنع' : 'تحذير فقط',
                    style: GoogleFonts.cairo(fontSize: 10, color: v.wasBlocked ? AppColors.error : AppColors.warning, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}