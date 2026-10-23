import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// Period Close Checklist Widget (F-04)
// Pre-close validation checklist before fiscal period closing
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// A single checklist item that can be auto-verified or manually checked.
class ChecklistItem {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Future<bool> Function()? autoVerify;
  bool isCompleted;
  bool isVerifying;
  String? errorMessage;

  ChecklistItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.autoVerify,
    this.isCompleted = false,
    this.isVerifying = false,
    this.errorMessage,
  });
}

/// Reusable Period Close Checklist — shows a list of pre-close verification items.
///
/// Each item can be:
/// - Auto-verified (has an `autoVerify` function that checks the system)
/// - Manually checked (user confirms they've done it)
///
/// The "Close Period" button is only enabled when all items are completed.
class PeriodCloseChecklist extends StatefulWidget {
  final List<ChecklistItem> items;
  final String title;
  final VoidCallback? onAllCompleted;

  const PeriodCloseChecklist({
    super.key,
    required this.items,
    this.title = 'قائمة التحقق قبل الإقفال',
    this.onAllCompleted,
  });

  @override
  State<PeriodCloseChecklist> createState() => _PeriodCloseChecklistState();

  /// Default checklist for fiscal period closing
  static List<ChecklistItem> getDefaultCloseChecklist({
    required Future<bool> Function() verifyTrialBalance,
    required Future<bool> Function() verifyPendingEntries,
    required Future<bool> Function() verifyBankReconciliation,
  }) {
    return [
      ChecklistItem(
        id: 'trial_balance',
        title: tr('ميزان المراجعة متوازن'),
        description: tr('التحقق من أن مجموع المدين يساوي مجموع الدائن'),
        icon: PhosphorIconsBold.scales,
        autoVerify: verifyTrialBalance,
      ),
      ChecklistItem(
        id: 'pending_entries',
        title: tr('لا توجد قيود معلقة'),
        description: tr('جميع القيود المحاسبية تم ترحيلها'),
        icon: PhosphorIconsBold.notebook,
        autoVerify: verifyPendingEntries,
      ),
      ChecklistItem(
        id: 'bank_reconciliation',
        title: tr('تسوية البنك مكتملة'),
        description: tr('تم مطابقة كشف البنك مع السجلات'),
        icon: PhosphorIconsBold.bank,
        autoVerify: verifyBankReconciliation,
      ),
      ChecklistItem(
        id: 'inventory_count',
        title: tr('جرد المخزون'),
        description: tr('تم جرد المخزون ومعالجة الفروقات'),
        icon: PhosphorIconsBold.package,
      ),
      ChecklistItem(
        id: 'ar_ap_review',
        title: tr('مراجعة الذمم المدينة والدائنة'),
        description: tr('تأكيد أرصدة العملاء والموردين'),
        icon: PhosphorIconsBold.usersThree,
      ),
      ChecklistItem(
        id: 'backup',
        title: tr('نسخة احتياطية'),
        description: tr('تم أخذ نسخة احتياطية كاملة قبل الإقفال'),
        icon: PhosphorIconsBold.database,
      ),
    ];
  }
}

class _PeriodCloseChecklistState extends State<PeriodCloseChecklist> {
  @override
  void initState() {
    super.initState();
    _runAutoVerifications();
  }

  Future<void> _runAutoVerifications() async {
    for (final item in widget.items) {
      if (item.autoVerify != null && !item.isCompleted) {
        setState(() => item.isVerifying = true);
        try {
          final result = await item.autoVerify!();
          if (mounted) {
            setState(() {
              item.isCompleted = result;
              item.isVerifying = false;
              item.errorMessage = result ? null : tr('فشل التحقق');
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              item.isVerifying = false;
              item.errorMessage = e.toString();
            });
          }
        }
      }
    }
  }

  bool get allCompleted => widget.items.every((item) => item.isCompleted);
  int get completedCount => widget.items.where((item) => item.isCompleted).length;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsBold.listChecks, size: 22, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.title, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: allCompleted
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$completedCount / ${widget.items.length}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: allCompleted ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widget.items.isEmpty ? 0 : completedCount / widget.items.length,
                backgroundColor: AppColors.border.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(allCompleted ? AppColors.success : AppColors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            // Checklist items
            ...widget.items.map((item) => _buildChecklistItem(item)),
            if (allCompleted && widget.onAllCompleted != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onAllCompleted,
                  icon: const Icon(PhosphorIconsBold.checkCircle, size: 18),
                  label: Text(tr('تنفيذ الإقفال'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem(ChecklistItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: item.autoVerify != null
            ? null
            : () => setState(() => item.isCompleted = !item.isCompleted),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: item.isCompleted
                ? AppColors.success.withValues(alpha: 0.05)
                : item.errorMessage != null
                    ? AppColors.error.withValues(alpha: 0.05)
                    : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.isCompleted
                  ? AppColors.success.withValues(alpha: 0.3)
                  : item.errorMessage != null
                      ? AppColors.error.withValues(alpha: 0.3)
                      : AppColors.border.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              if (item.isVerifying)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else if (item.isCompleted)
                const Icon(PhosphorIconsBold.checkCircle, size: 20, color: AppColors.success)
              else if (item.errorMessage != null)
                const Icon(PhosphorIconsBold.warningCircle, size: 20, color: AppColors.error)
              else
                Icon(item.icon, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                        color: item.isCompleted ? AppColors.textMuted : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      item.errorMessage ?? item.description,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: item.errorMessage != null ? AppColors.error : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.autoVerify != null && !item.isVerifying && !item.isCompleted)
                IconButton(
                  icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
                  onPressed: () async {
                    setState(() => item.isVerifying = true);
                    try {
                      final result = await item.autoVerify!();
                      if (mounted) {
                        setState(() {
                          item.isCompleted = result;
                          item.isVerifying = false;
                          item.errorMessage = result ? null : tr('فشل التحقق');
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          item.isVerifying = false;
                          item.errorMessage = e.toString();
                        });
                      }
                    }
                  },
                  tooltip: tr('إعادة التحقق'),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
