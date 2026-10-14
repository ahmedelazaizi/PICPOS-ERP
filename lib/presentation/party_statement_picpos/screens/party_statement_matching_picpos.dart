part of 'party_statement_picpos_screen.dart';

mixin _StatementMatchingMixin on _StatementTabsMixin {
  // ═══ ٣أ) مطابقة الدفعات — كشفُ العميل ═══════════════════════════════════
  @override
  Future<_TabData> _matchCustomerTab() async {
    final pid = partyId!;
    final pays = await _repo.getPartyPaymentMatches(
      partyId: pid,
      from: range.start,
      to: range.end,
    );
    if (pays.isEmpty) return const _TabData();
    final open = await _repo.getPartyOpenInvoices(
      partyId: pid,
      supplier: false,
    );

    final matched = pays.where((p) => p.fullyMatched).toList();
    final loose = pays.where((p) => !p.fullyMatched).toList();
    final partial = open.where((o) => o.paid > 0).toList();

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.link,
        label: tr('دفعات مطابَقة'),
        value: '${matched.length}',
        tint: _tintOk,
        vs: _money(matched.fold<double>(0, (s, p) => s + p.amount)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.linkBreak,
        label: tr('غير مطابَقة'),
        value: '${loose.length}',
        tint: loose.isEmpty ? _tintOk : _tintWarn,
        vs: _money(loose.fold<double>(0, (s, p) => s + p.unallocated)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.receipt,
        label: tr('فواتير مسدَّدة جزئياً'),
        value: '${partial.length}',
        tint: partial.isEmpty ? _tintOk : _tintWarn,
        vs: _money(partial.fold<double>(0, (s, o) => s + o.remaining)),
      ),
      // ليس رقماً مقيساً بل **وصفُ سلوكِ النظام** — والدفعةُ فعلاً تُخصم من
      // أقدم فاتورةٍ ما لم تُربَط يدويّاً. وذكرُه هنا يشرح عمودَ «المقترحة».
      PicPosHubKpi(
        icon: PhosphorIconsBold.gear,
        label: tr('قاعدة المطابقة'),
        value: tr('الأقدم أولاً'),
        tint: _tintBrand,
        vs: tr('ما لم تُربط يدوياً'),
      ),
    ];

    return _TabData(
      badge: '${loose.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        PicPosSectionHeader(
          title: tr('حالة مطابقة الدفعات'),
          subtitle: tr(
            'الدفعة غير المطابَقة تُنقص الرصيد الكلي لكنها لا تُقفل فاتورة بعينها — وهذا ما يُربك أعمار الدين',
          ),
          icon: PhosphorIconsBold.link,
          showDivider: false,
        ),
        // ⚠️ **تُمرَّر البطاقاتُ كاملةً بلا `take`**: القصُّ يقع في
        //    `_FilterableBoard` **بعد** الترشيح، وإلّا بحث المشغّلُ في ستٍّ
        //    وهو يظنّ أنّه يبحث في الكلّ.
        _FilterableBoard(
          query: query,
          columns: [
            PicPosBoardColumn(
              label: tr('دفعات غير مطابَقة'),
              icon: PhosphorIconsBold.linkBreak,
              tint: _tintWarn,
              total: loose.length,
              cards: [
                for (final p in loose)
                  PicPosBoardCard(
                    title: '${p.paymentNumber} · ${_money(p.amount)}',
                    subtitle: '${df.format(p.paymentDate)} · ${p.method}',
                    value: _money(p.unallocated),
                    meta: p.invoiceCount == 0
                        ? tr('دفعة تحت الحساب بلا فاتورة')
                        : tr('مخصَّصة جزئياً على {p0} فاتورة', {
                            'p0': p.invoiceCount,
                          }),
                    metaIcon: p.invoiceCount == 0
                        ? PhosphorIconsBold.question
                        : PhosphorIconsBold.arrowRight,
                    metaTint: _tintWarn,
                  ),
              ],
            ),
            _suggestionColumn(loose, open),
            PicPosBoardColumn(
              label: tr('مطابَقة بالفعل'),
              icon: PhosphorIconsBold.link,
              tint: _tintOk,
              total: matched.length,
              cards: [
                for (final p in matched)
                  PicPosBoardCard(
                    title: p.paymentNumber,
                    subtitle: '${df.format(p.paymentDate)} · ${p.method}',
                    value: _money(p.amount),
                    meta: tr('وُزّعت على {p0} فاتورة', {'p0': p.invoiceCount}),
                    metaIcon: PhosphorIconsBold.checkCircle,
                    metaTint: _tintOk,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// عمودُ «المطابقةِ المقترحة» — **يُحسَب بقاعدة الأقدمِ أوّلاً** المعلنةِ في
  /// المؤشّر، لا يُنقَل من التصميم.
  ///
  /// ⚠️ **اقتراحٌ يُقرأ لا فعلٌ يُنفَّذ**: الربطُ اليدويُّ للدفعة بفاتورةٍ لم
  /// يُبنَ في هذه الجولة (أمرُ المالك)، فالبطاقةُ تقول ما **سيقع** بالقاعدة
  /// القائمة ولا تحمل زرّاً يوهم بغيرِ ذلك.
  PicPosBoardColumn _suggestionColumn(
    List<PartyPaymentMatchRow> loose,
    List<PartyOpenInvoiceRow> open,
  ) {
    final cards = <PicPosBoardCard>[];
    // نسخةٌ قابلةٌ للاستهلاك من المتبقّي على كلّ فاتورة، بترتيب الاستحقاق
    // (‏الاستعلامُ يعود مرتّباً تصاعديّاً بـ`due_at`).
    final pool = [
      for (final o in open)
        if (o.remaining > 0.01) (row: o, left: o.remaining),
    ].map((e) => _Pending(e.row, e.left)).toList();

    var idx = 0;
    for (final p in loose) {
      var left = p.unallocated;
      while (left > 0.01 && idx < pool.length) {
        final target = pool[idx];
        final take = left < target.left ? left : target.left;
        cards.add(
          PicPosBoardCard(
            title: '${p.paymentNumber} ← ${target.row.invoiceNumber}',
            subtitle: tr('استحقاق {p0} · {p1}', {
              'p0': df.format(target.row.dueDate),
              'p1': target.row.bucket,
            }),
            value: _money(take),
            meta: take >= target.left - 0.01
                ? tr('يُقفل الفاتورة بالكامل')
                : tr('سداد جزئي — يتبقّى {p0}', {
                    'p0': _money(target.left - take),
                  }),
            metaIcon: take >= target.left - 0.01
                ? PhosphorIconsBold.checkCircle
                : PhosphorIconsBold.arrowRight,
            metaTint: take >= target.left - 0.01 ? _tintOk : _tintBrand,
          ),
        );
        left -= take;
        target.left -= take;
        if (target.left <= 0.01) idx++;
      }
      if (left > 0.01) {
        cards.add(
          PicPosBoardCard(
            title: tr('{p0} · متبقٍ', {'p0': p.paymentNumber}),
            subtitle: tr('لا فاتورة قائمة تستوعبه'),
            value: _money(left),
            meta: tr('يبقى تحت الحساب'),
            metaIcon: PhosphorIconsBold.question,
            metaTint: _tintWarn,
          ),
        );
      }
    }

    return PicPosBoardColumn(
      label: tr('مطابقة مقترحة'),
      icon: PhosphorIconsBold.lightbulb,
      tint: _tintBrand,
      total: cards.length,
      // بلا `take` — القصُّ في `_FilterableBoard` بعد الترشيح.
      cards: cards,
    );
  }

  // ═══ ٣ب) مطابقة الفواتير بالاستلام — كشفُ المورد ═════════════════════════
  //
  // ⚠️ **الأعمدةُ كمّيّاتٌ لا مبالغ.** التصميمُ يكتب «62,000» و«57,320» ج.م،
  //    و`getPurchaseOrderMatches` يعود بـ`purchase_order_items.quantity`
  //    و`received_quantity` و`purchase_invoice_items.quantity` — ثلاثُ
  //    **كمّيّات**. وتقييمُها بالسعر يقتضي سعرَ سطرِ الأمر وسعرَ سطرِ الفاتورة
  //    معاً (‏وفرقُهما هو «فرقُ السعر» نفسُه)، وهو استعلامٌ آخر. فالعمودُ
  //    يقول ما قِيس، والعنوانُ يقول إنّه كمّيّة.
  //
  // ⚠️ **والصفُّ سطرُ صنفٍ لا فاتورة**: الاستعلامُ يضمّ `purchase_order_items`
  //    فيعطي سطراً لكلّ صنفٍ في كلّ أمر. والتصميمُ يعدّ فواتير، فالعدّادُ هنا
  //    يقول «سطراً» صراحةً.
  @override
  Future<_TabData> _matchSupplierTab() async {
    final pid = partyId!;
    final rows = await _repo.getPurchaseOrderMatches(
      supplierId: pid,
      from: range.start,
      to: range.end,
    );
    if (rows.isEmpty) return const _TabData();

    final clean = rows.where((r) => r.clean).toList();
    final gaps = rows.where((r) => !r.clean).toList();
    final qtyGaps = rows.where((r) => r.qtyGap.abs() >= 0.001).toList();
    final billGaps = rows
        .where((r) => r.qtyGap.abs() < 0.001 && r.billingGap.abs() >= 0.001)
        .toList();
    final orders = rows.map((r) => r.orderId).toSet();

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: tr('مطابقة ثلاثية سليمة'),
        value: '${clean.length}',
        tint: _tintOk,
        vs: tr('من {p0} سطراً في {p1} أمر', {
          'p0': rows.length,
          'p1': orders.length,
        }),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.gitDiff,
        label: tr('بها فروق'),
        value: '${gaps.length}',
        tint: gaps.isEmpty ? _tintOk : _tintErr,
        vs: _pct(_ratio(gaps.length.toDouble(), rows.length.toDouble())),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.package,
        label: tr('فروق استلام'),
        value: '${qtyGaps.length}',
        tint: qtyGaps.isEmpty ? _tintOk : _tintWarn,
        vs: tr('المستلم يخالف المطلوب'),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.tag,
        label: tr('فروق فوترة'),
        value: '${billGaps.length}',
        tint: billGaps.isEmpty ? _tintOk : _tintErr,
        vs: tr('المفوتر يخالف المستلم'),
      ),
    ];

    return _TabData(
      badge: '${gaps.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<PoMatchRow>(
          query: query,
          title: tr('مطابقة أمر الشراء بالمستلم بالمفوتر'),
          subtitle: tr(
            'الفرق بين المستلم والمفوتر هو ما يُطالَب به المورد · كميات',
          ),
          minWidth: 860,
          columns: [
            PicPosTableColumn(tr('أمر الشراء'), flex: 1.4),
            PicPosTableColumn(tr('الصنف'), flex: 1.6),
            PicPosTableColumn(
              tr('المطلوب'),
              flex: 1.1,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المستلم'),
              flex: 1.1,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('المفوتر'),
              flex: 1.1,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(
              tr('الفرق'),
              flex: 1.2,
              align: PicPosCellAlign.end,
            ),
            PicPosTableColumn(tr('نوع الفرق'), flex: 1.5),
            PicPosTableColumn(tr('إجراء'), flex: 1.2),
          ],
          groups: [
            (label: tr('الكل'), items: rows),
            (label: tr('بها فروق'), items: gaps),
            (label: tr('سليمة'), items: clean),
          ],
          buildRow: (r) => PicPosTableRow(
            cells: [
              PicPosTextCell(
                r.orderNumber,
                sub: r.receivedAt == null
                    ? tr('لم يُستلم بعد')
                    : tr('استُلم {p0}', {'p0': df.format(r.receivedAt!)}),
                icon: PhosphorIconsBold.receipt,
                tint: r.clean ? _tintOk : _tintErr,
              ),
              PicPosTextCell(r.productName),
              PicPosTextCell(_qty(r.ordered)),
              PicPosTextCell(_qty(r.received)),
              PicPosTextCell(_qty(r.invoiced)),
              r.clean
                  ? const PicPosTextCell('—')
                  : PicPosTrendCell(
                      _qty(
                        r.billingGap.abs() >= 0.001 ? r.billingGap : r.qtyGap,
                      ),
                      up: false,
                    ),
              PicPosTextCell(r.gapKind, tint: r.clean ? _tintOk : _tintErr),
              // ⚠️ **السطرُ السليمُ بلا زرّ**: لا مطالبةَ على ما طابق. والزرُّ
              //    يفتح المطالبةَ على **كلّ** الفروق لا على سطره وحدَه — فهي
              //    مراسلةٌ واحدةٌ تجمعها، وإرسالُ مطالبةٍ لكلّ سطرٍ يُغرق المورد.
              if (r.clean)
                const PicPosTextCell('—')
              else
                PicPosButtonCell(
                  tr('مطالبة'),
                  icon: PhosphorIconsBold.bell,
                  tint: _tintWarn,
                  onPressed: () => openClaim(gaps),
                ),
            ],
          ),
          totals: (list) {
            var o = 0.0;
            var rc = 0.0;
            var iv = 0.0;
            for (final r in list) {
              o += r.ordered;
              rc += r.received;
              iv += r.invoiced;
            }
            return [
              _count(list.length, tr('سطراً')),
              '',
              _qty(o),
              _qty(rc),
              _qty(iv),
              _qty(iv - rc),
              '',
              '',
            ];
          },
        ),
      ],
    );
  }
}

/// فاتورةٌ قائمةٌ ومقدارُ ما بقي منها أثناءَ توزيعِ الدفعات — قابلةٌ للتعديل
/// لأنّ توزيعَ الأقدمِ أوّلاً يستهلكها على مراحل.
class _Pending {
  _Pending(this.row, this.left);

  final PartyOpenInvoiceRow row;
  double left;
}
