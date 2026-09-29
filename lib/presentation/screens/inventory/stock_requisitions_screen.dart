import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../domain/entities/stock_requisition_entity.dart';
import '../../../../domain/entities/stock_requisition_item_entity.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/enums/requisition_status.dart';
import 'dart:ui' as ui;
import 'providers/stock_requisitions_controller.dart';
import 'stock_requisition_create_screen.dart';

class StockRequisitionsScreen extends ConsumerStatefulWidget {
  const StockRequisitionsScreen({super.key});

  @override
  ConsumerState<StockRequisitionsScreen> createState() => _StockRequisitionsScreenState();
}

class _StockRequisitionsScreenState extends ConsumerState<StockRequisitionsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _createNewRequisition() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const StockRequisitionCreateScreen(),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(stockRequisitionsControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stockRequisitionsControllerProvider);
    final controller = ref.read(stockRequisitionsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('طلبات صرف المخزون بين الفروع')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              tooltip: tr('تحديث'),
              onPressed: () => ref.invalidate(stockRequisitionsControllerProvider),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _createNewRequisition,
              icon: const Icon(PhosphorIconsBold.plus),
              label:  Text(tr('طلب جديد')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: state.isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ShimmerLoading.list(itemCount: 6),
              )
            : Column(
                children: [
                  // Filters Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: theme.cardColor,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: tr('بحث برقم الطلب أو اسم الفرع...'),
                              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            onChanged: controller.updateSearchQuery,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<String>(
                          segments:  [
                            ButtonSegment(value: 'all', label: Text(tr('الكل'))),
                            ButtonSegment(value: 'pending', label: Text(tr('معلق'))),
                            ButtonSegment(value: 'approved', label: Text(tr('معتمد'))),
                            ButtonSegment(value: 'fulfilled', label: Text(tr('منفذ'))),
                            ButtonSegment(value: 'rejected', label: Text(tr('مرفوض'))),
                          ],
                          selected: {state.statusFilter},
                          onSelectionChanged: (val) {
                            controller.updateStatusFilter(val.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Data Table Section
                  Expanded(
                    child: state.filteredRequisitions.isEmpty
                        ?  Center(child: Text(tr('لا توجد طلبات صرف مخزون تطابق البحث')))
                        : Card(
                            margin: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columns:  [
                                    DataColumn(label: Text(tr('رقم الطلب'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('التاريخ'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('من فرع'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('إلى فرع'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('المستخدم'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('الحالة'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(tr('الإجراءات'), style: const TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: state.filteredRequisitions.map((req) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(req.requisitionNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        DataCell(Text(req.requisitionDate.toString().substring(0, 10))),
                                        DataCell(Text(req.fromBranchName ?? tr('غير محدد'))),
                                        DataCell(Text(req.toBranchName ?? tr('غير محدد'))),
                                        DataCell(Text(req.createdByUserName ?? tr('مجهول'))),
                                        DataCell(_buildStatusBadge(statusToDb(req.status))),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(PhosphorIconsBold.eye, size: 18),
                                                color: AppColors.info,
                                                tooltip: tr('عرض التفاصيل'),
                                                onPressed: () => _showRequisitionDetails(req),
                                              ),
                                              if (req.status == RequisitionStatus.pending) ...[
                                                IconButton(
                                                  icon: const Icon(PhosphorIconsBold.checkCircle, size: 18),
                                                  color: AppColors.success,
                                                  tooltip: tr('اعتماد وصرف'),
                                                  onPressed: state.processingIds.contains(req.id)
                                                      ? null
                                                      : () async {
                                                          final err = await controller.approve(req.id);
                                                          if (err != null && context.mounted) {
                                                            AppToast.show(context, err, type: ToastType.error);
                                                          }
                                                        },
                                                ),
                                                IconButton(
                                                  icon: const Icon(PhosphorIconsBold.xCircle, size: 18),
                                                  color: AppColors.error,
                                                  tooltip: tr('رفض'),
                                                  onPressed: state.processingIds.contains(req.id)
                                                      ? null
                                                      : () async {
                                                          final err = await controller.reject(req.id);
                                                          if (err != null && context.mounted) {
                                                            AppToast.show(context, err, type: ToastType.error);
                                                          }
                                                        },
                                                ),
                                              ]
                                            ],
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

  Future<_RequisitionDetails> _loadRequisitionDetails(int id) async {
    final inventory = ref.read(inventoryRepositoryProvider);
    final products = ref.read(productRepositoryProvider);
    final requisition = await inventory.getStockRequisitionById(id);
    if (requisition == null) {
      throw StateError('لم يعد طلب الصرف موجوداً');
    }
    final items = await inventory.getStockRequisitionItems(id);
    final productRows = await products.getProductsByIds(
      items.map((item) => item.productId).toSet().toList(),
    );
    return _RequisitionDetails(
      requisition: requisition,
      items: items,
      products: {for (final product in productRows) product.id: product},
    );
  }

  void _showRequisitionDetails(StockRequisitionEntity request) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr('تفاصيل طلب {p0}', {'p0': request.requisitionNumber})),
          content: SizedBox(
            width: 620,
            child: FutureBuilder<_RequisitionDetails>(
              future: _loadRequisitionDetails(request.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Text(snapshot.error?.toString() ?? tr('تعذر تحميل التفاصيل'));
                }
                final details = snapshot.data!;
                final requisition = details.requisition;
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('التاريخ: {p0}', {'p0': requisition.requisitionDate.toString().substring(0, 10)})),
                      Text(tr('الحالة: {p0}', {'p0': statusToDb(requisition.status)})),
                      Text(tr('من فرع: {p0}', {'p0': requisition.fromBranchName ?? requisition.fromBranchId})),
                      Text(tr('إلى فرع: {p0}', {'p0': requisition.toBranchName ?? requisition.toBranchId})),
                      if (requisition.notes?.isNotEmpty == true)
                        Text(tr('ملاحظات: {p0}', {'p0': requisition.notes})),
                      const Divider(),
                      if (details.items.isEmpty)
                         Text(tr('لا توجد أصناف في هذا الطلب'))
                      else
                        ...details.items.map((item) {
                          final product = details.products[item.productId];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(product?.name ?? tr('منتج #{p0}', {'p0': item.productId})),
                            subtitle: Text(product?.code ?? ''),
                            trailing: Text(
                              tr('{p0} / منفذ {p1}', {'p0': item.quantity, 'p1': item.fulfilledQuantity}),
                            ),
                          );
                        }),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child:  Text(tr('إغلاق')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
        label = tr('معلق');
        break;
      case 'approved':
        color = AppColors.primary;
        label = tr('معتمد');
        break;
      case 'fulfilled':
        color = AppColors.success;
        label = tr('تم الصرف');
        break;
      case 'rejected':
        color = AppColors.error;
        label = tr('مرفوض');
        break;
      default:
        color = Colors.grey;
        label = 'غير معروف';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _RequisitionDetails {
  final StockRequisitionEntity requisition;
  final List<StockRequisitionItemEntity> items;
  final Map<int, ProductEntity> products;

  const _RequisitionDetails({
    required this.requisition,
    required this.items,
    required this.products,
  });
}
