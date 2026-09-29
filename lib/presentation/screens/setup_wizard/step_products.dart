part of '../setup_wizard_screen.dart';

extension _SetupWizardProductsExt on _SetupWizardScreenState {
  // ═══════════════════════════════════════════════════════════════════════
  // STEP 3: Products
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildProductsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(
          tr('أضف منتجاتك الأولى'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
         Text(
          tr('أضف بعض المنتجات للبدء. يمكنك استيراد المزيد لاحقاً من ملف Excel.'),
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        // Add Product Form
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _productNameController,
                        label: tr('اسم المنتج'),
                        hint: tr('مثال: حليب كامل الدسم'),
                        icon: PhosphorIconsBold.package,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _productPriceController,
                        label: tr('سعر البيع'),
                        hint: '25.00',
                        icon: PhosphorIconsBold.tag,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _productCostController,
                        label: tr('سعر الشراء'),
                        hint: '20.00',
                        icon: PhosphorIconsBold.money,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(PhosphorIconsBold.plus, size: 16),
                      label:  Text(tr('إضافة')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Product list
        if (_sampleProducts.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(PhosphorIconsBold.package,
                    size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                 Text(
                  tr('لم تُضف منتجات بعد — يمكنك تخطي هذه الخطوة'),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          )
        else
          ...List.generate(_sampleProducts.length, (i) {
            final p = _sampleProducts[i];
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text('${i + 1}',
                      style: const TextStyle(color: AppColors.primary)),
                ),
                title: Text(p['name']!,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(tr('بيع: {p0}  |  شراء: {p1}', {'p0': p['price'], 'p1': p['cost']})),
                trailing: IconButton(
                  icon: const Icon(PhosphorIconsBold.trash,
                      color: AppColors.error, size: 18),
                  onPressed: () =>
                      setState(() => _sampleProducts.removeAt(i)),
                ),
              ),
            );
          }),
      ],
    );
  }
}
