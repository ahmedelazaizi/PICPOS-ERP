import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
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
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('طلبات صرف المخزون بين الفروع'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              tooltip: 'تحديث',
              onPressed: () => ref.invalidate(stockRequisitionsControllerProvider),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _createNewRequisition,
              icon: const Icon(PhosphorIconsBold.plus),
              label: const Text('طلب جديد'),
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
                              hintText: 'بحث برقم الطلب أو اسم الفرع...',
                              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            onChanged: controller.updateSearchQuery,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('الكل')),
                            ButtonSegment(value: 'pending', label: Text('معلق')),
                            ButtonSegment(value: 'approved', label: Text('معتمد')),
                            ButtonSegment(value: 'fulfilled', label: Text('منفذ')),
                            ButtonSegment(value: 'rejected', label: Text('مرفوض')),
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
                        ? const Center(child: Text('لا توجد طلبات صرف مخزون تطابق البحث'))
                        : Card(
                            margin: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(AppColors.surface),
                                  columns: const [
                                    DataColumn(label: Text('رقم الطلب', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('من فرع', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('إلى فرع', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('المستخدم', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('الإجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: state.filteredRequisitions.map((req) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(req.requisitionNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        DataCell(Text(req.requisitionDate.toString().substring(0, 10))),
                                        DataCell(Text(req.fromBranchName ?? 'غير محدد')),
                                        DataCell(Text(req.toBranchName ?? 'غير محدد')),
                                        DataCell(Text(req.createdByUserName ?? 'مجهول')),
                                        DataCell(_buildStatusBadge(statusToDb(req.status))),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(PhosphorIconsBold.eye, size: 18),
                                                color: AppColors.info,
                                                onPressed: () {
                                                  // TODO: View details
                                                },
                                              ),
                                              if (req.status == RequisitionStatus.pending) ...[
                                                IconButton(
                                                  icon: const Icon(PhosphorIconsBold.checkCircle, size: 18),
                                                  color: AppColors.success,
                                                  tooltip: 'اعتماد وصرف',
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
                                                  tooltip: 'رفض',
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

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
        label = 'معلق';
        break;
      case 'approved':
        color = AppColors.primary;
        label = 'معتمد';
        break;
      case 'fulfilled':
        color = AppColors.success;
        label = 'تم الصرف';
        break;
      case 'rejected':
        color = AppColors.error;
        label = 'مرفوض';
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
