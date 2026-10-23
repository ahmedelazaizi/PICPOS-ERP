import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../../widgets/permission_guard.dart';
import '../providers/cart_controller.dart';

/// زرار طباعة أمر شغل لفاتورة معلقة — مستخرج كودجت top-level عشان يتعمله
/// اختبار widget من غير الديالوج كله.
///
/// بدون `allowManagerOverride`: نفس معاملة زرارَي «استرجاع»/«حذف» جنبه في
/// `_HeldOrderTile` — بدون الصلاحية الزرار يختفي تماماً، مفيش تصريح مدير
/// لإعادة طباعة فاتورة سابقة (مش عملية مالية حرجة).
@visibleForTesting
Widget buildHeldOrderPrintButton({required VoidCallback onPrint}) {
  return PermissionGuard(
    permission: PermissionCodes.posWorkOrder,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.printer, size: 20),
      color: AppColors.info,
      tooltip: tr('طباعة'),
      onPressed: onPrint,
    ),
  );
}

class HeldOrdersDialog extends ConsumerWidget {
  final Function(int orderId) onRetrieve;

  const HeldOrdersDialog({super.key, required this.onRetrieve});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heldOrdersAsync = ref.watch(heldOrdersProvider);
    final cartController = ref.read(cartControllerProvider.notifier);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.clockCounterClockwise,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
             Text(tr('الفواتير المعلقة')),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: heldOrdersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
            data: (orders) {
              if (orders.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                itemCount: orders.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return _HeldOrderTile(
                    order: order,
                    onRetrieve: () => onRetrieve(order.id),
                    onDelete: () => cartController.deleteHeldOrder(order.id),
                    onPrint: () => _printHeldOrder(context, ref, order),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }

  Future<void> _printHeldOrder(BuildContext context, WidgetRef ref, HeldOrder order) async {
    try {
      // ISS-06: Route data fetch through heldOrderWithItemsProvider
      final orderData = await ref.read(heldOrderWithItemsProvider(order.id).future);
      if (orderData == null) {
        if (context.mounted) {
          AppToast.show(context, tr('لم يتم العثور على بيانات الطلب المعلق'), type: ToastType.error);
        }
        return;
      }

      final items = orderData['items'] as List<Map<String, dynamic>>;

      // Issue 2 (Feature 019): group items by category and inject a header
      // row before each group so the printed receipt is sectioned (مأكولات /
      // مشروبات / …). Uncategorized items fall into a "غير مصنف" bucket.
      // Order: items keep their input order within a category; categories
      // appear in the order they're first seen so the layout is stable.
      final grouped = <String, List<Map<String, dynamic>>>{};
      final uncategorized = tr('غير مصنف');
      for (final item in items) {
        final categoryName = item['categoryName'] as String? ?? uncategorized;
        grouped.putIfAbsent(categoryName, () => []).add(item);
      }

      final invoiceItems = <InvoiceItem>[];
      grouped.forEach((categoryName, rows) {
        // Skip headers when there's only one category — keeps the print
        // identical to the legacy flat layout for the common single-category
        // case.
        if (grouped.length > 1) {
          invoiceItems.add(InvoiceItem(
            name: categoryName,
            quantity: 0,
            price: 0,
            total: 0,
            isCategoryHeader: true,
          ));
        }
        for (final item in rows) {
          final product = item['product'];
          final quantity = (item['quantity'] as num).toDouble();
          final unitPrice = item['customPrice'] as double? ??
              (item['unitPrice'] as num).toDouble();
          invoiceItems.add(InvoiceItem(
            name: product.name as String,
            quantity: quantity,
            price: unitPrice,
            total: quantity * unitPrice,
            note: item['note'] as String?,
          ));
        }
      });

      await InvoiceGenerator.printWorkOrderReceipt(
        orderNumber: order.holdNumber,
        date: order.createdAt,
        categoryName: tr('فاتورة معلقة'),
        items: invoiceItems,
        customerName: order.customerName,
        // ISS-06: Raw DB access retained — printing utilities require the
        // database instance to resolve printer settings and receipt templates.
        db: ref.read(databaseProvider),
      );

      if (context.mounted) {
        AppToast.show(context, tr('تم طباعة الفاتورة المعلقة {p0}', {'p0': order.holdNumber}), type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('فشل في طباعة الفاتورة المعلقة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Widget _buildEmptyState() {
    return  Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(PhosphorIconsBold.tray, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            tr('لا توجد فواتير معلقة'),
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _HeldOrderTile extends ConsumerWidget {
  final HeldOrder order;
  final VoidCallback onRetrieve;
  final VoidCallback onDelete;
  final VoidCallback onPrint;

  const _HeldOrderTile({
    required this.order,
    required this.onRetrieve,
    required this.onDelete,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(PhosphorIconsBold.receipt, color: AppColors.warning),
      ),
      title: Row(
        children: [
          Text(
            order.holdNumber,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (order.customerName != null && order.customerName!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                order.customerName!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${order.subtotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr} • ${_formatTime(order.createdAt)}',
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildHeldOrderPrintButton(onPrint: onPrint),
          PermissionGuard(
            permission: PermissionCodes.posRestoreHeld,
            child: IconButton(
              icon: const Icon(
                PhosphorIconsBold.arrowCounterClockwise,
                size: 20,
              ),
              color: AppColors.success,
              tooltip: tr('استرجاع'),
              onPressed: () {
                Navigator.pop(context);
                onRetrieve();
              },
            ),
          ),
          PermissionGuard(
            permission: PermissionCodes.posDeleteHeld,
            child: IconButton(
              icon: const Icon(PhosphorIconsBold.trash, size: 20),
              color: AppColors.error,
              tooltip: tr('حذف'),
              onPressed: () => _showDeleteConfirmation(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تأكيد الحذف')),
        content:  Text(tr('هل أنت متأكد من حذف هذه الفاتورة المعلقة؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child:  Text(tr('حذف')),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}