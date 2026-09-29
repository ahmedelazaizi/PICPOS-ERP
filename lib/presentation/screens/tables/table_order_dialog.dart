import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart'; // Only for model types
import '../../pos/screens/pos_table_service_screen.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Callback types for table order dialog actions
typedef OnPrintKitchen =
    Future<void> Function(RestaurantTable table, TableOrder order);
typedef OnCloseTable = void Function(RestaurantTable table, TableOrder order);
typedef OnAddItems = void Function(RestaurantTable table);
typedef OnMerge = void Function(RestaurantTable table, TableOrder order);

/// Dialog widget for viewing and managing table orders
/// Phase 1: Converted to StatefulWidget to fix N+1 query pattern —
/// pre-loads ALL product names in one batch instead of per-row FutureBuilder
class TableOrderDialog extends StatefulWidget {
  final RestaurantTable table;
  final TableOrder order;
  final List<TableOrderItem> items;
  /// PIR-10: Replaces AppDatabase with a product name resolver callback
  final Future<String?> Function(int productId) resolveProductName;
  final OnPrintKitchen onPrintKitchen;
  final OnCloseTable onCloseTable;
  final OnMerge onMerge;

  const TableOrderDialog({
    super.key,
    required this.table,
    required this.order,
    required this.items,
    required this.resolveProductName,
    required this.onPrintKitchen,
    required this.onCloseTable,
    required this.onMerge,
  });

  @override
  State<TableOrderDialog> createState() => _TableOrderDialogState();
}

class _TableOrderDialogState extends State<TableOrderDialog> {
  final Map<int, String> _productNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _preloadProductNames();
  }

  /// Batch-load all product names to avoid N+1 queries
  Future<void> _preloadProductNames() async {
    final uniqueIds = widget.items.map((i) => i.productId).toSet();
    for (final id in uniqueIds) {
      final name = await widget.resolveProductName(id);
      _productNames[id] = name ?? tr('صنف #{id}', {'id': id});
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
        actionsPadding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.circlesThree, color: AppColors.info, size: 20),
            const SizedBox(width: 6),
            Text(widget.table.name, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${widget.order.total.toStringAsFixed(2)} ${AppConstants.currencySymbolEn}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          height: 220,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : widget.items.isEmpty
                  ?  Center(
                      child: Text(
                        tr('لا توجد أصناف في الطلب'),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final item = widget.items[idx];
                        final productName = _productNames[item.productId] ?? tr('صنف #{p0}', {'p0': item.productId});
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(PhosphorIconsBold.package, size: 18),
                          title: Text(
                            productName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${item.unitPrice.toStringAsFixed(2)} × ${item.quantity.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            '${item.total.toStringAsFixed(2)} ${AppConstants.currencySymbolEn}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        );
                      },
                    ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => widget.onMerge(widget.table, widget.order),
                icon: const Icon(PhosphorIconsBold.intersect, size: 16),
                label:  Text(tr('دمج'), style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.warning, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              TextButton.icon(
                onPressed: () async {
                  await widget.onPrintKitchen(widget.table, widget.order);
                  if (context.mounted) {
                    AppToast.show(context, tr('تم إرسال الطلب للمطبخ'), type: ToastType.success);
                  }
                },
                icon: const Icon(PhosphorIconsBold.cookingPot, size: 16),
                label:  Text(tr('المطبخ'), style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:  Text(tr('إغلاق'), style: const TextStyle(fontSize: 12)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.onPrintKitchen(widget.table, widget.order);
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TablePosScreen(
                          tableId: widget.table.id,
                          tableName: widget.table.name,
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(PhosphorIconsBold.plus, size: 16),
                label:  Text(tr('إضافة'), style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCloseTable(widget.table, widget.order);
                },
                icon: const Icon(PhosphorIconsBold.receipt, size: 16),
                label:  Text(tr('إغلاق طاولة'), style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

