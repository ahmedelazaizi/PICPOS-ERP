import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/widgets/app_toast.dart';

/// Compliance Dashboard Screen — لوحة الامتثال
class ComplianceDashboardScreen extends ConsumerStatefulWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  ConsumerState<ComplianceDashboardScreen> createState() => _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState extends ConsumerState<ComplianceDashboardScreen> {
  bool _isRunning = false;
  List<Map<String, dynamic>> _results = [];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            if (_isRunning)
              const LinearProgressIndicator()
            else if (_results.isNotEmpty)
              _buildScoreBar(),
            Expanded(child: _results.isEmpty ? _buildEmptyState() : _buildResults()),
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
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: AlignmentDirectional.topEnd, end: AlignmentDirectional.bottomStart,
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
              Text('لوحة الامتثال', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('SOX / IFRS / ISA 315 — تقييم جاهزية التدقيق', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _isRunning ? null : _runAudit,
            icon: Icon(_isRunning ? PhosphorIconsBold.circleNotch : PhosphorIconsBold.play, size: 18),
            label: Text(_isRunning ? 'جاري الفحص...' : 'تشغيل فحص الامتثال', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF1B5E20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar() {
    final avg = _results.isEmpty ? 0.0
        : _results.fold<double>(0, (s, r) => s + ((r['score'] as num?) ?? 0)) / _results.length;
    final color = avg >= 80 ? AppColors.success : (avg >= 50 ? AppColors.warning : AppColors.error);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: color.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(
            avg >= 80 ? PhosphorIconsBold.checkCircle : (avg >= 50 ? PhosphorIconsBold.warning : PhosphorIconsBold.xCircle),
            color: color, size: 28,
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('النتيجة الإجمالية', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
              Text('${avg.toStringAsFixed(0)}%',
                  style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: avg / 100,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              avg >= 80 ? 'جاهز للتدقيق' : (avg >= 50 ? 'يحتاج تحسين' : 'غير جاهز'),
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.shieldCheck, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('فحص الامتثال', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text('اضغط "تشغيل فحص الامتثال" لتقييم جاهزية النظام للتدقيق',
              style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _categoryChip('IFRS', PhosphorIconsBold.bookOpen),
              _categoryChip('Audit Trail', PhosphorIconsBold.path),
              _categoryChip('SOD', PhosphorIconsBold.users),
              _categoryChip('Data Integrity', PhosphorIconsBold.database),
              _categoryChip('VAT', PhosphorIconsBold.receipt),
              _categoryChip('Period Controls', PhosphorIconsBold.calendar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildCheckCard(_results[index]),
    );
  }

  Widget _buildCheckCard(Map<String, dynamic> check) {
    final score = ((check['score'] as num?) ?? 0).toDouble();
    final status = check['status'] as String? ?? 'pending';
    final color = status == 'pass' ? AppColors.success : (status == 'warning' ? AppColors.warning : AppColors.error);
    final icon = status == 'pass' ? PhosphorIconsBold.checkCircle
        : (status == 'warning' ? PhosphorIconsBold.warning : PhosphorIconsBold.xCircle);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(check['checkName'] ?? '', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(check['description'] ?? '', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('${score.toStringAsFixed(0)}%',
                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ),
            if (check['details'] != null && (check['details'] as String).isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(check['details'] as String,
                    style: GoogleFonts.cairo(fontSize: 11, color: color, height: 1.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runAudit() async {
    setState(() => _isRunning = true);
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final results = await accountingRepo.runComplianceAudit();
      setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    } finally {
      setState(() => _isRunning = false);
    }
  }
}
