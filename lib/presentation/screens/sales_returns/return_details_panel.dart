part of '../sales_returns_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RETURN DETAILS PANEL — Item list, quantity controls, exchange mode, summary
// ═══════════════════════════════════════════════════════════════════════════

mixin _ReturnDetailsPanelMixin on ConsumerState<SalesReturnsScreen> {
  // Abstract — provided by _ReturnLogicMixin at composition time
  Future<void> processReturn();
  TextEditingController get returnReasonController;

  Widget buildReturnDetailsPanel(
    SalesReturnState state,
    SalesReturnNotifier notifier,
  ) {
    final invoice = state.selectedInvoice!;
    final items = state.invoiceItems;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Invoice info header
          Card(
            color: AppColors.info.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.invoice,
                    color: AppColors.info,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'فاتورة: ${invoice.invoiceNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'التاريخ: ${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year}',
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: AppColors.info,
                        ),
                      ),
                      Text(
                        '${items.length} أصناف',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Return type toggle - compact
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'نوع المرتجع:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => notifier.toggleFullReturn(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: state.isFullReturn
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : null,
                          border: Border.all(
                            color: state.isFullReturn
                                ? AppColors.primary
                                : AppColors.textMuted.withValues(alpha: 0.3),
                            width: state.isFullReturn ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              state.isFullReturn
                                  ? PhosphorIconsBold.checkCircle
                                  : PhosphorIconsBold.circle,
                              color: state.isFullReturn
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'إرجاع الفاتورة كاملة',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => notifier.toggleFullReturn(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !state.isFullReturn
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : null,
                          border: Border.all(
                            color: !state.isFullReturn
                                ? AppColors.primary
                                : AppColors.textMuted.withValues(alpha: 0.3),
                            width: !state.isFullReturn ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              !state.isFullReturn
                                  ? PhosphorIconsBold.checkCircle
                                  : PhosphorIconsBold.circle,
                              color: !state.isFullReturn
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'إرجاع أصناف محددة',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Items list
          const Row(
            children: [
              Icon(
                PhosphorIconsBold.package,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                'الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Card(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: items.length,
                separatorBuilder: (ctx, idx) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final returnQty = state.returnQuantities[item.id] ?? 0;
                  final product = state.productCache[item.productId];
                  final previouslyReturned =
                      state.previouslyReturnedQty[item.id] ?? 0;
                  final availableToReturn = item.quantity - previouslyReturned;
                  final isFullyReturned = availableToReturn <= 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      product?.name ??
                                          'صنف #${item.productId}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color:
                                            isFullyReturned ? Colors.grey : null,
                                        decoration: isFullyReturned
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (previouslyReturned > 0)
                                    Container(
                                      margin: const EdgeInsetsDirectional.only(start: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isFullyReturned
                                            ? Colors.grey.withValues(alpha: 0.2)
                                            : AppColors.warning.withValues(
                                                alpha: 0.2,
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isFullyReturned
                                            ? 'مرتجع بالكامل'
                                            : 'تم إرجاع ${previouslyReturned.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isFullyReturned
                                              ? Colors.grey
                                              : AppColors.warning,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.quantity.toStringAsFixed(0)} × ${item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)} = ${item.total.toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              // Per-line tax indicator: show the rate + amount
                              // captured on the original invoice row so the
                              // cashier can see which lines were taxable vs
                              // exempt on a mixed invoice.
                              Row(
                                children: [
                                  Icon(
                                    item.taxAmount > 0
                                        ? PhosphorIconsBold.receipt
                                        : PhosphorIconsBold.prohibit,
                                    size: 11,
                                    color: item.taxAmount > 0
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.taxAmount > 0
                                        ? 'ضريبة ${item.taxRate.toStringAsFixed(0)}% = ${item.taxAmount.toStringAsFixed(AppConstants.decimalPlaces)}'
                                        : 'معفى من الضريبة',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: item.taxAmount > 0
                                          ? AppColors.primary
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                              if (previouslyReturned > 0 && !isFullyReturned)
                                Text(
                                  'متاح للإرجاع: ${availableToReturn.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.info,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Quantity selector
                        if (!state.isFullReturn && !isFullyReturned)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(PhosphorIconsBold.minusCircle),
                                color: returnQty > 0
                                    ? AppColors.error
                                    : AppColors.textMuted,
                                onPressed: returnQty > 0
                                    ? () => notifier.updateReturnQuantity(
                                        item.id,
                                        returnQty - 1,
                                      )
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: returnQty > 0
                                      ? AppColors.warning
                                          .withValues(alpha: 0.2)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  returnQty.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: returnQty > 0
                                        ? AppColors.warning
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(PhosphorIconsBold.plusCircle),
                                color: returnQty < availableToReturn
                                    ? AppColors.success
                                    : AppColors.textMuted,
                                onPressed: returnQty < availableToReturn
                                    ? () => notifier.updateReturnQuantity(
                                        item.id,
                                        returnQty + 1,
                                      )
                                    : null,
                              ),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.warning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'إرجاع: ${returnQty.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ),

                        // Item return total
                        SizedBox(
                          width: 100,
                          child: Text(
                            '${notifier.calculateItemRefundTotal(item.id, returnQty).toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: returnQty > 0
                                  ? AppColors.warning
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Damaged/Waste toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                   Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: state.isDamaged
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.textMuted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      PhosphorIconsBold.trash,
                      color: state.isDamaged ? AppColors.error : AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تسجيل كإتلاف (هالك)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'لن تتم إضافة الأصناف المرتجعة إلى المخزون المتاح للاستخدام',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: state.isDamaged,
                    activeThumbColor: AppColors.error,
                    onChanged: (val) => notifier.toggleDamagedMode(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // B4: Return reason categorization
          DropdownButtonFormField<String>(
            value: (this as _SalesReturnsScreenState)._selectedReasonCategory.isEmpty
                ? null
                : (this as _SalesReturnsScreenState)._selectedReasonCategory,
            decoration: const InputDecoration(
              labelText: 'سبب الإرجاع',
              prefixIcon: Icon(PhosphorIconsBold.notepad, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: AppConstants.returnReasonCategories
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (val) {
              setState(() {
                (this as _SalesReturnsScreenState)._selectedReasonCategory = val ?? '';
                if (val != null && val != 'أخرى') {
                  returnReasonController.text = val;
                } else if (val == 'أخرى') {
                  returnReasonController.text = '';
                }
              });
            },
          ),
          if ((this as _SalesReturnsScreenState)._selectedReasonCategory == 'أخرى') ...[
            const SizedBox(height: 6),
            TextField(
              controller: returnReasonController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات إضافية',
                prefixIcon: Icon(PhosphorIconsBold.textT, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 8),

          // Exchange mode toggle - compact
          _buildExchangeModeCard(state, notifier),
          const SizedBox(height: 8),

          // Return summary and button - compact
          Card(
            color: AppColors.warning.withValues(alpha: 0.1),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إجمالي المرتجع:',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${notifier.calculateReturnTotal().toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed:
                          state.isProcessing ? null : processReturn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      icon: state.isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              PhosphorIconsBold.arrowCounterClockwise,
                              size: 18,
                            ),
                      label: Text(
                        'تأكيد الإرجاع (${state.returnQuantities.values.where((q) => q > 0).length} صنف)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeModeCard(
    SalesReturnState state,
    SalesReturnNotifier notifier,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsBold.arrowsLeftRight,
                  color: AppColors.info,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'استبدال بمنتج آخر',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: state.isExchangeMode,
                  activeTrackColor: AppColors.info,
                  // ⛔ معطَّل عن قصد: مسار الاستبدال هنا بيحسب الفرق ويعرضه للكاشير
                  //    وبيقبضه، لكنه **ما بيبيعش الصنف البديل خالص** — لا قيد ولا خروج
                  //    مخزون. البديل: مرتجع مستقل + فاتورة بيع.
                  onChanged: null,
                ),
              ],
            ),
            if (state.isExchangeMode) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () async {
                        final productRepo = ref.read(productRepositoryProvider);
                        final products = await productRepo.getAllProducts();
                         if (!mounted) return;
                        final selected = await showDialog<ProductEntity>(
                                                    context: context,
                          builder: (ctx) => Directionality(
                            textDirection: TextDirection.rtl,
                            child: AlertDialog(
                              title: const Text('اختر المنتج البديل'),
                              content: SizedBox(
                                width: 500,
                                height: 400,
                                child: ListView.builder(
                                  itemCount: products.length,
                                  itemBuilder: (ctx, idx) => ListTile(
                                    title: Text(products[idx].name),
                                    subtitle: Text(
                                      '${products[idx].salePrice.toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                                    ),
                                    onTap: () =>
                                        Navigator.pop(ctx, products[idx]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                         if (!mounted) return;
                        if (selected != null) {
                          notifier.setExchangeProduct(selected);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: state.exchangeProduct != null
                                ? AppColors.info
                                : AppColors.textMuted
                                    .withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: state.exchangeProduct != null
                              ? AppColors.info
                                  .withValues(alpha: 0.05)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              state.exchangeProduct != null
                                  ? PhosphorIconsBold.checkCircle
                                  : PhosphorIconsBold.plus,
                              color: state.exchangeProduct != null
                                  ? AppColors.info
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              state.exchangeProduct?.name ??
                                  'اختر المنتج البديل',
                              style: TextStyle(
                                fontWeight:
                                    state.exchangeProduct != null
                                        ? FontWeight.bold
                                        : null,
                                color: state.exchangeProduct != null
                                    ? AppColors.info
                                    : AppColors.textMuted,
                              ),
                            ),
                            if (state.exchangeProduct != null) ...[
                              const Spacer(),
                              Text(
                                '${state.exchangeProduct!.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (state.exchangeProduct != null)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.minusCircle),
                          color: state.exchangeQuantity > 1
                              ? AppColors.info
                              : AppColors.textMuted,
                          onPressed: state.exchangeQuantity > 1
                              ? () => notifier.updateExchangeQuantity(
                                  state.exchangeQuantity - 1,
                                )
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColors.info.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            state.exchangeQuantity.toStringAsFixed(0),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.plusCircle),
                          color: AppColors.info,
                          onPressed: () =>
                              notifier.updateExchangeQuantity(
                            state.exchangeQuantity + 1,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (state.exchangeProduct != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        notifier.calculateExchangeDifference() >= 0
                            ? AppColors.warning.withValues(alpha: 0.1)
                            : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          notifier.calculateExchangeDifference() >= 0
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notifier.calculateExchangeDifference() >= 0
                            ? 'يدفع العميل فرق:'
                            : 'يسترد العميل:',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${notifier.calculateExchangeDifference().abs().toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color:
                              notifier.calculateExchangeDifference() >=
                                      0
                                  ? AppColors.warning
                                  : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
