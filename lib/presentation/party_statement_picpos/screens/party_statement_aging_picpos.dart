part of 'party_statement_picpos_screen.dart';

mixin _StatementAgingMixin on _StatementTabsMixin {
  // ═══ ٢أ) أعمار الدين — كشفُ العميل ══════════════════════════════════════
  @override
  Future<_TabData> _agingTab() async {
    final pid = partyId!;
    final open = await _repo.getPartyOpenInvoices(
      partyId: pid,
      supplier: false,
    );
    if (open.isEmpty) return const _TabData();
    final metrics = await _repo.getPartyProfileMetrics(
      partyId: pid,
      supplier: false,
    );

    final order = [tr('لم يحن'), tr('١—٣٠'), tr('٣١—٦٠'), tr('فوق ٦٠')];
    final sums = {for (final b in order) b: 0.0};
    final counts = {for (final b in order) b: 0};
    for (final o in open) {
      sums[o.bucket] = sums[o.bucket]! + o.remaining;
      counts[o.bucket] = counts[o.bucket]! + 1;
    }
    final total = sums.values.fold<double>(0, (a, b) => a + b);

    final terms = party?.paymentTermsDays ?? 0;
    final kpis = <PicPosHubKpi>[
      for (var i = 0; i < order.length; i++)
        PicPosHubKpi(
          icon: switch (i) {
            0 => PhosphorIconsBold.checkCircle,
            1 => PhosphorIconsBold.clock,
            2 => PhosphorIconsBold.clockCountdown,
            _ => PhosphorIconsBold.warningOctagon,
          },
          label: i == 0
              ? tr('مستحق لم يحن')
              : tr('{p0} يوماً', {'p0': order[i]}),
          value: _money(sums[order[i]]!),
          tint: _bucketTint(order[i]),
          vs: tr('{p0} من القائم', {
            'p0': _pct(_ratio(sums[order[i]]!, total)),
          }),
        ),
      // ⚠️ التصميمُ يسمّيه «متوسط أيام التحصيل ٣٤» — أي من الإصدار إلى
      //    السداد. والمقيسُ في `getPartyProfileMetrics` هو الفرقُ بين
      //    **الاستحقاق** وآخرِ دفعة، فجمعُ مهلةِ السداد عليه كان سيضخّم
      //    الرقمَ لكلّ فاتورةٍ سابقةٍ لـv164 (‏استحقاقُها = إصدارُها).
      //    فيُعرَض ما قِيس بالضبط، وتُذكَر المهلةُ بجانبه.
      PicPosHubKpi(
        icon: PhosphorIconsBold.timer,
        label: tr('متوسط السداد بعد الاستحقاق'),
        value: metrics.settledInvoices == 0
            ? tr('لا بيانات')
            : tr('{p0} يوماً', {
                'p0': metrics.avgSettlementDays.toStringAsFixed(0),
              }),
        tint: metrics.settledInvoices == 0
            ? _tintIdle
            : (metrics.avgSettlementDays > 0 ? _tintErr : _tintOk),
        vs: terms == 0
            ? tr('بلا مهلة متفقة')
            : tr('مدة السماح {terms} يوماً', {'terms': terms}),
      ),
    ];

    return _TabData(
      badge: '${open.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        PicPosBarList(
          title: tr('توزيع الرصيد على أعمار الدين'),
          subtitle: tr('العمر من تاريخ الاستحقاق'),
          items: [
            for (final b in order)
              PicPosBarItem(
                icon: switch (b) {
                  'لم يحن' => PhosphorIconsBold.checkCircle,
                  '١—٣٠' => PhosphorIconsBold.clock,
                  '٣١—٦٠' => PhosphorIconsBold.clockCountdown,
                  _ => PhosphorIconsBold.warningOctagon,
                },
                tint: _bucketTint(b),
                label: b == 'لم يحن'
                    ? tr('لم يحن استحقاقه')
                    : tr('متأخر {b} يوماً', {'b': b}),
                sub: _count(counts[b]!, tr('فاتورة')),
                value: sums[b]!,
                caption: _pct(_ratio(sums[b]!, total)),
                display: _money(sums[b]!),
              ),
          ],
        ),
        _FilterableTable<PartyOpenInvoiceRow>(
          query: query,
          title: tr('الفواتير القائمة وأعمارها'),
          subtitle: tr('كل فاتورة بما سُدّد منها وما تبقّى وعمر تأخرها'),
          // ⚠️ **عمودا إجراءٍ لا واحدٌ كالتصميم.** التصميمُ يضع «تحصيل» وحدَه
          //    ويفتح «متابعة» من مكانٍ لا يظهر في الصورة. والفعلان مختلفان
          //    تماماً — أحدُهما يحرّك مالاً والآخرُ يسجّل مكالمة — فدمجُهما
          //    في زرٍّ واحدٍ كان يُخفي أحدَهما. والحدُّ الأدنى رُفع فيتمرّر
          //    الجدولُ أفقيّاً بدل أن تزدحم تسعةُ أعمدةٍ على شاشةٍ ضيّقة.
          minWidth: 940,
          columns: [
            PicPosTableColumn(tr('الفاتورة'), flex: 1.5),
            PicPosTableColumn(tr('التاريخ'), flex: 1.2),
            PicPosTableColumn(tr('الاستحقاق'), flex: 1.2),
            PicPosTableColumn(
              tr('القيمة'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المسدَّد'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المتبقي'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(tr('عمر التأخر'), flex: 1.3),
            PicPosTableColumn(tr('إجراء'), flex: 1.2),
            PicPosTableColumn(tr('متابعة'), flex: 1.2),
          ],
          groups: [
            (label: tr('القائمة'), items: open),
            (label: tr('متأخرة'), items: open.where((o) => o.overdue).toList()),
          ],
          buildRow: _openInvoiceRow,
          totals: _openInvoiceTotals,
        ),
      ],
    );
  }

  PicPosTableRow _openInvoiceRow(PartyOpenInvoiceRow o) => PicPosTableRow(
    cells: [
      PicPosTextCell(
        o.invoiceNumber,
        icon: PhosphorIconsBold.receipt,
        tint: _bucketTint(o.bucket),
      ),
      PicPosTextCell(df.format(o.invoiceDate)),
      PicPosTextCell(df.format(o.dueDate)),
      PicPosTextCell(_money(o.total)),
      PicPosTextCell(o.paid == 0 ? '—' : _money(o.paid)),
      PicPosTextCell(_money(o.remaining)),
      PicPosBarCell(
        o.overdue ? _count(o.daysLate, tr('يوماً')) : tr('لم يحن'),
        // شريطُ التأخّر يُقاس على ٩٠ يوماً — حدُّ آخرِ شريحةٍ في التقادم،
        // وما فوقَه يمتلئ. ونسبةٌ بلا سقفٍ كانت ستجعل فاتورةً واحدةً
        // قديمةً تسحق باقيَ الصفوف بصريّاً.
        o.overdue ? (o.daysLate / 90).clamp(0.0, 1.0) : 0.0,
        _bucketTint(o.bucket),
      ),
      PicPosButtonCell(
        tr('تحصيل'),
        icon: PhosphorIconsBold.handCoins,
        tint: _tintOk,
        onPressed: openVoucher,
      ),
      PicPosButtonCell(
        tr('متابعة'),
        icon: PhosphorIconsBold.phone,
        tint: _tintBrand,
        onPressed: () => openFollowUp(o),
      ),
    ],
  );

  List<String> _openInvoiceTotals(List<PartyOpenInvoiceRow> rows) {
    var t = 0.0;
    var p = 0.0;
    var r = 0.0;
    for (final o in rows) {
      t += o.total;
      p += o.paid;
      r += o.remaining;
    }
    return [
      _count(rows.length, tr('بند')),
      '',
      '',
      _money(t),
      _money(p),
      _money(r),
      '',
      '',
      '',
    ];
  }

  // ═══ ٢ب) المستحق والاستحقاق — كشفُ المورد ═══════════════════════════════
  @override
  Future<_TabData> _dueTab() async {
    final pid = partyId!;
    final open = await _repo.getPartyOpenInvoices(partyId: pid, supplier: true);
    if (open.isEmpty) return const _TabData();

    // ⚠️ **الشرائحُ الأربعُ متباينةٌ لا متداخلة.** التصميمُ يضع «يستحق خلال ٧
    //    أيام» و«يستحق ٨—٣٠» و«لم يحن» — وثلاثتُها لا تستوعب **المتأخّر**،
    //    فيسقط أعجلُ ما على المنشأة من الكشف. فأُضيفت شريحةُ «متأخّر» أوّلاً.
    double sumWhere(bool Function(PartyOpenInvoiceRow) f) =>
        open.where(f).fold<double>(0, (s, o) => s + o.remaining);

    final overdueSum = sumWhere((o) => o.daysLate > 0);
    final week = sumWhere((o) => o.daysLate <= 0 && o.daysLate >= -7);
    final month = sumWhere((o) => o.daysLate < -7 && o.daysLate >= -30);
    final later = sumWhere((o) => o.daysLate < -30);

    // الخصمُ النقديُّ المتاحُ **يُحسَب من شرطَي v164 معاً**: نسبةٌ بلا مهلةٍ
    // لا معنى لها، فكلتاهما صفرٌ = لا خصمَ معجَّل. والفاتورةُ تدخل الحسابَ
    // إن كان اليومُ لم يتجاوز مهلتَها بعد.
    final pct = party?.earlyPaymentDiscountPct ?? 0;
    final days = party?.earlyPaymentDiscountDays ?? 0;
    final now = DateTime.now();
    final hasDiscount = pct > 0 && days > 0;
    double discountOf(PartyOpenInvoiceRow o) {
      if (!hasDiscount) return 0;
      final deadline = o.invoiceDate.add(Duration(days: days));
      return now.isAfter(deadline) ? 0 : o.remaining * pct / 100;
    }

    final discount = open.fold<double>(0, (s, o) => s + discountOf(o));

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.warningOctagon,
        label: tr('متأخر السداد'),
        value: _money(overdueSum),
        tint: overdueSum > 0 ? _tintErr : _tintOk,
        vs: overdueSum > 0 ? tr('فات استحقاقه') : tr('لا متأخرات'),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.clock,
        label: tr('يستحق خلال ٧ أيام'),
        value: _money(week),
        tint: week > 0 ? _tintErr : _tintOk,
        vs: tr('التزام قريب'),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.calendarCheck,
        label: tr('يستحق ٨—٣٠ يوماً'),
        value: _money(month),
        tint: _tintWarn,
        vs: tr('ضمن الشهر'),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: tr('لم يحن'),
        value: _money(later),
        tint: _tintOk,
        vs: tr('فوق ٣٠ يوماً'),
      ),
      // ⚠️ التصميمُ يضع هنا «الرصيد البنكي 186,400» ليُقارَن بالمستحقّ. وهو
      //    بيانةُ خزينةٍ لا بيانةُ طرف، وقراءتُها تربط كشفَ المورد بمستودعِ
      //    الخزينة كلِّه. فبقي الخصمُ النقديُّ — وهو الرقمُ الذي يغيّر قرارَ
      //    السداد فعلاً — والمقارنةُ بالبنك بندٌ لم يُطلَب.
      PicPosHubKpi(
        icon: PhosphorIconsBold.percent,
        label: tr('خصم نقدي متاح'),
        value: hasDiscount ? _money(discount) : tr('لا خصم متفق'),
        tint: hasDiscount && discount > 0 ? _tintOk : _tintIdle,
        vs: hasDiscount
            ? tr('{p0}٪ خلال {days} يوماً', {
                'p0': pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1),
                'days': days,
              })
            : '',
      ),
    ];

    return _TabData(
      badge: '${open.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<PartyOpenInvoiceRow>(
          query: query,
          title: tr('المستحق للمورد وتواريخه'),
          subtitle: tr('الخصم النقدي المتاح يُقارن بتكلفة الاحتفاظ بالنقد'),
          columns: [
            PicPosTableColumn(tr('المستند'), flex: 1.5),
            PicPosTableColumn(tr('التاريخ'), flex: 1.2),
            PicPosTableColumn(tr('الاستحقاق'), flex: 1.2),
            PicPosTableColumn(
              tr('القيمة'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المسدَّد'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المتبقي'),
              flex: 1.4,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(tr('خصم نقدي'), flex: 1.3),
            PicPosTableColumn(tr('إجراء'), flex: 1.2),
          ],
          groups: [
            (label: tr('كل المستحق'), items: open),
            (
              label: tr('خلال ٧ أيام'),
              items: open.where((o) => o.daysLate >= -7).toList(),
            ),
            (
              label: tr('بخصم نقدي'),
              items: open.where((o) => discountOf(o) > 0).toList(),
            ),
          ],
          buildRow: (o) => PicPosTableRow(
            cells: [
              PicPosTextCell(
                o.invoiceNumber,
                icon: PhosphorIconsBold.receipt,
                tint: o.overdue ? _tintErr : _tintWarn,
              ),
              PicPosTextCell(df.format(o.invoiceDate)),
              PicPosTextCell(
                df.format(o.dueDate),
                sub: o.overdue
                    ? tr('تأخر {p0} يوماً', {'p0': o.daysLate})
                    : tr('باقٍ {p0} يوماً', {'p0': -o.daysLate}),
              ),
              PicPosTextCell(_money(o.total)),
              PicPosTextCell(o.paid == 0 ? '—' : _money(o.paid)),
              PicPosTextCell(_money(o.remaining)),
              discountOf(o) > 0
                  ? PicPosTrendCell(_money(discountOf(o)), up: true)
                  : const PicPosTextCell('—'),
              PicPosButtonCell(
                tr('سداد'),
                icon: PhosphorIconsBold.handCoins,
                tint: _tintOk,
                onPressed: openVoucher,
              ),
            ],
          ),
          totals: (rows) {
            var t = 0.0;
            var p = 0.0;
            var r = 0.0;
            var d = 0.0;
            for (final o in rows) {
              t += o.total;
              p += o.paid;
              r += o.remaining;
              d += discountOf(o);
            }
            return [
              _count(rows.length, tr('بند')),
              '',
              '',
              _money(t),
              _money(p),
              _money(r),
              d > 0 ? _money(d) : '',
              '',
            ];
          },
        ),
        PicPosBarList(
          title: tr('جدول الالتزامات القادمة'),
          subtitle: tr('ما علينا للمورد موزَّعاً على الأسابيع'),
          items: [
            PicPosBarItem(
              icon: PhosphorIconsBold.warningOctagon,
              tint: _tintErr,
              label: tr('متأخر الآن'),
              sub: _count(
                open.where((o) => o.daysLate > 0).length,
                tr('مستند'),
              ),
              value: overdueSum,
              caption: _pct(
                _ratio(overdueSum, overdueSum + week + month + later),
              ),
              display: _money(overdueSum),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.clock,
              tint: _tintErr,
              label: tr('هذا الأسبوع'),
              sub: _count(
                open.where((o) => o.daysLate <= 0 && o.daysLate >= -7).length,
                tr('مستند'),
              ),
              value: week,
              caption: _pct(_ratio(week, overdueSum + week + month + later)),
              display: _money(week),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.calendarCheck,
              tint: _tintWarn,
              label: tr('خلال الشهر'),
              sub: _count(
                open.where((o) => o.daysLate < -7 && o.daysLate >= -30).length,
                tr('مستند'),
              ),
              value: month,
              caption: _pct(_ratio(month, overdueSum + week + month + later)),
              display: _money(month),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.checkCircle,
              tint: _tintOk,
              label: tr('بعد الشهر'),
              sub: _count(
                open.where((o) => o.daysLate < -30).length,
                tr('مستند'),
              ),
              value: later,
              caption: _pct(_ratio(later, overdueSum + week + month + later)),
              display: _money(later),
            ),
          ],
        ),
      ],
    );
  }
}
