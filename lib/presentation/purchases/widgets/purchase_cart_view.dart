import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/purchases_controller.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Purchase cart view widget
class PurchaseCartView extends ConsumerWidget {
  final VoidCallback? onSave;
  final VoidCallback? onClear;

  const PurchaseCartView({super.key, this.onSave, this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(purchasesControllerProvider);
    final controller = ref.read(purchasesControllerProvider.notifier);

    return Column(
      children: [
        // Header
        _buildHeader(state, controller),

        // Cart items
        Expanded(
          child: state.cart.isEmpty
              ? _buildEmptyState()
              : _buildCartList(state, controller),
        ),

        // Totals
        _buildTotals(state),

        // Save button
        _buildSaveButton(state),
      ],
    );
  }

  Widget _buildHeader(PurchasesState state, PurchasesController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.shoppingCart, size: 20),
          const SizedBox(width: 8),
          Text(
            '??? ????????? (${state.cart.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (state.cart.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                controller.clearForm();
                onClear?.call();
              },
              icon: const Icon(PhosphorIconsBold.trash, size: 16),
              label: const Text('???'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
          Icon(
            PhosphorIconsBold.package,
            size: 64,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '????? ?????',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(PurchasesState state, PurchasesController controller) {
    return ListView.builder(
      itemCount: state.cart.length,
      itemBuilder: (context, index) {
        final item = state.cart[index];
        return _PurchaseCartTile(
          item: item,
          index: index,
          onRemove: () => controller.removeFromCart(index),
          onQuantityChanged: (qty) => controller.updateQuantity(index, qty),
          onCostChanged: (cost) => controller.updateUnitCost(index, cost),
          onTaxRateChanged: (rate) =>
              controller.updateTaxRate(index, rate), // Added callback
        );
      },
    );
  }

  Widget _buildTotals(PurchasesState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: '?????? ?????????',
            value: state.total,
            isTotal: true,
          ),
          if (state.paid > 0)
            _TotalRow(
              label: '???????',
              value: state.paid,
              valueColor: AppColors.success,
            ),
          if (state.remaining > 0)
            _TotalRow(
              label: '???????',
              value: state.remaining,
              valueColor: AppColors.warning,
            ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(PurchasesState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: state.cart.isEmpty || state.isProcessing ? null : onSave,
          icon: state.isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsBold.floppyDisk),
          label: Text(state.isProcessing ? '???? ?????...' : '??? ????????'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Purchase cart item tile
class _PurchaseCartTile extends StatelessWidget {
  final PurchaseCartItemEntity item;
  final int index;
  final VoidCallback onRemove;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onCostChanged;
  final ValueChanged<double> onTaxRateChanged; // Added callback

  const _PurchaseCartTile({
    required this.item,
    required this.index,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onCostChanged,
    required this.onTaxRateChanged, // Added callback
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product info row
          Row(
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsBold.trash, size: 18),
                color: AppColors.error,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      item.productCode,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${item.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quantity and cost row
          Row(
            children: [
              // Quantity
              Expanded(
                child: Row(
                  children: [
                    const Text('??????: ', style: TextStyle(fontSize: 12)),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.minus, size: 14),
                      visualDensity: VisualDensity.compact,
                      onPressed: item.quantity > 1
                          ? () => onQuantityChanged(item.quantity - 1)
                          : onRemove,
                    ),
                    Text(item.quantity.toStringAsFixed(0)),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onQuantityChanged(item.quantity + 1),
                    ),
                  ],
                ),
              ),

              // Unit cost
              Expanded(
                child: TextField(
                  controller: TextEditingController(
                    text: item.unitCost.toStringAsFixed(AppConstants.decimalPlaces),
                  ),
                  decoration: const InputDecoration(
                    labelText: '?????',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onSubmitted: (value) {
                    final cost = double.tryParse(value);
                    if (cost != null) onCostChanged(cost);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Tax rate
              SizedBox(
                width: 80,
                child: TextField(
                  controller: TextEditingController(
                    text: item.taxRate.toStringAsFixed(0),
                  ),
                  decoration: const InputDecoration(
                    labelText: '????? %',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (value) {
                    final rate = double.tryParse(value);
                    if (rate != null) onTaxRateChanged(rate);
                  },
                ),
              ),
            ],
          ),

          // Batch info if present
          if (item.batchNumber != null || item.expiryDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '????: ${item.batchNumber ?? '-'} | ????????: ${item.expiryDate?.toString().split(' ')[0] ?? '-'}',
                style: const TextStyle(fontSize: 11, color: AppColors.info),
              ),
            ),
        ],
      ),
    );
  }
}

/// Total row widget
class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? valueColor;
  final bool isTotal;

  const _TotalRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? (isTotal ? AppColors.primary : null),
              fontSize: isTotal ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
