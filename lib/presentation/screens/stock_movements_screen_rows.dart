part of 'stock_movements_screen.dart';

extension _StockMovementsScreenRows on _StockMovementsScreenState {
  Widget _buildMovementRow(
    BuildContext context,
    InventoryRepository repo,
    StockMovementData m,
  ) {
    final typeInfo =
        _StockMovementsScreenState._movementTypes[m.movementType] ??
        _StockMovementsScreenState._movementTypes['adjustment']!;
    final isPositive = m.quantity > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Date
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateFormat.format(m.createdAt),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _timeFormat.format(m.createdAt),
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
          // Type badge
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeInfo.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(typeInfo.icon, size: 12, color: typeInfo.color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      typeInfo.label,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: typeInfo.color,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Product
          Expanded(
            flex: 2,
            child: Text(
              m.productName ?? '#${m.productId}',
              style: GoogleFonts.cairo(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Warehouse
          Expanded(
            flex: 1,
            child: Text(
              m.warehouseName ?? '#${m.warehouseId}',
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: context.picposSecondary,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Quantity
          Expanded(
            flex: 1,
            child: Text(
              '${isPositive ? '+' : ''}${m.quantity.toStringAsFixed(1)}',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPositive ? AppColors.success : AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Cost
          Expanded(
            flex: 1,
            child: Text(
              m.unitCost.toStringAsFixed(AppConstants.decimalPlaces),
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: context.picposSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Balance after
          Expanded(
            flex: 1,
            child: Text(
              m.balanceAfter.toStringAsFixed(1),
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Reference
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.referenceType != null)
                  Text(
                    _translateReference(m.referenceType!, m.referenceId),
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: AppColors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (m.notes != null && m.notes!.isNotEmpty)
                  Text(
                    m.notes!,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: context.picposMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _translateReference(String type, int? id) {
    final label = switch (type) {
      'invoice' => tr('فاتورة'),
      'purchase_invoice' => tr('فاتورة شراء'),
      'pos_sale' => tr('بيع POS'),
      'return' => tr('مرتجع'),
      'transfer' => tr('تحويل'),
      'adjustment' => tr('تسوية'),
      'audit' => tr('جرد'),
      'manufacturing' => tr('تصنيع'),
      _ => type,
    };
    return id != null ? '$label #$id' : label;
  }
}
