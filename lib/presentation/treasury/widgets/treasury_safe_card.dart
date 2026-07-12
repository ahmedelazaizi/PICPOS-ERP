import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import '../../../domain/repositories/treasury_repository.dart';
import '../../widgets/branch_chip.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../../../../core/constants/app_constants.dart';

class TreasurySafeCard extends StatelessWidget {
  final SafeData safe;
  final bool isBank;
  final VoidCallback? onTap;

  const TreasurySafeCard({
    super.key,
    required this.safe,
    this.isBank = false,
    this.onTap,
  });

  Color _safeColor() {
    switch (safe.safeType) {
      case 'cash':
        return AppColors.success;
      case 'click':
        return const Color(0xFF8B5CF6); // purple
      case 'bank':
        return AppColors.info;
      default:
        return const Color(0xFFEA580C); // orange for custom
    }
  }

  IconData _safeIcon() {
    switch (safe.safeType) {
      case 'cash':
        return PhosphorIconsBold.money;
      case 'click':
        return PhosphorIconsBold.cellSignalFull;
      case 'bank':
        return PhosphorIconsBold.bank;
      default:
        return PhosphorIconsBold.vault;
    }
  }

  String _safeLabel(AppLocalizations l) {
    switch (safe.safeType) {
      case 'cash':
        return l.cash;
      case 'click':
        return 'تحويل كليك';
      case 'bank':
        return l.bank;
      default:
        return safe.safeType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final color = _safeColor();
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      elevation: 0,
      color: color.withValues(alpha: 0.04),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          minVerticalPadding: 0,
          leading: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _safeIcon(),
              color: color,
              size: 16,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  safe.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Feature 004 — branch chip: tells the operator at a glance
              // which branch each safe belongs to. Hidden when the safe has
              // no branch link (legacy unscoped safes).
              BranchChip(branchId: safe.branchId, compact: true),
            ],
          ),
          subtitle: Text(
            safe.isDefault
                ? localizations.defaultSafe
                : _safeLabel(localizations),
            style: const TextStyle(fontSize: 9),
          ),
          trailing: Text(
            '${NumberFormat('#,##0.00', 'ar').format(safe.balance)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: safe.balance > 0
                  ? color
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
