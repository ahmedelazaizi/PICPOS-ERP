import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../purchases_form_notifier.dart';
import '../../../../../../../core/constants/app_constants.dart';

class PurchaseItemsTable extends StatelessWidget {
  final List<PurchaseCartItem> cart;
  final Function(int, double) onUpdateQuantity;
  final Function(int, double) onUpdateUnitCost;
  final Function(int, double) onUpdateSalePrice;
  final Function(int, double) onUpdateTaxRate;
  final Function(int, String?) onUpdateBatchNumber;
  final Function(int) onSelectExpiryDate;
  final Function(int) onRemoveItem;
  final Function(int, int unitId, String unitName, double factor, double costPrice)? onUpdateUnit;

  const PurchaseItemsTable({
    super.key,
    required this.cart,
    required this.onUpdateQuantity,
    required this.onUpdateUnitCost,
    required this.onUpdateSalePrice,
    required this.onUpdateTaxRate,
    required this.onUpdateBatchNumber,
    required this.onSelectExpiryDate,
    required this.onRemoveItem,
    this.onUpdateUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            const Text(
              'لا توجد أصناف مختارة',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const Text(
              'ابحث عن صنف وأضفه للفاتورة',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          Theme.of(context).scaffoldBackgroundColor,
        ),
        columnSpacing: 12,
        columns: const [
          DataColumn(
            label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: Text(
              'اسم الصنف',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'الكمية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'سعر الشراء',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'سعر البيع',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'الضريبة %',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'رقم التشغيلة',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'الصلاحية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'الإجمالي',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        rows: cart.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(
                SizedBox(
                  width: 200,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      if (item.selectedUnitName != null)
                        Text(
                          item.selectedUnitName!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.info,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DataCell(
                _buildTableTextField(
                  initialValue: item.quantity.toStringAsFixed(0),
                  onChanged: (v) =>
                      onUpdateQuantity(index, double.tryParse(v) ?? 1),
                  width: 80,
                ),
              ),
              DataCell(
                _buildTableTextField(
                  initialValue: item.unitCost.toStringAsFixed(AppConstants.decimalPlaces),
                  onChanged: (v) =>
                      onUpdateUnitCost(index, double.tryParse(v) ?? 0),
                  width: 100,
                ),
              ),
              DataCell(
                _buildTableTextField(
                  initialValue: item.salePrice.toStringAsFixed(AppConstants.decimalPlaces),
                  onChanged: (v) =>
                      onUpdateSalePrice(index, double.tryParse(v) ?? 0),
                  width: 100,
                ),
              ),
              DataCell(
                _buildTableTextField(
                  initialValue: item.taxRate.toStringAsFixed(0),
                  onChanged: (v) =>
                      onUpdateTaxRate(index, double.tryParse(v) ?? 0),
                  suffixText: '%',
                  width: 70,
                ),
              ),
              DataCell(
                _buildTableTextField(
                  initialValue: item.batchNumber ?? '',
                  onChanged: (v) =>
                      onUpdateBatchNumber(index, v.isEmpty ? null : v),
                  hintText: 'Batch...',
                  isNumber: false,
                  width: 100,
                ),
              ),
              DataCell(
                InkWell(
                  onTap: () => onSelectExpiryDate(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.expiryDate == null
                              ? 'اختر تاريخ'
                              : DateFormat(
                                  'yyyy-MM-dd',
                                ).format(item.expiryDate!),
                          style: TextStyle(
                            fontSize: 12,
                            color: item.expiryDate == null
                                ? AppColors.textMuted
                                : null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.calendar_today, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
              DataCell(
                Text(
                  '${item.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  onPressed: () => onRemoveItem(index),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableTextField({
    required String initialValue,
    required Function(String) onChanged,
    double width = 100,
    String? suffixText,
    String? hintText,
    bool isNumber = true,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initialValue,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          suffixText: suffixText,
          hintText: hintText,
          hintStyle: const TextStyle(fontSize: 12),
        ),
        style: const TextStyle(fontSize: 13),
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: onChanged,
      ),
    );
  }
}
