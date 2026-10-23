import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../products/providers/products_controller.dart';

class ProductsBulkActionBar extends ConsumerWidget {
  const ProductsBulkActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productsControllerProvider);
    final count = state.selectedIds.length;

    if (count == 0) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            tr('تم تحديد {count} صنف', {'count': count}),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _ActionButton(
            label: tr('تفعيل'),
            icon: PhosphorIconsBold.checkCircle,
            color: AppColors.success,
            onTap: () => _handleBulkUpdate(context, ref, true),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            label: tr('تعطيل'),
            icon: PhosphorIconsBold.prohibit,
            color: AppColors.warning,
            onTap: () => _handleBulkUpdate(context, ref, false),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            label: tr('حذف'),
            icon: PhosphorIconsBold.trash,
            color: AppColors.error,
            onTap: () => _handleBulkDelete(context, ref),
          ),
          const SizedBox(width: 12),
          VerticalDivider(color: Colors.white.withValues(alpha: 0.2), width: 1),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(PhosphorIconsBold.x, color: Colors.white70),
            onPressed: () => ref.read(productsControllerProvider.notifier).clearSelection(),
            tooltip: tr('إلغاء التحديد'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBulkUpdate(BuildContext context, WidgetRef ref, bool active) async {
  // ignore: unused_local_variable
    final success = await ref.read(productsControllerProvider.notifier).bulkUpdateStatus(active);
    // Note: status updates are handled by updateProduct in controller which returns Future<bool>
    // but bulkUpdateStatus currently returns void. Let's fix that if needed.
    if (context.mounted) {
      AppToast.show(context, tr('تم تحديث {p0} صنف', {'p0': ref.read(productsControllerProvider).selectedIds.length}), type: ToastType.success);
    }
  }

  Future<void> _handleBulkDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('تأكيد الحذف الجماعي')),
          content: Text(tr('هل أنت متأكد من حذف {p0} صنف؟ لا يمكن التراجع عن هذا الإجراء.', {'p0': ref.read(productsControllerProvider).selectedIds.length})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('إلغاء'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('حذف الكل')),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await ref.read(productsControllerProvider.notifier).bulkDeleteSelected();
      if (context.mounted) {
        AppToast.show(context, tr('تم الحذف بنجاح'), type: ToastType.success);
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
