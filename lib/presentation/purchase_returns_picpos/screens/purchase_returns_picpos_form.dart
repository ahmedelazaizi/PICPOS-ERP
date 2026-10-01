// استمارةُ مردود المشتريات على تصميم المالك المرجعيّ (المرحلة C2 من البند ٣).
//
// حلّت محلَّ `purchase_returns_picpos_details.dart` (لوحِ «قائمة + تفاصيل»).
// والتخطيطُ عمودٌ واحدٌ كاستمارة الفاتورة: رأسُ الصفحة ← بطاقةُ الترويسة
// (الفاتورةُ الأصليّة بمنتقٍ، قيمتُها، حالةُ سدادها، التاريخ، المورد، المستودع
// الصادر، سببُ المردود) ← جدولُ الأصناف المرتجعة ← تسويةُ المبلغ مع المورد
// بجوار «تفاصيل إضافية» ← شريطُ الأفعال.
//
// ⚠️ **عرضٌ خالص — لا سطرَ منطقٍ تبدّل.** «مراجعة واعتماد» ← `processReturn`
// (حوارُ التأكيد ← موافقةُ المدير ← `notifier.processReturn` ← المستودع)،
// والكمّيّةُ ← `notifier.updateReturnQuantity` (وهو يقصّ عند المتاح بنفسه)،
// والسببُ ← `notifier.updateReturnReason`، ومنتقي الفاتورة ←
// `notifier.selectInvoice` بنفس فلاتر SQL (المدى · الرقم · المورد · الصنف).
//
// ═══ وقراراتُ المالك السابقةُ على هذه الشاشة — ما بقي منها وما تبدّل ═══
//
// • **لا «حفظ مسودة»**: ترحيلٌ بخطوةٍ واحدةٍ كما اليوم — لا دورةَ مسوّدة.
//   والتصميمُ الجديدُ يعرض الزرَّ، لكنّه وعدٌ بحفظٍ لا يقع؛ فشريطُ الأفعال
//   (`PicPosReturnActionBar`) لا يقبل فعلَ مسوّدةٍ أصلاً.
// • **شارةُ الحالة** يعرضها التصميمُ الجديد، فعادت — بنصّ «جديد» لا «مسودة»:
//   مستندٌ لم يُرحَّل بعد، لا حالةٌ محفوظةٌ مؤقّتاً.
// • **ولا رقمَ مُخمَّن**: رقمُ المردود يُولَّد في المعاملة
//   (`generateInvoiceNumber('PRET-')`)، فالرأسُ يقول «يُولَّد تلقائياً».
// • **«طريقة التسوية» حقلٌ مقروءٌ لا قائمة**: المحرّكُ يقسم آليّاً.
part of 'purchase_returns_picpos_screen.dart';

mixin _PurchaseReturnsPicposForm on ConsumerState<PurchaseReturnsPicposScreen> {
  // Provided by _PurchaseReturnsPicposLogic at composition time.
  Future<void> processReturn();

  _PurchaseReturnsPicposScreenState get _screen =>
      this as _PurchaseReturnsPicposScreenState;

  /// مفتاحُ عائلة `partyNamesMapProvider` **ثابتُ الهويّة** لكلّ مورّد: القائمةُ
  /// لا تُقارَن بقيمتها، فقائمةٌ جديدةٌ في كلّ بناءٍ تعني جلباً جديداً كلَّ مرّة.
  final _supplierKeys = <int, List<int>>{};

  Widget buildReturnForm(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    return PicPosReturnFormLayout(
      header: _buildInvoiceHeader(state, notifier),
      lines: PicPosFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('الأصناف المرتجعة'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _buildItemsList(state, notifier),
            const SizedBox(height: 12),
            _buildReturnTotals(notifier),
          ],
        ),
      ),
      settlement: _buildSettlementMirror(notifier),
      details: _buildDetails(state),
      actionBar: _buildReturnFooter(state, notifier),
    );
  }

  /// «تفاصيل إضافية» — ضريبةُ كلّ سطرٍ كما سُجّلت على الفاتورة الأصليّة
  /// (فاتورةٌ قد تخلط الخاضعَ بالمعفى). ⚠️ **بلا حقل ملاحظات**: المردودُ لا
  /// يحفظ ملاحظةً (السببُ وحدَه يصل صفَّ المستند)، وحقلٌ يُكتَب فيه ثمّ
  /// يُهمَل هو عينُ عطب «بُني ولم يُوصَل».
  Widget _buildDetails(PurchaseReturnState state) {
    final muted = context.picposMuted;
    final invoice = state.selectedInvoice;
    return PicPosCollapsibleCard(
      title: tr('تفاصيل إضافية'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (invoice != null &&
              (invoice.supplierInvoiceNumber ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${tr('رقم فاتورة المورد')}: ${invoice.supplierInvoiceNumber}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
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
                      item.item.taxAmount > 0
                          ? PhosphorIconsBold.receipt
                          : PhosphorIconsBold.prohibit,
                      size: 12,
                      color:
                          item.item.taxAmount > 0 ? AppColors.primary : muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      item.item.taxAmount > 0
                          ? tr('ضريبة {p0}% = {p1}', {
                              'p0': item.item.taxRate.toStringAsFixed(0),
                              'p1': picposReturnMoney(item.item.taxAmount),
                            })
                          : tr('معفى من الضريبة'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            item.item.taxAmount > 0 ? AppColors.primary : muted,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// منتقي الفاتورة الأصليّة — **نفسُ** لوح القائمة وفلاترِ SQL وعدّاداتِها،
  /// في حوارٍ بدل عمودٍ دائم، كما يعرض التصميمُ حقلاً واحداً.
  Future<void> _openInvoicePicker() async {
    final notifier = ref.read(purchaseReturnProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => Dialog(
        backgroundColor: Theme.of(dCtx).cardColor,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 900,
          height: 640,
          child: Consumer(
            builder: (cCtx, cRef, _) {
              final st = cRef.watch(purchaseReturnProvider);
              final rows = [for (final inv in st.invoices) _screen._toRow(inv)];
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
                    PicPosReturnsSummaryCards(
                      kpis: PicPosReturnKpis.from(rows),
                      isSales: false,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: PicPosReturnsInvoicePanel(
                        rows: rows,
                        selectedId: st.selectedInvoice?.id,
                        isLoading: st.isLoading,
                        emptyMessage:
                            tr('لا توجد فواتير مشتريات في هذه الفترة'),
                        onSelect: (r) {
                          final inv = byId[r.id];
                          if (inv == null) return;
                          notifier.selectInvoice(inv);
                          Navigator.pop(dCtx);
                        },
                        filters: _screen._buildListFilters(st, cRef),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// ترويسةُ المستند — رأسُ الصفحة وشبكةُ الحقول.
  ///
  /// ⚠️ **شارةُ الحالة «جديد» لا «مسودة»**، و**الرقمُ «يُولَّد تلقائياً»** —
  /// راجع رأسَ الملفّ.
  ///
  /// سببُ المردود — قائمةٌ ثابتةٌ **إلزاميّة** (قرارُ المالك). 🔴 **وكان
  /// يُكتَب في حالةٍ محلّيّةٍ لا تغادر الودجت**، و`PurchaseReturns.reason`
  /// عمودٌ قائمٌ بلا كاتب. فالقيمةُ تمرّ عبر المزوّد إلى المستودع إلى صفّ
  /// المستند.
  Widget _buildInvoiceHeader(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    final invoice = state.selectedInvoice;
    const none = '—';

    String supplierName = none;
    if (invoice != null) {
      final key =
          _supplierKeys.putIfAbsent(invoice.supplierId, () => [invoice.supplierId]);
      supplierName = ref.watch(partyNamesMapProvider(key)).maybeWhen(
            data: (m) => m[invoice.supplierId],
            orElse: () => null,
          ) ??
          tr('مورد #{p0}', {'p0': invoice.supplierId});
    }
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
            title: tr('مردود مشتريات'),
            number: tr('يُولَّد تلقائياً'),
            statusLabel: tr('جديد'),
          ),
          const SizedBox(height: 14),
          PicPosFormGrid(
            children: [
              PicPosFormField(
                key: const Key('picpos_return_invoice_picker'),
                icon: PhosphorIconsBold.receipt,
                label: tr('رقم فاتورة المشتريات الأصلية'),
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
                // المردودُ يُختَم بلحظة التنفيذ — عرضٌ لا اختيار.
                value: DateTime.now().toString().substring(0, 10),
                readOnly: true,
                trailing: PhosphorIconsBold.lockSimple,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.truck,
                label: tr('المورد'),
                required: true,
                value: supplierName,
                readOnly: true,
              ),
              PicPosFormField(
                icon: PhosphorIconsBold.warehouse,
                label: tr('المستودع الصادر'),
                required: true,
                value: warehouseName,
                readOnly: true,
              ),
              PicPosFormDropdownField(
                key: const Key('picpos_return_reason'),
                icon: PhosphorIconsBold.notepad,
                label: tr('سبب المردود'),
                required: true,
                items: AppConstants.purchaseReturnReasons,
                value: state.returnReason,
                onChanged: notifier.updateReturnReason,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// جدولُ الأصناف — «المشتراة» و«المرتجع سابقاً» و«المتاح حالياً» (قرارُ
  /// المالك 2026-09-18: الثلاثةُ تُعرَض).
  ///
  /// 🔴 **والمتاحُ ليس عرضاً فحسب — هو السقفُ نفسُه** (`maxReturnableFor`).
  /// سقفُ الحقل كان الكمّيّةَ الأصليّةَ وحدَها، فردُّ خمسةٍ من خمسةٍ مرّتَين
  /// كان يمرّ ويخصم المخزونَ مرّتَين ويخفّض ذمّةَ المورّد مرّتَين.
  Widget _buildItemsList(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    final invoice = state.selectedInvoice;
    final lines = <PicPosReturnLine>[
      for (final item in state.invoiceItems)
        () {
          final qty = state.returnQuantities[item.item.id] ?? 0;
          return PicPosReturnLine(
            id: item.item.id,
            name: item.product.name,
            originalQty: item.item.quantity,
            previouslyReturned:
                state.alreadyReturnedByProduct[item.item.productId] ?? 0.0,
            available: notifier.maxReturnableFor(item.item.id),
            returnQty: qty,
            unitPrice: item.item.unitCost,
            lineValue: qty * item.item.unitCost,
          );
        }(),
    ];
    return PicPosReturnLinesTable(
      lines: lines,
      originalQtyLabel: tr('الكمية المشتراة'),
      returnQtyLabel: tr('كمية المردود'),
      unitPriceLabel: tr('سعر التكلفة'),
      lineValueLabel: tr('قيمة المردود'),
      loading: invoice != null && state.isLoading,
      emptyMessage: invoice == null
          ? tr('اختر الفاتورة الأصلية لعرض أصنافها')
          : tr('لا توجد أصناف في هذه الفاتورة'),
      onQtyChanged: notifier.updateReturnQuantity,
    );
  }

  /// شريطُ الإجماليّات النحيف — لبِنةُ القشرة.
  ///
  /// ⚠️ **وثلاثةُ أرقامٍ لا رقمٌ واحد**: الضريبةُ كانت غائبةً عن العرض بينما
  /// تدخل تسويةَ المورّد إجماليّاً — فالمستخدمُ يرى «١٠٠» ويُخصَم من الذمّة
  /// «١١٤».
  Widget _buildReturnTotals(PurchaseReturnNotifier notifier) {
    final total = notifier.calculateReturnTotal();
    return PicPosTotalsBar(
      items: [
        PicPosTotal(
          label: tr('صافي المرتجع'),
          value: total.toStringAsFixed(AppConstants.decimalPlaces),
        ),
        PicPosTotal(
          label: tr('الضريبة'),
          value: notifier
              .calculateReturnVat()
              .toStringAsFixed(AppConstants.decimalPlaces),
        ),
        PicPosTotal(
          label: tr('إجمالي المرتجع'),
          value: (total + notifier.calculateReturnVat())
              .toStringAsFixed(AppConstants.decimalPlaces),
          emphasis: true,
          tone: AppColors.error,
        ),
      ],
    );
  }

  /// «تسوية المبلغ مع المورد» — **مرآةٌ مشتقّةٌ لا حقولُ إدخال**.
  ///
  /// 🔴 **قرارُ المالك 2026-09-18**: التصميمُ عرض «طريقة التسوية» قائمةً
  /// منسدلة، والمحرّكُ **لا يستشيرها**: يقسم آليّاً — ما يُخصَم من ذمّة
  /// المورّد بقدر ما نَدين له، والباقي نقداً. فقائمةٌ تُعرَض ولا تُقرأ هي
  /// أسوأُ من غيابها: يختار المستخدمُ «استرداد نقدي» فيُخفَّض رصيدُ الذمّة
  /// ولا يصله شيء. والتصميمُ الجديدُ يعرض الطريقةَ ثانيةً، فتُعرَض **حقلاً
  /// مقروءاً** بما سيفعله المحرّك.
  ///
  /// ⚠️ **وكلُّ الأرقام مشتقّةٌ من نفس الدالّة** التي ينفّذها المستودعُ
  /// ومعالجُ الـAPI — لا نسخةٌ سادسةٌ من الصيغة.
  Widget _buildSettlementMirror(PurchaseReturnNotifier notifier) {
    final s = notifier.settlement;
    const none = '—';
    if (s == null) {
      return PicPosSettlementCard(
        title: tr('تسوية المبلغ مع المورد'),
        method: none,
        rows: [
          PicPosSettlementRow(tr('الرصيد المستحق حالياً'), none),
          PicPosSettlementRow(tr('قيمة التخفيض'), none),
        ],
        resultLabel: tr('الرصيد بعد التسوية'),
        resultValue: none,
      );
    }
    String money(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);
    return PicPosSettlementCard(
      title: tr('تسوية المبلغ مع المورد'),
      // الوصفُ مشتقٌّ من الأرقام في `methodLabel` — لا مُختارٌ من قائمة.
      method: tr(s.methodLabel),
      rows: [
        PicPosSettlementRow(tr('الرصيد المستحق حالياً'), money(s.remainingBefore)),
        PicPosSettlementRow(tr('قيمة التخفيض'), money(s.apPortion)),
        if (s.touchesCash)
          PicPosSettlementRow(tr('استرداد نقدي'), money(s.cashPortion)),
      ],
      resultLabel: tr('الرصيد بعد التسوية'),
      resultValue: money(s.remainingAfter),
    );
  }

  /// شريطُ الأفعال — لبِنةُ الاستمارة.
  ///
  /// ⚠️ **بفعلٍ واحدٍ لا فعلَين.** التصميمُ يعرض «حفظ مسودة» و«مراجعة
  /// واعتماد»، وقرارُ المالك على هذه الشاشة **ترحيلٌ بخطوةٍ واحدةٍ كما
  /// اليوم**. فزرُّ مسوّدةٍ لا دورةَ حياةٍ خلفَه يعد بحفظٍ لا يقع.
  ///
  /// ⚠️ **وزرٌّ معطَّلٌ بسببٍ ظاهرٍ** لا مخفيّ: إخفاؤه يجعل المستخدمَ يبحث
  /// عن فعلٍ يظنّه غائباً، والتلميحُ يقول ما ينقص.
  Widget _buildReturnFooter(
    PurchaseReturnState state,
    PurchaseReturnNotifier notifier,
  ) {
    final total = notifier.calculateReturnTotal();
    final String? hint = state.selectedInvoice == null
        ? null
        : state.returnReason == null
            ? tr('اختر سبب المردود أولاً')
            : (total <= 0 ? tr('حدّد كميات المرتجع') : null);
    return PicPosReturnActionBar(
      primaryLabel: tr('مراجعة واعتماد'),
      busy: state.isProcessing,
      hint: hint,
      onPrimary: (total > 0 && state.returnReason != null)
          ? processReturn
          : null,
      // الشاشةُ تُدفَع من سجلّ المردودات — «رجوع» يعيد إليه.
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).maybePop()
          : null,
    );
  }
}
