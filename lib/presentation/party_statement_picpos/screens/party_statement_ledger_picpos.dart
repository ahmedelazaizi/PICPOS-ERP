part of 'party_statement_picpos_screen.dart';

mixin _StatementLedgerMixin on _StatementTabsMixin {
  // ═══ ١) الحركة والرصيد ═════════════════════════════════════════════════
  //
  // ⚠️ **الرصيدُ الجاري ورصيدُ أوّل الفترة لا يُحسبان هنا.**
  // `getPartyStatement` يحسب الافتتاحيَّ من حركةِ ما قبل الفترة (مبيعاتٌ −
  // مقبوضاتٌ − مدفوعاتٌ − مذكّراتُ مرتجعٍ + شيكات)، ويُدرج صفَّه أوّلَ الكشف،
  // ثمّ يملأ الرصيدَ الجاريَ بحلقةٍ تحترم اتّجاهَ الطرف. وإعادةُ الحساب هنا
  // كانت ستُنتج رقمين لنفس السؤال.
  @override
  Future<_TabData> _ledgerTab() async {
    final pid = partyId!;
    final entries = await _repo.getPartyStatement(
      pid,
      fromDate: range.start,
      toDate: range.end,
      branchId: branchId,
    );
    if (entries.isEmpty) return const _TabData();

    // الفاتورةُ القائمةُ تُعرَف بوجود رقمها في نتيجة `getPartyOpenInvoices`،
    // فعمودُ «الحالة» مقيسٌ لا مُخمَّن. و`PartyStatementEntry` وحدَه لا يحمل
    // حالةَ السداد.
    final open = await _repo.getPartyOpenInvoices(
      partyId: pid,
      supplier: isSupplier,
      branchId: branchId,
    );
    final openByNumber = {for (final o in open) o.invoiceNumber: o};

    var debit = 0.0;
    var credit = 0.0;
    for (final e in entries) {
      debit += e.debit;
      credit += e.credit;
    }
    final closing = entries.last.balance;
    final opening = entries
        .where((e) => e.entryType == 'opening')
        .fold<double>(0, (_, e) => e.balance);

    // المؤشّرُ الخامسُ يفترق بين الكشفين كما في التصميم: العميلُ يُسأل عمّا
    // تأخّر عليه، والمورّدُ عمّا يستحقّ قريباً.
    final overdue = open
        .where((o) => o.overdue)
        .fold<double>(0, (s, o) => s + o.remaining);
    final dueSoon = open
        .where((o) => o.daysLate >= -7)
        .fold<double>(0, (s, o) => s + o.remaining);

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.arrowSquareIn,
        label: tr('رصيد أول الفترة'),
        value: _money(opening),
        tint: _tintIdle,
        vs: df.format(range.start),
      ),
      PicPosHubKpi(
        icon: isSupplier
            ? PhosphorIconsBold.handCoins
            : PhosphorIconsBold.receipt,
        label: tr('إجمالي المدين'),
        value: _money(debit),
        tint: isSupplier ? _tintOk : _tintErr,
        vs: isSupplier ? tr('مدفوعات ومرتجعات') : tr('فواتير ورسوم'),
      ),
      PicPosHubKpi(
        icon: isSupplier
            ? PhosphorIconsBold.receipt
            : PhosphorIconsBold.handCoins,
        label: tr('إجمالي الدائن'),
        value: _money(credit),
        tint: isSupplier ? _tintErr : _tintOk,
        vs: isSupplier ? tr('فواتير شراء') : tr('تحصيلات ومرتجعات'),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.scales,
        label: tr('الرصيد الختامي'),
        value: _money(closing),
        tint: closing == 0 ? _tintIdle : (isSupplier ? _tintErr : _tintBrand),
        vs: closing == 0
            ? tr('مسوّى')
            : (isSupplier ? tr('دائن لصالح المورد') : tr('مدين على العميل')),
      ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.clock,
          label: tr('يستحق خلال ٧ أيام'),
          value: _money(dueSoon),
          tint: dueSoon > 0 ? _tintErr : _tintOk,
          vs: tr('شاملاً المتأخر'),
        )
      else
        PicPosHubKpi(
          icon: PhosphorIconsBold.warning,
          label: tr('المتأخر منه'),
          value: _money(overdue),
          tint: overdue > 0 ? _tintErr : _tintOk,
          vs: tr('فوق مدة السماح'),
        ),
    ];

    // شرائحُ الترشيح **تعمل فعلاً**: شريحةٌ لا تُرشِّح تكذب كزرٍّ لا يفعل.
    final groups = <({String label, List<PartyStatementEntry> items})>[
      (label: tr('كل الحركات'), items: entries),
      (
        label: tr('فواتير'),
        items: entries
            .where((e) => e.entryType == 'invoice' || e.entryType == 'purchase')
            .toList(),
      ),
      (
        label: isSupplier ? tr('مدفوعات') : tr('تحصيلات'),
        items: entries
            .where((e) => e.entryType == (isSupplier ? 'payment' : 'receipt'))
            .toList(),
      ),
      (
        label: tr('مرتجعات'),
        items: entries
            .where(
              (e) => e.entryType == 'sales_return' || e.entryType == 'memo',
            )
            .toList(),
      ),
      if (isSupplier)
        (
          label: tr('خصومات'),
          items: entries.where((e) => e.entryType == 'discount').toList(),
        )
      else
        (
          label: tr('أوراق'),
          items: entries
              .where((e) => e.entryType == 'commercial_paper')
              .toList(),
        ),
    ];

    /// خليّةُ عمودٍ واحدٍ من صفٍّ واحد — الكتالوجُ يختار أيَّها يُبنى.
    PicPosCell cellOf(String columnId, PartyStatementEntry e) =>
        switch (columnId) {
          kStatementColumnDate => PicPosTextCell(df.format(e.date)),
          // ⚠️ **بلون العلامة**: التصميمُ يرسم رقمَ المستند رابطاً تحته خطّ،
          //    وهو ما يُنقَر ليُفتَح. والصفُّ كلُّه قابلٌ للنقر هنا، فاللونُ
          //    يقول «هذا ما يُفتَح» بلا خطٍّ يوحي بمتصفِّح.
          kStatementColumnDoc => PicPosTextCell(
            (e.invoiceNumber ?? '').isEmpty ? '—' : e.invoiceNumber!,
            icon: _entryIcon(e.entryType),
            tint: _entryTint(e.entryType),
          ),
          kStatementColumnDesc => PicPosTextCell(e.description),
          kStatementColumnDebit => PicPosTextCell(
            e.debit == 0 ? '—' : _money(e.debit),
          ),
          kStatementColumnCredit => PicPosTextCell(
            e.credit == 0 ? '—' : _money(e.credit),
          ),
          kStatementColumnBalance => PicPosTextCell(_money(e.balance)),
          _ => _statusPill(e, openByNumber),
        };

    /// خانةُ المجاميع تحت عمودٍ واحد.
    ///
    /// ⚠️ المجاميعُ مجاميعُ **العمود المعروض** لا مجاميعَ الكشف كلِّه — فتتغيّر
    /// مع الشريحة، وإلّا قرأ المشغّلُ مجموعاً لا يخصّ ما يراه.
    String totalOf(String columnId, List<PartyStatementEntry> rows) {
      switch (columnId) {
        case kStatementColumnDate:
          return _count(rows.length, tr('حركة'));
        case kStatementColumnDebit:
          return _money(rows.fold<double>(0, (t, e) => t + e.debit));
        case kStatementColumnCredit:
          return _money(rows.fold<double>(0, (t, e) => t + e.credit));
        case kStatementColumnBalance:
          return rows.isEmpty ? '—' : _money(rows.last.balance);
        default:
          return '';
      }
    }

    return _TabData(
      badge: '${entries.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _LedgerTable(
          columnsVN: visibleColumns,
          selectedVN: selectedEntry,
          query: query,
          groups: groups,
          subtitle: isSupplier
              ? tr(
                  'الدائن يزيد ما علينا للمورد والمدين ينقصه · الرصيد الجاري تراكمي',
                )
              : tr(
                  'مرتّب زمنياً · المدين يزيد الذمة والدائن ينقصها · الرصيد الجاري تراكمي',
                ),
          cell: cellOf,
          total: totalOf,
          onCustomize: openColumnPicker,
        ),
      ],
      // شريطُ التصميم السفليّ: «عرض المستند · طباعة الكشف · تصدير».
      footer: _StatementActionBar(
        selectedVN: selectedEntry,
        onPrint: printStatement,
        onExport: exportToExcel,
      ),
    );
  }

  IconData _entryIcon(String type) => switch (type) {
    'opening' => PhosphorIconsBold.arrowSquareIn,
    'invoice' || 'purchase' => PhosphorIconsBold.receipt,
    'receipt' || 'payment' => PhosphorIconsBold.handCoins,
    'sales_return' || 'memo' => PhosphorIconsBold.arrowUUpLeft,
    'commercial_paper' => PhosphorIconsBold.note,
    'discount' => PhosphorIconsBold.percent,
    _ => PhosphorIconsBold.dotsThree,
  };

  Color _entryTint(String type) => switch (type) {
    'opening' => _tintIdle,
    'invoice' || 'purchase' => isSupplier ? _tintErr : _tintBrand,
    'receipt' || 'payment' => _tintOk,
    'sales_return' || 'memo' => _tintViolet,
    'commercial_paper' => AppColors.primaryLight,
    'discount' => _tintOk,
    _ => _tintIdle,
  };

  /// حالةُ الصفّ — الفاتورةُ وحدَها تُقاس بالقائمِ من الذمّة، والباقي يُسمّى
  /// بنوعه. والتصميمُ يكتب «مسدَّدة» على كلّ فاتورةٍ لأنّه صورة.
  PicPosCell _statusPill(
    PartyStatementEntry e,
    Map<String, PartyOpenInvoiceRow> openByNumber,
  ) {
    if (e.entryType == 'invoice' || e.entryType == 'purchase') {
      final o = openByNumber[e.invoiceNumber ?? ''];
      if (o == null) return PicPosPillCell(tr('مسدَّدة'), _tintOk);
      return o.overdue
          ? PicPosPillCell(
              tr('متأخرة {p0} يوماً', {'p0': o.daysLate}),
              _tintErr,
            )
          : PicPosPillCell(tr('قائمة'), _tintWarn);
    }
    return switch (e.entryType) {
      'opening' => PicPosPillCell(tr('مُدوَّر'), _tintIdle),
      'receipt' => PicPosPillCell(tr('محصَّل'), _tintOk),
      'payment' => PicPosPillCell(tr('مدفوع'), _tintOk),
      'sales_return' || 'memo' => PicPosPillCell(tr('مرتجع'), _tintViolet),
      'commercial_paper' => PicPosPillCell(tr('ورقة'), _tintBrand),
      'discount' => PicPosPillCell(tr('خصم'), _tintOk),
      _ => PicPosPillCell(tr('حركة'), _tintIdle),
    };
  }
}
