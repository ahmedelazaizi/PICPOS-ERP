// منطق منسوخ من inventory_bonds_screen.dart (monolith) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/inventory/inventory_bonds_screen.dart)
// مونوليث ٤٦٠ سطر بلا `part of` files. الـ State (_InventoryBondsScreenState)
// بما فيها initState (تحميل المستودع الافتراضي + توليد رقم السند التلقائي)
// وإضافة/حذف صنف وحفظ/تصفير السند بعد النجاح — كل ده مكتوب inline. بما إنه
// مفيش part نقدر نستوردها، فالفورك هنا بينسخ جسم الدوال دي حرفياً بلا أي
// تعديل منطقي (بما فيها تعليقات المواصفة على رسائل النجاح/التصفير بعد الحفظ)
// — يتغيّر بس اسم الكلاس وطبقة العرض (تستخدم picpos_shell بدل
// Scaffold+AppBar+FloatingActionButton). `_ProductSearchDialog` كلاس داخلي
// خاص (private) في الأصل فبينُسخ حرفياً هنا كمان (نفس قاعدة النسخ).
// `inventoryBondsControllerProvider` و`BondItemModel` و`allWarehousesProvider`
// و`allProductsProvider` و`searchProductsProvider` مُعاد استخدامهم من UralCash
// زي ما هم (import، مش نسخ).
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../domain/entities/product_entity.dart';

import '../../../data/providers/providers.dart';
import '../../screens/inventory/providers/inventory_bonds_controller.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_toolbar.dart';

/// شاشة سندات المخزون بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `inventoryBondsControllerProvider`
/// (وتوابعه `InventoryBondsState`/`InventoryBondsNotifier`/`BondItemModel`)
/// و`allWarehousesProvider`/`allProductsProvider`/`searchProductsProvider` من
/// UralCash — فقط طبقة العرض تبدّلت لـ picpos_shell (هيدر + PicPosContentCard
/// حول جدول الأصناف بدل Scaffold+AppBar، وPicPosToolbar بدل
/// FloatingActionButton).
///
/// FULL PARITY مع الأصل: قائمة نوع السند (رصيد افتتاحي/سند إضافة)، قائمة
/// المستودع (مطلوبة)، رقم السند التلقائي (BND- + طابع زمني)، حقل الملاحظات،
/// جدول الأصناف بأعمدته الثمانية (الصنف/التصنيف/المورد/الرصيد الحالي/الكمية
/// المضافة/سعر التكلفة/سعر البيع/حذف) بحقوله القابلة للتعديل مباشرة، حوار بحث
/// الصنف (`_ProductSearchDialog`)، حفظ السند وتصفير النموذج بعد النجاح مع
/// إبقاء المستودع مختاراً، وكل رسائل التوست/التحقق.
///
/// راجع lib/presentation/screens/inventory/inventory_bonds_screen.dart (الأصل).
class InventoryBondsPicposScreen extends ConsumerStatefulWidget {
  const InventoryBondsPicposScreen({super.key});

  @override
  ConsumerState<InventoryBondsPicposScreen> createState() =>
      _InventoryBondsPicposScreenState();
}

class _InventoryBondsPicposScreenState
    extends ConsumerState<InventoryBondsPicposScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bondNumberController = TextEditingController();
  final _notesController = TextEditingController();

  String _bondType = 'opening'; // opening, in
  int? _selectedWarehouseId;
  final DateTime _bondDate = DateTime.now();

  // Items in the bond
  final List<BondItemModel> _items = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultWarehouse();
    _bondNumberController.text = 'BND-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _loadDefaultWarehouse() async {
    final warehouseId = await ref
        .read(inventoryBondsControllerProvider.notifier)
        .getDefaultWarehouseId();
    if (warehouseId != null && mounted) {
      setState(() {
        _selectedWarehouseId = warehouseId;
      });
    }
  }

  void _addItem() async {
    // Open product search dialog
    final product = await showDialog<ProductEntity>(
      context: context,
      builder: (context) => _ProductSearchDialog(),
    );

    if (product != null) {
      // Check if already exists
      if (_items.any((item) => item.product.id == product.id)) {
        if (!mounted) return;
        AppToast.show(context, 'هذا الصنف موجود بالفعل في السند');
        return;
      }

      // Fetch extra details (Supplier, Category Name)
      final itemModel = await ref
          .read(inventoryBondsControllerProvider.notifier)
          .getProductDetailsForBond(product);
      if (itemModel != null) {
        setState(() {
          _items.add(itemModel);
        });
      }
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _saveBond() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      AppToast.show(context, 'يجب إضافة أصناف للسند');
      return;
    }
    if (_selectedWarehouseId == null) {
      AppToast.show(context, 'يرجى اختيار المستودع');
      return;
    }

    setState(() => _isSaving = true);

    final success = await ref
        .read(inventoryBondsControllerProvider.notifier)
        .saveBond(
          bondType: _bondType,
          warehouseId: _selectedWarehouseId!,
          notes: _notesController.text,
          items: _items,
          date: _bondDate,
        );

    setState(() => _isSaving = false);

    if (success && mounted) {
      // Spec 109 US2 — explicit success message naming what just happened
      // (JE + balances added) so the user knows the work is complete and
      // does not re-tap the save button.
      AppToast.show(
        context,
        'تم إضافة قيد السند المخزني وإضافة الأرصدة بنجاح',
        type: ToastType.success,
      );

      // Reset form — full clear so a stray tap on save produces only the
      // "أضف أصنافاً" guard rather than a duplicate bond.
      _formKey.currentState?.reset();
      setState(() {
        _items.clear();
        _bondNumberController.text =
            'BND-${DateTime.now().millisecondsSinceEpoch}';
        _notesController.clear();
        // Warehouse selection is kept on purpose: cashiers typically add
        // multiple bonds for the same warehouse in a row.
      });
    } else if (mounted) {
      AppToast.show(
        context,
        'فشل حفظ السند — راجع البيانات وحاول مرة أخرى',
        type: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(allWarehousesProvider);

    return PicPosScreenScaffold(
      title: 'سندات المخزون',
      subtitle: 'إدخال وإخراج المخزون بالسندات',
      icon: PhosphorIconsBold.stackPlus,
      headerActions: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.floppyDisk),
          tooltip: 'حفظ السند',
          onPressed: _isSaving ? null : _saveBond,
        ),
      ],
      toolbar: PicPosToolbar(
        children: [
          ElevatedButton.icon(
            onPressed: _addItem,
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('إضافة صنف'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section
            PicPosContentCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _bondType,
                          decoration: const InputDecoration(
                            labelText: 'نوع السند',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'opening',
                              child: Text('رصيد افتتاحي (Opening Balance)'),
                            ),
                            DropdownMenuItem(
                              value: 'in',
                              child: Text('سند إضافة (Add Stock)'),
                            ),
                          ],
                          onChanged: (val) => setState(() => _bondType = val!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: warehouses.when(
                          data: (list) => DropdownButtonFormField<int>(
                            initialValue: _selectedWarehouseId,
                            decoration: const InputDecoration(
                              labelText: 'المستودع',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: list
                                .map(
                                  (w) => DropdownMenuItem(
                                    value: w.id,
                                    child: Text(w.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedWarehouseId = val),
                            validator: (val) => val == null ? 'مطلوب' : null,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) =>
                              const Text('خطأ في تحميل المستودعات'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _bondNumberController,
                          decoration: const InputDecoration(
                            labelText: 'رقم السند',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          readOnly: true, // Auto-generated for now
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Items Table
            Expanded(
              child: PicPosContentCard(
                padding: const EdgeInsets.all(8),
                child: _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'لم يتم إضافة أصناف بعد. اضغط على زر الإضافة (+)',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 20,
                          columns: const [
                            DataColumn(label: Text('الصنف')),
                            DataColumn(label: Text('التصنيف')),
                            DataColumn(label: Text('المورد')),
                            DataColumn(label: Text('الرصيد الحالي')),
                            DataColumn(label: Text('الكمية المضافة')),
                            DataColumn(label: Text('سعر التكلفة')),
                            DataColumn(label: Text('سعر البيع')),
                            DataColumn(label: Text('حذف')),
                          ],
                          rows: _items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(Text(item.categoryName)),
                                DataCell(Text(item.supplierName)),
                                DataCell(
                                  Text(
                                    item.product.currentStock
                                        .toStringAsFixed(2),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      initialValue: item.quantity > 0
                                          ? item.quantity.toString()
                                          : '',
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        hintText: '0',
                                      ),
                                      onChanged: (val) {
                                        item.quantity =
                                            double.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      initialValue:
                                          item.costPrice.toString(),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) {
                                        item.costPrice =
                                            double.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      initialValue:
                                          item.salePrice.toString(),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) {
                                        item.salePrice =
                                            double.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(
                                      PhosphorIconsBold.trash,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSearchDialog extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Simple search dialog
    return AlertDialog(
      title: const Text('بحث عن صنف'),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'بحث...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                // Implement live search provider update here if needed
                // For now we assume the provider refetches or filters
                ref.invalidate(searchProductsProvider(val));
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  // We'll use a specific provider for searching or just watchAllProducts and filter locally for simplicity in this specific ephemeral dialog
                  final allProducts = ref.watch(allProductsProvider);
                  return allProducts.when(
                    data: (products) {
                      // Local filtering for demo
                      return ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final p = products[index];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                              'Code: ${p.code} | Stock: ${p.currentStock}',
                            ),
                            trailing: Text('${p.salePrice}'),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      );
                    },
                    loading: () => Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    ),
                    error: (e, s) => Text('Error: $e'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
