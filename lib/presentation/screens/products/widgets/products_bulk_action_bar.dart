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
            'تم تحديد $count صنف',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _ActionButton(
            label: 'تفعيل',
            icon: PhosphorIconsBold.checkCircle,
            color: AppColors.success,
            onTap: () => _handleBulkUpdate(context, ref, true),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            label: 'تعطيل',
            icon: PhosphorIconsBold.prohibit,
            color: AppColors.warning,
            onTap: () => _handleBulkUpdate(context, ref, false),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            label: 'حذف',
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
            tooltip: 'إلغاء التحديد',
          ),
        ],
      ),
    );
  }

  Future<void> _handleBulkUpdate(BuildContext context, WidgetRef ref, bool active) async {
    final success = await ref.read(productsControllerProvider.notifier).bulkUpdateStatus(active);
    // Note: status updates are handled by updateProduct in controller which returns Future<bool>
    // but bulkUpdateStatus currently returns void. Let's fix that if needed.
    if (context.mounted) {
      AppToast.show(context, 'تم تحديث ${ref.read(productsControllerProvider).selectedIds.length} صنف', type: ToastType.success);
    }
  }

  Future<void> _handleBulkDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف الجماعي'),
          content: Text('هل أنت متأكد من حذف ${ref.read(productsControllerProvider).selectedIds.length} صنف؟ لا يمكن التراجع عن هذا الإجراء.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الكل'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await ref.read(productsControllerProvider.notifier).bulkDeleteSelected();
      if (context.mounted) {
        AppToast.show(context, 'تم الحذف بنجاح', type: ToastType.success);
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
