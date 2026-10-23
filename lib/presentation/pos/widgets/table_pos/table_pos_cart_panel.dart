import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../providers/cart_controller.dart';
import 'table_pos_cart_item.dart';

class TablePosCartPanel extends ConsumerWidget {
  final Function(int, double) onUpdateQuantity;
  final Function(int) onRemove;
  final Function(int) onAddNote;

  const TablePosCartPanel({
    super.key,
    required this.onUpdateQuantity,
    required this.onRemove,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartControllerProvider);
    final items = cartState.items;
    final total = cartState.total;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          right: BorderSide(
              color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          // Cart header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.receipt,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(tr('سلة الطلب'),
                    style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                Text(
                  '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),

          // Cart items list
          Expanded(
            child: items.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    itemCount: items.length,
                    itemBuilder: (ctx, index) {
                      return TablePosCartItem(
                        item: items[index],
                        index: index,
                        onUpdateQuantity: onUpdateQuantity,
                        onRemove: onRemove,
                        onAddNote: () => onAddNote(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsBold.shoppingCart,
                size: 40,
                color: Colors.white.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 14),
          Text(tr('السلة فارغة'),
              style: GoogleFonts.cairo(
                  fontSize: 14,
                  color:
                      Colors.white.withValues(alpha: 0.2),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(tr('اختر أصناف من القائمة'),
              style: GoogleFonts.cairo(
                  fontSize: 11,
                  color:
                      Colors.white.withValues(alpha: 0.1))),
        ],
      ),
    );
  }
}
