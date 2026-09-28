// ignore_for_file: library_private_types_in_public_api
// منسوخ من lib/presentation/screens/widgets/sales_invoices/sales_batch_action_bar.dart
// — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
part of 'sales_invoices_picpos_screen.dart';

class SalesBatchActionBar extends ConsumerStatefulWidget {
  const SalesBatchActionBar({super.key});

  @override
  ConsumerState<SalesBatchActionBar> createState() => _SalesBatchActionBarState();
}

class _SalesBatchActionBarState extends ConsumerState<SalesBatchActionBar> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final selectedInvoices = ref.watch(salesInvoicesControllerProvider.select((s) => s.selectedInvoices));
    if (selectedInvoices.isEmpty) return const SizedBox.shrink();

    final allInvoices = ref.watch(salesInvoicesControllerProvider.select((s) => s.allInvoices));
    final controller = ref.read(salesInvoicesControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'تم تحديد ${selectedInvoices.length} فاتورة مسجلة',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  controller.clearSelection();
                },
                icon: const Icon(PhosphorIconsBold.x, color: Colors.white70),
                label: const Text('إلغاء التحديد', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  if (context.mounted) {
                    AppToast.show(context, 'جاري تطوير طباعة الفواتير المجمعة', type: ToastType.info);
                  }
                },
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                label: const Text('طباعة المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _saving ? null : () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: AlertDialog(
                        title: const Row(
                          children: [
                            Icon(PhosphorIconsBold.warning, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('تأكيد الحذف المجمع'),
                          ],
                        ),
                        content: Text('هل أنت متأكد من حذف ${selectedInvoices.length} فاتورة محددة؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                            child: const Text('حذف الجميع'),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (confirm == true) {
                    // 063 (D1-005): dual-approval gate (settings-flag gated;
                    // OFF by default = no dialog, no UX change).
                    final approved = await DualApprovalService.requireApprovalForOp(
                      context,
                      ref,
                      operation: DualApprovalOperation.voidInvoice,
                      details: 'حذف ${selectedInvoices.length} فاتورة',
                    );
                    if (!approved) {
                      if (context.mounted) {
                        AppToast.show(context, 'الموافقة الثنائية مرفوضة — لم يتم الحذف', type: ToastType.warning);
                      }
                      return;
                    }
                    setState(() => _saving = true);
                    try {
                      for (final invoiceId in selectedInvoices) {
                        final inv = allInvoices.firstWhere((element) => element.id == invoiceId);
                        await controller.deleteInvoice(invoiceId, inv.invoiceNumber, inv.total);
                      }
                      controller.clearSelection();
                      if (context.mounted) {
                        AppToast.show(context, 'تم حذف الفواتير المحددة بنجاح', type: ToastType.success);
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  }
                },
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(PhosphorIconsBold.trash, size: 18),
                label: const Text('حذف المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
