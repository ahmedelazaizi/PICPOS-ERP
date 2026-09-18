// سطرُ الإدخال السريع وجدولُ البنود — الجزءُ الأيمنُ من شاشة «فاتورة جديدة».
part of 'picpos_invoice_form.dart';

/// نِسَبُ الأعمدة كما في التصميم — مصدرٌ واحدٌ للرأس والصفوف معاً.
///
/// نسختان منفصلتان كانتا ستنحرفان بأوّل تعديلٍ فتُزاح العناوينُ عن أعمدتها
/// بلا ما يكسر بناءً — انحرافٌ لا يظهر إلا بالعين.
const _kIdxW = 4;

/// عمودُ الصنف — **وهو الذي يدفع ثمنَ عمود الخصم وحدَه**.
///
/// 🔴 عمودٌ ثامنٌ يُضاف بلا إعادةِ توزيعٍ يسرق من **كلّ** جارٍ بنسبته.
/// وقياسٌ عند ١٢٠٠ بكسل: حقلُ الكمّيّة ينزل من ٢٠ بكسلاً إلى ٩ — حقلٌ
/// لا يُكتَب فيه. فيُطرَح عرضُ الخصم من عرض الصنف، ويبقى مجموعُ
/// النِّسَب ٩٥ في النمطَين، **فتتطابق أعرضةُ الأعمدة السبعة الأخرى
/// بكسلاً بكسل**.
///
/// واسمُ الصنف يتحمّلها: سطران مع `ellipsis`، لا رقمٌ يُقرأ خطأً.
int _nameW(PicPosInvoiceKind kind) =>
    kind.supportsLineDiscount ? 33 - _kDiscW : 33;
const _kUnitW = 10;
const _kQtyW = 13;
const _kPriceW = 12;

/// عمودُ «الخصم» — **يُضاف ولا يُزيح**.
///
/// نِسَبُ الأعمدة الأخرى تُركت كما هي حرفاً، فنمطُ المبيعات (الذي لا عمودَ
/// خصمٍ له) يبقى بتخطيطه السابق بلا إزاحةِ بكسل. راجع
/// [PicPosInvoiceKind.supportsLineDiscount].
const _kDiscW = 10;
const _kTaxW = 10;
const _kTotalW = 13;
const double _kDelW = 42;

/// مفتاحُ حقلِ البحث في سطر الإدخال السريع — يستهدفه الاختبارُ بالاسم لا
/// بالترتيب.
@visibleForTesting
const quickAddSearchKey = Key('picpos_quick_add_search');

/// شريطُ «أمر الشراء المصدر» — الاتّجاهُ الجديد بقرار المالك 2026-09-18.
///
/// ═══ ولماذا من هنا لا من هناك ═══
///
/// القائمُ اليومَ عكسُه: زرٌّ على شاشة الأوامر يُنشئ فاتورةً بلا أن يراها
/// أحد — بمخزن الأمر وتاريخِ اليوم وبلا رقم فاتورةِ مورّد. والاتّجاهُ
/// الجديد يجعل الفاتورةَ هي المستندَ الذي يُراجَع قبل أن يتحرّك المخزون.
///
/// ⚠️ **والأمرُ يُستهلَك بالحفظ لا بالربط**: الربطُ هنا اختيارٌ يُفَكّ،
/// والختمُ يقع في معاملة `createPurchaseInvoice` وحدَها.
class _PicPosOrderLinkBar extends StatelessWidget {
  const _PicPosOrderLinkBar({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final linked = state.widget.purchaseOrders
        .where((o) => o.id == state._sourceOrderId)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: linked != null
              ? AppColors.info.withValues(alpha: .55)
              : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.link,
              size: 14, color: linked != null ? AppColors.info : muted),
          const SizedBox(width: 8),
          Text('أمر الشراء المصدر',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: muted)),
          const SizedBox(width: 12),
          if (linked == null)
            OutlinedButton.icon(
              onPressed: () => state._linkPurchaseOrder(context),
              icon: const Icon(PhosphorIconsBold.link, size: 14),
              label: const Text('ربط أمر شراء',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            )
          else ...[
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  linked.orderNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.info,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'فكّ الربط — البنودُ تبقى',
              onPressed: state._unlinkPurchaseOrder,
              icon: const Icon(PhosphorIconsBold.x, size: 13),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
          const Spacer(),
          if (linked != null)
            Flexible(
              child: Text(
                'يُستهلَك الأمرُ بحفظ الفاتورة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// سطرُ الإدخال السريع — باركودٌ عريضٌ ثمّ كمّيّةٌ ثمّ إضافة.
class _PicPosQuickAdd extends StatelessWidget {
  const _PicPosQuickAdd({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final field = _fField(context);

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // ── الباركود / البحث ────────────────────────────────────────
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: field,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: .55),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.barcode,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      // مفتاحٌ صريحٌ لا ترتيبٌ في الشجرة: في نمط المشتريات
                      // يسبق حقلُ «رقم فاتورة المورد» هذا الحقلَ، فاستهدافُه
                      // بـ`byType(TextField).first` كان يكتب في الحقل الخطأ —
                      // ويمرّ الاختبارُ في نمطٍ ويسقط في الآخر لسببٍ لا علاقةَ
                      // له بما يُقاس.
                      key: quickAddSearchKey,
                      controller: state._searchController,
                      focusNode: state._searchFocus,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'امسح الباركود أو اكتب اسم الصنف…',
                        hintStyle: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      onSubmitted: (_) => _submit(context),
                    ),
                  ),
                  // شارةُ F2 — والاختصارُ موصولٌ فعلاً أدناه، لا مرسومٌ فقط.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'F2',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),

          // ── الكمّيّة ────────────────────────────────────────────────
          _box(
            context,
            width: 112,
            label: 'الكمية',
            child: TextField(
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              controller: TextEditingController(
                text: state._quickQty == state._quickQty.roundToDouble()
                    ? state._quickQty.toInt().toString()
                    : state._quickQty.toString(),
              ),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) =>
                  state._quickQty = NumberUtils.tryParseLocale(v) ?? 1,
            ),
          ),
          const SizedBox(width: 9),

          // ── زرُّ الإضافة ────────────────────────────────────────────
          Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => _submit(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.plus, size: 15, color: Colors.white),
                    SizedBox(width: 7),
                    Text('إضافة',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),

          // ── بحثٌ متقدّم ─────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => _openPicker(context),
            icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 15),
            label: const Text('بحث متقدم'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(
    BuildContext context, {
    required double width,
    required String label,
    required Widget child,
  }) {
    final muted = _fMuted(context);
    return Container(
      width: width,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: _fField(context),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800, color: muted)),
          SizedBox(height: 18, child: child),
        ],
      ),
    );
  }

  /// إدخالٌ من الحقل: باركودٌ مطابقٌ تماماً يُضاف فوراً، وإلّا فُتح المنتقي
  /// على النصّ المكتوب.
  ///
  /// والمطابقةُ الحرفيّةُ للباركود أوّلاً بقصد: قارئُ الباركود يُنهي بـEnter،
  /// ففتحُ حوارٍ عند كلّ مسحةٍ كان سيُبطل الغرضَ من القارئ.
  void _submit(BuildContext context) {
    final q = state._searchController.text.trim();
    if (q.isEmpty) {
      _openPicker(context);
      return;
    }
    final byBarcode = state.widget.products
        .where((p) => p.barcode.isNotEmpty && p.barcode == q)
        .firstOrNull;
    if (byBarcode != null) {
      state._addProduct(byBarcode);
      return;
    }
    final exact = state.widget.products
        .where((p) => p.name.toLowerCase() == q.toLowerCase())
        .firstOrNull;
    if (exact != null) {
      state._addProduct(exact);
      return;
    }
    _openPicker(context);
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: 'اختر صنفاً',
        items: [
          for (final p in state.widget.products)
            (
              id: p.id,
              title: p.name,
              subtitle: p.sub.isNotEmpty
                  ? p.sub
                  : p.priceFor(state.widget.kind)
                      .toStringAsFixed(AppConstants.decimalPlaces),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final p = state.widget.products.where((x) => x.id == picked).firstOrNull;
    if (p != null) state._addProduct(p);
  }
}

/// جدولُ البنود — رأسٌ ثابتٌ، صفوفٌ مُفهرَسة، وتذييلُ إحصاء.
class _PicPosLinesTable extends StatelessWidget {
  const _PicPosLinesTable({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = state._lines;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: lines.isEmpty
                ? _empty(context)
                // مُفهرَسٌ لا `Column` في `SingleChildScrollView`: فاتورةُ
                // جملةٍ قد تحمل مئاتِ البنود، وبناءُ كلِّها في كلِّ إطارٍ هو
                // العطبُ نفسُه الذي عولج في قائمة الفواتير.
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, i) => _LineRow(
                      state: state,
                      index: i,
                      line: lines[i],
                    ),
                  ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    Widget cell(String t, int flex, {TextAlign? align}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              t,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
        );

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _fField(context),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          cell('#', _kIdxW),
          cell('الصنف', _nameW(state.widget.kind)),
          cell('الوحدة', _kUnitW),
          cell('الكمية', _kQtyW),
          cell(state.widget.kind.priceLabel, _kPriceW),
          if (state.widget.kind.supportsLineDiscount) cell('الخصم', _kDiscW),
          cell('الضريبة', _kTaxW),
          cell('الإجمالي', _kTotalW, align: TextAlign.end),
          const SizedBox(width: _kDelW),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final muted = _fMuted(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsBold.plusCircle, size: 15, color: muted),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'استخدم سطر الإدخال أعلاه أو اضغط F2 لإضافة صنف جديد للفاتورة',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final t = state._totals;
    String n(double v) => v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(AppConstants.decimalPlaces);

    Widget sep() => Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: theme.dividerColor,
        );

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: _fField(context),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      // ⚠️ **مجموعةُ الإحصاء في `Flexible` بقصد.** كانت ثلاثةَ نصوصٍ عاريةً
      // مع `Spacer` في صفٍّ واحد، فتفيض بـ١١٣ بكسل على شاشةِ ٨٠٠ — وهو
      // مقاسُ كثيرٍ من شاشات نقاط البيع لا حالةٌ نادرة. والفيضُ في Flutter
      // ليس قصّاً صامتاً بل شريطٌ أصفرُ وأسودُ فوق الواجهة.
      child: Row(
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('${t.lineCount} بند',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
                sep(),
                Flexible(
                  child: Text('إجمالي الكمية ${n(t.quantityTotal)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
                sep(),
                Flexible(
                  child: Text(
                    // متوسّطٌ على صفرِ بنودٍ يعطي `NaN` لا استثناءً — فيُحرَس.
                    'متوسط قيمة البند '
                    '${n(t.lineCount == 0 ? 0 : t.subtotal / t.lineCount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('المجموع الفرعي',
              maxLines: 1,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: muted)),
          const SizedBox(width: 9),
          Text(
            t.subtotal.toStringAsFixed(AppConstants.decimalPlaces),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// صفُّ بندٍ واحد — كمّيّةٌ بمُنقِصٍ ومُزيد، وسعرٌ محرَّر، وحبّةُ ضريبةٍ تُنقَر.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.state,
    required this.index,
    required this.line,
  });

  final _PicPosInvoiceFormState state;
  final int index;
  final PicPosInvoiceLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final field = _fField(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // ── الترتيب ─────────────────────────────────────────────────
          Expanded(
            flex: _kIdxW,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: field,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: muted,
                  ),
                ),
              ),
            ),
          ),

          // ── الصنف ───────────────────────────────────────────────────
          Expanded(
            flex: _nameW(state.widget.kind),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                line.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // ── الوحدة ──────────────────────────────────────────────────
          Expanded(
            flex: _kUnitW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  line.unitName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.info,
                  ),
                ),
              ),
            ),
          ),

          // ── الكمّيّة ────────────────────────────────────────────────
          Expanded(
            flex: _kQtyW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  color: field,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _step(
                      icon: PhosphorIconsBold.minus,
                      color: muted,
                      // الكمّيّةُ لا تنزل تحت واحد: صفرٌ يعني سطراً بلا
                      // أثرٍ ماليّ، وسالبٌ يقلب اتّجاهَ حركة المخزون.
                      onTap: line.quantity <= 1
                          ? null
                          : () => state._updateLine(
                                index,
                                line.copyWith(quantity: line.quantity - 1),
                              ),
                    ),
                    Expanded(
                      child: _QtyField(
                        key: ValueKey('qty_${line.productId}'),
                        quantity: line.quantity,
                        onCommit: (q) => state._updateLine(
                          index,
                          line.copyWith(quantity: q),
                        ),
                      ),
                    ),
                    _step(
                      icon: PhosphorIconsBold.plus,
                      color: AppColors.primary,
                      onTap: () => state._updateLine(
                        index,
                        line.copyWith(quantity: line.quantity + 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── السعر ───────────────────────────────────────────────────
          Expanded(
            flex: _kPriceW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: field,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.centerRight,
                child: TextField(
                  key: ValueKey('price_${line.productId}'),
                  controller: TextEditingController(
                    text: line.unitPrice
                        .toStringAsFixed(AppConstants.decimalPlaces),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (v) => state._updateLine(
                    index,
                    line.copyWith(
                        unitPrice: NumberUtils.tryParseLocale(v) ??
                            line.unitPrice),
                  ),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
            ),
          ),

          // ── الخصم — مبلغٌ لكلّ صنف (المشتريات وحدَها) ──────────────
          //
          // 🔴 **البوّابةُ هي عينُها التي تكتب المفتاحَ في خريطة الحفظ**
          // (`PicPosInvoiceLine.toSaveMap`). فلا يُعرَض حقلٌ لنمطٍ لا يقرؤه
          // مسارُ حفظه: المستخدمُ يكتب خصماً ويراه في الإجمالي ثمّ يُحفَظ
          // بلا خصم.
          if (state.widget.kind.supportsLineDiscount)
            Expanded(
              flex: _kDiscW,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: field,
                    border: Border.all(
                      color: line.appliedDiscount > 0
                          ? AppColors.warning.withValues(alpha: .55)
                          : theme.dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.centerRight,
                  child: TextField(
                    key: ValueKey('discount_${line.productId}'),
                    controller: TextEditingController(
                      text: line.appliedDiscount
                          .toStringAsFixed(AppConstants.decimalPlaces),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: line.appliedDiscount > 0
                          ? AppColors.warning
                          : null,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    // ⚠️ **والقيمةُ المعروضةُ هي المحصورة**: خصمٌ أكبرُ من قيمة
                    // السطر يُحصَر في `appliedDiscount`، فلو عُرض الخامُ لقرأ
                    // المستخدمُ رقماً لا يُحفَظ.
                    onSubmitted: (v) => state._updateLine(
                      index,
                      line.copyWith(
                          discount:
                              NumberUtils.tryParseLocale(v) ?? line.discount),
                    ),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  ),
                ),
              ),
            ),

          // ── الضريبة — حبّةٌ تُنقَر للتبديل ──────────────────────────
          Expanded(
            flex: _kTaxW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _TaxPill(
                enabled: line.taxEnabled,
                rate: line.taxRate,
                onTap: () => state._updateLine(
                  index,
                  line.copyWith(taxEnabled: !line.taxEnabled),
                ),
              ),
            ),
          ),

          // ── الإجمالي ────────────────────────────────────────────────
          Expanded(
            flex: _kTotalW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    line.lineTotalWithTax
                        .toStringAsFixed(AppConstants.decimalPlaces),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                  if (line.taxEnabled && line.taxAmount > 0)
                    Text(
                      'منها ضريبة '
                      '${line.taxAmount.toStringAsFixed(AppConstants.decimalPlaces)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── الحذف ───────────────────────────────────────────────────
          SizedBox(
            width: _kDelW,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => state._removeLine(index),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(PhosphorIconsBold.trash,
                        size: 13, color: AppColors.error),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 30,
        child: Icon(
          icon,
          size: 11,
          color: onTap == null ? color.withValues(alpha: .3) : color,
        ),
      ),
    );
  }
}

/// حقلُ الكمّيّة — يُكتب ويُنقَر.
///
/// ── بلاغُ المالك (2026-08-23) ─────────────────────────────────────────────
/// «الكمّيّةُ لا تُكتب في فاتورة جديدة» — كانت `Text` بين زرَّي `+`/`−`،
/// فإدخالُ ٥٠ يعني ٤٩ نقرة.
///
/// ── ولماذا ودجتٌ بحالةٍ لا `TextField` في مكانها ─────────────────────────
/// المتحكّمُ المبنيُّ داخل `build` — كحقلِ السعرِ المجاور — يُعاد إنشاؤه مع
/// كلّ إعادةِ رسم. وتثبيتُ الكمّيّةِ يُعيد رسمَ الصفِّ كلِّه، فالمؤشّرُ يقفز
/// ويضيع نصفُ ما كُتب. فالحالةُ هنا تملك متحكّمَها وتُزامنه من النموذج
/// **حين لا يكون الحقلُ تحت التحرير** وحدَها.
///
/// والتثبيتُ يقع على `done` **وعلى فقدِ التركيز** معاً: من كتب ٥٠ ثمّ نقر
/// خارجَ الحقلِ بلا `Enter` كان يفقد ما كتب — وهو نفسُ البلاغ من بابٍ آخر.
class _QtyField extends StatefulWidget {
  const _QtyField({
    super.key,
    required this.quantity,
    required this.onCommit,
  });

  final double quantity;
  final ValueChanged<double> onCommit;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  /// صحيحةٌ تُعرَض بلا كسر، وكسريّةٌ تُعرَض بكسرها — الوزنُ `1.25` قائم.
  static String _format(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.quantity));
    _focus = FocusNode()
      ..addListener(() {
        if (!_focus.hasFocus) _commit();
      });
  }

  @override
  void didUpdateWidget(covariant _QtyField old) {
    super.didUpdateWidget(old);
    // زرَّا `+`/`−` يغيّران الكمّيّةَ من خارج الحقل، فيُعرَض الجديد. أمّا
    // والمستخدمُ يكتب فلا يُنتزَع منه ما بين يديه.
    if (widget.quantity != old.quantity && !_focus.hasFocus) {
      _controller.text = _format(widget.quantity);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// يقرأ المكتوبَ ويثبّته — أو يُرجع المعروضَ إلى آخرِ قيمةٍ صحيحة.
  ///
  /// والحدُّ محفوظٌ كما كان على زرّ `−`: صفرٌ سطرٌ بلا أثرٍ ماليّ، وسالبٌ
  /// يقلب اتّجاهَ حركةِ المخزون. فما لا يُقرأ رقماً موجباً يُرفَض ويُردّ
  /// المعروضُ — ولا تُكتب قيمةٌ صامتةٌ خلفَ المستخدم.
  ///
  /// والقراءةُ بـ`tryParseLocale` لا `double.parse`: الأرقامُ العربيّةُ
  /// مقبولةٌ، و`parse` كانت ترمي عليها.
  void _commit() {
    final parsed = NumberUtils.tryParseLocale(_controller.text);
    if (parsed == null || parsed <= 0) {
      _controller.text = _format(widget.quantity);
      return;
    }
    _controller.text = _format(parsed);
    if (parsed != widget.quantity) widget.onCommit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _focus.unfocus(),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        fontFeatures: [ui.FontFeature.tabularFigures()],
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// حبّةُ الضريبة — مشتعلةٌ أو مطفأة، والنسبةُ تُعرض حين تُشتعل.
class _TaxPill extends StatelessWidget {
  const _TaxPill({
    required this.enabled,
    required this.rate,
    required this.onTap,
  });

  final bool enabled;
  final double rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = _fMuted(context);
    final on = enabled && rate > 0;
    final color = on ? AppColors.info : muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            border: Border.all(color: color.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.prohibit,
                size: 11,
                color: color,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  // النسبةُ من الصنف أو من إعداد النظام — لا «١٤٪» مطبوعة.
                  on ? '${rate.toStringAsFixed(0)}%' : 'بلا',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
