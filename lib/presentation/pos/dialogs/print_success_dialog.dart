import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Dialog shown after successful sale with print option
class PrintSuccessDialog extends StatelessWidget {
  final String invoiceNumber;
  final double total;
  final VoidCallback onPrint;

  const PrintSuccessDialog({
    super.key,
    required this.invoiceNumber,
    required this.total,
    required this.onPrint,
  });

  /// Show the print success dialog
  static Future<void> show({
    required BuildContext context,
    required String invoiceNumber,
    required double total,
    required VoidCallback onPrint,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: PrintSuccessDialog(
          invoiceNumber: invoiceNumber,
          total: total,
          onPrint: () {
            Navigator.pop(ctx);
            onPrint();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              PhosphorIconsBold.checkCircle,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          const Text('??? ??????? ?????!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '??? ????????: $invoiceNumber',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '????????: ${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          const Text('?? ???? ????? ????????'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('??'),
        ),
        ElevatedButton.icon(
          onPressed: onPrint,
          icon: const Icon(PhosphorIconsBold.printer),
          label: const Text('?????'),
        ),
      ],
    );
  }
}
