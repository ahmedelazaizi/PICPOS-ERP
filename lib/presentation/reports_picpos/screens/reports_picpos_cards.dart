part of 'reports_picpos_screen.dart';

extension _ReportsPicposCards on _ReportsPicposScreenState {
  // -----------------------------------------------------------------------
  // Reusable mini-pieces
  // -----------------------------------------------------------------------
  Widget _miniHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  /// Resolves a flat item back to a real entry/shortcut and invokes its action
  /// while recording the open. Used by chip taps (favorites, recents, and
  /// search results).
  void _openFlatItem(_FlatItem item) {
    _registerOpen(item.id);
    if (item.isShortcut) {
      final cat = item.category;
      final shortcut =
          cat.shortcuts.firstWhere((s) => s.id == item.id);
      final parent = cat.mainReports.firstWhere(
        (r) => r.id == shortcut.parentReportId,
        orElse: () => cat.mainReports.first,
      );
      // Honour the shortcut's own destination here too — otherwise finding
      // «حسب المجموعة» through search would land somewhere different from
      // clicking the same chip in the category card.
      (shortcut.action ?? parent.action)();
    } else {
      final entry = item.category.mainReports.firstWhere(
        (r) => r.id == item.id,
        orElse: () => item.category.mainReports.first,
      );
      entry.action();
    }
  }

  // -----------------------------------------------------------------------
  // الشريطُ الجانبيُّ للفئات — عمودُ ٣١٨ في التصميم.
  //
  // ⚠️ **الفئاتُ مجمَّعةٌ لا مسطَّحة.** التصميمُ يرتّبها في خمس مجموعات، وثلاثَ
  //    عشرةَ بطاقةً في شبكةٍ واحدةٍ بلا تجميعٍ تُقرأ قائمةً لا بنية. والمجموعةُ
  //    تُقرأ من [_kCatGroup]، وحارسٌ يمنع أن تُضاف فئةٌ بلا مجموعةٍ فتسقط
  //    صامتةً خارجَ الشريط.
  // -----------------------------------------------------------------------
  Widget _categoryRail() {
    final byGroup = <String, List<PicposReportCategory>>{};
    for (final c in _categories) {
      byGroup.putIfAbsent(_kCatGroup[c.id] ?? _kGroupOrder.last, () => [])
          .add(c);
    }
    final side = BorderSide(color: context.picposHairline);
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        // الحدُّ على الحافّة المواجهة للمحتوى — يسارٌ في RTL.
        border: rtl ? Border(left: side) : Border(right: side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 16),
              children: [
                for (final g in _kGroupOrder)
                  if ((byGroup[g] ?? const []).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 6),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                    for (final c in byGroup[g]!) _railItem(c),
                  ],
              ],
            ),
          ),
          _railFooter(),
        ],
      ),
    );
  }

  Widget _railItem(PicposReportCategory cat) {
    final on = cat.id == _expandedCatId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => setState(() => _expandedCatId = cat.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color:
                  on ? cat.color.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: on ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(cat.icon, size: 17, color: cat.color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                          color: on ? cat.color : context.picposText,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _catMeta(cat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${cat.mainReports.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: on ? cat.color : context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «٣ تقارير · ٨ اختصارات» — **مقيسٌ من الفئة** لا مكتوبٌ بيد.
  String _catMeta(PicposReportCategory c) {
    final r = tr('{p0} تقرير', {'p0': c.mainReports.length});
    return c.shortcuts.isEmpty ? r : tr('{r} · {p0} اختصار', {'r': r, 'p0': c.shortcuts.length});
  }

  /// تذييلُ الشريط.
  ///
  /// ⚠️ التصميمُ يكتب هنا «آخر مزامنة 14:32 · ٣ فروع»، ولا مقياسَ لوقت
  /// المزامنة في هذه الشاشة — فما يُكتب هو ما يُعَدّ فعلاً: عددُ ما في
  /// الشاشة، وأنّ كلَّ تقريرٍ يُحسَب لحظةَ فتحه (وهو ما تفعله الشاشاتُ فعلاً).
  Widget _railFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.clockCounterClockwise,
              size: 17, color: context.picposMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('{p0} تقريراً واختصاراً في {p1} فئة', {'p0': _allItems.length, 'p1': _categories.length}),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposText,
                  ),
                ),
                Text(
                  tr('كلُّ تقريرٍ يُحسَب لحظةَ فتحه'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // لوحةُ التفصيل — الفئةُ المختارةُ وحدَها، كما في التصميم.
  // -----------------------------------------------------------------------
  Widget _detailPane(PicposReportCategory cat, int cols) {
    final pinned = _pinnedItems();
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(26, 22, 26, 30),
      children: [
        _kpiRow(cols),
        const SizedBox(height: 18),
        if (pinned.isNotEmpty) ...[
          _pinnedCard(pinned),
          const SizedBox(height: 18),
        ],
        _detailHeader(cat),
        const SizedBox(height: 14),
        _detailReports(cat, cols),
        if (cat.shortcuts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _shortcutsBar(cat),
        ],
      ],
    );
  }

  // -----------------------------------------------------------------------
  // صفُّ المؤشّرات — أربعُ بطاقاتٍ في صدر التصميم.
  //
  // ⚠️ **الأرقامُ من قائمة الدخل لا من عدّادٍ في الشاشة**، ومحصورةٌ بصلاحية
  //    فروع المستخدم داخلَ الاستعلام نفسِه.
  //
  // ⚠️ **والنسبةُ تختفي حين لا أساسَ لها.** التصميمُ يرسم «١٢٪ ▲» دائماً،
  //    ويومُ أمسٍ بلا حركةٍ يجعلها قسمةً على صفر — و«٠٪» تُقرأ «لم يتغيّر»
  //    بينما الحقيقةُ «لا مقارنة». فيُحذَف السهمُ كلُّه لا يُكتَب صفر.
  // -----------------------------------------------------------------------
  Widget _kpiRow(int cols) {
    final async = ref.watch(reportsHubKpiProvider);
    return async.when(
      loading: () => _kpiSkeleton(cols),
      // ⚠️ لا تُبتلَع: مؤشّرٌ فارغٌ بلا سبب يُقرأ «صفرُ مبيعات».
      error: (e, _) => PicPosDialogBanner(
        icon: PhosphorIconsBold.warningCircle,
        color: AppColors.warning,
        text: tr('تعذّر حسابُ مؤشّرات اليوم: {e}', {'e': e}),
      ),
      data: (k) {
        final cards = <Widget>[
          _kpiCard(PhosphorIconsBold.currencyCircleDollar, tr('مبيعات اليوم'),
              _money(k.revenue.today), tr('ج.م'), k.revenue, AppColors.success),
          _kpiCard(PhosphorIconsBold.trendUp, tr('صافي الربح'),
              _money(k.netProfit.today), tr('ج.م'), k.netProfit, AppColors.primary),
          _kpiCard(PhosphorIconsBold.receipt, tr('عدد الفواتير'),
              k.invoices.today.toStringAsFixed(0), tr('فاتورة'), k.invoices,
              AppColors.info),
          _kpiCard(PhosphorIconsBold.arrowUUpLeft, tr('المرتجعات'),
              _money(k.salesReturns.today), tr('ج.م'), k.salesReturns,
              AppColors.error,
              upIsGood: false),
        ];
        return _kpiGrid(cards, cols);
      },
    );
  }

  /// أربعةُ أعمدةٍ في التصميم، وتنكسر مع ضيق لوحة التفصيل.
  Widget _kpiGrid(List<Widget> cards, int cols) {
    final n = cols >= 3 ? 4 : (cols == 2 ? 2 : 1);
    final rows = <List<Widget>>[];
    for (var i = 0; i < cards.length; i += n) {
      rows.add(cards.skip(i).take(n).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: i < rows[r].length
                        ? rows[r][i]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _kpiSkeleton(int cols) => _kpiGrid(
        [
          for (var i = 0; i < 4; i++)
            Container(
              height: 86,
              decoration: BoxDecoration(
                color: context.picposCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.picposHairline),
              ),
            ),
        ],
        cols,
      );

  String _money(double v) =>
      NumberFormat('#,##0', 'en').format(v.roundToDouble());

  Widget _kpiCard(
    IconData icon,
    String label,
    String value,
    String unit,
    ReportsKpiValue pair,
    Color tint, {
    bool upIsGood = true,
  }) {
    final delta = ReportsHubKpi.deltaPercent(pair);
    final up = (delta ?? 0) >= 0;
    final good = up == upIsGood;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: context.picposText,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.picposMuted,
                ),
              ),
              if (delta != null) ...[
                const Spacer(),
                Icon(
                  up ? PhosphorIconsBold.trendUp : PhosphorIconsBold.trendDown,
                  size: 13,
                  color: good ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  tr('{p0}٪', {'p0': delta.abs().toStringAsFixed(0)}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: good ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailHeader(PicposReportCategory cat) {
    final desc = _kCatDesc[cat.id];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(cat.icon, size: 25, color: cat.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cat.title,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: context.picposText,
                ),
              ),
              if (desc != null) ...[
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailReports(PicposReportCategory cat, int cols) {
    final rows = <List<PicposReportEntry>>[];
    for (var i = 0; i < cat.mainReports.length; i += cols) {
      rows.add(cat.mainReports.skip(i).take(cols).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 13),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: 13),
                  Expanded(
                    child: i < rows[r].length
                        ? _detailReportCard(cat, rows[r][i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// بطاقةُ تقريرٍ كما في التصميم.
  ///
  /// ⚠️ **الشرائحُ السفليّةُ اختصاراتُ التقرير الحقيقيّة** لا «تبويبات»:
  /// التصميمُ يرسم `tabs` لكلّ بطاقةٍ، ولا حقلَ تبويباتٍ في `PicposReportEntry`
  /// — فكتابتُها كانت ستكون اختراعاً. والاختصاراتُ التي أبوها هذا التقرير
  /// بيانٌ قائمٌ يعطي نفسَ الشكل ويصدُق.
  Widget _detailReportCard(PicposReportCategory cat, PicposReportEntry r) {
    final isFav = _favorites.contains(r.id);
    final tags = cat.shortcuts.where((s) => s.parentReportId == r.id).toList();
    final shown = tags.take(3).toList();
    final rest = tags.length - shown.length;

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _registerOpen(r.id);
          r.action();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.picposCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.picposHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(cat.icon, size: 19, color: cat.color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                            color: context.picposText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          r.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            color: context.picposMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _toggleFavorite(r.id),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          isFav
                              ? PhosphorIconsFill.star
                              : PhosphorIconsBold.star,
                          size: 15,
                          color:
                              isFav ? AppColors.warning : context.picposMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 11),
                  decoration: BoxDecoration(
                    border:
                        Border(top: BorderSide(color: context.picposHairline)),
                  ),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final s in shown)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.picposField,
                            borderRadius: BorderRadius.circular(7),
                            border:
                                Border.all(color: context.picposHairline),
                          ),
                          child: Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: context.picposMuted,
                            ),
                          ),
                        ),
                      if (rest > 0)
                        Text(
                          '+$rest',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: context.picposBrandInk,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (r.permission != null) {
      return PermissionGuard(
        permission: r.permission!,
        allowManagerOverride: r.allowManagerOverride,
        actionName: r.title,
        child: card,
      );
    }
    return card;
  }

}