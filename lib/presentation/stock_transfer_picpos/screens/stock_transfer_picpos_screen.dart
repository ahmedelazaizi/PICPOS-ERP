// منطق منسوخ من stock_transfer_screen.dart (monolith) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/inventory/stock_transfer_screen.dart)
// مونوليث ٤٣٥ سطر بلا `part of` files. الـ State (_StockTransferScreenState)
// بما فيها initState (تحميل مستودع المصدر الافتراضي) وإضافة/حذف صنف وحفظ
// التحويل بكل تحقّقاته وتصفير النموذج بعد النجاح — كل ده مكتوب inline. بما
// إنه مفيش part نقدر نستوردها، فالفورك هنا بينسخ جسم الدوال دي حرفياً بلا أي
// تعديل منطقي (بما فيها تعليق Spec-117 على fallback رسالة الخطأ عند فشل
// الحفظ) — يتغيّر بس اسم الكلاس وطبقة العرض (تستخدم picpos_shell بدل
// Scaffold+AppBar+FloatingActionButton). `_ProductSearchDialog` كلاس داخلي
// خاص (private) في الأصل — وهو `ConsumerStatefulWidget` بحالة `_query` خاصة
// به (يختلف عن نسخة توأمه Task 5) — فبينُسخ حرفياً هنا كمان (نفس قاعدة
// النسخ)، مش النسخة بتاعة inventory_bonds_picpos.
// `stockTransferControllerProvider` و`TransferItemModel` و`allWarehousesProvider`
// و`allProductsProvider` و`searchProductsProvider` مُعاد استخدامهم من UralCash
// زي ما هم (import، مش نسخ).
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
import '../../screens/inventory/providers/stock_transfer_controller.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_toolbar.dart';

/// شاشة التحويل المخزني بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `stockTransferControllerProvider`
/// (وتوابعه `StockTransferState`/`StockTransferNotifier`/`TransferItemModel`)
/// و`allWarehousesProvider`/`allProductsProvider`/`searchProductsProvider` من
/// UralCash — فقط طبقة العرض تبدّلت لـ picpos_shell (هيدر + PicPosContentCard
/// حول قسم المستودعات وجدول الأصناف بدل Scaffold+AppBar، وPicPosToolbar بدل
/// FloatingActionButton).
///
/// FULL PARITY مع الأصل: قائمة مستودع المصدر (مطلوبة)، قائمة مستودع الوجهة
/// (مطلوبة)، حقل ملاحظات التحويل، جدول الأصناف بأعمدته الخمسة (الصنف/الرصيد
/// الكلي/التكلفة/الكمية المحولة/حذف) بحقل الكمية القابل للتعديل مباشرة، حوار
/// بحث الصنف (`_ProductSearchDialog`)، تنفيذ التحويل بكل تحقّقاته (أصناف
/// فارغة، مستودعين مطلوبين، مصدر≠وجهة) وتصفير النموذج بعد النجاح، وكل رسائل
/// التوست/التحقق.
///
/// راجع lib/presentation/screens/inventory/stock_transfer_screen.dart (الأصل).
class StockTransferPicposScreen extends ConsumerStatefulWidget {
  const StockTransferPicposScreen({super.key});

  @override
  ConsumerState<StockTransferPicposScreen> createState() =>
      _StockTransferPicposScreenState();
}

class _StockTransferPicposScreenState
    extends ConsumerState<StockTransferPicposScreen> {
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
      AppToast.show(context, 'يرجى اختيار مستودع المصدر أولاً');
      return;
    }

    final product = await showDialog<ProductEntity>(
      context: context,
      builder: (context) => _ProductSearchDialog(),
    );

    if (product != null) {
      if (_items.any((item) => item.product.id == product.id)) {
        if (!mounted) return;
        AppToast.show(context, 'هذا الصنف موجود بالفعل في القائمة');
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
      AppToast.show(context, 'يجب إضافة أصناف للتحويل');
      return;
    }
    if (_fromWarehouseId == null || _toWarehouseId == null) {
      AppToast.show(context, 'يرجى اختيار مستودع المصدر والوجهة');
      return;
    }
    if (_fromWarehouseId == _toWarehouseId) {
      AppToast.show(context, 'لا يمكن التحويل لنفس المستودع');
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
        'تمت عملية التحويل بنجاح',
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
          ?? 'تعذّر حفظ التحويل المخزني — حاول مرة أخرى';
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

    return PicPosScreenScaffold(
      title: 'سند تحويل اصناف',
      subtitle: 'نقل الأصناف بين المستودعات',
      icon: PhosphorIconsBold.arrowsLeftRight,
      headerActions: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.check),
          tooltip: 'تنفيذ التحويل',
          onPressed: _isSaving ? null : _saveTransfer,
        ),
      ],
      toolbar: PicPosToolbar(
        children: [
          ElevatedButton.icon(
            onPressed: _addItem,
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('إضافة صنف للتحويل'),
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
                        child: warehouses.when(
                          data: (list) => DropdownButtonFormField<int>(
                            initialValue: _fromWarehouseId,
                            decoration: const InputDecoration(
                              labelText: 'تحويل من (المصدر)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                PhosphorIconsBold.arrowUpRight,
                                color: Colors.red,
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
                                setState(() => _fromWarehouseId = val),
                            validator: (val) => val == null ? 'مطلوب' : null,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => const Text('خطأ'),
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
                            decoration: const InputDecoration(
                              labelText: 'تحويل إلى (الوجهة)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                PhosphorIconsBold.arrowDownLeft,
                                color: Colors.green,
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
                                setState(() => _toWarehouseId = val),
                            validator: (val) => val == null ? 'مطلوب' : null,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => const Text('خطأ'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات التحويل',
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
                            'أضف الأصناف المراد تحويلها',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    // Vertical scroll — a tall transfer can have dozens of
                    // rows; without this outer scroller the card's
                    // clipBehavior silently hides rows past the visible
                    // height (parity with the original's outer `ListView`
                    // around the table).
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('الصنف')),
                              DataColumn(label: Text('الرصيد الكلي')),
                              DataColumn(label: Text('التكلفة'), numeric: true),
                              DataColumn(label: Text('الكمية المحولة')),
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
                                        color: Colors.red,
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
            ),
          ],
        ),
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
      title: const Text('اختيار صنف للتحويل'),
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
                        return const Center(
                          child: Text('لا توجد نتائج مطابقة'),
                        );
                      }
                      return ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final p = products[index];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                              'باركود: ${p.code} | المخزون الكلي: ${p.currentStock}',
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
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
