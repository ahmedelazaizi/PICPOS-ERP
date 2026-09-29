part of 'pos_dialogs.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Result of the payment dialog
class PaymentResult {
  final String method;
  final double total; // Changed from totalPaid for consistency
  final double? cashAmount;
  final double? bankAmount;
  final double? clickAmount;
  final int? customerId;
  final String? customerName;

  const PaymentResult({
    required this.method,
    required this.total,
    this.cashAmount,
    this.bankAmount,
    this.clickAmount,
    this.customerId,
    this.customerName,
  });
}

/// Cart item edit data
class CartItemEditData {
  final double? price;
  final String? note;
  final bool shouldDelete;

  const CartItemEditData({this.price, this.note}) : shouldDelete = false;
  const CartItemEditData.delete()
      : price = null,
        note = null,
        shouldDelete = true;
}

/// Delivery configuration data
class DeliveryData {
  final int? companyId;
  final int? companyPartyId; // #Phase2
  final int? courierId;
  final double fee;
  final String status;

  const DeliveryData({
    this.companyId,
    this.companyPartyId,
    this.courierId,
    required this.fee,
    required this.status,
  });
}

class _HoldOrderDialog extends StatefulWidget {
  const _HoldOrderDialog();

  @override
  State<_HoldOrderDialog> createState() => _HoldOrderDialogState();
}

class _HoldOrderDialogState extends State<_HoldOrderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:  Text(tr('تعليق الفاتورة')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Text(tr('أدخل اسم العميل للتعليق (اختياري)')),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration:  InputDecoration(
              hintText: tr('اسم العميل (اختياري)'),
              prefixIcon: const Icon(PhosphorIconsBold.user),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.isEmpty ? '' : v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _controller.text.isEmpty ? '' : _controller.text),
          child:  Text(tr('تعليق')),
        ),
      ],
    );
  }
}
