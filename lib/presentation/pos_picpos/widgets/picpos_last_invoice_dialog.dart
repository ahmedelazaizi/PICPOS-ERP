import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../pos/providers/pos_controller.dart';
import '../../pos/providers/pos_notification_provider.dart';
import '../../pos/widgets/pos_invoice_items_view.dart';
import '../../widgets/permission_guard.dart';
import '../providers/picpos_last_invoice_provider.dart';
import 'picpos_pos_text.dart';

/// «الفاتورة السابقة» — آخر فاتورة للكاشير الحالي، بأصنافها وكمياتها
/// ومجموعها، مع إعادة الطباعة (طلب ٩).
///
/// أخد خانة زر «طباعة F3» القديم في صف الأزرار: الطباعة انتقلت جوه `دفع`
/// (طلب ١) فالخانة اتفرّغت، والحاجة اللي الكاشير بيطلبها فعلاً في المكان ده هي
/// «العميل رجع، وريني آخر فاتورة واطبعها تاني».
///
/// بيقرأ من [picposLastInvoiceProvider] — **نفس** مصدر رقم الفاتورة في
/// الترويسة، فمستحيل الاتنين يعرضوا فاتورتين مختلفتين.
class PicPosLastInvoiceDialog extends ConsumerWidget {
  const PicPosLastInvoiceDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: PicPosLastInvoiceDialog(),
      ),
    );
  }

  static const _methodLabels = {
    'cash': 'نقدي',
    'card': 'بطاقة',
    'click': 'كليك',
    'transfer': 'تحويل',
    'credit': 'آجل',
    'mixed': 'متعدد',
    'multiple': 'متعدد',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(picposLastInvoiceProvider);

    return async.when(
      loading: () => const AlertDialog(
        content: SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => AlertDialog(
        title: Text('الفاتورة السابقة', style: PicPosText.v(16)),
        content: Text('تعذّر التحميل: $e', style: PicPosText.v(13)),
        actions: [_closeButton(context)],
      ),
      data: (invoice) {
        if (invoice == null) return _empty(context);

        final t = invoice.createdAt;
        final time = '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';

        return AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text('فاتورة #${invoice.invoiceNumber}',
                    style: PicPosText.v(16)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsBold.clock,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(time, style: PicPosText.v(12)),
                      const SizedBox(width: 12),
                      const Icon(PhosphorIconsBold.wallet,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        _methodLabels[invoice.paymentMethod] ??
                            invoice.paymentMethod,
                        style: PicPosText.v(12),
                      ),
                      if (invoice.orderNumber != null) ...[
                        const SizedBox(width: 12),
                        const Icon(PhosphorIconsBold.hash,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('طلب ${invoice.orderNumber}',
                            style: PicPosText.v(12)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                PosInvoiceItemsView(
                  invoiceId: invoice.id,
                  invoiceTotal: invoice.total,
                  maxHeight: 320,
                ),
              ],
            ),
          ),
          actions: [
            _closeButton(context),
            PermissionGuard(
              permission: PermissionCodes.posPrint,
              child: ElevatedButton.icon(
                onPressed: () => _reprint(context, ref, invoice.id),
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                label: const Text('إعادة الطباعة'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) => AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.receiptX, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text('الفاتورة السابقة', style: PicPosText.v(16)),
          ],
        ),
        content: Text(
          'لا توجد فاتورة سابقة في هذه الوردية',
          style: PicPosText.l(14),
        ),
        actions: [_closeButton(context)],
      );

  Widget _closeButton(BuildContext context) => TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('إغلاق', style: PicPosText.l(14)),
      );

  Future<void> _reprint(
    BuildContext context,
    WidgetRef ref,
    int invoiceId,
  ) async {
    try {
      await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
      if (context.mounted) {
        showPosToast(context, ref, 'تمت إعادة الطباعة',
            type: PosNotificationType.success);
      }
    } catch (e) {
      if (context.mounted) {
        showPosToast(context, ref, 'تعذّرت الطباعة: $e',
            type: PosNotificationType.error);
      }
    }
  }
}
