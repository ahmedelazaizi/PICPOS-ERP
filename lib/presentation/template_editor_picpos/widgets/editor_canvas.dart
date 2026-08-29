// كانفاسُ المحرّر — النطاقاتُ تتراصّ، والعناصرُ بإحداثيّاتٍ داخلَها.
//
// ── ولا منطقَ تخطيطٍ في هذا الملفّ ───────────────────────────────────────
// «إن اضطررتَ لكتابة منطق تخطيطٍ في ملفّ الواجهة فالمحرّكُ ناقص»
// (‏`EDITOR-ARCHITECTURE.md` §٩). فما هنا **عرضٌ مباشرٌ للنموذج**: ارتفاعُ
// النطاق كما هو، وموضعُ العنصر كما هو، مضروبةً في مقياسٍ واحد. ولا يُحسب
// انقسامُ صفحةٍ ولا تمدّدُ نطاق — ذاك عملُ `LayoutEngine`، ويظهر أثرُه في
// وضع المعاينة الذي يستدعيه فعلاً.
//
// ── والاتّجاه ────────────────────────────────────────────────────────────
// `xMm` تُقاس من **حافّة البداية** (اليمين في العربيّة)، وهو ما يفعله
// `planPage` قبل أن يقلبها للراسم. فالوضعُ هنا بـ`PositionedDirectional`
// لا `Positioned`: الأخيرةُ تقيس من اليسار دائماً، فيقفز كلُّ عنصرٍ عند
// أوّل حفظ.

import 'package:flutter/material.dart';

import '../../../domain/printing/template_document.dart';
import '../../picpos_shell/picpos_surface.dart';

/// بكسلاتٌ لكلِّ مليمترٍ عند تكبيرٍ ١٠٠٪.
const double editorPixelsPerMm = 3.2;

/// ألوانُ النطاقات — نفسُ ترميز التصميم.
const _bandTints = <BandId, Color>{
  BandId.header: Color(0xFF0250D3),
  BandId.info: Color(0xFF8B5CF6),
  BandId.party: Color(0xFF4A80E8),
  BandId.details: Color(0xFFF59E0B),
  BandId.totals: Color(0xFF22C55E),
  BandId.footer: Color(0xFF6B7280),
};

const _bandLabels = <BandId, String>{
  BandId.header: 'الرأس',
  BandId.info: 'البيانات',
  BandId.party: 'الطرف',
  BandId.details: 'التفاصيل',
  BandId.totals: 'المجاميع',
  BandId.footer: 'التذييل',
};

Color bandTint(BandId id) => _bandTints[id] ?? const Color(0xFF6B7280);
String bandLabel(BandId id) => _bandLabels[id] ?? id.name;

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.document,
    required this.values,
    required this.rows,
    required this.zoom,
    required this.showGrid,
    required this.selectedBand,
    required this.selectedElement,
    required this.onSelectBand,
    required this.onSelectElement,
    required this.onSelectTable,
    required this.onMove,
    required this.onResize,
  });

  final TemplateDocument document;
  final Map<String, String> values;

  /// صفوفُ العيّنة كما يبنيها المحرّكُ — لا بياناتٌ مكتوبةٌ بجانب الواجهة.
  ///
  /// جدولٌ برأسٍ بلا صفوفٍ لا يُظهر عرضَ الأعمدة ولا محاذاتَها ولا كم
  /// يشغل من الورقة — وهو ما كان يجعل نطاقَ التفاصيل يبدو شريطاً رفيعاً.
  final List<List<String>> rows;

  final double zoom;
  final bool showGrid;
  final BandId? selectedBand;
  final String? selectedElement;

  final ValueChanged<BandId> onSelectBand;
  final void Function(BandId, String) onSelectElement;
  final VoidCallback onSelectTable;

  /// (النطاق، المعرّف، x، y) — بالمليمتر داخلَ النطاق.
  final void Function(BandId, String, double, double) onMove;
  final void Function(BandId, String, double, double) onResize;

  @override
  Widget build(BuildContext context) {
    final k = editorPixelsPerMm * zoom;
    final paperWidth = document.paper.widthMm * k;
    final margins = document.paper.margins;

    // ⚠️ **تمريرٌ في الاتّجاهين**: الورقةُ عرضُها ثابتٌ بالمليمتر ولا تضيق مع
    //    الشاشة. وبلا التمرير الأفقيِّ يفيض الصفُّ ٨٨ بكسلاً عند عرض ١٤٠٠ —
    //    وهو ما لا يظهر في `analyze` إطلاقاً، ومسكه اختبارُ التركيب.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // مسطرةُ النطاقات — تُسمّي كلَّ شريحةٍ وتفتح خصائصَها.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final band in document.bands)
                _BandGutter(
                  band: band,
                  heightPx: band.heightMm * k,
                  selected: band.id == selectedBand,
                  onTap: () => onSelectBand(band.id),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: paperWidth,
            // ⚠️ **الورقةُ صفحةٌ كاملةٌ لا مجموعَ نطاقاتها**: بلا هذا القيد
            //    ينتهي البياضُ عند آخر نطاقٍ فتبدو الورقةُ مقصوصة — قالبٌ
            //    نطاقاتُه ١٨٢مم كان يُرسم على ورقةِ A4 طولُها ١٨٢ لا ٢٩٧.
            //    و`minHeight` لا `height`: الفائضُ يظهر ولا يُقصّ، فيرى
            //    المستخدمُ أنّ تخطيطَه تجاوز الصفحة بدل أن يختفي صامتاً.
            //    والورقُ المتّصلُ (`heightMm == null`) يبقى بطول محتواه.
            constraints: document.paper.heightMm == null
                ? null
                : BoxConstraints(minHeight: document.paper.heightMm! * k),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Color(0x3D0B1220),
                    blurRadius: 38,
                    offset: Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final band in document.bands)
                  _BandSurface(
                    band: band,
                    k: k,
                    contentLeftPx: margins.left * k,
                    contentWidthPx: document.paper.contentWidthMm * k,
                    values: values,
                    rows: rows,
                    table: document.table,
                    showGrid: showGrid,
                    selected: band.id == selectedBand,
                    selectedElement: selectedElement,
                    onTapBand: () => onSelectBand(band.id),
                    onTapTable: onSelectTable,
                    onSelectElement: (id) => onSelectElement(band.id, id),
                    onMove: (id, x, y) => onMove(band.id, id, x, y),
                    onResize: (id, w, h) => onResize(band.id, id, w, h),
                  ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _BandGutter extends StatelessWidget {
  const _BandGutter({
    required this.band,
    required this.heightPx,
    required this.selected,
    required this.onTap,
  });

  final TemplateBand band;
  final double heightPx;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = bandTint(band.id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: heightPx,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: selected ? 0.22 : 0.08),
          border: BorderDirectional(
            end: BorderSide(color: tint, width: 2.5),
          ),
        ),
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            bandLabel(band.id),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w800, color: tint),
          ),
        ),
      ),
    );
  }
}

class _BandSurface extends StatelessWidget {
  const _BandSurface({
    required this.band,
    required this.k,
    required this.contentLeftPx,
    required this.contentWidthPx,
    required this.values,
    required this.rows,
    required this.table,
    required this.showGrid,
    required this.selected,
    required this.selectedElement,
    required this.onTapBand,
    required this.onTapTable,
    required this.onSelectElement,
    required this.onMove,
    required this.onResize,
  });

  final TemplateBand band;
  final double k;
  final double contentLeftPx;
  final double contentWidthPx;
  final Map<String, String> values;
  final List<List<String>> rows;
  final TableSpec? table;
  final bool showGrid;
  final bool selected;
  final String? selectedElement;
  final VoidCallback onTapBand;
  final VoidCallback onTapTable;
  final ValueChanged<String> onSelectElement;
  final void Function(String, double, double) onMove;
  final void Function(String, double, double) onResize;

  @override
  Widget build(BuildContext context) {
    final tint = bandTint(band.id);

    return GestureDetector(
      onTap: onTapBand,
      child: Container(
        height: band.heightMm * k,
        decoration: BoxDecoration(
          color: selected ? tint.withValues(alpha: 0.05) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: tint.withValues(alpha: 0.35),
              width: selected ? 1.4 : 0.8,
            ),
          ),
        ),
        // النطاقُ المخفيُّ يبهت ولا يختفي: إخفاؤه في المحرّر يجعل المستخدمَ
        // يظنّ عناصرَه ضاعت.
        foregroundDecoration: band.visible
            ? null
            : const BoxDecoration(color: Color(0x66FFFFFF)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (showGrid)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GridPainter(stepPx: 2 * k),
                  ),
                ),
              ),
            if (band.growsWithData && table != null)
              PositionedDirectional(
                start: contentLeftPx,
                top: 2,
                width: contentWidthPx,
                child: GestureDetector(
                  onTap: onTapTable,
                  child: _TablePreview(
                      table: table!, rows: rows, widthPx: contentWidthPx),
                ),
              ),
            for (final el in band.elements)
              PositionedDirectional(
                start: contentLeftPx + el.xMm * k,
                top: el.yMm * k,
                width: el.wMm * k,
                height: el.hMm * k,
                child: _ElementBox(
                  element: el,
                  k: k,
                  text: _textOf(el),
                  selected: el.id == selectedElement,
                  onTap: () => onSelectElement(el.id),
                  onMove: (dxMm, dyMm) => onMove(
                      el.id, el.xMm + dxMm, el.yMm + dyMm),
                  onResize: (dwMm, dhMm) => onResize(
                      el.id, el.wMm + dwMm, el.hMm + dhMm),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ما يُعرض في الصندوق — القيمةُ المحلولةُ، وإلّا التسميةُ، وإلّا المفتاح.
  ///
  /// ⚠️ ولا يُترك فارغاً: صندوقٌ بلا نصٍّ لا يُميَّز عن صندوقٍ آخر، والمحرّرُ
  /// يصير رقعةَ مستطيلاتٍ لا يُعرف أيُّها اسمُ الشركة.
  String _textOf(TemplateElement el) {
    final v = values[el.contentKey];
    if (v != null && v.isNotEmpty) return v;
    final label = el.labelAr;
    if (label != null && label.isNotEmpty) return label;
    return el.contentKey.isEmpty ? '—' : el.contentKey;
  }
}

class _ElementBox extends StatelessWidget {
  const _ElementBox({
    required this.element,
    required this.k,
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onMove,
    required this.onResize,
  });

  final TemplateElement element;
  final double k;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  /// الإزاحةُ **بالمليمتر** — التحويلُ من البكسل يقع هنا مرّةً.
  final void Function(double, double) onMove;
  final void Function(double, double) onResize;

  @override
  Widget build(BuildContext context) {
    final brand = context.picposBrandInk;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onTap(),
      onPanUpdate: (d) {
        // في RTL يزيد `start` كلّما تحرّك المؤشّرُ يساراً على الشاشة.
        final dir = Directionality.of(context);
        final dx = dir == TextDirection.rtl ? -d.delta.dx : d.delta.dx;
        onMove(dx / k, d.delta.dy / k);
      },
      child: Opacity(
        opacity: element.visible ? 1 : 0.35,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? brand.withValues(alpha: 0.10) : null,
            border: Border.all(
              color: selected
                  ? brand
                  : const Color(0xFF0B1220).withValues(alpha: 0.12),
              width: selected ? 1.6 : 0.8,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Align(
                  alignment: switch (element.align) {
                    TextAlignSpec.start => AlignmentDirectional.centerStart,
                    TextAlignSpec.center => Alignment.center,
                    TextAlignSpec.end => AlignmentDirectional.centerEnd,
                  },
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // ‏١pt = ٠٫٣٥٢٨مم — نفسُ التحويل في ورقة المعاينة.
                      fontSize: element.fontSize * 0.3528 * k,
                      fontWeight:
                          element.bold ? FontWeight.w700 : FontWeight.w400,
                      color: const Color(0xFF0B1220),
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              if (element.condition != null &&
                  element.condition!.trim().isNotEmpty)
                const PositionedDirectional(
                  end: 1,
                  top: 1,
                  child: Icon(Icons.filter_alt,
                      size: 9, color: Color(0xFF8B5CF6)),
                ),
              if (selected)
                PositionedDirectional(
                  end: -5,
                  bottom: -5,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      final dir = Directionality.of(context);
                      final dw =
                          dir == TextDirection.rtl ? -d.delta.dx : d.delta.dx;
                      onResize(dw / k, d.delta.dy / k);
                    },
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: brand,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
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

/// معاينةُ الجدول في نطاق التفاصيل — رؤوسُ الأعمدة بعرضها النسبيّ.
///
/// وهي **رؤوسٌ لا صفوف**: عددُ الصفوف يقرّره التخطيطُ بالبيانات، وعرضُ عددٍ
/// ثابتٍ هنا يجعل المحرّرَ يَعِد بارتفاعٍ لا يقع.
class _TablePreview extends StatelessWidget {
  const _TablePreview({
    required this.table,
    required this.rows,
    required this.widthPx,
  });

  final TableSpec table;
  final List<List<String>> rows;
  final double widthPx;

  @override
  Widget build(BuildContext context) {
    final cols = table.visibleColumns;
    if (cols.isEmpty) return const SizedBox.shrink();

    // صفوفُ العيّنةِ المعروضةُ — [kDesignTableRows] كما يحجز النطاقُ تماماً،
    // فلا يعد المحرّرُ مساحةً لا يملؤها ولا يملأ مساحةً لم يحجزها.
    final shown = rows.take(kDesignTableRows).toList(growable: false);

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF0B1220), width: 1.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF0B1220)),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (final c in cols)
                  Expanded(
                    flex: (c.flex * 10).round().clamp(1, 1000),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.labelAr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: _align(c.align),
                            style: TextStyle(
                                fontSize: table.headerFontSize * 0.8,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0B1220)),
                          ),
                          if (table.bilingualHeaders && c.labelEn.isNotEmpty)
                            Text(
                              c.labelEn,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: _align(c.align),
                              style: TextStyle(
                                  fontSize: table.headerFontSize * 0.62,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF8B95A5)),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < shown.length; i++)
            Container(
              color: i.isOdd ? const Color(0xFFFAFBFD) : null,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  for (var j = 0; j < cols.length; j++)
                    Expanded(
                      flex: (cols[j].flex * 10).round().clamp(1, 1000),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          j < shown[i].length ? shown[i][j] : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: _align(cols[j].align),
                          style: TextStyle(
                              fontSize: table.fontSize * 0.8,
                              color: const Color(0xFF0B1220)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  TextAlign _align(ColumnAlign a) => switch (a) {
        ColumnAlign.start => TextAlign.start,
        ColumnAlign.center => TextAlign.center,
        ColumnAlign.end => TextAlign.end,
      };
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.stepPx});

  final double stepPx;

  @override
  void paint(Canvas canvas, Size size) {
    if (stepPx < 3) return;
    final paint = Paint()..color = const Color(0xFFC9D2E0);
    for (var x = 0.0; x < size.width; x += stepPx) {
      for (var y = 0.0; y < size.height; y += stepPx) {
        canvas.drawCircle(Offset(x, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.stepPx != stepPx;
}
