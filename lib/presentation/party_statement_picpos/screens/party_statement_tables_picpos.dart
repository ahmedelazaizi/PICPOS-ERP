part of 'party_statement_picpos_screen.dart';

/// هل يطابق الصفُّ نصَّ البحث؟
///
/// يُقرأ **ما يراه المشغّلُ في الصفّ** — نصوصُ الخلايا الستّ كلُّها ومعها
/// أسطرُها الخافتة. والبحثُ في الكائن المصدر بدلاً منها كان سيجد ما لا يظهر
/// ويُخفق فيما يظهر (رقمُ المستند مثلاً مُنسَّقٌ في الخليّة لا في الصفّ).
///
/// و`PicPosCell` مغلقةٌ (`sealed`)، فالتبديلُ شاملٌ بالبناء: خليّةٌ جديدةٌ في
/// اللبنة تكسر الترجمةَ هنا بدل أن تسقط من البحث صامتة.
bool _rowMatches(PicPosTableRow row, String q) {
  for (final c in row.cells) {
    final text = switch (c) {
      PicPosTextCell(:final text, :final sub) => '$text ${sub ?? ''}',
      PicPosPillCell(:final text) => text,
      PicPosBarCell(:final text) => text,
      PicPosTrendCell(:final text) => text,
      PicPosButtonCell(:final text) => text,
      // زرُّ الاختيار لا نصَّ فيه — والبحثُ يقرأ ما يُقرأ.
      PicPosRadioCell() => '',
    };
    if (text.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// جدولٌ شرائحُه **تُرشِّح فعلاً**، ويسمع بحثَ الترويسة.
///
/// `PicPosDataTable` بلا حالة (‏تأخذ `rows` و`selectedChip` جاهزَين)، وتحميلُ
/// التبويبة يقع في دالّةٍ غيرِ متزامنةٍ لا في `build`. فبلا هذه الحاويةِ كانت
/// الشريحةُ ستُرسَم ولا تفعل — وشريحةٌ لا تُرشِّح تكذب كزرٍّ لا يفعل.
class _FilterableTable<T> extends StatefulWidget {
  const _FilterableTable({
    super.key,
    required this.title,
    required this.columns,
    required this.groups,
    required this.buildRow,
    required this.query,
    this.subtitle,
    this.totals,
    this.minWidth = 760,
    this.headerAction,
  });

  final String title;
  final String? subtitle;
  final List<PicPosTableColumn> columns;

  /// ودجتٌ في آخر رأس الجدول — «تخصيص الأعمدة».
  final Widget? headerAction;

  /// شريحةٌ لكلّ مجموعة، وعدّادُها طولُها بعدَ البحث.
  final List<({String label, List<T> items})> groups;

  final PicPosTableRow Function(T) buildRow;

  /// مجاميعُ **المعروض** — تُعاد لكلّ شريحةٍ وبحثٍ على حدة.
  final List<String> Function(List<T>)? totals;

  final ValueListenable<String> query;

  final double minWidth;

  @override
  State<_FilterableTable<T>> createState() => _FilterableTableState<T>();
}

class _FilterableTableState<T> extends State<_FilterableTable<T>> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.query,
      builder: (context, raw, _) {
        final q = raw.trim().toLowerCase();
        // مدىً آمنٌ بعد تبديل الطرف أو المدى: عددُ المجموعات قد يتغيّر.
        final sel = _sel < widget.groups.length ? _sel : 0;

        /// يبني صفوفَ المجموعة ويُبقي المطابقَ منها وحدَه.
        List<({T item, PicPosTableRow row})> pairs(List<T> src) {
          final out = <({T item, PicPosTableRow row})>[];
          for (final it in src) {
            final row = widget.buildRow(it);
            if (q.isEmpty || _rowMatches(row, q)) out.add((item: it, row: row));
          }
          return out;
        }

        // النوعُ صريحٌ: `const []` في طرفِ الشرطيّة كانت تُنزل الاستدلالَ إلى
        // `dynamic` فتضيع أنواعُ الخانات في السطرين التاليين.
        final List<({T item, PicPosTableRow row})> shown = widget.groups.isEmpty
            ? []
            : pairs(widget.groups[sel].items);

        return PicPosDataTable(
          title: widget.title,
          subtitle: widget.subtitle,
          minWidth: widget.minWidth,
          headerAction: widget.headerAction,
          columns: widget.columns,
          selectedChip: sel,
          chips: [
            for (var i = 0; i < widget.groups.length; i++)
              PicPosTableChip(
                label: widget.groups[i].label,
                // ⚠️ **العدّادُ يُحسَب بعد البحث.** ولو بقي طولَ المجموعة
                //    الكاملةِ لقرأ المشغّلُ «فواتير ١٨» فوقَ ثلاثة صفوف.
                count: q.isEmpty
                    ? '${widget.groups[i].items.length}'
                    : '${pairs(widget.groups[i].items).length}',
                onTap: () => setState(() => _sel = i),
              ),
          ],
          rows: [for (final p in shown) p.row],
          totals: widget.totals?.call([for (final p in shown) p.item]),
          emptyLabel: q.isEmpty
              ? tr('لا صفوفَ لعرضها')
              : tr('لا نتيجةَ للبحث عن «{raw}»', {'raw': raw}),
        );
      },
    );
  }
}

/// هل تطابق بطاقةُ اللوحة نصَّ البحث؟ — نفسُ قاعدةِ الصفّ: ما يُقرأ فيها.
bool _cardMatches(PicPosBoardCard c, String q) =>
    '${c.title} ${c.subtitle} ${c.value} ${c.meta}'.toLowerCase().contains(q);

/// لوحةُ حالاتٍ تسمع بحثَ الترويسة.
///
/// ⚠️ **بلا هذه الحاوية كان البحثُ يبدو معطَّلاً على تبويبةٍ كاملة**: تبويبةُ
/// «مطابقة الدفعات» لوحةٌ لا جدول، فكتابةُ رقمِ سندٍ فيها ما كانت تفعل شيئاً
/// ولا تقول لماذا.
///
/// ⚠️ **والقصُّ يقع هنا لا عند البناء**: تصلها البطاقاتُ **كاملةً** فتُرشِّحها
/// ثمّ تعرض منها [maxCards]. ولو قُصَّت قبلها لبحث المشغّلُ في ستٍّ ظانّاً
/// أنّه يبحث في الكلّ.
class _FilterableBoard extends StatelessWidget {
  const _FilterableBoard({required this.columns, required this.query});

  /// أعمدةٌ تحمل بطاقاتِها **كلَّها**، و`total` عددُها الكلّيّ.
  final List<PicPosBoardColumn> columns;
  final ValueListenable<String> query;

  /// ما يُعرَض من كلّ عمود — والعدّادُ في الرأس يقول الباقي.
  static const int _maxCards = 6;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: query,
      builder: (context, raw, _) {
        final q = raw.trim().toLowerCase();
        return PicPosStatusBoard(
          emptyLabel: q.isEmpty ? tr('لا شيءَ هنا') : tr('لا نتيجةَ للبحث'),
          columns: [
            for (final col in columns)
              () {
                final kept = q.isEmpty
                    ? col.cards
                    : [
                        for (final c in col.cards)
                          if (_cardMatches(c, q)) c,
                      ];
                return PicPosBoardColumn(
                  label: col.label,
                  icon: col.icon,
                  tint: col.tint,
                  // العدّادُ يقول عددَ ما يخصّ الحالةَ الآن: الكلَّ بلا بحثٍ،
                  // والمطابقَ مع بحث.
                  total: q.isEmpty ? col.total : kept.length,
                  cards: kept.take(_maxCards).toList(),
                );
              }(),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// جدولُ الكشف — أعمدةٌ تُختار، وصفٌّ يُختار
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **لا يُعيد الاستعلام.** تبديلُ عمودٍ عرضٌ خالصٌ، فمفتاحُ `_futures` لا
// يحمل الأعمدةَ ولا الاختيار: يسمع الجدولُ مُبلِّغَين ويعيد بناءَ نفسِه.
//
// ⚠️ **والبحثُ يقرأ الظاهرَ وحدَه** بعد التخصيص — وهو عينُ عقد `_rowMatches`:
// «يُقرأ ما يراه المشغّل». فإخفاءُ عمودِ البيان يُخرجه من البحث أيضاً، ولو
// بقي مبحوثاً فيه لأعطى نتائجَ لا يُرى سببُها.
class _LedgerTable extends StatelessWidget {
  const _LedgerTable({
    required this.columnsVN,
    required this.selectedVN,
    required this.query,
    required this.groups,
    required this.subtitle,
    required this.cell,
    required this.total,
    required this.onCustomize,
  });

  final ValueListenable<Set<String>> columnsVN;
  final ValueNotifier<PartyStatementEntry?> selectedVN;
  final ValueListenable<String> query;
  final List<({String label, List<PartyStatementEntry> items})> groups;
  final String subtitle;
  final PicPosCell Function(String columnId, PartyStatementEntry e) cell;
  final String Function(String columnId, List<PartyStatementEntry> rows) total;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: columnsVN,
      builder: (context, visible, _) {
        // الترتيبُ ترتيبُ الكتالوج دائماً — التفضيلُ يحفظ **أيَّها** لا أيُّها
        // أوّل.
        final cols = [
          for (final c in kStatementColumnCatalogue)
            if (visible.contains(c.id)) c,
        ];
        return ValueListenableBuilder<PartyStatementEntry?>(
          valueListenable: selectedVN,
          builder: (context, selected, _) => _FilterableTable<PartyStatementEntry>(
            // ⚠️ **بلا مفتاحٍ عمداً**: حالةُ `_FilterableTable` هي الشريحةُ
            //    المنتقاةُ وحدَها، وهي فهرسٌ في `groups` لا في الأعمدة. ومفتاحٌ
            //    يحمل الأعمدةَ كان سيُعيد بناءَ الحالة عند كلّ تخصيصٍ فيرتدّ
            //    الترشيحُ إلى «كل الحركات» بلا سبب.
            query: query,
            title: tr('كشف الحركة — الرصيد الجاري'),
            subtitle: subtitle,
            headerAction: _CustomizeColumnsButton(onTap: onCustomize),
            columns: [
              for (final c in cols)
                PicPosTableColumn(c.label, flex: c.flex, align: c.align),
            ],
            groups: groups,
            buildRow: (e) => PicPosTableRow(
              cells: [for (final c in cols) cell(c.id, e)],
              selected: identical(selected, e),
              // نقرةٌ ثانيةٌ على المختار تُلغي الاختيار — وإلّا بقي الشريطُ
              // السفليُّ معلّقاً على صفٍّ لا سبيلَ للتخلّي عنه.
              onTap: () => selectedVN.value = identical(selected, e) ? null : e,
            ),
            totals: (rows) => [for (final c in cols) total(c.id, rows)],
          ),
        );
      },
    );
  }
}

class _CustomizeColumnsButton extends StatelessWidget {
  const _CustomizeColumnsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.picposField,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: context.picposHairline),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsBold.slidersHorizontal,
                size: 13,
                color: context.picposMuted,
              ),
              const SizedBox(width: 6),
              Text(
                tr('تخصيص الأعمدة'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريطُ أفعال الكشف — **مثبَّتٌ أسفلَ التبويبة**.
///
/// ⚠️ **و«عرض المستند» يتبع وجودَ الوجهة لا وجودَ الصفّ**: صفُّ الرصيد
/// الافتتاحيّ بلا مستندٍ أصلاً، وتسويةُ رصيدٍ صفُّ خزنةٍ لا وثيقةَ له. فزرٌّ
/// يُعرَض على كلّ صفٍّ ثمّ لا يقفز في نصفها يُقرأ عطباً — والخريطةُ **مغلقةٌ**
/// بالاسم كما في «المستند المصدر».
class _StatementActionBar extends ConsumerWidget {
  const _StatementActionBar({
    required this.selectedVN,
    required this.onPrint,
    required this.onExport,
  });

  final ValueNotifier<PartyStatementEntry?> selectedVN;
  final Future<void> Function() onPrint;
  final Future<void> Function() onExport;

  /// مفرداتُ الكشف تلتقي مفرداتِ اليومية في خمسٍ وتفترق في واحدة.
  ///
  /// `sales_return_balance` صفُّ `safe_transactions` يحمل أثرَ مردودٍ لا
  /// فاتورةَ له (‏Spec 136 ISS-26) — فوجهتُه وجهةُ صفِّ الخزنة، لا شاشةُ
  /// فواتيرَ لن تجد فيها شيئاً بهذا المعرّف.
  String? _referenceTypeOf(PartyStatementEntry e) =>
      e.referenceType == 'sales_return_balance'
      ? 'safe_transaction'
      : e.referenceType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<PartyStatementEntry?>(
      valueListenable: selectedVN,
      builder: (context, selected, _) {
        final target = selected == null
            ? null
            : resolveJournalSourceTarget(
                referenceType: _referenceTypeOf(selected),
                referenceId: selected.referenceId,
                allowedScreenIds: AppConfig.allowedScreenIds.toSet(),
              );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            color: context.picposCard,
            border: Border(top: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            children: [
              Icon(
                selected == null
                    ? PhosphorIconsBold.cursorClick
                    : PhosphorIconsBold.fileText,
                size: 15,
                color: context.picposMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  selected == null
                      ? tr('اختر سطراً لعرض مستنده')
                      : (target == null
                            ? tr('{p0} — لا مستندَ يُفتَح', {
                                'p0': selected.description,
                              })
                            : '${selected.invoiceNumber ?? selected.description}'
                                  ' · ${target.label}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: context.picposMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => unawaited(onExport()),
                icon: const Icon(PhosphorIconsBold.downloadSimple, size: 16),
                label: Text(tr('تصدير')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(onPrint()),
                icon: const Icon(PhosphorIconsBold.printer, size: 16),
                label: Text(tr('طباعة الكشف')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                // 🔴 **الفتحُ عبر القناة لا مباشرةً**: مالكُ التابات وحدَه يعرف
                //    الصلاحيّاتِ وتاريخَ الرجوع وسقفَ التابات — وهي نفسُ قناةِ
                //    «المستند المصدر» في اليومية العامة.
                onPressed: target == null
                    ? null
                    : () => ref
                          .read(screenNavigationProvider.notifier)
                          .open(target.screenId.navigationIndex),
                icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 16),
                label: Text(tr('عرض المستند')),
              ),
            ],
          ),
        );
      },
    );
  }
}
