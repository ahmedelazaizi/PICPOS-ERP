import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../domain/entities/stock_requisition_item_entity.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../data/providers/providers.dart';
import 'dart:ui' as ui;
import 'providers/stock_requisitions_controller.dart';
// To reuse _ProductSearchDialog if it's public, otherwise we can recreate it.

// Reusing Item Model format for UI state
class RequisitionItemModel {
  final ProductEntity product;
  double quantity;
  String? notes;

  RequisitionItemModel({
    required this.product,
    this.quantity = 1.0,
    this.notes,
  });
}

class StockRequisitionCreateScreen extends ConsumerStatefulWidget {
  const StockRequisitionCreateScreen({super.key});

  @override
  ConsumerState<StockRequisitionCreateScreen> createState() => _StockRequisitionCreateScreenState();
}

class _StockRequisitionCreateScreenState extends ConsumerState<StockRequisitionCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  int? _fromBranchId; // The branch asking for stock
  int? _toBranchId;   // The branch sending stock
  final List<RequisitionItemModel> _items = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _addItem() async {
    // We typically search products. A custom dialog or extending existing ones.
    // For simplicity, we use a basic dialog here or import existing product search dialog.
    // In URAL-ERP, you might have ProductSearchDialog. Let's do a basic one.
    final product = await _showProductSearchDialog();
    if (product != null) {
      if (_items.any((item) => item.product.id == product.id)) {
        if (!mounted) return;
        AppToast.show(context, 'هذا الصنف موجود بالفعل في القائمة', type: ToastType.warning);
        return;
      }
      setState(() {
        _items.add(RequisitionItemModel(product: product, quantity: 1));
      });
    }
  }

  Future<ProductEntity?> _showProductSearchDialog() async {
    // This is a simplified version, it assumes you have a searchProductsProvider
    return showDialog<ProductEntity>(
      context: context,
      builder: (context) => _ProductSearchDialogRequisition(),
    );
  }

  Future<void> _removeItem(int index) async {
    // BUG-U38: confirm before dropping an entered requisition line.
    final ok = await AppConfirmDialog.show(
      context,
      title: 'حذف السطر',
      message: 'هل تريد حذف هذا الصنف من الطلب؟',
      confirmLabel: 'حذف',
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _saveRequisition() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      AppToast.show(context, 'يجب إضافة أصناف للطلب', type: ToastType.error);
      return;
    }
    if (_fromBranchId == null || _toBranchId == null) {
      AppToast.show(context, 'يرجى اختيار الفرع الطالب والمورد', type: ToastType.error);
      return;
    }
    if (_fromBranchId == _toBranchId) {
      AppToast.show(context, 'لا يمكن الطلب من نفس الفرع', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    final reqItems = _items.map((item) => StockRequisitionItemEntity(
      id: 0,
      requisitionId: 0, // Ignored by companion insertion
      productId: item.product.id,
      quantity: item.quantity,
      notes: item.notes,
    )).toList();

    final error = await ref
        .read(stockRequisitionsControllerProvider.notifier)
        .createRequisition(
          fromBranchId: _fromBranchId!,
          toBranchId: _toBranchId!,
          notes: _notesController.text,
          items: reqItems,
        );

    setState(() => _isSaving = false);

    if (error == null && mounted) {
      AppToast.show(context, 'تم حفظ الطلب بنجاح', type: ToastType.success);
      Navigator.pop(context, true); // Return true to indicate success
    } else if (mounted) {
      // BUG-U18: show the actual reason from the controller, not a generic line.
      AppToast.show(context, error ?? 'حدث خطأ أثناء حفظ الطلب',
          type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branchesState = ref.watch(userAccessibleBranchesProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إنشاء طلب صرف قيد الانتظار'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.check),
              tooltip: 'حفظ الطلب',
              onPressed: _isSaving ? null : _saveRequisition,
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header Settings
              Container(
                padding: const EdgeInsets.all(16),
                color: theme.cardColor,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: branchesState.when(
                            data: (branches) {
                              return DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'الفرع الطالب (لي)',
                                  border: OutlineInputBorder(),
                                ),
                                initialValue: _fromBranchId,
                                items: branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                                onChanged: (v) => setState(() => _fromBranchId = v),
                                validator: (v) => v == null ? 'مطلوب' : null,
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (err, stack) => const Text('خطأ في تحميل الفروع'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: branchesState.when(
                            data: (branches) {
                              return DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'الفرع المورد (منه)',
                                  border: OutlineInputBorder(),
                                ),
                                initialValue: _toBranchId,
                                items: branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                                onChanged: (v) => setState(() => _toBranchId = v),
                                validator: (v) => v == null ? 'مطلوب' : null,
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (err, stack) => const Text('خطأ في تحميل الفروع'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (أسباب الطلب أو تفاصيل النقل)',
                        border: OutlineInputBorder(),
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
                        child: _items.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Text('أضف الأصناف التي ترغب بطلبها', style: TextStyle(color: Colors.grey)),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('الصنف')),
                                    DataColumn(label: Text('الكمية المطلوبة')),
                                    DataColumn(label: Text('ملاحظات الصنف')),
                                    DataColumn(label: Text('حذف')),
                                  ],
                                  rows: _items.asMap().entries.map((e) {
                                    final index = e.key;
                                    final item = e.value;
                                    return DataRow(cells: [
                                      DataCell(Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                      DataCell(
                                        SizedBox(
                                          width: 100,
                                          child: TextFormField(
                                            initialValue: item.quantity.toString(),
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            onChanged: (val) => item.quantity = double.tryParse(val) ?? 1,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 200,
                                          child: TextFormField(
                                            initialValue: item.notes,
                                            decoration: const InputDecoration(hintText: 'ملاحظة', isDense: true, border: InputBorder.none),
                                            onChanged: (val) => item.notes = val,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        IconButton(
                                          icon: const Icon(PhosphorIconsBold.trash, color: Colors.red),
                                          onPressed: () => _removeItem(index),
                                        ),
                                      ),
                                    ]);
                                  }).toList(),
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
          label: const Text('إضافة صنف للطلب'),
          icon: const Icon(PhosphorIconsBold.plus),
        ),
      ),
    );
  }
}

class _ProductSearchDialogRequisition extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختيار صنف للطلب'),
        content: SizedBox(
          width: 500,
          height: 600,
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'بحث بالاسم أو الباركود...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  ref.invalidate(searchProductsProvider(val));
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final allProducts = ref.watch(allProductsProvider);
                    return allProducts.when(
                      data: (products) {
                        return ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            return ListTile(
                              title: Text(p.name),
                              subtitle: Text('باركود: ${p.code} | السعر: ${p.salePrice}'),
                              trailing: const Icon(PhosphorIconsBold.plusCircle),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        );
                      },
                      loading: () => Padding(
                        padding: const EdgeInsets.all(16),
                        child: ShimmerLoading.list(itemCount: 6),
                      ),
                      error: (e, s) => Text(friendlyError(e, context: 'STOCK-REQ-LOAD')),
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
      ),
    );
  }
}
