import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../../domain/entities/product_entity.dart';
import '../sales_invoices_notifier.dart';
import '../../../../presentation/widgets/searchable_unit_selection_dialog.dart';

class SalesItemsTable extends ConsumerWidget {
  const SalesItemsTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesInvoicesFormProvider);
    final notifier = ref.read(salesInvoicesFormProvider.notifier);
    final currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

    // Product Search
    final products = ref.watch(allProductsProvider).value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product Search Section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('إضافة صنف:'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Autocomplete<ProductEntity>(
                optionsBuilder: (textValue) {
                  if (textValue.text.isEmpty) {
                    return const Iterable<ProductEntity>.empty();
                  }
                  return products.where(
                    (p) =>
                        p.name.toLowerCase().contains(
                          textValue.text.toLowerCase(),
                        ) ||
                        p.code.contains(textValue.text),
                  );
                },
                displayStringForOption: (p) => p.name,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration:  InputDecoration(
                          hintText: tr('ابحث عن صنف بالاسم أو الباركود...'),
                          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      );
                    },
                onSelected: (product) {
                  notifier.addToCart(product);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Items Table
         Text(
          tr('الأصناف في الفاتورة:'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (state.cart.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.border,
                style: BorderStyle.none,
              ),
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child:  Center(
              child: Text(
                tr('لم يتم إضافة أصناف بعد'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: DataTable(
              columnSpacing: 12,
              columns:  [
                DataColumn(label: Text(tr('الصنف'))),
                DataColumn(label: Text(tr('الوحدة'))),
                DataColumn(label: Text(tr('الكمية'))),
                DataColumn(label: Text(tr('السعر'))),
                DataColumn(label: Text(tr('الضريبة %'))),
                DataColumn(label: Text(tr('قيمة الضريبة'))),
                DataColumn(label: Text(tr('الإجمالي'))),
                const DataColumn(label: Text('')),
              ],
              rows: state.cart.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            item.productCode,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      InkWell(
                        onTap: () async {
                          final units = await ref.read(productRepositoryProvider).getProductUnits(item.productId);
                          if (units.isEmpty) return;

                          if (context.mounted) {
                            final selectedUnit = await showDialog<ProductUnit>(
                              context: context,
                              builder: (context) => SearchableUnitSelectionDialog(
                                units: units,
                                currentUnitName: item.selectedUnitName,
                              ),
                            );

                            if (selectedUnit != null) {
                              notifier.updateUnit(
                                idx,
                                unitId: selectedUnit.id,
                                unitName: selectedUnit.unitName,
                                quantityInBase: selectedUnit.quantityInBase,
                                unitPrice: selectedUnit.salePrice,
                              );
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.selectedUnitName ?? tr('قطعة'),
                                style: const TextStyle(
                                  color: AppColors.info,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(PhosphorIconsBold.caretDown, size: 12, color: AppColors.info),
                            ],
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          initialValue: '${item.quantity}',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          onChanged: (val) {
                            final qty = double.tryParse(val) ?? 1;
                            notifier.updateQuantity(idx, qty);
                          },
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: '${item.unitPrice}',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          onChanged: (val) {
                            final price = double.tryParse(val) ?? 0;
                            notifier.updateUnitPrice(idx, price);
                          },
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 140,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: item.taxEnabled,
                              visualDensity: VisualDensity.compact,
                              onChanged: (val) =>
                                  notifier.updateLineTaxEnabled(idx, val ?? false),
                            ),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('sales_tax_rate_${idx}_${item.productId}_${item.taxEnabled}'),
                                enabled: item.taxEnabled,
                                initialValue: item.taxRate.toStringAsFixed(0),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  suffixText: '%',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (val) {
                                  final rate = double.tryParse(val) ?? 0.0;
                                  notifier.updateLineTaxRate(idx, rate);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      Text(item.taxAmount.toStringAsFixed(AppConstants.decimalPlaces)),
                    ),
                    DataCell(
                      Text(
                        currencyFormat.format(item.total + item.taxAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.trash, size: 18),
                        color: AppColors.error,
                        onPressed: () => notifier.removeFromCart(idx),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
