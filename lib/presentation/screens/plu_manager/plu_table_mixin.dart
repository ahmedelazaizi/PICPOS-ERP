part of '../plu_manager_screen.dart';

mixin _PluTableMixin on ConsumerState<PluManagerScreen> {
  // Abstract members satisfied by _PluManagerScreenState
  Map<int, TextEditingController> get _pluControllers;
  Future<void> _savePlu(Product product, String pluText);
  Future<void> _clearPlu(Product product);
  Future<void> _toggleWeight(Product product, bool isWeight);

  // ═══════════════════════════════════════════════════════════════════
  // PRODUCT TABLE
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildProductTable(List<Product> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsBold.magnifyingGlass,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'لا توجد نتائج',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 50, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('اسم المنتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 100, child: Text('الكود', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 60, child: Center(child: Text('وزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                SizedBox(width: 130, child: Text('رقم PLU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Center(child: Text('إجراءات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: products.length,
              itemBuilder: (ctx, i) => _buildProductRow(products[i], i),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text('إجمالي: ${products.length} صنف', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 16),
                Text('مُعيّن PLU: ${products.where((p) => p.scalePluNumber != null).length}', style: const TextStyle(fontSize: 12, color: AppColors.success)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product product, int index) {
    final hasPlu = product.scalePluNumber != null;
    final controller = _pluControllers[product.id] ??= TextEditingController(
      text: product.scalePluNumber?.toString() ?? '',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : AppColors.surface.withValues(alpha: 0.5),
        border: hasPlu ? const Border(right: BorderSide(color: AppColors.success, width: 3)) : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (product.isSoldByWeight)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 4),
                    child: Icon(PhosphorIconsBold.scales, size: 14, color: AppColors.warning),
                  ),
                Expanded(
                  child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          SizedBox(width: 100, child: Text(product.code, style: const TextStyle(fontSize: 12, fontFamily: AppTypography.mono, color: AppColors.textMuted))),
          SizedBox(width: 80, child: Text(product.salePrice.toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          SizedBox(
            width: 60,
            child: Center(
              child: Switch(
                value: product.isSoldByWeight,
                onChanged: (v) => _toggleWeight(product, v),
                activeThumbColor: AppColors.warning,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'أدخل PLU',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                suffixIcon: hasPlu ? const Icon(PhosphorIconsBold.checkCircle, color: AppColors.success, size: 16) : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13, fontFamily: AppTypography.mono, fontWeight: FontWeight.bold),
              onSubmitted: (v) => _savePlu(product, v),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _savePlu(product, controller.text),
                  tooltip: 'حفظ PLU',
                  color: AppColors.primary,
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.trash, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _clearPlu(product),
                  tooltip: 'حذف PLU',
                  color: AppColors.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
