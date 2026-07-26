import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../pos/providers/cart_controller.dart';

/// Discount + totals block, with the previous-invoice info strip underneath.
class PicPosTotalsBar extends ConsumerWidget {
  final VoidCallback onEditDiscount;
  final VoidCallback onPreviousInvoices;

  const PicPosTotalsBar({
    super.key,
    required this.onEditDiscount,
    required this.onPreviousInvoices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final totals = cart.totals;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _Amount(
                label: 'عدد الأصناف',
                value: '${cart.items.length}',
                isCount: true,
              ),
              const SizedBox(width: 18),
              _Amount(
                label: 'الإجمالي قبل الخصم',
                value: NumberUtils.formatCurrency(totals.subtotal),
              ),
              const SizedBox(width: 18),
              InkWell(
                onTap: onEditDiscount,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _Amount(
                        label: 'الخصم',
                        value: NumberUtils.formatCurrency(
                            totals.totalDiscount),
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      const Icon(PhosphorIconsBold.pencilSimple,
                          size: 13, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Grand total gets the loudest treatment on the screen — it is
              // the number the cashier reads out and the customer checks.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text(
                      'المجموع',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      NumberUtils.formatCurrency(cart.total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _PreviousInvoicesStrip(onTap: onPreviousInvoices),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool isCount;

  const _Amount({
    required this.label,
    required this.value,
    this.color,
    this.isCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isCount ? 15 : 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PreviousInvoicesStrip extends StatelessWidget {
  final VoidCallback onTap;

  const _PreviousInvoicesStrip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(PhosphorIconsBold.clockCounterClockwise,
                size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text(
              'معلومات الفواتير السابقة',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            Spacer(),
            Text(
              'عرض',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 4),
            Icon(PhosphorIconsBold.caretLeft,
                size: 12, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
