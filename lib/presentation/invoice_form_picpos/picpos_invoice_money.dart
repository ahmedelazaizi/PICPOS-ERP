// العمودُ الماليّ — البطاقةُ الداكنة، الدفع، الملاحظات، التنبيهات، الأزرار.
part of 'picpos_invoice_form.dart';

/// تنبيهٌ سياقيٌّ واحد.
class _Notice {
  const _Notice(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;
}

class _PicPosMoneyPanel extends StatelessWidget {
  const _PicPosMoneyPanel({required this.state, required this.expand});
  final _PicPosInvoiceFormState state;

  /// ‏`true` حين يكون الارتفاعُ **محدوداً** (التخطيطُ العريض)، فتُدفَع
  /// الأزرارُ إلى الأسفل بـ`Spacer`.
  ///
  /// ⚠️ و`Spacer` داخل عمودٍ غيرِ محدودِ الارتفاع **يرمي** لا يتجاهَل: في
  /// التخطيط الضيّق يعيش هذا العمودُ داخل `SingleChildScrollView`، فالمساحةُ
  /// المتبقّيةُ لا نهائيّةٌ ولا معنى لتوزيعها. فيُطوى العمودُ حينئذٍ على
  /// محتواه.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _hero(context),
        const SizedBox(height: 12),
        _payment(context),
        const SizedBox(height: 12),
        _notes(context),
        const SizedBox(height: 12),
        ..._notices(context),
        if (expand) const Spacer(),
        const SizedBox(height: 12),
        _actions(context),
      ],
    );
  }

  // ── البطاقةُ الداكنة ────────────────────────────────────────────────
  Widget _hero(BuildContext context) {
    final t = state._totals;
    final kind = state.widget.kind;
    String f0(double v) => v.toStringAsFixed(0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: _fHero(context),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Stack(
          children: [
            PositionedDirectional(
              end: -30,
              top: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .05),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.currencyCircleDollar,
                        size: 16, color: Color(0xFF7FA6F2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kind.netLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB4C0D3),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: .15),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: .4)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'مسودة',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.net.toStringAsFixed(AppConstants.decimalPlaces),
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -.5,
                          color: Colors.white,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          AppConstants.currencySymbolEn,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7FA6F2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _chip('الفرعي', f0(t.subtotal), Colors.white),
                    // الخصمُ المعروضُ هو **ما يُمرَّر إلى المحرّك**: حقلُ
                    // الترويسة + خصومُ السطور. وعرضُ أحدهما وحدَه كان يُظهر
                    // رقماً لا يطابق فرقَ «المجموع − الإجمالي» على الشاشة
                    // نفسِها.
                    _chip('خصم', '−${f0(t.discountTotal)}', AppColors.warning),
                    _chip(
                      // النسبةُ من الإعداد لا «١٤٪» مطبوعة — والتصميمُ كتبها
                      // قيمةَ عيّنةٍ لا عقداً.
                      'ضريبة ${state.widget.systemTaxRate.toStringAsFixed(0)}%',
                      '+${f0(t.tax)}',
                      const Color(0xFF7FB0FF),
                    ),
                    _chip('البنود', '${t.lineCount}', Colors.white),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String k, String v, Color c) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB4C0D3))),
            const SizedBox(width: 6),
            Text(v,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c,
                    fontFeatures: const [ui.FontFeature.tabularFigures()])),
          ],
        ),
      );

  // ── بطاقةُ الدفع ────────────────────────────────────────────────────
  Widget _payment(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final t = state._totals;
    final paid = t.clampPaid(state._paidRaw);
    final remaining = t.remainingAfter(state._paidRaw);
    final unpaid = remaining > 0.01;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.wallet,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  state.widget.kind.payTitle,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _methods(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _moneyBox(
                        context,
                        label: state.widget.kind.paidLabel,
                        child: TextField(
                          controller: state._paidController,
                          // رقمُ المستخدمِ يوقف التهيئةَ التلقائيّة. و`onChanged`
                          // لا يُستدعى على الإسناد البرمجيّ، فهو الفارقُ
                          // الوحيدُ الموثوقُ بين يدِ المستخدم ويدِ الشاشة.
                          onChanged: (_) => state._paidTouched = true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [ui.FontFeature.tabularFigures()],
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: (unpaid ? AppColors.error : AppColors.success)
                              .withValues(alpha: .08),
                          border: Border.all(
                            color:
                                (unpaid ? AppColors.error : AppColors.success)
                                    .withValues(alpha: .30),
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('المتبقي',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: muted)),
                            const SizedBox(height: 2),
                            Text(
                              remaining.toStringAsFixed(
                                  AppConstants.decimalPlaces),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: unpaid
                                    ? AppColors.error
                                    : AppColors.success,
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // خصمُ المستند — الخصمُ الوحيدُ الذي يصل القاعدةَ فعلاً.
                _moneyBox(
                  context,
                  label: 'خصم على الفاتورة',
                  child: TextField(
                    controller: state._discountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (paid > 0 && paid < t.net) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: t.paidPct(state._paidRaw) / 100,
                      minHeight: 5,
                      backgroundColor: muted.withValues(alpha: .18),
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.success),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyBox(BuildContext context,
      {required String label, required Widget child}) {
    final muted = _fMuted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _fField(context),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800, color: muted)),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  Widget _methods(BuildContext context) {
    const methods = [
      ('cash', 'نقدي', PhosphorIconsBold.money),
      ('credit', 'آجل', PhosphorIconsBold.calendarDot),
      ('transfer', 'تحويل', PhosphorIconsBold.squaresFour),
    ];
    final muted = _fMuted(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _fField(context),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final (key, label, icon) in methods)
            Expanded(
              child: Material(
                color: state._paymentMethod == key
                    ? AppColors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    // ‏«آجل» يُصفِّر المدفوع و«نقدي» يملؤه بالكامل — **تهيئةً
                    // لا إلزاماً**. الحقلُ يبقى مصدرَ الحقيقة الوحيد لِما
                    // يُحفَظ، وهو الدرسُ المكتوبُ في `_handleSave` القائم:
                    // وضعُ الدفع كان يفرض سداداً كاملاً فيُنشئ سنداً لم
                    // يُصدره أحد.
                    //
                    // واختيارُ الطريقةِ صراحةً **يُعيد تسليحَ التهيئة**: من
                    // نقر الحبّةَ يطلب رقمَها، فيُنسى ما كتبه قبلها.
                    state.setState(() {
                      state._paymentMethod = key;
                      state._paidTouched = false;
                    });
                    state._syncAutoPaid();
                  },
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 13,
                            color: state._paymentMethod == key
                                ? Colors.white
                                : muted),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: state._paymentMethod == key
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: state._paymentMethod == key
                                ? Colors.white
                                : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── الملاحظات ───────────────────────────────────────────────────────
  Widget _notes(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوانان مرنان: العمودُ الماليُّ ٤٢٠ ثابتةً، والنصّان معاً
          // يتجاوزانها بـ١٧ بكسل — فيضٌ يرسم شريطاً أصفرَ وأسودَ فوق البطاقة.
          Row(
            children: [
              Icon(PhosphorIconsBold.notePencil, size: 14, color: muted),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('ملاحظات على الفاتورة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text('تظهر في الطباعة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: muted)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              color: _fField(context),
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(11),
            ),
            child: TextField(
              controller: state._notesController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: 'اكتب ملاحظة تخص هذا المستند…',
                hintStyle: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── التنبيهاتُ السياقيّة ────────────────────────────────────────────
  //
  // ⚠️ **ولا تنبيهَ يدّعي ما لم يُقَس.** التصميمُ يكتب «الرصيد المتاح يكفي
  // جميع البنود» — وهي جملةٌ عن المخزون. فلا تُطبَع إلّا حين تصل الأرصدةُ
  // فعلاً في [PicPosInvoiceForm.availableStock]؛ وحين تصل تُقال الحقيقةُ
  // كاملةً: تكفي، أو لا تكفي ويُسمَّى الصنفُ الناقص.
  List<Widget> _notices(BuildContext context) {
    final t = state._totals;
    final kind = state.widget.kind;
    final items = <_Notice>[];

    if (t.quantityTotal > 0) {
      final qty = t.quantityTotal == t.quantityTotal.roundToDouble()
          ? t.quantityTotal.toInt().toString()
          : t.quantityTotal.toStringAsFixed(AppConstants.decimalPlaces);
      if (kind.isSales) {
        items.add(_Notice(
          PhosphorIconsBold.arrowSquareOut,
          'سيُخصم من المخزن $qty وحدة عند الحفظ.',
          AppColors.info,
        ));
        final short = _shortages();
        if (short != null) {
          items.add(_Notice(
            PhosphorIconsBold.warningCircle,
            short,
            AppColors.warning,
          ));
        } else if (state.widget.availableStock != null) {
          items.add(const _Notice(
            PhosphorIconsBold.checkCircle,
            'الرصيد المتاح يكفي جميع البنود.',
            AppColors.success,
          ));
        }
      } else {
        items.add(_Notice(
          PhosphorIconsBold.arrowSquareIn,
          'سيُضاف للمخزن $qty وحدة عند الحفظ، ويُحدَّث متوسط سعر التكلفة '
              'لكل صنف.',
          AppColors.info,
        ));
      }
    }

    final remaining = t.remainingAfter(state._paidRaw);
    if (remaining > 0.01) {
      final r = remaining.toStringAsFixed(AppConstants.decimalPlaces);
      items.add(_Notice(
        PhosphorIconsBold.warningCircle,
        kind.isSales
            ? 'المتبقي $r سيُسجَّل على حساب العميل.'
            : 'المتبقي $r سيُسجَّل كالتزام على حساب المورد.',
        AppColors.warning,
      ));
    }

    if (state._supplierInvoiceMissing) {
      items.add(const _Notice(
        PhosphorIconsBold.sealWarning,
        'أدخل رقم فاتورة المورد قبل الحفظ — مطلوب للمطابقة الضريبية.',
        AppColors.error,
      ));
    }

    if (items.isEmpty) return const [];
    return [
      for (final n in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: n.color.withValues(alpha: .10),
              border: Border.all(color: n.color.withValues(alpha: .30)),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(n.icon, size: 15, color: n.color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    n.text,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// رسالةُ النقص، أو `null` حين يكفي الرصيدُ — أو حين لا تُعرَف الأرصدةُ
  /// أصلاً (وحينها لا يُقال شيءٌ في الاتّجاهَين).
  String? _shortages() {
    final stock = state.widget.availableStock;
    if (stock == null) return null;
    final short = <String>[];
    for (final l in state._lines) {
      final have = stock[l.productId];
      // صنفٌ غائبٌ عن الخريطة ليس صنفاً برصيدِ صفر — قد يكون غيرَ مخزَّنٍ
      // أصلاً (خدمة). فيُتخطّى بدل أن يُتَّهم بالنقص.
      if (have == null) continue;
      if (l.quantity > have) {
        short.add('${l.productName} (متاح '
            '${have.toStringAsFixed(AppConstants.decimalPlaces)})');
      }
    }
    if (short.isEmpty) return null;
    return 'الرصيد لا يكفي: ${short.join(' · ')}';
  }

  // ── الأزرار ─────────────────────────────────────────────────────────
  Widget _actions(BuildContext context) {
    final theme = Theme.of(context);
    final busy = state._saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _primary(
                context,
                icon: PhosphorIconsBold.checkCircle,
                label: 'حفظ الفاتورة',
                shortcut: 'F9',
                onTap: busy ? null : () => state._save(printAfterSave: false),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 132,
              height: 48,
              child: OutlinedButton.icon(
                onPressed:
                    busy ? null : () => state._save(printAfterSave: true),
                icon: const Icon(PhosphorIconsBold.printer, size: 16),
                label: const Text('حفظ وطباعة',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            if (state.widget.onSaveDraft != null) ...[
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : state._saveDraft,
                    icon: const Icon(PhosphorIconsBold.floppyDisk, size: 14),
                    label: Text(
                      // ‏«مسودة» في المشتريات و«عرض سعر» في المبيعات: الاسمُ
                      // يقول ما سيحدث فعلاً — والعرضُ يذهب إلى تبويبه.
                      state.widget.kind.isSales
                          ? 'حفظ كعرض سعر'
                          : 'حفظ كمسودة',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : state.widget.onCancel,
                  icon: const Icon(PhosphorIconsBold.xCircle,
                      size: 14, color: AppColors.error),
                  label: const Text('إلغاء',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _primary(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String shortcut,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: onTap == null
          ? AppColors.primary.withValues(alpha: .5)
          : AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(shortcut,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: .7))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
