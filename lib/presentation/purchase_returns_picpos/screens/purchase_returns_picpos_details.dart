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
        // «المشتراة» و«المرتجع سابقاً» و«المتاح حالياً» — قرارُ المالك
        // 2026-09-18: الثلاثةُ تُعرَض، وكان يُعرَض الأوّلُ وحدَه.
        final purchasedQty = item.item.quantity;
        final alreadyReturned =
            state.alreadyReturnedByProduct[item.item.productId] ?? 0.0;
        final maxQty = notifier.maxReturnableFor(item.item.id);

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
                        'المشتراة: ${purchasedQty.toStringAsFixed(0)}'
                        ' • السعر: ${item.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      // 🔴 **والمتاحُ ليس عرضاً فحسب — هو السقفُ نفسُه.**
                      // سقفُ الحقل كان الكمّيّةَ الأصليّةَ وحدَها، فردُّ
                      // خمسةٍ من خمسةٍ مرّتَين كان يمرّ ويخصم المخزونَ
                      // مرّتَين ويخفّض ذمّةَ المورّد مرّتَين.
                      Text(
                        'المرتجع سابقاً: ${alreadyReturned.toStringAsFixed(0)}'
                        ' • المتاح حالياً: ${maxQty.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: maxQty <= 0
                              ? AppColors.error
                              : AppColors.textMuted,
                        ),
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

  /// «تسوية المبلغ مع المورد» — **مرآةٌ مشتقّةٌ لا حقولُ إدخال**.
  ///
  /// 🔴 **قرارُ المالك 2026-09-18**: التصميمُ عرض «طريقة التسوية» قائمةً
  /// منسدلة، والمحرّكُ **لا يستشيرها**: يقسم آليّاً — ما يُخصَم من ذمّة
  /// المورّد بقدر ما نَدين له، والباقي نقداً. فقائمةٌ تُعرَض ولا تُقرأ هي
  /// أسوأُ من غيابها: يختار المستخدمُ «استرداد نقدي» فيُخفَّض رصيدُ الذمّة
  /// ولا يصله شيء.
  ///
  /// ⚠️ **وكلُّ الأرقام مشتقّةٌ من نفس الدالّة** التي ينفّذها المستودعُ
  /// ومعالجُ الـAPI — لا نسخةٌ سادسةٌ من الصيغة.
  Widget _buildSettlementMirror(PurchaseReturnNotifier notifier) {
    final s = notifier.settlement;
    if (s == null || s.gross <= 0) return const SizedBox.shrink();

    Widget row(String label, String value, {bool emphasis = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: emphasis ? 15 : 13,
                  fontWeight:
                      emphasis ? FontWeight.w800 : FontWeight.w700,
                  color: emphasis ? AppColors.primary : null,
                ),
              ),
            ],
          ),
        );

    String money(double v) =>
        v.toStringAsFixed(AppConstants.decimalPlaces);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تسوية المبلغ مع المورد',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          row('طريقة التسوية', s.methodLabel),
          row('الرصيد المستحق حالياً', money(s.remainingBefore)),
          if (s.touchesPayable) row('تخفيض الذمة', money(s.apPortion)),
          if (s.touchesCash) row('استرداد نقدي', money(s.cashPortion)),
          row('الرصيد بعد التسوية', money(s.remainingAfter),
              emphasis: true),
        ],
      ),
    );
  }

  Widget _buildReturnFooter(
PurchaseReturnState state, PurchaseReturnNotifier notifier) {
    final total = notifier.calculateReturnTotal();
    final screenState = this as _PurchaseReturnsPicposScreenState;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.picposField,
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
          // سببُ المردود — قائمةٌ ثابتةٌ **إلزاميّة** (قرارُ المالك).
          //
          // 🔴 **وكان يُكتَب في حالةٍ محلّيّةٍ لا تغادر الودجت.**
          // `_selectedReasonCategory` و`_returnReasonController` يُملآن ثمّ
          // يُهملان: `processReturn` لا يقرأهما، و`PurchaseReturns.reason`
          // عمودٌ قائمٌ **بلا كاتبٍ واحد** في المستودع كلّه. فالقيمةُ تمرّ
          // الآن عبر المزوّد إلى المستودع إلى صفّ المستند.
          DropdownButtonFormField<String>(
            initialValue: state.returnReason,
            decoration: const InputDecoration(
              labelText: 'سبب المردود *',
              prefixIcon: Icon(PhosphorIconsBold.notepad, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: AppConstants.purchaseReturnReasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: notifier.updateReturnReason,
          ),

          const SizedBox(height: 12),
          _buildSettlementMirror(notifier),
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
          // ⚠️ **زرٌّ معطَّلٌ بسببٍ ظاهرٍ** لا مخفيّ: إخفاؤه يجعل المستخدمَ
          // يبحث عن فعلٍ يظنّه غائباً، والتلميحُ يقول ما ينقص.
          Tooltip(
            message: state.returnReason == null
                ? 'اختر سبب المردود أولاً'
                : (total <= 0
                    ? 'حدّد كميات المرتجع'
                    : 'تنفيذ المرتجع'),
            child: ElevatedButton.icon(
            onPressed: (total > 0 &&
                    state.returnReason != null &&
                    !state.isProcessing)
                ? processReturn
                : null,
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
          ),
        ],
      ),
      ],
      ),
    );
  }
}
