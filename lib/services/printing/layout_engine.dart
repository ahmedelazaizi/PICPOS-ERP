/// محرّكُ التخطيط — **مصدرُ الحقيقة الوحيدُ للمواضع**.
///
/// ── لماذا واحدٌ لا اثنان ───────────────────────────────────────────────────
/// كان في المشروع ثلاثةُ رُسّامٍ لكلٍّ منها حسابُ تخطيطٍ خاصّ: راسمُ الـPDF،
/// ونافذةُ المعاينة، ومعاينةُ محرّر الأقسام. ووجودُ `debugRenderItemsTable`
/// كمِقبضِ اختبارٍ دليلٌ مكتوبٌ على أنّهم اكتووا من «المعاينة ≠ الورق».
///
/// هذا المحرّكُ يُنتج [PositionedPage] — عناصرَ بمواضعَ **نهائيّةٍ مطلقةٍ على
/// الصفحة**. الراسمان يأخذانها كما هي ولا يحسبان شيئاً. فيستحيل أن تختلف
/// المعاينةُ عن الورق، لأنّ التخطيطَ حُسب مرّةً واحدة.
///
/// ── محورُ السينات ─────────────────────────────────────────────────────────
/// [PositionedElement.xMm] و[PositionedCell.xMm] تُقاس من **حافّة البداية**
/// (اليسارُ في LTR واليمينُ في RTL). المحرّكُ لا يعرف اتّجاهَ النصّ عمداً —
/// الراسمُ يعرفه، والقاعدةُ واحدةٌ للراسمَين فلا تفترقُ المعاينةُ عن الورق.
///
/// ── ولا يعرف pdf ولا Flutter ──────────────────────────────────────────────
/// مثلَ [TemplateDocument] تماماً — وهذا ما يجعله قابلاً للاختبار بلا واجهة.
library;

import '../../domain/printing/condition_evaluator.dart';
import '../../domain/printing/template_document.dart';

/// خليّةٌ واحدةٌ في صفِّ جدولٍ — بموضعها النهائيِّ وعرضها.
class PositionedCell {
  final String columnKey;
  final double xMm;
  final double wMm;
  final ColumnAlign align;
  final String text;

  /// السطرُ الثاني في رأسٍ ثنائيِّ اللغة — فارغٌ في خلايا البيانات وفي
  /// الرؤوس أحاديّةِ اللغة.
  final String subText;

  const PositionedCell({
    required this.columnKey,
    required this.xMm,
    required this.wMm,
    required this.align,
    required this.text,
    this.subText = '',
  });
}

/// صفٌّ واحدٌ من الجدول بموضعه النهائيِّ على الصفحة.
class PositionedRow {
  /// فهرسُ الصفِّ في البيانات الأصليّة — يبقى ثابتاً عبر الصفحات، فترقيمُ
  /// «م» لا يعيد البدءَ من واحدٍ في الصفحة الثانية.
  final int sourceIndex;

  final double yMm;
  final double heightMm;
  final List<PositionedCell> cells;

  const PositionedRow({
    required this.sourceIndex,
    required this.yMm,
    required this.heightMm,
    required this.cells,
  });
}

/// شريحةُ جدولٍ على صفحةٍ واحدة.
class PositionedTable {
  final double xMm;
  final double yMm;
  final double wMm;

  /// خلايا رأس الجدول — فارغةٌ حين لا يُعاد الرأسُ على هذه الصفحة.
  final List<PositionedCell> headerCells;

  /// ارتفاعُ الرأس — صفرٌ حين لا رأسَ على هذه الصفحة.
  final double headerHeightMm;

  /// الثنائيّةُ **النافذة** لا المطلوبة — تُطفأ على الورق الضيّق مهما طلب
  /// القالب. الراسمُ يقرأ هذه لا [TableSpec.bilingualHeaders].
  final bool bilingualHeaders;

  final List<PositionedRow> rows;

  const PositionedTable({
    required this.xMm,
    required this.yMm,
    required this.wMm,
    required this.headerCells,
    required this.headerHeightMm,
    required this.bilingualHeaders,
    required this.rows,
  });

  /// الارتفاعُ الكلّيُّ الذي تشغله الشريحة.
  double get totalHeightMm =>
      headerHeightMm + rows.fold<double>(0, (s, r) => s + r.heightMm);
}

/// عنصرٌ بموضعٍ نهائيٍّ مطلقٍ على الصفحة.
class PositionedElement {
  final String id;
  final String contentKey;
  final BandId band;

  final double xMm;
  final double yMm;
  final double wMm;
  final double hMm;

  final String text;
  final String? labelAr;
  final String? labelEn;
  final double fontSize;
  final bool bold;
  final TextAlignSpec align;
  final String? colorHex;

  const PositionedElement({
    required this.id,
    required this.contentKey,
    required this.band,
    required this.xMm,
    required this.yMm,
    required this.wMm,
    required this.hMm,
    this.text = '',
    this.labelAr,
    this.labelEn,
    this.fontSize = 10,
    this.bold = false,
    this.align = TextAlignSpec.start,
    this.colorHex,
  });
}

/// صفحةٌ واحدةٌ جاهزةٌ للرسم — لا حسابَ بعدها.
class PositionedPage {
  final int pageNumber;
  final int pageCount;
  final double widthMm;
  final double heightMm;
  final List<PositionedElement> elements;
  final List<PositionedTable> tables;

  const PositionedPage({
    required this.pageNumber,
    required this.pageCount,
    required this.widthMm,
    required this.heightMm,
    required this.elements,
    required this.tables,
  });
}

/// صفحةٌ قيدَ البناء — تُختم في [LayoutEngine.paginate].
class _PageDraft {
  final elements = <PositionedElement>[];
  final tables = <PositionedTable>[];
  double contentBottomMm = 0;
}

/// عتبةُ «الورق الضيّق» بالمليمتر — تحتها تُطفأ العناوينُ الثنائيّة.
///
/// تفصل الحراريَّ (٥٨مم ⇒ ٥٢ متاحة · ٨٠مم ⇒ ٧٤) عن A5 (١٤٨مم ⇒ ١٣٨).
const double narrowPaperMm = 100;

/// يحوّل [TemplateDocument] + بيانات ⇒ صفحاتٍ بمواضعَ نهائيّة.
class LayoutEngine {
  const LayoutEngine._();

  /// [rows] صفوفُ الجدول منسَّقةً نصّاً — طولُ كلِّ صفٍّ يطابق
  /// [TableSpec.visibleColumns] بالترتيب. و[values] قيمُ العناصر بمفتاح
  /// [TemplateElement.contentKey].
  static List<PositionedPage> paginate({
    required TemplateDocument document,
    required List<List<String>> rows,
    Map<String, String> values = const {},
  }) {
    final paper = document.paper;
    final bands = document.orderedVisibleBands;

    // ── النطاقاتُ المثبَّتةُ على الصفحة ───────────────────────────────────
    // الرأسُ يعلو كلَّ صفحةٍ والتذييلُ يقعّرها. وهذا ما يجعل «رقمَ الصفحة»
    // ذا معنى. والورقُ المتّصلُ (الحراريّ) لا قاعَ له فتذييلُه يتدفّق.
    TemplateBand? pinnedHeader;
    TemplateBand? pinnedFooter;
    for (final b in bands) {
      if (!b.repeatEachPage) continue;
      if (b.id == BandId.header) pinnedHeader = b;
      if (b.id == BandId.footer && !paper.isContinuous) pinnedFooter = b;
    }

    final flowBands = bands
        .where((b) => b != pinnedHeader && b != pinnedFooter)
        .toList(growable: false);

    final flowTop = paper.margins.top + (pinnedHeader?.heightMm ?? 0);
    // الورقُ المتّصلُ بلا قاع — نستعمل حدّاً عالياً جدّاً فلا ينكسر أبداً.
    final flowBottom = paper.isContinuous
        ? double.infinity
        : paper.heightMm! - paper.margins.bottom - (pinnedFooter?.heightMm ?? 0);

    final startX = paper.margins.left;
    final contentWidth = paper.contentWidthMm;

    final drafts = <_PageDraft>[_PageDraft()];
    var cursorY = flowTop;

    void breakPage() {
      drafts.add(_PageDraft());
      cursorY = flowTop;
    }

    for (final band in flowBands) {
      if (band.growsWithData && document.table != null) {
        cursorY = _layoutDetails(
          band: band,
          table: document.table!,
          rows: rows,
          drafts: drafts,
          startX: startX,
          contentWidth: contentWidth,
          flowTop: flowTop,
          flowBottom: flowBottom,
          cursorY: cursorY,
          onBreak: breakPage,
        );
        continue;
      }

      // نطاقٌ عاديّ — لا يُقطع في منتصفه. لا يسع الصفحةَ ⇒ صفحةٌ جديدة.
      if (cursorY + band.heightMm > flowBottom && drafts.last.contentBottomMm > flowTop) {
        breakPage();
      }
      drafts.last.elements.addAll(_placeBand(band, cursorY, startX, values));
      cursorY += band.heightMm;
      drafts.last.contentBottomMm = cursorY;
    }

    // ── الختم ─────────────────────────────────────────────────────────────
    final pageCount = drafts.length;
    final pages = <PositionedPage>[];

    for (var i = 0; i < pageCount; i++) {
      final draft = drafts[i];
      final elements = <PositionedElement>[];

      if (pinnedHeader != null) {
        elements.addAll(
          _placeBand(pinnedHeader, paper.margins.top, startX, values),
        );
      }
      elements.addAll(draft.elements);
      if (pinnedFooter != null) {
        final footerTop =
            paper.heightMm! - paper.margins.bottom - pinnedFooter.heightMm;
        elements.addAll(_placeBand(pinnedFooter, footerTop, startX, values));
      }

      pages.add(
        PositionedPage(
          pageNumber: i + 1,
          pageCount: pageCount,
          widthMm: paper.widthMm,
          heightMm:
              paper.heightMm ?? draft.contentBottomMm + paper.margins.bottom,
          elements: List.unmodifiable(elements),
          tables: List.unmodifiable(draft.tables),
        ),
      );
    }

    return List.unmodifiable(pages);
  }

  /// **مسارُ الانبعاث الوحيد.** كلُّ عنصرٍ يخرج من هنا — فقاعدةُ الإظهار
  /// تُطبَّق مرّةً واحدةً ولا يوجد مسارٌ ثانٍ ينساها.
  static List<PositionedElement> _placeBand(
    TemplateBand band,
    double bandTop,
    double startX,
    Map<String, String> values,
  ) =>
      [
        for (final el in band.elements)
          if (_shows(el, values))
            PositionedElement(
              id: el.id,
              contentKey: el.contentKey,
              band: band.id,
              xMm: startX + el.xMm,
              yMm: bandTop + el.yMm,
              wMm: el.wMm,
              hMm: el.hMm,
              text: values[el.contentKey] ?? '',
              labelAr: el.labelAr,
              labelEn: el.labelEn,
              fontSize: el.fontSize,
              bold: el.bold,
              align: el.align,
              colorHex: el.colorHex,
            ),
      ];

  /// هل يُطبع هذا العنصر؟ ثلاثةُ حواجزَ بالترتيب.
  static bool _shows(TemplateElement el, Map<String, String> values) {
    // ١ · أطفأه المستخدمُ في المحرّر.
    if (!el.visible) return false;

    // ٢ · شرطُ الإظهار. والغموضُ يُظهِر — انظر `condition_evaluator`.
    if (!evaluateCondition(el.condition, values)) return false;

    // ٣ · التسميةُ المعلَّقة: حقلٌ بقيمةٍ فارغةٍ لا يُطبع ولو كانت له تسمية.
    //     «الكاشير:» بلا اسمٍ يجعل القارئَ يظنّ البيانَ ناقصاً لا الحقلَ
    //     غيرَ مفعَّل — وهو عطبٌ مرصودٌ على ورقٍ حقيقيّ (2026-08-11).
    //
    //     والنصُّ الثابتُ (`contentKey` فارغ) يُستثنى: هو نفسُه القيمة،
    //     وخلطُه بالحقلِ الفارغ يمحو تذييلَ كلِّ إيصال.
    if (el.contentKey.isEmpty) return true;
    return (values[el.contentKey] ?? '').isNotEmpty;
  }

  /// يوزّع صفوفَ الجدول على الصفحات ويُرجع موضعَ المؤشِّر بعدَ آخر صفّ.
  ///
  /// ارتفاعُ النطاق المعلَنُ يعمل **حدّاً أدنى** لا مقاساً ثابتاً: جدولٌ
  /// أقصرُ منه لا يُصعِّد ما بعده فوقَ حدود التصميم، وأطولُ منه يدفعه.
  static double _layoutDetails({
    required TemplateBand band,
    required TableSpec table,
    required List<List<String>> rows,
    required List<_PageDraft> drafts,
    required double startX,
    required double contentWidth,
    required double flowTop,
    required double flowBottom,
    required double cursorY,
    required void Function() onBreak,
  }) {
    final columns = table.visibleColumns;
    final widths = _columnWidths(columns, contentWidth);

    // العناوينُ الثنائيّةُ تُطفأ على الورق الضيّق مهما طلب القالب: ٥٢مم لا
    // تسع سطرين لكلِّ عمود، والسطرُ الثاني يدهس الصفَّ الأوّل من البيانات.
    // العتبةُ تفصل الحراريَّ (٥٨/٨٠) عن A5 (١٤٨) وA4 (٢١٠).
    final bilingual = table.bilingualHeaders && contentWidth >= narrowPaperMm;
    final headerHeight = bilingual ? table.rowHeightMm * 1.6 : table.rowHeightMm;

    final detailsTop = cursorY;
    var y = cursorY;
    var index = 0;
    var isFirstSlice = true;

    while (index < rows.length || isFirstSlice) {
      // رأسُ الجدول: على الشريحة الأولى دائماً، وعلى ما بعدها بـrepeatHeader.
      final wantsHeader = isFirstSlice || table.repeatHeader;
      final headerOnThisSlice = wantsHeader ? headerHeight : 0.0;

      // لا يسع الرأسَ وصفّاً واحداً على الأقلّ ⇒ صفحةٌ جديدة.
      final needed = headerOnThisSlice + table.rowHeightMm;
      if (index < rows.length && y + needed > flowBottom && y > flowTop) {
        onBreak();
        y = flowTop;
        continue;
      }

      final sliceTop = y;
      final headerCells = wantsHeader
          ? _cells(
              columns,
              widths,
              startX,
              [for (final c in columns) c.labelAr],
              subTexts:
                  bilingual ? [for (final c in columns) c.labelEn] : null,
            )
          : const <PositionedCell>[];
      y += headerOnThisSlice;

      final sliceRows = <PositionedRow>[];
      while (index < rows.length) {
        if (y + table.rowHeightMm > flowBottom) break;
        sliceRows.add(
          PositionedRow(
            sourceIndex: index,
            yMm: y,
            heightMm: table.rowHeightMm,
            cells: _cells(columns, widths, startX, rows[index]),
          ),
        );
        y += table.rowHeightMm;
        index++;
      }

      drafts.last.tables.add(
        PositionedTable(
          xMm: startX,
          yMm: sliceTop,
          wMm: contentWidth,
          headerCells: headerCells,
          headerHeightMm: headerOnThisSlice,
          bilingualHeaders: bilingual,
          rows: List.unmodifiable(sliceRows),
        ),
      );
      drafts.last.contentBottomMm = y;

      isFirstSlice = false;
      if (index >= rows.length) break;

      // لم يُستهلك صفٌّ واحدٌ في هذه الجولة ⇒ الصفحةُ ضيّقةٌ عن الصفّ أصلاً.
      // نكسر لتفادي دورةٍ لا تنتهي.
      if (sliceRows.isEmpty) {
        onBreak();
        y = flowTop;
      }
    }

    // الحدُّ الأدنى المعلَن — يُطبَّق على الشريحة الأخيرة وحدَها.
    final minBottom = detailsTop + band.heightMm;
    final bottom = drafts.length == 1 && y < minBottom ? minBottom : y;
    drafts.last.contentBottomMm = bottom;
    return bottom;
  }

  /// أنصبةُ الأعمدة من العرض المتاح — نسبيّةٌ بـ`flex` لا مليمترات، فالجدولُ
  /// يعيد توزيعَ نفسه حين يتغيّر عرضُ الورق.
  static List<double> _columnWidths(
    List<TableColumn> columns,
    double contentWidth,
  ) {
    final totalFlex = columns.fold<double>(0, (s, c) => s + c.flex);
    if (totalFlex <= 0) {
      final even = columns.isEmpty ? 0.0 : contentWidth / columns.length;
      return List.filled(columns.length, even);
    }
    return [for (final c in columns) contentWidth * (c.flex / totalFlex)];
  }

  static List<PositionedCell> _cells(
    List<TableColumn> columns,
    List<double> widths,
    double startX,
    List<String> texts, {
    List<String>? subTexts,
  }) {
    final cells = <PositionedCell>[];
    var x = startX;
    for (var i = 0; i < columns.length; i++) {
      cells.add(
        PositionedCell(
          columnKey: columns[i].key,
          xMm: x,
          wMm: widths[i],
          align: columns[i].align,
          text: i < texts.length ? texts[i] : '',
          subText: (subTexts != null && i < subTexts.length) ? subTexts[i] : '',
        ),
      );
      x += widths[i];
    }
    return List.unmodifiable(cells);
  }
}
