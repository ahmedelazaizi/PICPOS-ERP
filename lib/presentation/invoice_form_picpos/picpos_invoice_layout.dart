// تخطيطُ شاشة الفاتورة على تصميم المالك المرجعيّ (المرحلة C1).
//
// عمودٌ واحد: رأسُ الصفحة (العنوان + الرقم + حالةُ المستند) ← بطاقةُ حقول
// الترويسة ← سطرُ البحث والإضافة ← جدولُ البنود ← الإجماليّات بجوار الدفع ←
// «تفاصيل إضافية» المطويّة ← شريطُ الأفعال الثابتُ أسفلَ الشاشة.
//
// ⚠️ **عرضٌ خالص.** كلُّ زرٍّ هنا ينادي الدالّةَ نفسَها التي كان يناديها
// قبل إعادة التصميم: «مراجعة واعتماد» ← `_save(printAfterSave: false)`
// (وهو ما يقرعه F9)، «حفظ وطباعة» ← `_save(printAfterSave: true)`،
// «حفظ مسودة» ← `_saveDraft` (عرضُ سعرٍ في المبيعات، ولا وجودَ له في
// المشتريات)، «معاينة A4» ← `_previewA4`، «رجوع» ← `onCancel`. فلا تحقّقَ
// ولا ترقيمَ ولا قيدَ يتبدّل.
part of 'picpos_invoice_form.dart';

/// ارتفاعُ جدول البنود — يتبع عددَ السطور بين حدّين، فيبقى الجدولُ والإجماليّاتُ
/// معاً على ٧٦٨ بكسل لفاتورةٍ عاديّة، ويتمرّر الجدولُ داخلَه لفاتورة جملة.
double _linesTableHeight(int lines) {
  final h = 38.0 + 46.0 + (lines < 2 ? 2 : lines) * 57.0;
  return h.clamp(200.0, 420.0);
}

class _PicPosInvoiceLayout extends StatelessWidget {
  const _PicPosInvoiceLayout({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 960;
        final pad = wide ? 20.0 : 12.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('picpos_invoice_scroll'),
                padding: EdgeInsetsDirectional.fromSTEB(pad, 16, pad, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PicPosPageHeader(state: state),
                    const SizedBox(height: 12),
                    _PicPosDocBar(state: state),
                    const SizedBox(height: 12),
                    if (state._showOneTimeCustomer) ...[
                      _PicPosOneTimeCustomerBar(state: state),
                      const SizedBox(height: 12),
                    ],
                    if (state._canLinkPurchaseOrder) ...[
                      _PicPosOrderLinkBar(state: state),
                      const SizedBox(height: 12),
                    ],
                    _PicPosQuickAdd(state: state),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: _linesTableHeight(state._lines.length),
                      child: _PicPosLinesTable(state: state),
                    ),
                    const SizedBox(height: 12),
                    _PicPosTotalsSection(state: state, wide: wide),
                    const SizedBox(height: 12),
                    // التنبيهاتُ السياقيّةُ كما هي (مخزونٌ، متبقٍّ، رقمُ فاتورة
                    // المورد) — من اللوحة الماليّة نفسِها لا نسخةٍ ثانية.
                    ..._PicPosMoneyPanel(state: state, expand: false)
                        ._notices(context),
                    _PicPosAdditionalDetails(state: state),
                  ],
                ),
              ),
            ),
            _PicPosActionBar(state: state, wide: wide),
          ],
        );
      },
    );
  }
}

/// رأسُ الصفحة — العنوانُ والرقمُ وشارةُ الحالة.
class _PicPosPageHeader extends StatelessWidget {
  const _PicPosPageHeader({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final muted = _fMuted(context);
    final statusColor = w.isEdit ? AppColors.info : AppColors.warning;
    return Row(
      children: [
        Icon(
          w.kind.isSales
              ? PhosphorIconsBold.receipt
              : PhosphorIconsBold.shoppingCart,
          size: 22,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            w.kind.isSales ? tr('فاتورة مبيعات') : tr('فاتورة مشتريات'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            w.invoiceNumberPreview,
            key: const Key('picpos_invoice_header_number'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          key: const Key('picpos_invoice_status_chip'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .12),
            border: Border.all(color: statusColor.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            // «مسودة» حتى يُحفَظ المستند — والتحريرُ يقول ما هو.
            w.isEdit ? tr('تعديل') : tr('مسودة'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// الإجماليّاتُ بجوار الدفع — كتلتان على العريض، وعمودٌ واحدٌ على الضيّق.
class _PicPosTotalsSection extends StatelessWidget {
  const _PicPosTotalsSection({required this.state, required this.wide});
  final _PicPosInvoiceFormState state;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    // كتلةُ الدفع القائمة كما هي: طرقُ الدفع (نقدي/آجل/تحويل)، الاستحقاقُ
    // المشتقُّ المقفول، المدفوعُ الآن، المتبقّي، والخصمُ على الفاتورة.
    final payment =
        _PicPosMoneyPanel(state: state, expand: false)._payment(context);
    final totals = _PicPosTotalsCard(state: state);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [totals, const SizedBox(height: 12), payment],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 4, child: totals),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: payment),
        ],
      ),
    );
  }
}

/// كتلةُ الإجماليّات — الفرعيّ، الخصم، الضريبة، والإجماليُّ النهائيُّ مُبرَزاً.
class _PicPosTotalsCard extends StatelessWidget {
  const _PicPosTotalsCard({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final t = state._totals;
    final cur = state.widget.entryCurrency;
    String f(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row(tr('المجموع الفرعي'), f(t.subtotal)),
          // الخصمُ المعروضُ هو ما يُمرَّر إلى المحرّك: حقلُ الترويسة + خصومُ
          // السطور — نفسُ رقم اللوحة الماليّة القديمة.
          row(tr('إجمالي الخصم'), f(t.discountTotal), color: AppColors.warning),
          // النسبةُ من الإعداد لا رقمٌ مطبوع.
          row(
            tr('ضريبة {p0}%', {
              'p0': state.widget.systemTaxRate.toStringAsFixed(0),
            }),
            f(t.tax),
          ),
          const SizedBox(height: 6),
          Container(
            key: const Key('picpos_invoice_grand_total'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.widget.kind.netLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${f(t.net)} ${cur?.symbol ?? AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // المقابلُ المحلّيُّ للمشتريات الخارجيّة — يُعرَض مع الأجنبيّ لا بدلَه.
          if (cur != null) ...[
            const SizedBox(height: 6),
            Text(
              '≈ ${foreignToLocal(foreign: t.net, localPerForeign: cur.localPerForeign).toStringAsFixed(AppConstants.decimalPlaces)}'
              ' ${AppConstants.currencySymbolEn}'
              '  ·  ${cur.code} 1 = ${cur.localPerForeign}',
              key: const Key('invoice_local_equivalent'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: muted,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «تفاصيل إضافية» — صفٌّ مطويٌّ يحمل الملاحظات (تظهر في الطباعة).
///
/// ⚠️ **بلا مرفقات**: لا بنيةَ لها في المسار، وصفٌّ يَعِد بما لا يُحفَظ
/// أسوأُ من غيابه. ويُفتَح تلقائيّاً متى حملت الفاتورةُ ملاحظةً قائمة، فلا
/// يُخفي التحريرُ ما كُتب.
class _PicPosAdditionalDetails extends StatelessWidget {
  const _PicPosAdditionalDetails({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final open = state._detailsOpen;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('picpos_invoice_details_toggle'),
              onTap: () => state.setState(() => state._detailsOpen = !open),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.fileText, size: 15, color: muted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        tr('تفاصيل إضافية'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      open
                          ? PhosphorIconsBold.caretUp
                          : PhosphorIconsBold.caretDown,
                      size: 13,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child:
                  _PicPosMoneyPanel(state: state, expand: false)._notes(context),
            ),
        ],
      ),
    );
  }
}

/// شريطُ الأفعال الثابت أسفلَ الشاشة.
class _PicPosActionBar extends StatelessWidget {
  const _PicPosActionBar({required this.state, required this.wide});
  final _PicPosInvoiceFormState state;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = state._saving;
    final w = state.widget;
    final onPrimary = theme.colorScheme.onPrimary;

    final primary = FilledButton.icon(
      key: const Key('picpos_invoice_approve'),
      onPressed: busy ? null : () => state._save(printAfterSave: false),
      icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // التحريرُ يقول ما يحدث: «اعتمادٌ» على تحريرٍ يوهم بإنشاء ثانية.
            w.isEdit ? tr('حفظ التعديلات') : tr('مراجعة واعتماد'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          // شارةُ F9 — الاختصارُ موصولٌ فعلاً في `CallbackShortcuts`.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: onPrimary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'F9',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: onPrimary.withValues(alpha: .8),
              ),
            ),
          ),
        ],
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );

    OutlinedButton outlined({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      Color? color,
    }) =>
        OutlinedButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon, size: 15, color: color),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: BorderSide(color: theme.dividerColor),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
        );

    final startGroup = <Widget>[
      primary,
      outlined(
        key: const Key('picpos_invoice_save_print'),
        icon: PhosphorIconsBold.printer,
        label: tr('حفظ وطباعة'),
        onPressed: busy ? null : () => state._save(printAfterSave: true),
      ),
      // المبيعاتُ وحدَها: المسودّةُ فيها **عرضُ سعر** يُحفَظ في تبويبه (قرارُ
      // المالك 2026-08-21)، والمشترياتُ بلا مسودّةٍ أصلاً (2026-09-19).
      if (w.onSaveDraft != null)
        outlined(
          key: const Key('picpos_invoice_save_draft'),
          icon: PhosphorIconsBold.floppyDisk,
          label: tr('حفظ مسودة (عرض سعر)'),
          onPressed: busy ? null : state._saveDraft,
        ),
    ];
    final endGroup = <Widget>[
      if (w.onPreviewA4 != null)
        TextButton.icon(
          key: const Key('picpos_invoice_preview_a4'),
          onPressed: busy ? null : state._previewA4,
          icon: const Icon(PhosphorIconsBold.printer, size: 16),
          label: Text(
            tr('معاينة A4'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      outlined(
        key: const Key('picpos_invoice_back'),
        icon: Directionality.of(context) == ui.TextDirection.rtl
            ? PhosphorIconsBold.caretRight
            : PhosphorIconsBold.caretLeft,
        label: tr('رجوع'),
        onPressed: busy ? null : w.onCancel,
      ),
    ];

    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(
          wide ? 20 : 12, 10, wide ? 20 : 12, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Wrap(spacing: 9, runSpacing: 8, children: startGroup),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: endGroup,
          ),
        ],
      ),
    );
  }
}
