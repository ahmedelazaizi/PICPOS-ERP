import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// Quick-add product dialog shown when scanning an unknown barcode.
/// Allows cashier to quickly add a product with minimal info without
/// leaving the POS screen.
class QuickAddProductDialog extends ConsumerStatefulWidget {
  final String barcode;

  const QuickAddProductDialog({super.key, required this.barcode});

  /// Show the dialog and return the product ID if created, null if cancelled.
  static Future<int?> show(BuildContext context, String barcode) {
    return showDialog<int?>(
      context: context,
      builder: (_) => QuickAddProductDialog(barcode: barcode),
    );
  }

  @override
  ConsumerState<QuickAddProductDialog> createState() =>
      _QuickAddProductDialogState();
}

class _QuickAddProductDialogState
    extends ConsumerState<QuickAddProductDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  int? _selectedCategoryId;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text) ?? 0;

    if (name.isEmpty) {
      AppToast.show(context, tr('يرجى إدخال اسم الصنف'), type: ToastType.warning);
      return;
    }
    if (price <= 0) {
      AppToast.show(context, tr('يرجى إدخال سعر صحيح'), type: ToastType.warning);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Day 6C: use repository convenience method — no Drift types in presentation.
      //
      // Spec 029 / US5 — REVERTS Cluster 024 / Issue 8 belt-and-suspenders.
      // The previous fix persisted `allowNegativeSale=true` on the new
      // product row whenever the global toggle was ON at quick-add time.
      // Side effect: if the operator later turned the global toggle OFF,
      // the per-product flag stayed true and the cart guard's
      // `!product.allowNegativeSale` short-circuited — the product kept
      // selling at negative stock contrary to the operator's intent.
      //
      // Fix: leave the column default (false) on the new row. The cart's
      // OR-of-flags handles the dynamic case correctly:
      //   - global ON → `!globalNegativeSales` is false → gate doesn't fire
      //   - global OFF → both flags false → gate fires (correct)
      // The provider-loading race that motivated Cluster 024 is now
      // closed by eager-loading `enableNegativeSalesProvider` at app
      // startup (see main.dart). With the value populated by the time
      // the POS screen is interactive, the `?? false` fallback in the
      // cart guard is defensive remnant only.
      //
      // See specs/029-sync-regression-hardening/contracts/quick-add-neg-sales.md.
      final productRepo = ref.read(productRepositoryProvider);
      final id = await productRepo.quickAddProduct(
        name: name,
        salePrice: price,
        barcode: widget.barcode.isEmpty ? null : widget.barcode,
        categoryId: _selectedCategoryId,
      );

      // Issue 9 (Feature 018): on client mode the create routes through
      // ClientWriteInterceptor and the local Drift table sees no write until
      // the next pull-sync, so allProductsProvider's stream doesn't re-emit.
      // Invalidating forces the POS grid to re-fetch and pick up the new row.
      // Spec 150 BUG-1: the grid moved onto posGridProductsProvider, so refresh
      // that one too (allProductsProvider still backs other product lists).
      ref.invalidate(allProductsProvider);
      ref.invalidate(posGridProductsProvider);

      if (mounted) {
        AppToast.show(
          context,
          tr('✅ تم إضافة "{name}" بنجاح', {'name': name}),
          type: ToastType.success,
        );
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(visibleCategoriesProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.plusCircle, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('إضافة صنف جديد سريعة'))),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barcode (locked)
              TextField(
                readOnly: true,
                controller: TextEditingController(text: widget.barcode),
                decoration: InputDecoration(
                  labelText: tr('الباركود'),
                  prefixIcon: const Icon(PhosphorIconsBold.barcode),
                  border: const OutlineInputBorder(),
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),

              // Product name
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration:  InputDecoration(
                  labelText: tr('اسم الصنف *'),
                  prefixIcon: const Icon(PhosphorIconsBold.tag),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Sale price
              TextField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration:  InputDecoration(
                  labelText: tr('سعر البيع *'),
                  prefixIcon: const Icon(PhosphorIconsBold.currencyDollar),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Category dropdown
              categoriesAsync.when(
                data: (categories) => DropdownButtonFormField<int?>(
                  initialValue: _selectedCategoryId,
                  isExpanded: true,
                  decoration:  InputDecoration(
                    labelText: tr('التصنيف (اختياري)'),
                    prefixIcon: const Icon(PhosphorIconsBold.folders),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                     DropdownMenuItem(
                      value: null,
                      child: Text(tr('بدون تصنيف')),
                    ),
                    ...categories.map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (val) =>
                      setState(() => _selectedCategoryId = val),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) =>  Text(tr('خطأ في تحميل التصنيفات')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsBold.floppyDisk),
            label:  Text(tr('حفظ وإضافة للسلة')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
