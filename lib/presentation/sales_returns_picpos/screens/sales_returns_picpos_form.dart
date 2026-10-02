// استمارةُ مرتجع المبيعات على تصميم المالك المرجعيّ (المرحلة C2 من البند ٣).
//
// حلّت محلَّ `sales_returns_picpos_details.dart` (لوحِ «قائمة + تفاصيل»
// المنسوخ من UralCash). والتخطيطُ عمودٌ واحدٌ كاستمارة الفاتورة: رأسُ الصفحة
// ← بطاقةُ الترويسة (الفاتورةُ الأصليّة بمنتقٍ، قيمتُها، حالةُ سدادها،
// التاريخ، العميل، المخزن، سببُ الإرجاع) ← جدولُ الأصناف المرتجعة ← التسويةُ
// بجوار «تفاصيل إضافية» ← شريطُ الأفعال.
//
// ⚠️ **عرضٌ خالص — لا سطرَ منطقٍ تبدّل.** كلُّ فعلٍ ينادي ما كان يناديه:
//   • «مراجعة واعتماد» ← `processReturn` (حوارُ التأكيد ← موافقةُ المدير على
//     المرتجع عالي القيمة ← `runWithOpenShiftPrompt` ← المزوّد ← المستودع).
//   • الكمّيّة ← `notifier.updateReturnQuantity`، «كامل/محدّد» ←
//     `toggleFullReturn`، «إتلاف» ← `toggleDamagedMode`.
//   • منتقي الفاتورة ← `notifier.selectInvoice` من نفس قائمة المدى وترشيحِه.
//
// 🔴 **وما سقط عمداً**: بطاقةُ «استبدال بمنتج آخر». مفتاحُها كان معطّلاً
//    بقصد (`onChanged: null` — المسارُ لا يبيع البديلَ: لا قيدَ ولا خروجَ
//    مخزون)، ولا نداءَ لـ`toggleExchangeMode` في المستودع كلّه، فما تحت
//    المفتاح لا يُرسَم أبداً. والقرارُ: لا يُعرَض إلا فعلٌ له معالجٌ قائم.
// ⚠️ **J2 (قرارُ المالك) — «حفظ مسودة» عاد**: دورةُ المسوّدة في
// `sales_returns_picpos_drafts.dart`؛ و«مراجعة واعتماد» محكومٌ بصلاحية
// `sales_return_approve` ويمرّ بالمعالج القائم نفسِه.
part of 'sales_returns_picpos_screen.dart';

mixin _SalesReturnsPicposForm on ConsumerState<SalesReturnsPicposScreen> {
  // Provided by _SalesReturnsPicposLogic / the State at composition time.
  TextEditingController get returnReasonController;

  _SalesReturnsPicposScreenState get _screen =>
      this as _SalesReturnsPicposScreenState;

  Widget buildReturnForm(SalesReturnState state, SalesReturnNotifier notifier) {
    final invoice = state.selectedInvoice;
    final canApprove = _screen.canApproveReturn;
    return PicPosReturnFormLayout(
      header: _buildHeaderCard(state, notifier),
      lines: _buildLinesCard(state, notifier),
      settlement: _buildSettlement(state, notifier),
      details: _buildDetails(state),
      actionBar: PicPosReturnActionBar(
        primaryLabel: tr('مراجعة واعتماد'),
        busy: state.isProcessing || _screen._savingDraft,
        hint: invoice != null && !canApprove
            ? tr('لا تملك صلاحية الاعتماد — احفظها مسودة')
            : null,
        // المعالجُ القائمُ نفسُه بعد حفظ المسوّدة — يتحقّق من الكمّيّات
        // ويعرض حوارَ التأكيد.
        onPrimary: invoice == null || !canApprove ? null : _screen.approveReturn,
        secondaryLabel: tr('حفظ مسودة'),
        onSecondary: invoice == null ? null : () => _screen.saveDraft(),
        onBack: Navigator.of(context).canPop()
            ? () => Navigator.of(context).maybePop()
            : null,
      ),
    );
  }

  Widget _buildHeaderCard(
    SalesReturnState state,
    SalesReturnNotifier notifier,
  ) {
    final invoice = state.selectedInvoice;
    const none = '—';
    final now = DateTime.now();
    final other = tr('أخرى');
    final reasons = AppConstants.returnReasonCategories;
    final selectedReason = _screen._selectedReasonCategory;

    final warehouseName = invoice == null
        ? none
        : (ref.watch(warehouseNameMapProvider)[invoice.warehouseId] ??
            tr('مخزن #{p0}', {'p0': invoice.warehouseId}));

    return PicPosFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosDocPageHeader(
            icon: PhosphorIconsBold.arrowUUpLeft,
            title: tr('مرتجع مبيعات'),
            // رقمُ المرتجع (SRET-) يُولَّد داخلَ معاملة الترحيل — فلا رقمَ
            // مُخمَّناً هنا؛ والمسوّدةُ تُعرَّف بمعرّفها (J2).
            number: _screen._draftId != null
                ? 'D-${_screen._draftId}'
                : tr('يُولَّد تلقائياً'),
            // «جديد» قبل الحفظ، و«مسودة» بعده (J2).
            statusLabel:
                _screen._draftId != null ? tr('مسودة') : tr('جديد'),
            statusColor: _screen._draftId != null
                ? AppColors.warning
                : AppColors.info,
          ),
          const SizedBox(height: 14),
          PicPosFormGrid(
            children: [
              PicPosFormField(
                key: const Key('picpos_return_invoice_picker'),
                icon: PhosphorIconsBold.receipt,
                label: tr('رقم فاتورة المبيعات الأصلية'),
                required: true,
                value: invoice?.invoiceNumber ?? tr('اختر الفاتورة الأصلية'),
                valueColor: invoice == null ? AppColors.error : null,
                trailing: PhosphorIconsBold.magnifyingGlass,
                onTap: state.isProcessing ? null : _openInvoicePicker,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.coins,
                label: tr('قيمة الفاتورة الأصلية'),
                value: invoice == null ? none : picposReturnMoney(invoice.total),
                readOnly: true,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.wallet,
                label: tr('حالة السداد'),
                value: invoice == null
                    ? none
                    : picposPaymentStatusLabel(
                        total: invoice.total,
                        paid: invoice.paid,
                      ),
                readOnly: true,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.calendarBlank,
                label: tr('التاريخ'),
                required: true,
                // المرتجعُ يُختَم بلحظة التنفيذ — عرضٌ لا اختيار.
                value: now.toString().substring(0, 10),
                readOnly: true,
                trailing: PhosphorIconsBold.lockSimple,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.user,
                label: tr('العميل'),
                value: invoice == null
                    ? none
                    : (state.customerNames[invoice.customerId] ??
                        tr('عميل نقدي')),
                readOnly: true,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.warehouse,
                label: tr('المستودع الوارد'),
                value: warehouseName,
                readOnly: true,
              ),
              // B4: تصنيفُ سبب الإرجاع — نفسُ الحالة ونفسُ ما يُكتَب في
              // `returnReasonController` (الذي يقرؤه `processReturn`).
              PicPosFormDropdownField(
                key: const Key('picpos_return_reason'),
                icon: PhosphorIconsBold.notepad,
                label: tr('سبب الإرجاع'),
                items: reasons,
                value: selectedReason.isEmpty ? null : selectedReason,
                onChanged: (val) {
                  setState(() {
                    _screen._selectedReasonCategory = val ?? '';
                    if (val != null && val != other) {
                      returnReasonController.text = val;
                    } else if (val == other) {
                      returnReasonController.text = '';
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinesCard(SalesReturnState state, SalesReturnNotifier notifier) {
    final invoice = state.selectedInvoice;
    final lines = <PicPosReturnLine>[
      for (final item in state.invoiceItems)
        () {
          final prev = state.previouslyReturnedQty[item.id] ?? 0;
          final available = item.quantity - prev;
          final qty = state.returnQuantities[item.id] ?? 0;
          return PicPosReturnLine(
            id: item.id,
            name: state.productCache[item.productId]?.name ??
                tr('صنف #{p0}', {'p0': item.productId}),
            originalQty: item.quantity,
            previouslyReturned: prev,
            available: available > 0 ? available : 0,
            returnQty: qty,
            unitPrice: item.unitPrice,
            lineValue: notifier.calculateItemRefundTotal(item.id, qty),
            // «إرجاع الفاتورة كاملة» يملأ المتاحَ كلَّه ويقفل الحقل كما كان.
            editable: !state.isFullReturn,
          );
        }(),
    ];

    return PicPosFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                tr('الأصناف المرتجعة'),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PicPosToggleChip(
                    key: const Key('picpos_return_full'),
                    label: tr('إرجاع الفاتورة كاملة'),
                    selected: state.isFullReturn,
                    onTap: invoice == null
                        ? null
                        : () => notifier.toggleFullReturn(true),
                  ),
                  PicPosToggleChip(
                    key: const Key('picpos_return_partial'),
                    label: tr('إرجاع أصناف محددة'),
                    selected: !state.isFullReturn,
                    onTap: invoice == null
                        ? null
                        : () => notifier.toggleFullReturn(false),
                  ),
                  // الإتلاف: الأصنافُ المرتجعةُ لا تعود للمخزون المتاح.
                  Tooltip(
                    message: tr(
                        'لن تتم إضافة الأصناف المرتجعة إلى المخزون المتاح للاستخدام'),
                    child: PicPosToggleChip(
                      key: const Key('picpos_return_damaged'),
                      label: tr('تسجيل كإتلاف (هالك)'),
                      selected: state.isDamaged,
                      tone: AppColors.error,
                      icon: PhosphorIconsBold.trash,
                      onTap: () => notifier.toggleDamagedMode(!state.isDamaged),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          PicPosReturnLinesTable(
            lines: lines,
            originalQtyLabel: tr('الكمية المباعة'),
            returnQtyLabel: tr('كمية المرتجع'),
            unitPriceLabel: tr('سعر البيع'),
            lineValueLabel: tr('قيمة المرتجع'),
            loading: invoice != null && state.isLoading,
            emptyMessage: invoice == null
                ? tr('اختر الفاتورة الأصلية لعرض أصنافها')
                : tr('لا توجد أصناف في هذه الفاتورة'),
            onQtyChanged: notifier.updateReturnQuantity,
          ),
          const SizedBox(height: 12),
          PicPosTotalsBar(
            items: [
              PicPosTotal(
                label: tr('عدد الأصناف'),
                value:
                    '${state.returnQuantities.values.where((q) => q > 0).length}',
              ),
              PicPosTotal(
                label: tr('إجمالي المرتجع'),
                value: picposReturnMoney(notifier.calculateReturnTotal()),
                emphasis: true,
                tone: AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// «تسوية المبلغ مع العميل» — **مرآةٌ مشتقّةٌ لا قائمةُ اختيار.**
  ///
  /// 🔴 المحرّكُ لا يستشير اختياراً: يقاصّ ذمّةَ العميل أوّلاً بقدر ما بقي
  /// عليه، ثمّ يردّ الباقي **بطريقة القبض الأصليّة** (نقدٌ/بنكٌ/مختلط). فهي
  /// طريقةٌ واحدةٌ ثابتةٌ تُعرَض حقلاً مقروءاً.
  ///
  /// ⚠️ والأرقامُ من [SalesReturnRefundSplit.from] **بنفس الوسائط** التي
  /// يمرّرها المستودعُ (`_refundSplitFor`) — لا نسخةٌ ثانيةٌ من القسمة.
  Widget _buildSettlement(SalesReturnState state, SalesReturnNotifier notifier) {
    final invoice = state.selectedInvoice;
    const none = '—';
    if (invoice == null) {
      return PicPosSettlementCard(
        title: tr('تسوية المبلغ مع العميل'),
        method: none,
        rows: [
          PicPosSettlementRow(tr('الرصيد المستحق حالياً'), none),
          PicPosSettlementRow(tr('قيمة التخفيض'), none),
        ],
        resultLabel: tr('الرصيد بعد التسوية'),
        resultValue: none,
      );
    }
    final total = notifier.calculateReturnTotal();
    final split = SalesReturnRefundSplit.from(
      invoiceTotal: invoice.total,
      invoicePaid: invoice.paid,
      paymentMethod: invoice.paymentMethod,
      cashPaid: invoice.cashPaid,
      bankPaid: invoice.bankPaid,
      totalReturn: total,
      hasCustomer: invoice.customerId != null,
      invoiceRoundingAdjustment: invoice.roundingAdjustment,
    );
    // المستحقُّ على الفاتورة كما تقرؤه القسمة: بلا فرق التقريب، ولا ذمّةَ
    // لعميلٍ نقديٍّ أصلاً.
    final due = invoice.customerId == null
        ? 0.0
        : (invoice.total - invoice.paid - invoice.roundingAdjustment)
            .clamp(0.0, double.infinity)
            .toDouble();
    final parts = <String>[
      if (split.arRefund > 0) tr('تخفيض ذمة العميل'),
      if (split.cashRefund > 0) tr('استرداد نقدي'),
      if (split.bankRefund > 0) tr('استرداد بنكي'),
    ];
    return PicPosSettlementCard(
      title: tr('تسوية المبلغ مع العميل'),
      method: parts.isEmpty ? tr('لا تسوية') : parts.join(' + '),
      rows: [
        PicPosSettlementRow(tr('الرصيد المستحق حالياً'), picposReturnMoney(due)),
        PicPosSettlementRow(
            tr('قيمة التخفيض'), picposReturnMoney(split.arRefund)),
        if (split.cashRefund > 0)
          PicPosSettlementRow(
              tr('استرداد نقدي'), picposReturnMoney(split.cashRefund)),
        if (split.bankRefund > 0)
          PicPosSettlementRow(
              tr('استرداد بنكي'), picposReturnMoney(split.bankRefund)),
      ],
      resultLabel: tr('الرصيد بعد التسوية'),
      resultValue: picposReturnMoney(due - split.arRefund),
    );
  }

  /// «تفاصيل إضافية» — نصُّ السبب الحرّ (متى اختير «أخرى») وضريبةُ كلّ سطر
  /// كما سُجّلت على الفاتورة الأصليّة (فاتورةٌ قد تخلط الخاضعَ بالمعفى).
  Widget _buildDetails(SalesReturnState state) {
    final muted = context.picposMuted;
    // عناصرُ القائمة نفسُها مترجَمةٌ (`AppConstants.returnReasonCategories`)،
    // فـ«أخرى» تُقارَن بنصّها المعروض — كما في منتقي السبب أعلاه.
    final other = tr('أخرى');
    final isOther = _screen._selectedReasonCategory == other;
    return PicPosCollapsibleCard(
      title: tr('تفاصيل إضافية'),
      forceOpen: isOther,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOther) ...[
            TextField(
              key: const Key('picpos_return_reason_notes'),
              controller: returnReasonController,
              decoration: InputDecoration(
                labelText: tr('ملاحظات إضافية'),
                prefixIcon: const Icon(PhosphorIconsBold.textT, size: 18),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
            ),
            const SizedBox(height: 10),
          ],
          if (state.invoiceItems.isEmpty)
            Text(
              tr('اختر الفاتورة الأصلية لعرض أصنافها'),
              style: TextStyle(fontSize: 12, color: muted),
            )
          else
            for (final item in state.invoiceItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      item.taxAmount > 0
                          ? PhosphorIconsBold.receipt
                          : PhosphorIconsBold.prohibit,
                      size: 12,
                      color: item.taxAmount > 0 ? AppColors.primary : muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        state.productCache[item.productId]?.name ??
                            tr('صنف #{p0}', {'p0': item.productId}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      item.taxAmount > 0
                          ? tr('ضريبة {p0}% = {p1}', {
                              'p0': item.taxRate.toStringAsFixed(0),
                              'p1': picposReturnMoney(item.taxAmount),
                            })
                          : tr('معفى من الضريبة'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: item.taxAmount > 0 ? AppColors.primary : muted,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// منتقي الفاتورة الأصليّة — **نفسُ** لوح القائمة وترشيحِه (المدى والبحث)
  /// وعدّاداتِه، في حوارٍ بدل عمودٍ دائم، كما يعرض التصميمُ حقلاً واحداً.
  Future<void> _openInvoicePicker() async {
    final notifier = ref.read(salesReturnProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => Dialog(
        backgroundColor: Theme.of(dCtx).cardColor,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 880,
          height: 620,
          child: StatefulBuilder(
            builder: (sCtx, setLocal) => Consumer(
              builder: (cCtx, cRef, _) {
                final st = cRef.watch(salesReturnProvider);
                final allRows = [
                  for (final inv in st.invoices) _screen._toRow(inv, st),
                ];
                final kpis = PicPosReturnKpis.from(allRows);
                final rows = allRows
                    .where((r) => r.matchesNumber(
                        _screen._invoiceSearchController.text))
                    .toList();
                final byId = {for (final inv in st.invoices) inv.id: inv};
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('اختر الفاتورة الأصلية'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('إغلاق'),
                            icon: const Icon(PhosphorIconsBold.x, size: 16),
                            onPressed: () => Navigator.pop(dCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PicPosReturnsSummaryCards(kpis: kpis, isSales: true),
                      const SizedBox(height: 12),
                      Expanded(
                        child: PicPosReturnsInvoicePanel(
                          rows: rows,
                          selectedId: st.selectedInvoice?.id,
                          isLoading: st.isLoading,
                          emptyMessage: tr('لا توجد فواتير في هذه الفترة'),
                          onSelect: (r) {
                            final inv = byId[r.id];
                            if (inv == null) return;
                            notifier.selectInvoice(inv);
                            Navigator.pop(dCtx);
                          },
                          filters: _screen._buildListFilters(
                            st,
                            onSearchChanged: () => setLocal(() {}),
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
      ),
    );
  }
}
