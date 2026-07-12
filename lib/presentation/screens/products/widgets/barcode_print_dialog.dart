import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../services/invoice_generator.dart';

class BarcodePrintDialog extends StatefulWidget {
  final ProductEntity product;

  const BarcodePrintDialog({super.key, required this.product});

  static Future<void> show(BuildContext context, ProductEntity product) {
    return showDialog(
      context: context,
      builder: (context) => BarcodePrintDialog(product: product),
    );
  }

  @override
  State<BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<BarcodePrintDialog> {
  final copiesController = TextEditingController(text: '1');

  @override
  void dispose() {
    copiesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.barcode, color: AppColors.warning),
            SizedBox(width: 8),
            Text('طباعة باركود'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المنتج: ${widget.product.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (widget.product.barcode != null &&
                  widget.product.barcode!.isNotEmpty)
                Text(
                  'الباركود: ${widget.product.barcode}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: copiesController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'عدد النسخ',
                  prefixIcon: const Icon(PhosphorIconsBold.copy, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final copies = int.tryParse(copiesController.text) ?? 1;
              Navigator.pop(context);

              // Print barcode
              await InvoiceGenerator.printBarcodeLabel(
                productName: widget.product.name,
                barcodeValue: widget.product.barcode ?? widget.product.code,
                price: widget.product.salePrice,
                copies: copies,
              );

              if (context.mounted) {
                AppToast.show(
                  context,
                  'تمت طباعة $copies نسخة من الباركود',
                  type: ToastType.success,
                );
              }
            },
            icon: const Icon(PhosphorIconsBold.printer, size: 16),
            label: const Text('طباعة'),
          ),
        ],
      ),
    );
  }
}
