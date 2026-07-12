import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/searchable_dropdown.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../widgets/dialogs/add_product_dialog.dart';
import '../purchases_form_notifier.dart';
import 'purchase_items_table.dart';
import '../../../../../../../core/constants/app_constants.dart';
import '../../../../data/providers/manufacturing_providers.dart';

class PurchaseForm extends ConsumerStatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final TextEditingController paidController;
  final TextEditingController notesController;
  final TextEditingController supplierInvoiceController;

  const PurchaseForm({
    super.key,
    required this.onSave,
    required this.onCancel,
    required this.paidController,
    required this.notesController,
    required this.supplierInvoiceController,
  });

  @override
  ConsumerState<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends ConsumerState<PurchaseForm> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchasesFormProvider);
    final notifier = ref.read(purchasesFormProvider.notifier);
    final products = ref.watch(allProductsProvider);

    final filteredProducts = products.when(
      data: (prods) {
        return _searchController.text.isEmpty
            ? prods
            : prods
                  .where(
                    (p) =>
                        p.name.contains(_searchController.text) ||
                        p.code.contains(_searchController.text),
                  )
                  .toList();
      },
      loading: () => <ProductEntity>[],
      error: (_, _) => <ProductEntity>[],
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Supplier Selection Row
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.user, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'المورد:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ref
                        .watch(allSuppliersProvider)
                        .when(
                          data: (suppliers) => PartySearchableDropdown(
                            parties: suppliers,
                            selectedId: state.selectedSupplierId,
                            label: 'اختر المورد',
                            hint: 'ابحث عن المورد...',
                            isRequired: true,
                            onChanged: (v) => notifier.selectSupplier(v),
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('خطأ: $e'),
                        ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: widget.supplierInvoiceController,
                      decoration: const InputDecoration(
                        labelText: 'رقم فاتورة المورد',
                        hintText: 'أدخل الرقم اليدوي...',
                        prefixIcon: Icon(PhosphorIconsBold.hash),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => notifier.updateSupplierInvoiceNumber(v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Warehouse Selection
                  SizedBox(
                    width: 220,
                    child: ref.watch(warehouseListProvider).when(
                      data: (warehouses) => DropdownButtonFormField<int?>(
                        initialValue: state.selectedWarehouseId ?? (warehouses.isNotEmpty ? warehouses.first.id : null),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'المستودع',
                          isDense: true,
                          prefixIcon: Icon(PhosphorIconsBold.warehouse, size: 18),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: warehouses.map((w) => DropdownMenuItem<int?>(
                          value: w.id,
                          child: Text(w.name, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => notifier.selectWarehouse(v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('خطأ: $e'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(PhosphorIconsBold.userPlus),
                    tooltip: 'إضافة مورد جديد',
                    color: AppColors.primary,
                    onPressed: () {
                      // Handled by parent screen to use context correctly
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Products Search Panel (Left)
                SizedBox(
                  width: 320,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                PhosphorIconsBold.magnifyingGlass,
                                size: 20,
                                color: AppColors.info,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'البحث عن أصناف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'اسم الصنف أو الكود...',
                              prefixIcon: const Icon(
                                PhosphorIconsBold.magnifyingGlass,
                                size: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await AddProductDialog.show(
                                context,
                              );
                              if (result != null) {
                                ref.invalidate(allProductsProvider);
                                final newProduct = await ref
                                    .read(productRepositoryProvider)
                                    .getProductById(result.productId);
                                if (newProduct != null && mounted) {
                                  notifier.addToCart(newProduct);
                                }
                              }
                            },
                            icon: const Icon(PhosphorIconsBold.plus, size: 16),
                            label: const Text('إضافة صنف جديد'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.success,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final p = filteredProducts[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${p.costPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        PhosphorIconsBold.plus,
                                        color: AppColors.success,
                                      ),
                                      onPressed: () => notifier.addToCart(p),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Cart Panel (Right)
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                PhosphorIconsBold.shoppingCart,
                                size: 20,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'الأصناف المختارة',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${state.cart.length} صنف',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Expanded(
                            child: PurchaseItemsTable(
                              cart: state.cart,
                              onUpdateQuantity: (idx, qty) =>
                                  notifier.updateQuantity(idx, qty),
                              onUpdateUnitCost: (idx, cost) =>
                                  notifier.updateUnitCost(idx, cost),
                              onUpdateSalePrice: (idx, price) =>
                                  notifier.updateSalePrice(idx, price),
                              onUpdateTaxRate: (idx, rate) =>
                                  notifier.updateTaxRate(idx, rate),
                              onUpdateBatchNumber: (idx, value) =>
                                  notifier.updateBatchNumber(idx, value),
                              onSelectExpiryDate: (idx) =>
                                  _selectExpiryDate(context, ref, idx),
                              onRemoveItem: (idx) =>
                                  notifier.removeFromCart(idx),
                            ),
                          ),

                          const Divider(height: 24),
                          _buildSummaryAndActions(state),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndActions(PurchasesFormState state) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(
                      'المجموع:',
                      '${state.subtotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    ),
                    const SizedBox(height: 4),
                    _buildSummaryRow(
                      'الضريبة:',
                      '${state.tax.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    ),
                    const Divider(),
                    _buildSummaryRow(
                      'الإجمالي النهائي:',
                      '${state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: widget.paidController,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المدفوع',
                      prefixIcon: Icon(PhosphorIconsBold.currencyCircleDollar),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) => ref
                        .read(purchasesFormProvider.notifier)
                        .updatePaidAmount(double.tryParse(v) ?? 0),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: widget.notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      prefixIcon: Icon(PhosphorIconsBold.note),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(PhosphorIconsBold.x),
              label: const Text('إلغاء'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: state.isLoading ? null : widget.onSave,
              icon: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(PhosphorIconsBold.check),
              label: Text(state.isEditMode ? 'تحديث الفاتورة' : 'حفظ الفاتورة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : null,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : null,
          ),
        ),
      ],
    );
  }

  Future<void> _selectExpiryDate(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    final cart = ref.read(purchasesFormProvider).cart;
    final currentDate = index < cart.length ? cart[index].expiryDate : null;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      ref.read(purchasesFormProvider.notifier).updateExpiryDate(index, picked);
    }
  }
}
