import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import 'customer_selector_v2.dart';

/// Dialog for selecting a customer in the POS
class PosCustomerSelectionDialog extends StatelessWidget {
  const PosCustomerSelectionDialog({super.key});

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const PosCustomerSelectionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.user, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr('اختيار عميل')),
          ],
        ),
        content: const SizedBox(width: 500, child: CustomerSelectorV2()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }
}
