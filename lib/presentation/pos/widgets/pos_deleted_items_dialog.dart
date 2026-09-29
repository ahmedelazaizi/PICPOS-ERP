import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../providers/pos_controller.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';

/// Dialog for viewing deleted items in the current POS session
class PosDeletedItemsDialog extends ConsumerWidget {
  const PosDeletedItemsDialog({super.key});

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    // Permission check
    final perms = ref.read(currentUserPermissionsProvider).value ?? [];
    if (!perms.hasPermission(PermissionCodes.posDeletedItems)) return;

    return showDialog<void>(
      context: context,
      builder: (context) => const PosDeletedItemsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posState = ref.watch(posControllerProvider);
    final deletedItems = posState.deletedItems;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.trash, color: AppColors.error),
            const SizedBox(width: 8),
             Text(tr('الأصناف المحذوفة')),
            const Spacer(),
            Text(
              tr('{p0} صنف', {'p0': deletedItems.length}),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 350,
          child: deletedItems.isEmpty
              ?  Center(
                  child: Text(
                    tr('لا توجد أصناف محذوفة'),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: deletedItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = deletedItems[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.error.withValues(alpha: 0.1),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                      title: Text(item.productName),
                      subtitle: Text(
                        // السطر ده بيعرض معادلة، فلازم تكون صحيحة حسابياً.
                        // كان `= item.total` وهو شامل الضريبة، يعني
                        // «٧ × ٥ = ٤٠.٦» — رقم مايطلعش من الضرب المكتوب
                        // قدامه. `subtotal` هو ناتج الضرب بالظبط.
                        tr('{p0} × {p1} = {p2} د.أ', {'p0': item.quantity, 'p1': item.effectivePrice.toStringAsFixed(AppConstants.decimalPlaces), 'p2': item.subtotal.toStringAsFixed(AppConstants.decimalPlaces)}),
                      ),
                      trailing: Text(
                        item.note ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (deletedItems.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                ref.read(posControllerProvider.notifier).clearDeletedItems();
                Navigator.pop(context);
              },
              icon: const Icon(PhosphorIconsBold.trash, size: 16),
              label:  Text(tr('مسح الكل')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }
}
