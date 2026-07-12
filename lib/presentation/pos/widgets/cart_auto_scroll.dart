part of 'cart_view.dart';

class _AutoScrollCartList extends StatefulWidget {
  final List<CartItemEntity> cart;
  final CartController controller;
  final CartState cartState;
  final Function(int index)? onEditItem;

  const _AutoScrollCartList({
    required this.cart,
    required this.controller,
    required this.cartState,
    this.onEditItem,
  });

  @override
  State<_AutoScrollCartList> createState() => _AutoScrollCartListState();
}

class _AutoScrollCartListState extends State<_AutoScrollCartList> {
  final ScrollController _scrollController = ScrollController();
  int _previousCartLength = 0;

  @override
  void initState() {
    super.initState();
    _previousCartLength = widget.cart.length;
  }

  @override
  void didUpdateWidget(_AutoScrollCartList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-scroll to bottom when new item is added
    if (widget.cart.length > _previousCartLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _previousCartLength = widget.cart.length;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.cart.length,
      itemBuilder: (context, index) {
        final item = widget.cart[index];
        return CartItemTile(
          item: item,
          index: index,
          onRemove: () => widget.controller.removeFromCart(index),
          onQuantityChanged: (qty) =>
              widget.controller.updateQuantity(index, qty),
          onPriceChanged: (newPrice) =>
              widget.controller.updatePrice(index, newPrice),
          onEdit: widget.onEditItem != null
              ? () => widget.onEditItem!(index)
              : null,
          isExchangeMode: widget.cartState.isExchangeMode,
          onToggleType: widget.cartState.isExchangeMode
              ? () => widget.controller.toggleItemType(index)
              : null,
          onPrintBarcode: () => _showBarcodePrintDialog(context, item),
        );
      },
    );
  }

  void _showBarcodePrintDialog(BuildContext context, CartItemEntity item) {
    int copies = 1;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.barcode, color: AppColors.warning),
              SizedBox(width: 8),
              Text('طباعة باركود'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'كود: ${item.productCode}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Copies selector
              const Text(
                'عدد النسخ:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: copies > 1
                        ? () => setDialogState(() => copies--)
                        : null,
                    icon: const Icon(PhosphorIconsBold.minus),
                    color: AppColors.error,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$copies',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: copies < 100
                        ? () => setDialogState(() => copies++)
                        : null,
                    icon: const Icon(PhosphorIconsBold.plus),
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Quick select buttons
              Wrap(
                spacing: 8,
                children: [5, 10, 20, 50]
                    .map(
                      (n) => ActionChip(
                        label: Text('$n'),
                        onPressed: () => setDialogState(() => copies = n),
                        backgroundColor: copies == n
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : null,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _printBarcode(context, item, copies);
              },
              icon: const Icon(PhosphorIconsBold.printer),
              label: Text('طباعة $copies نسخة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printBarcode(
    BuildContext context,
    CartItemEntity item,
    int copies,
  ) async {
    // Show printing indicator
    // Notification (was SnackBar)
    AppToast.show(context, 'إشعار', type: ToastType.success);

    try {
      // Use the product barcode (user-entered), fallback to productCode if no barcode
      final barcodeValue = item.barcode ?? item.productCode;

      if (barcodeValue.isEmpty) {
        AppToast.show(
          context,
          'هذا الصنف لا يحتوي على باركود',
          type: ToastType.warning,
        );
        return;
      }

      await InvoiceGenerator.printBarcodeLabel(
        barcodeValue: barcodeValue,
        productName: item.productName,
        price: item.effectivePrice,
        copies: copies,
      );

      if (context.mounted) {
        AppToast.show(
          context,
          'تم إرسال $copies باركود للطباعة ✓',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          'فشل في طباعة الباركود: $e',
          type: ToastType.error,
        );
      }
    }
  }
}
