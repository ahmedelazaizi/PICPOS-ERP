import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../domain/entities/product_entity.dart';

import '../../../data/providers/providers.dart';
import 'providers/inventory_bonds_controller.dart';

class InventoryBondsScreen extends ConsumerStatefulWidget {
  const InventoryBondsScreen({super.key});

  @override
  ConsumerState<InventoryBondsScreen> createState() =>
      _InventoryBondsScreenState();
}

class _InventoryBondsScreenState extends ConsumerState<InventoryBondsScreen> {
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
    final theme = Theme.of(context);
    final warehouses = ref.watch(allWarehousesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('أرصدة المخزون'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.floppyDisk),
            tooltip: 'حفظ السند',
            onPressed: _isSaving ? null : _saveBond,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.cardColor,
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
            const Divider(height: 1),

            // Items Table
            Expanded(
              child: Container(
                color: AppColors.surface,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
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
                                              keyboardType:
                                                  TextInputType.number,
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
                                              initialValue: item.costPrice
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.number,
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
                                              initialValue: item.salePrice
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.number,
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
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        label: const Text('إضافة صنف'),
        icon: const Icon(PhosphorIconsBold.plus),
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
