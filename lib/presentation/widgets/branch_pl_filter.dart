// ═══════════════════════════════════════════════════════════════════════════
// B-01: Branch-Level P&L Filter Widget
// Reusable branch/cost center filter bar for financial reports
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// A compact filter bar for branch and cost center selection on financial reports
class BranchPLFilterBar extends StatelessWidget {
  final List<BranchFilterItem> branches;
  final List<CostCenterFilterItem> costCenters;
  final int? selectedBranchId;
  final int? selectedCostCenterId;
  final ValueChanged<int?> onBranchChanged;
  final ValueChanged<int?> onCostCenterChanged;

  const BranchPLFilterBar({
    super.key,
    required this.branches,
    required this.costCenters,
    this.selectedBranchId,
    this.selectedCostCenterId,
    required this.onBranchChanged,
    required this.onCostCenterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.funnelSimple, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            // Branch Filter
            if (branches.isNotEmpty) ...[
              _filterDropdown<int?>(
                label: 'الفرع',
                value: selectedBranchId,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الفروع')),
                  ...branches.map((b) => DropdownMenuItem<int?>(
                    value: b.id,
                    child: Text(b.name),
                  )),
                ],
                onChanged: onBranchChanged,
              ),
              const SizedBox(width: 12),
            ],
            // Cost Center Filter
            if (costCenters.isNotEmpty) ...[
              _filterDropdown<int?>(
                label: 'مركز التكلفة',
                value: selectedCostCenterId,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل المراكز')),
                  ...costCenters.map((c) => DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name),
                  )),
                ],
                onChanged: onCostCenterChanged,
              ),
            ],
            const Spacer(),
            // Clear filters
            if (selectedBranchId != null || selectedCostCenterId != null)
              TextButton.icon(
                onPressed: () {
                  onBranchChanged(null);
                  onCostCenterChanged(null);
                },
                icon: const Icon(PhosphorIconsBold.x, size: 14),
                label: Text('مسح الفلاتر', style: GoogleFonts.cairo(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textPrimary),
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Branch item for the filter
class BranchFilterItem {
  final int id;
  final String name;

  const BranchFilterItem({required this.id, required this.name});
}

/// Cost center item for the filter
class CostCenterFilterItem {
  final int id;
  final String name;

  const CostCenterFilterItem({required this.id, required this.name});
}
