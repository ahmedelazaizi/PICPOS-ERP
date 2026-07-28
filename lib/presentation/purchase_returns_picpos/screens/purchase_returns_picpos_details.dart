// منسوخ من lib/presentation/screens/purchase_returns/return_details_panel.dart
// (mixin `_PurchaseReturnDetailsPanelMixin` في شاشة UralCash). الملف الأصل
// `part of` خاص فما ينفعش يتعمله import، فبينتقل بنسخ حرفي هنا — نفس الأسلوب
// المعتمد في sales_returns_picpos_details.dart. التغيير الوحيد: السطر الأول
// واسم الـ mixin/قيد `on` واسم كلاس الحالة في الـ cast
// (_PurchaseReturnsPicposScreenState). جسم الدوال بدون أي تعديل — أي إصلاح
// منطقي يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
part of 'purchase_returns_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE RETURN DETAILS PANEL — Implementation of the UI
// ═══════════════════════════════════════════════════════════════════════════

mixin _PurchaseReturnsPicposDetailsPanel
    on ConsumerState<PurchaseReturnsPicposScreen> {
  // Provided by mixin or main state
  Future<void> processReturn();

  Widget buildReturnDetailsPanel(PurchaseReturnState state, PurchaseReturnNotifier notifier) {
    if (state.selectedInvoice == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsBold.receipt, size: 80, color: AppColors.textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 24),
            const Text(
              'اختر فاتورة مشتريات لعرض تفاصيل الارتجاع',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Info
          _buildInvoiceHeader(state.selectedInvoice!),
          const SizedBox(height: 16),

          // Items List
          const Text('الأصناف في الفاتورة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Expanded(
            child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildItemsList(state, notifier),
          ),

          const Divider(height: 32),

          // Footer Action
          _buildReturnFooter(state, notifier),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader(PurchaseInvoiceData invoice) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(PhosphorIconsBold.receipt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فاتورة #${invoice.invoiceNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'التاريخ: ${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year} • الإجمالي: ${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList(PurchaseReturnState state, PurchaseReturnNotifier notifier) {
    if (state.invoiceItems.isEmpty) {
      return const Center(child: Text('لا توجد أصناف في هذه الفاتورة'));
    }

    return ListView.builder(
      itemCount: state.invoiceItems.length,
      itemBuilder: (context, index) {
        final item = state.invoiceItems[index];
        final returnQty = state.returnQuantities[item.item.id] ?? 0;
        final maxQty = item.item.quantity;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'الكمية: ${maxQty.toStringAsFixed(0)} • السعر: ${item.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      // Per-line tax indicator from the original purchase
                      // invoice row — one invoice may mix taxable and
                      // exempt items, so surface which this line was.
                      Row(
                        children: [
                          Icon(
                            item.item.taxAmount > 0
                                ? PhosphorIconsBold.receipt
                                : PhosphorIconsBold.prohibit,
                            size: 11,
                            color: item.item.taxAmount > 0
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.item.taxAmount > 0
                                ? 'ضريبة ${item.item.taxRate.toStringAsFixed(0)}% = ${item.item.taxAmount.toStringAsFixed(AppConstants.decimalPlaces)}'
                                : 'معفى من الضريبة',
                            style: TextStyle(
                              fontSize: 11,
                              color: item.item.taxAmount > 0
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Qty Controls
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.minus, size: 16),
                        onPressed: returnQty > 0
                          ? () => notifier.updateReturnQuantity(item.item.id, returnQty - 1)
                          : null,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.error.withValues(alpha: 0.1),
                          foregroundColor: AppColors.error,
                        ),
                      ),
                      Container(
                        width: 40,
                        alignment: Alignment.center,
                        child: Text(
                          returnQty.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.plus, size: 16),
                        onPressed: returnQty < maxQty
                          ? () => notifier.updateReturnQuantity(item.item.id, returnQty + 1)
                          : null,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.success.withValues(alpha: 0.1),
                          foregroundColor: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => notifier.updateReturnQuantity(item.item.id, maxQty),
                        child: const Text('الكل', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),

                Text(
                  '${(returnQty * item.item.unitCost).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReturnFooter(PurchaseReturnState state, PurchaseReturnNotifier notifier) {
    final total = notifier.calculateReturnTotal();
    final screenState = this as _PurchaseReturnsPicposScreenState;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // B4: Return reason categorization
          DropdownButtonFormField<String>(
            value: screenState._selectedReasonCategory.isEmpty ? null : screenState._selectedReasonCategory,
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
                screenState._selectedReasonCategory = val ?? '';
                if (val != null && val != 'أخرى') {
                  screenState._returnReasonController.text = val;
                } else if (val == 'أخرى') {
                  screenState._returnReasonController.text = '';
                }
              });
            },
          ),
          if (screenState._selectedReasonCategory == 'أخرى') ...[
            const SizedBox(height: 6),
            TextField(
              controller: screenState._returnReasonController,
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
          const SizedBox(height: 12),
          Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي المرتجع', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(
                  '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.error),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: (total > 0 && !state.isProcessing) ? processReturn : null,
            icon: state.isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(PhosphorIconsBold.arrowUUpLeft),
            label: const Text('تنفيذ المرتجع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      ],
      ),
    );
  }
}
