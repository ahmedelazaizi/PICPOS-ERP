import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../data/providers/providers.dart';
import 'providers/stock_transfer_controller.dart';

class StockTransferScreen extends ConsumerStatefulWidget {
  const StockTransferScreen({super.key});

  @override
  ConsumerState<StockTransferScreen> createState() =>
      _StockTransferScreenState();
}

class _StockTransferScreenState extends ConsumerState<StockTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  int? _fromWarehouseId;
  int? _toWarehouseId;
  final List<TransferItemModel> _items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultWarehouse();
  }

  Future<void> _loadDefaultWarehouse() async {
    final warehouseId = await ref
        .read(stockTransferControllerProvider.notifier)
        .getDefaultWarehouseId();
    if (warehouseId != null && mounted) {
      setState(() {
        _fromWarehouseId = warehouseId;
      });
    }
  }

  void _addItem() async {
    if (_fromWarehouseId == null) {
      AppToast.show(context, tr('يرجى اختيار مستودع المصدر أولاً'));
      return;
    }

    final product = await showDialog<ProductEntity>(
      context: context,
      builder: (context) => _ProductSearchDialog(),
    );

    if (product != null) {
      if (_items.any((item) => item.product.id == product.id)) {
        if (!mounted) return;
        AppToast.show(context, tr('هذا الصنف موجود بالفعل في القائمة'));
        return;
      }

      // Resolve the warehouse-specific average cost
      final warehouseCost = await ref
          .read(stockTransferControllerProvider.notifier)
          .getProductWarehouseCost(product.id, _fromWarehouseId!);

      setState(() {
        _items.add(TransferItemModel(
          product: product,
          quantity: 1,
          costPrice: warehouseCost,
        ));
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _saveTransfer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      AppToast.show(context, tr('يجب إضافة أصناف للتحويل'));
      return;
    }
    if (_fromWarehouseId == null || _toWarehouseId == null) {
      AppToast.show(context, tr('يرجى اختيار مستودع المصدر والوجهة'));
      return;
    }
    if (_fromWarehouseId == _toWarehouseId) {
      AppToast.show(context, tr('لا يمكن التحويل لنفس المستودع'));
      return;
    }

    setState(() => _isSaving = true);

    final success = await ref
        .read(stockTransferControllerProvider.notifier)
        .saveTransfer(
          fromWarehouseId: _fromWarehouseId!,
          toWarehouseId: _toWarehouseId!,
          notes: _notesController.text,
          items: _items,
        );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      AppToast.show(
        context,
        tr('تمت عملية التحويل بنجاح'),
        type: ToastType.success,
      );

      setState(() {
        _items.clear();
        _notesController.clear();
      });
    } else {
      // Spec 117 (Bug I) — قبلاً عند فشل التحويل، لا toast يظهر فالـ user
      // يرى الزر مرّ بدون أي feedback (silent failure). الآن نعرض
      // الـ controller error كـ toast مع fallback عام.
      final errorMsg = ref.read(stockTransferControllerProvider).error
          ?? tr('تعذّر حفظ التحويل المخزني — حاول مرة أخرى');
      AppToast.show(
        context,
        errorMsg,
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
        title:  Text(tr('تحويل مخزني')),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.check),
            tooltip: tr('تنفيذ التحويل'),
            onPressed: _isSaving ? null : _saveTransfer,
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
                        child: warehouses.when(
                          data: (list) => DropdownButtonFormField<int>(
                            initialValue: _fromWarehouseId,
                            decoration:  InputDecoration(
                              labelText: tr('تحويل من (المصدر)'),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                PhosphorIconsBold.arrowUpRight,
                                color: AppColors.error,
                              ),
                            ),
                            items: list
                                .map(
                                  (w) => DropdownMenuItem(
                                    value: w.id,
                                    child: Text(trData(w.name)),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _fromWarehouseId = val),
                            validator: (val) => val == null ? tr('مطلوب') : null,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) =>  Text(tr('خطأ')),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        PhosphorIconsBold.arrowRight,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: warehouses.when(
                          data: (list) => DropdownButtonFormField<int>(
                            initialValue: _toWarehouseId,
                            decoration:  InputDecoration(
                              labelText: tr('تحويل إلى (الوجهة)'),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                PhosphorIconsBold.arrowDownLeft,
                                color: Colors.green,
                              ),
                            ),
                            items: list
                                .map(
                                  (w) => DropdownMenuItem(
                                    value: w.id,
                                    child: Text(trData(w.name)),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _toWarehouseId = val),
                            validator: (val) => val == null ? tr('مطلوب') : null,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) =>  Text(tr('خطأ')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration:  InputDecoration(
                      labelText: tr('ملاحظات التحويل'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
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
                            ?  Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Text(
                                    tr('أضف الأصناف المراد تحويلها'),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns:  [
                                    DataColumn(label: Text(tr('الصنف'))),
                                    DataColumn(label: Text(tr('الرصيد الكلي'))),
                                    DataColumn(label: Text(tr('التكلفة')), numeric: true),
                                    DataColumn(label: Text(tr('الكمية المحولة'))),
                                    DataColumn(label: Text(tr('حذف'))),
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
                                        DataCell(
                                          Text(
                                            item.product.currentStock
                                                .toStringAsFixed(2),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            item.costPrice
                                                .toStringAsFixed(AppConstants.decimalPlaces),
                                            style: const TextStyle(
                                              color: AppColors.info,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 120,
                                            child: TextFormField(
                                              initialValue: item.quantity
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              onChanged: (val) {
                                                item.quantity =
                                                    double.tryParse(val) ?? 0;
                                              },
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          IconButton(
                                            icon: const Icon(
                                              PhosphorIconsBold.trash,
                                              color: AppColors.error,
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
        label:  Text(tr('إضافة صنف للتحويل')),
        icon: const Icon(PhosphorIconsBold.plus),
      ),
    );
  }
}

class _ProductSearchDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends ConsumerState<_ProductSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:  Text(tr('اختيار صنف للتحويل')),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              decoration:  InputDecoration(
                labelText: tr('بحث بالاسم أو الباركود...'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _query = val;
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final productsAsync = _query.isEmpty
                      ? ref.watch(allProductsProvider)
                      : ref.watch(searchProductsProvider(_query));

                  return productsAsync.when(
                    data: (products) {
                      if (products.isEmpty) {
                        return  Center(
                          child: Text(tr('لا توجد نتائج مطابقة')),
                        );
                      }
                      return ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final p = products[index];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                              tr('باركود: {p0} | المخزون الكلي: {p1}', {'p0': p.code, 'p1': p.currentStock}),
                            ),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      );
                    },
                    loading: () => Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    ),
                    error: (e, s) => Text(friendlyError(e)),
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
          child:  Text(tr('إلغاء')),
        ),
      ],
    );
  }
}
