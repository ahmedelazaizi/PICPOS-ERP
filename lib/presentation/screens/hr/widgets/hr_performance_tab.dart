import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';

/// HR Performance Evaluation Tab
class PerformanceTab extends ConsumerWidget {
  const PerformanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrRepo = ref.watch(hrRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<Employee>>(
        future: hrRepo.getAllEmployees(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final employees = snap.data!.where((e) => e.isActive).toList();

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.chartLine,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('تقييم أداء الموظفين',
                        style: GoogleFonts.cairo(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _showAddReviewDialog(context, ref, employees),
                      icon: const Icon(PhosphorIconsBold.plus, size: 16),
                      label: const Text('تقييم جديد'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
              // Reviews List
              Expanded(
                child: FutureBuilder<List<PerformanceReview>>(
                  future: hrRepo.getAllReviews(),
                  builder: (context, reviewSnap) {
                    if (!reviewSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final reviews = reviewSnap.data!;
                    if (reviews.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsBold.chartLine,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 8),
                            Text('لا توجد تقييمات بعد',
                                style: GoogleFonts.cairo(
                                    color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: reviews.length,
                      itemBuilder: (context, index) =>
                          _ReviewCard(review: reviews[index], employees: employees),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddReviewDialog(
      BuildContext context, WidgetRef ref, List<Employee> employees) {
    Employee? selectedEmployee;
    String periodType = 'monthly';
    int commitment = 70, productivity = 70, quality = 70, teamwork = 70;
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تقييم أداء جديد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<Employee>(
                      decoration: const InputDecoration(
                          labelText: 'الموظف', border: OutlineInputBorder()),
                      items: employees
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedEmployee = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                          labelText: 'نوع الفترة', border: OutlineInputBorder()),
                      initialValue: periodType,
                      items: const [
                        DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                        DropdownMenuItem(
                            value: 'quarterly', child: Text('ربع سنوي')),
                        DropdownMenuItem(value: 'annual', child: Text('سنوي')),
                      ],
                      onChanged: (v) => setState(() => periodType = v!),
                    ),
                    const SizedBox(height: 16),
                    _ScoreSlider(
                      label: 'الالتزام',
                      value: commitment,
                      onChanged: (v) =>
                          setState(() => commitment = v.round()),
                    ),
                    _ScoreSlider(
                      label: 'الإنتاجية',
                      value: productivity,
                      onChanged: (v) =>
                          setState(() => productivity = v.round()),
                    ),
                    _ScoreSlider(
                      label: 'الجودة',
                      value: quality,
                      onChanged: (v) => setState(() => quality = v.round()),
                    ),
                    _ScoreSlider(
                      label: 'العمل الجماعي',
                      value: teamwork,
                      onChanged: (v) => setState(() => teamwork = v.round()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'ملاحظات', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: selectedEmployee == null
                    ? null
                    : () async {
                        final hrRepo = ref.read(hrRepositoryProvider);
                        final now = DateTime.now();
                        final period = periodType == 'annual'
                            ? '${now.year}-annual'
                            : periodType == 'quarterly'
                                ? '${now.year}-Q${((now.month - 1) ~/ 3) + 1}'
                                : '${now.year}-${now.month.toString().padLeft(2, '0')}';
                        await hrRepo.addPerformanceReview(
                          employeeId: selectedEmployee!.id,
                          period: period,
                          periodType: periodType,
                          commitmentScore: commitment,
                          productivityScore: productivity,
                          qualityScore: quality,
                          teamworkScore: teamwork,
                          reviewerNotes: notesCtrl.text.isEmpty
                              ? null
                              : notesCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('حفظ التقييم'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<double> onChanged;

  const _ScoreSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = value >= 80
        ? const Color(0xFF059669)
        : value >= 60
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: color,
              label: '$value',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final PerformanceReview review;
  final List<Employee> employees;

  const _ReviewCard({required this.review, required this.employees});

  @override
  Widget build(BuildContext context) {
    final emp = employees.where((e) => e.id == review.employeeId).firstOrNull;
    final overall = review.overallRating;
    final color = overall >= 80
        ? const Color(0xFF059669)
        : overall >= 60
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);

    final periodLabels = {
      'monthly': 'شهري',
      'quarterly': 'ربع سنوي',
      'annual': 'سنوي',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('$overall',
                  style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp?.name ?? '#${review.employeeId}',
                      style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    '${review.period} — ${periodLabels[review.periodType] ?? review.periodType}',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            // Individual scores
            _miniScore('التزام', review.commitmentScore),
            _miniScore('إنتاج', review.productivityScore),
            _miniScore('جودة', review.qualityScore),
            _miniScore('فريق', review.teamworkScore),
          ],
        ),
      ),
    );
  }

  Widget _miniScore(String label, int score) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text('$score',
              style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          Text(label,
              style:
                  GoogleFonts.cairo(fontSize: 9, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
