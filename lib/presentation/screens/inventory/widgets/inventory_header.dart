import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';

class InventoryHeader extends StatelessWidget {
  const InventoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                PhosphorIconsBold.package,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
             Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('إدارة المخزون'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  tr('متابعة مستويات المخزون وحركات الأصناف ولائحة الصلاحيات'),
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
