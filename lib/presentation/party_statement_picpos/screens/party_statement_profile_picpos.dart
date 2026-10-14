part of 'party_statement_picpos_screen.dart';

mixin _StatementProfileMixin on _StatementTabsMixin {
  // ═══ ٤) الأوراق التجارية ════════════════════════════════════════════════
  //
  // ⚠️ **هذه التبويبةُ لا تتبع شريطَ المدى.** `getPartyPapers` يقرأ أوراقَ
  //    الطرف كلَّها بلا نافذةِ تاريخ — عمداً: ورقةٌ حُرِّرت قبل الفترة
  //    وتستحقّ بعدها **التزامٌ قائمٌ الآن**، وقصُّها بالمدى كان سيُخفي أخطرَ
  //    ما في الكشف. والعنوانُ يقول ذلك صراحةً.
  @override
  Future<_TabData> _papersTab() async {
    final papers = await _repo.getPartyPapers(partyId!);
    if (papers.isEmpty) return const _TabData();

    const liveStatuses = {
      'pending',
      'in_portfolio',
      'deposited',
      'deposited_for_collection',
    };
    List<CommercialPaperData> where(bool Function(CommercialPaperData) f) =>
        papers.where(f).toList();

    final live = where((p) => liveStatuses.contains(p.status));
    final endorsed = where((p) => p.status == 'endorsed');
    final cashed = where((p) => p.status == 'cashed');
    final bounced = where((p) => p.status == 'bounced');

    double sum(List<CommercialPaperData> l) =>
        l.fold<double>(0, (s, p) => s + p.amount);

    final kpis = <PicPosHubKpi>[
      // ⚠️ **التسميةُ لا تذكر الاتّجاه.** التصميمُ يقول «أوراق صادرة قائمة»
      //    لكشف المورد و«أوراق تحت التحصيل» لكشف العميل، وهو يفترض أنّ أوراقَ
      //    المورد صادرةٌ كلُّها وأوراقَ العميل واردةٌ كلُّها. و`getPartyPapers`
      //    يعود بأوراق الطرف **بالاتّجاهين** (وهو الصحيح: مورّدٌ قد يحمل شيكاً
      //    وارداً عن مرتجَع). فالعدّادُ يقول «قائمة» فقط، والاتّجاهُ يُقرأ في
      //    عمود «النوع» صفّاً صفّاً.
      PicPosHubKpi(
        icon: PhosphorIconsBold.note,
        label: tr('أوراق قائمة'),
        value: '${live.length}',
        tint: live.isEmpty ? _tintIdle : AppColors.primaryLight,
        vs: _money(sum(live)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.arrowBendUpLeft,
        label: tr('أوراق مُجيَّرة'),
        value: '${endorsed.length}',
        tint: endorsed.isEmpty ? _tintIdle : _tintViolet,
        vs: _money(sum(endorsed)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.warningOctagon,
        label: tr('أوراق مرتدة'),
        value: '${bounced.length}',
        tint: bounced.isEmpty ? _tintOk : _tintErr,
        vs: bounced.isEmpty ? tr('سجل نظيف') : _money(sum(bounced)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: isSupplier ? tr('مخصومة') : tr('محصَّلة'),
        value: '${cashed.length}',
        tint: cashed.isEmpty ? _tintIdle : _tintOk,
        vs: _money(sum(cashed)),
      ),
    ];

    return _TabData(
      badge: '${papers.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<CommercialPaperData>(
          query: query,
          title: isSupplier
              ? tr('الأوراق الصادرة والمقايضات')
              : tr('الأوراق التجارية والضمانات'),
          subtitle: isSupplier
              ? tr(
                  'الشيك الصادر التزام قائم حتى يُخصم · كل أوراق المورد بلا حصر بالمدى',
                )
              : tr(
                  'الشيك تحت التحصيل لا يُنقص الذمة حتى تحصيله · كل أوراق العميل بلا حصر بالمدى',
                ),
          columns: [
            PicPosTableColumn(tr('الورقة'), flex: 1.4),
            PicPosTableColumn(tr('النوع'), flex: 1.4),
            PicPosTableColumn(tr('البنك'), flex: 1.4),
            PicPosTableColumn(tr('الاستحقاق'), flex: 1.2),
            PicPosTableColumn(
              tr('المبلغ'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(tr('الحالة'), flex: 1.4),
          ],
          groups: [
            (label: tr('الكل'), items: papers),
            (label: tr('قائمة'), items: live),
            (label: tr('مُجيَّرة'), items: endorsed),
            (label: isSupplier ? tr('مخصومة') : tr('محصَّلة'), items: cashed),
            (label: tr('مرتدة'), items: bounced),
          ],
          buildRow: (p) => PicPosTableRow(
            cells: [
              PicPosTextCell(
                p.paperNumber,
                icon: PhosphorIconsBold.note,
                tint: _paperTint(p.status),
              ),
              PicPosTextCell(
                _paperType(p.type),
                sub: p.direction == 'issued' ? tr('صادر') : tr('وارد'),
              ),
              PicPosTextCell(
                (p.bankName ?? '').isEmpty ? '—' : p.bankName!,
                sub: [
                  if ((p.bankBranch ?? '').isNotEmpty) p.bankBranch!,
                  if ((p.accountNumber ?? '').isNotEmpty) p.accountNumber!,
                ].join(' · '),
              ),
              PicPosTextCell(df.format(p.dueDate)),
              PicPosTextCell(_money(p.amount)),
              PicPosPillCell(_paperStatus(p.status), _paperTint(p.status)),
            ],
          ),
          totals: (list) => [
            _count(list.length, tr('ورقة')),
            '',
            '',
            '',
            _money(sum(list)),
            '',
          ],
        ),
      ],
    );
  }

  String _paperType(String t) => switch (t) {
    'cheque' => tr('شيك'),
    'promissory_note' => tr('سند إذني'),
    'bill_of_exchange' => tr('كمبيالة'),
    _ => t,
  };

  String _paperStatus(String s) => switch (s) {
    'pending' => tr('معلق'),
    'in_portfolio' => tr('في الحافظة'),
    'deposited' => tr('مودع'),
    'deposited_for_collection' => tr('برسم التحصيل'),
    'cashed' => tr('محصَّل'),
    'bounced' => tr('مرتد'),
    'endorsed' => tr('مظهَّر'),
    'cancelled' => tr('ملغي'),
    _ => s,
  };

  Color _paperTint(String s) => switch (s) {
    'cashed' => _tintOk,
    'bounced' => _tintErr,
    'endorsed' => _tintViolet,
    'deposited' || 'deposited_for_collection' => AppColors.primaryLight,
    'cancelled' => _tintIdle,
    _ => _tintWarn,
  };

  // ═══ ٥) ملفُّ الطرف ══════════════════════════════════════════════════════
  //
  // رسمُ «سلوك السداد — آخر ٦ فواتير» (عميل) و«الخصم النقدي — المُستغَل مقابلَ
  // المُهدَر» (مورد) صارا مبنيَّين على `getPartySettlementRows`: **صفٌّ لكلّ
  // فاتورةٍ** بتاريخ آخرِ سدادٍ لها. وكان الاثنان متعذّرَين ما دام المصدرُ
  // متوسّطاتٍ مجمَّعة.
  //
  // ⚠️ **والعمودُ لا يُرسَم لفاتورةٍ لم تُسدَّد بعد بقيمةٍ صفريّة**: «لم تُسدَّد»
  //    ليست «سُدّدت في صفرِ يوم». تُرسَم بقيمةِ عمرها الجاري وتُوسَم بذلك،
  //    فيُقرأ الفرق.
  @override
  Future<_TabData> _profileTab() async {
    final p = party;
    if (p == null) return const _TabData();
    final metrics = await _repo.getPartyProfileMetrics(
      partyId: p.id,
      supplier: isSupplier,
    );
    final settlements = await _repo.getPartySettlementRows(
      partyId: p.id,
      supplier: isSupplier,
    );

    final terms = p.paymentTermsDays;
    final discPct = p.earlyPaymentDiscountPct;
    final discDays = p.earlyPaymentDiscountDays;
    final hasDiscount = discPct > 0 && discDays > 0;
    final usage = _ratio(p.balance.abs(), p.creditLimit);

    final kpis = <PicPosHubKpi>[
      if (!isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.creditCard,
          label: tr('حد الائتمان'),
          value: p.creditLimit == 0 ? tr('بلا حد') : _money(p.creditLimit),
          tint: p.creditLimit == 0
              ? _tintIdle
              : (usage >= 100 ? _tintErr : (usage >= 80 ? _tintWarn : _tintOk)),
          vs: p.creditLimit == 0
              ? tr('لم يُحدَّد')
              : tr('المستخدم {p0}', {'p0': _pct(usage)}),
        ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.calendarCheck,
        label: isSupplier ? tr('مدة السداد المتفقة') : tr('مدة السماح'),
        value: terms == 0 ? tr('فوري') : '$terms',
        tint: terms == 0 ? _tintIdle : _tintBrand,
        vs: terms == 0 ? tr('بلا أجل متفق') : tr('يوماً'),
      ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.percent,
          label: tr('خصم السداد المعجَّل'),
          value: hasDiscount
              ? tr('{p0}٪', {
                  'p0': discPct.toStringAsFixed(discPct % 1 == 0 ? 0 : 1),
                })
              : tr('لا خصم'),
          tint: hasDiscount ? _tintOk : _tintIdle,
          vs: hasDiscount
              ? tr('خلال {discDays} يوماً', {'discDays': discDays})
              : '',
        ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.truck,
          label: tr('الالتزام بمواعيد التوريد'),
          value: _pctOrNone(metrics.onTimeDeliveryPct),
          tint: metrics.onTimeDeliveryPct == null
              ? _tintIdle
              : (metrics.onTimeDeliveryPct! >= 80 ? _tintOk : _tintWarn),
          vs: tr('من {p0} أمراً مستلماً', {'p0': metrics.receivedOrders}),
        )
      else ...[
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
          vs: tr('من {p0} فاتورة مسدَّدة', {'p0': metrics.settledInvoices}),
        ),
        PicPosHubKpi(
          icon: PhosphorIconsBold.star,
          label: tr('الالتزام بالسداد'),
          value: _pctOrNone(metrics.onTimeSettlementPct),
          tint: metrics.onTimeSettlementPct == null
              ? _tintIdle
              : (metrics.onTimeSettlementPct! >= 80 ? _tintOk : _tintWarn),
          vs: tr('سُدِّدت في موعدها'),
        ),
      ],
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.star,
          label: tr('تقييم المورد'),
          // `null` = لم يُقيَّم — وهي حالةٌ مختلفةٌ عن «تقييمٌ منخفض».
          value: p.supplierRating == null
              ? tr('لم يُقيَّم')
              : '${p.supplierRating}/5',
          tint: p.supplierRating == null
              ? _tintIdle
              : (p.supplierRating! >= 4
                    ? _tintOk
                    : (p.supplierRating! >= 3 ? _tintWarn : _tintErr)),
          vs: p.supplierRating == null
              ? tr('حكم بشري لم يُسجَّل')
              : tr('من ٥ درجات'),
        ),
    ];

    final rows = <PicPosTableRow>[
      _profileRow(
        isSupplier ? tr('اسم المورد') : tr('اسم العميل'),
        p.name,
        sub: (p.code ?? '').isEmpty ? '' : tr('كود {p0}', {'p0': p.code}),
        icon: isSupplier
            ? PhosphorIconsBold.truck
            : PhosphorIconsBold.storefront,
        status: p.isActive ? tr('نشط') : tr('موقوف'),
        tint: p.isActive ? _tintOk : _tintErr,
      ),
      _profileRow(
        tr('الهاتف'),
        (p.phone ?? '').isEmpty ? '—' : p.phone!,
        icon: PhosphorIconsBold.phone,
        status: (p.phone ?? '').isEmpty ? tr('ناقص') : tr('مسجَّل'),
        tint: (p.phone ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        tr('العنوان'),
        (p.address ?? '').isEmpty ? '—' : p.address!,
        icon: PhosphorIconsBold.mapPin,
        status: (p.address ?? '').isEmpty ? tr('ناقص') : tr('مسجَّل'),
        tint: (p.address ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        tr('الرقم الضريبي'),
        [p.taxId, p.tin].where((v) => (v ?? '').isNotEmpty).join(' · ').isEmpty
            ? '—'
            : [p.taxId, p.tin].where((v) => (v ?? '').isNotEmpty).join(' · '),
        icon: PhosphorIconsBold.identificationCard,
        status: (p.taxId ?? p.tin ?? '').isEmpty ? tr('ناقص') : tr('موثَّق'),
        tint: (p.taxId ?? p.tin ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        tr('حد الائتمان'),
        p.creditLimit == 0 ? tr('بلا حد') : _money(p.creditLimit),
        sub: p.creditLimit == 0 ? '' : tr('المستخدم {p0}', {'p0': _pct(usage)}),
        icon: PhosphorIconsBold.creditCard,
        status: p.creditLimit == 0
            ? tr('غير محدد')
            : (usage >= 100 ? tr('تجاوز') : tr('ضمن الحد')),
        tint: p.creditLimit == 0
            ? _tintIdle
            : (usage >= 100 ? _tintErr : _tintOk),
      ),
      _profileRow(
        isSupplier ? tr('مدة السداد المتفقة') : tr('مدة السماح'),
        terms == 0 ? tr('فوري') : tr('{terms} يوماً', {'terms': terms}),
        sub: tr('يُشتق منها استحقاق كل فاتورة عند إصدارها'),
        icon: PhosphorIconsBold.calendarCheck,
        status: terms == 0 ? tr('بلا أجل') : tr('مفعَّل'),
        tint: terms == 0 ? _tintIdle : _tintOk,
      ),
      _profileRow(
        tr('خصم السداد المعجَّل'),
        hasDiscount
            ? tr('{p0}٪ خلال {discDays} يوماً', {
                'p0': discPct.toStringAsFixed(discPct % 1 == 0 ? 0 : 1),
                'discDays': discDays,
              })
            : tr('لا خصم'),
        icon: PhosphorIconsBold.percent,
        status: hasDiscount ? tr('مفعَّل') : tr('غير مفعَّل'),
        tint: hasDiscount ? _tintOk : _tintIdle,
      ),
      _profileRow(
        tr('الرصيد الحالي'),
        _money(p.balance),
        sub: p.balance == 0
            ? tr('مسوّى')
            : (p.balance > 0 ? tr('مدين') : tr('دائن')),
        icon: PhosphorIconsBold.scales,
        status: p.balance == 0
            ? tr('صفر')
            : (p.balance > 0 ? tr('له عليه') : tr('عليه له')),
        tint: p.balance == 0 ? _tintIdle : _tintBrand,
      ),
      if (isSupplier)
        _profileRow(
          tr('تقييم المورد'),
          p.supplierRating == null
              ? tr('لم يُقيَّم')
              : tr('{p0} من ٥', {'p0': p.supplierRating}),
          sub: tr('حكم بشري لا يُشتق من البيانات'),
          icon: PhosphorIconsBold.star,
          status: p.supplierRating == null ? tr('بلا تقييم') : tr('مسجَّل'),
          tint: p.supplierRating == null ? _tintIdle : _tintOk,
        )
      else
        _profileRow(
          tr('تاريخ الإضافة'),
          df.format(p.createdAt),
          icon: PhosphorIconsBold.clockCounterClockwise,
          status: p.isActive ? tr('نشط') : tr('موقوف'),
          tint: p.isActive ? _tintOk : _tintErr,
        ),
    ];

    return _TabData(
      blocks: [
        PicPosHubKpiRow(items: kpis),
        // مجموعةٌ واحدةٌ («البيانات» في التصميم) — والحاويةُ هنا لأجل البحث
        // لا لأجل الشرائح: بحثُ الترويسة يجب أن يعمل في كلّ تبويبة، وتبويبةٌ
        // واحدةٌ لا يعمل فيها تجعل المشغّلَ يظنّ البحثَ معطَّلاً.
        _FilterableTable<PicPosTableRow>(
          query: query,
          title: isSupplier
              ? tr('ملف المورد وشروط التعامل')
              : tr('ملف العميل وشروط التعامل'),
          subtitle: isSupplier
              ? tr('الشروط المتفقة تُطبَّق تلقائياً على كل أمر شراء')
              : tr('حد الائتمان يُفحص لحظياً قبل كل فاتورة آجلة'),
          minWidth: 560,
          columns: [
            PicPosTableColumn(tr('البند'), flex: 1.6),
            PicPosTableColumn(tr('القيمة'), flex: 2.2),
            PicPosTableColumn(tr('الحالة'), flex: 1.4),
          ],
          groups: [(label: tr('البيانات'), items: rows)],
          buildRow: (r) => r,
        ),
        // التصميمُ يضع الرسمَ **تحتَ** الجدول في هذه التبويبة وحدَها —
        // ولذلك كانت اللبناتُ قائمةً مرتَّبةً لا خاناتٍ مسمّاة.
        if (settlements.isNotEmpty)
          isSupplier
              ? _discountBars(settlements, discPct, discDays)
              : _settlementBars(settlements, terms),
      ],
    );
  }

  /// «سلوك السداد — آخر ٦ فواتير» في كشف العميل.
  ///
  /// العمودُ **أيّامُ السداد الفعليّة**، والمقارنةُ بمهلة السداد المتّفقة.
  /// وفاتورةٌ لم تُسدَّد تُرسَم بعمرها الجاري لا بصفر — فالصفرُ يُقرأ «سُدّدت
  /// فوراً» وهو عكسُ الحقيقة.
  PicPosBarList _settlementBars(List<PartySettlementRow> rows, int terms) {
    final now = DateTime.now();
    return PicPosBarList(
      title: tr('سلوك السداد — آخر {p0} فواتير', {'p0': rows.length}),
      subtitle: terms == 0
          ? tr('أيام السداد الفعلية · لا مهلة متفقة')
          : tr('أيام السداد الفعلية مقابل مهلة {terms} يوماً', {
              'terms': terms,
            }),
      items: [
        for (final r in rows.reversed)
          () {
            final paidDays = r.daysToPay;
            final ageDays = now.difference(r.invoiceDate).inDays;
            final days = paidDays ?? ageDays;
            final late = terms > 0 && days > terms;
            return PicPosBarItem(
              icon: paidDays == null
                  ? PhosphorIconsBold.clock
                  : (late
                        ? PhosphorIconsBold.warning
                        : PhosphorIconsBold.checkCircle),
              tint: paidDays == null ? _tintIdle : (late ? _tintErr : _tintOk),
              label: r.invoiceNumber,
              sub: paidDays == null
                  ? (r.paid > 0
                        ? tr('سُدّد جزء منها — والباقي معلّق')
                        : tr('لم تُسدَّد بعد'))
                  : tr('سُدّدت في {p0}', {'p0': _count(paidDays, 'يوماً')}),
              value: days.toDouble(),
              caption: _count(days, tr('يوماً')),
              display: paidDays == null
                  ? tr('جارية')
                  : (late
                        ? tr('تجاوز {p0}', {'p0': days - terms})
                        : tr('داخل المهلة')),
            );
          }(),
      ],
    );
  }

  /// «الخصم النقدي — المُستغَل مقابل المُهدَر» في كشف المورد.
  ///
  /// ⚠️ **بلا شرطِ خصمٍ متّفقٍ لا رسم**: نسبةٌ صفرٌ أو مهلةٌ صفرٌ تعني «لا خصمَ
  /// معجَّل»، ورسمُ «فات الخصم» على فواتيرَ لا خصمَ لها أصلاً اتّهامٌ بلا سبب.
  /// فتُعرَض حينَها أيّامُ السداد وحدَها.
  PicPosBarList _discountBars(
    List<PartySettlementRow> rows,
    double pct,
    int days,
  ) {
    final has = pct > 0 && days > 0;
    if (!has) {
      return PicPosBarList(
        title: tr('سلوك السداد — آخر {p0} فواتير', {'p0': rows.length}),
        subtitle: tr('لا خصم معجَّل متفق عليه — تُعرض أيام السداد وحدها'),
        items: [
          for (final r in rows.reversed)
            PicPosBarItem(
              icon: r.daysToPay == null
                  ? PhosphorIconsBold.clock
                  : PhosphorIconsBold.checkCircle,
              tint: r.daysToPay == null ? _tintIdle : _tintOk,
              label: r.invoiceNumber,
              sub: r.daysToPay == null
                  ? tr('لم تُسدَّد بعد')
                  : tr('سُدّدت في {p0}', {'p0': _count(r.daysToPay!, 'يوماً')}),
              value: (r.daysToPay ?? 0).toDouble(),
              caption: r.daysToPay == null
                  ? ''
                  : _count(r.daysToPay!, tr('يوماً')),
              display: r.daysToPay == null ? tr('جارية') : _money(r.total),
            ),
        ],
      );
    }

    return PicPosBarList(
      title: tr('الخصم النقدي — المُستغَل مقابل المُهدَر'),
      subtitle: tr('{p0}٪ خلال {days} يوماً · آخر {p1} فواتير', {
        'p0': pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1),
        'days': days,
        'p1': rows.length,
      }),
      items: [
        for (final r in rows.reversed)
          () {
            final captured = r.discountCaptured(days);
            final value = r.total * pct / 100;
            return PicPosBarItem(
              icon: captured == null
                  ? PhosphorIconsBold.clock
                  : (captured
                        ? PhosphorIconsBold.checkCircle
                        : PhosphorIconsBold.xCircle),
              tint: captured == null
                  ? _tintIdle
                  : (captured ? _tintOk : _tintErr),
              label: r.invoiceNumber,
              sub: r.daysToPay == null
                  ? tr('لم تُسدَّد بعد — الخصم ما زال ممكناً')
                  : tr('سُدّدت في {p0}', {'p0': _count(r.daysToPay!, 'يوماً')}),
              value: value,
              caption: captured == null
                  ? tr('متاح')
                  : (captured ? tr('استُغل الخصم') : tr('فات الخصم')),
              // الإشارةُ تقول الاتّجاه: ما استُغلّ وفرٌ، وما فات خسارةٌ مقيسة.
              display: captured == null
                  ? _money(value)
                  : (captured ? '+${_money(value)}' : '−${_money(value)}'),
            );
          }(),
      ],
    );
  }

  PicPosTableRow _profileRow(
    String label,
    String value, {
    String sub = '',
    required IconData icon,
    required String status,
    required Color tint,
  }) => PicPosTableRow(
    cells: [
      PicPosTextCell(label, icon: icon, tint: _tintBrand),
      PicPosTextCell(value, sub: sub.isEmpty ? null : sub),
      PicPosPillCell(status, tint),
    ],
  );
}
