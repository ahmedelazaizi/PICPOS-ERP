// عمليّاتُ التحرير — **خالصةٌ على [TemplateDocument] نفسِه**.
//
// ── لماذا لا نموذجَ تحريرٍ ثانٍ ───────────────────────────────────────────
// المغري أن يُبنى `EditableTemplate` بحقولٍ متغيّرةٍ ثمّ يُحوَّل إلى
// [TemplateDocument] عند العرض. وهذا يُنتج **مصدرَي حقيقةٍ للتخطيط**: يُحرّك
// المستخدمُ عنصراً في النموذج الأوّل، وتُحسب الورقةُ من الثاني، فينحرفان عند
// أوّل حقلٍ يُنسى في التحويل. وهو عينُ العطب الذي بُني المحرّكُ كلُّه لمنعه
// (‏`EDITOR-ARCHITECTURE.md` §٢، §٩).
//
// فالمحرّرُ يحمل [TemplateDocument] **واحداً**، وكلُّ تعديلٍ دالّةٌ خالصةٌ
// تُرجع مستنداً جديداً. والكانفاسُ يرسمه بـ`paginate` ⇐ `planPage` — نفسِ ما
// يذهب إلى الورق.
//
// نقيّ: لا `package:flutter` ولا `package:pdf` ولا قاعدةَ بيانات.
library;

import 'template_document.dart';

/// خطوةُ المحاذاة للشبكة بالمليمتر — عقدُ الأزرار: «السحبُ يقرّب لأقرب ٢مم».
const double gridStepMm = 2;

/// أصغرُ عنصرٍ يبقى قابلاً للإمساك والقراءة — عقدُ الأزرار: ٨×٤.
const double minElementWidthMm = 8;
const double minElementHeightMm = 4;

/// حدَّا حجم الخطّ في لوحة الخصائص.
const double minFontSize = 4;
const double maxFontSize = 48;

/// حدَّا عرض العمود النسبيّ.
const double minColumnFlex = 0.4;
const double maxColumnFlex = 6;

double _snap(double v, bool snap) =>
    snap ? (v / gridStepMm).round() * gridStepMm : (v * 10).round() / 10;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// يستبدل نطاقاً بمستنده — أساسُ كلِّ تعديلٍ أدناه.
TemplateDocument _withBand(TemplateDocument doc, TemplateBand next) =>
    TemplateDocument(
      paper: doc.paper,
      bands: [
        for (final b in doc.bands) b.id == next.id ? next : b,
      ],
      table: doc.table,
    );

TemplateDocument _withElement(
  TemplateDocument doc,
  BandId bandId,
  String elementId,
  TemplateElement Function(TemplateElement) edit,
) {
  for (final band in doc.bands) {
    if (band.id != bandId) continue;
    return _withBand(
      doc,
      band.copyWith(elements: [
        for (final e in band.elements) e.id == elementId ? edit(e) : e,
      ]),
    );
  }
  return doc;
}

/// ينقل عنصراً داخلَ نطاقه — **ولا يخرج منه**.
///
/// ⚠️ القصُّ عند حدود النطاق شرطُ صحّةٍ لا تجميل: عنصرٌ خارجَ نطاقه يُرسم
/// فوق النطاق التالي أو خارجَ الورقة، وقد قيس أنّ الراسمَ يقصّه صامتاً.
/// و`x` تُقاس من حافّة البداية داخلَ عرض المحتوى بعد الهوامش.
TemplateDocument moveElement(
  TemplateDocument doc, {
  required BandId bandId,
  required String elementId,
  required double xMm,
  required double yMm,
  bool snap = true,
}) {
  final band = doc.bands.where((b) => b.id == bandId).firstOrNull;
  if (band == null) return doc;

  return _withElement(doc, bandId, elementId, (e) {
    final maxX = (doc.paper.contentWidthMm - e.wMm).clamp(0.0, double.infinity);
    final maxY = (band.heightMm - e.hMm).clamp(0.0, double.infinity);
    return e.copyWith(
      xMm: _clamp(_snap(xMm, snap), 0, maxX),
      yMm: _clamp(_snap(yMm, snap), 0, maxY),
    );
  });
}

/// يغيّر حجمَ عنصرٍ بحدٍّ أدنى، ولا يتجاوز عرضَ المحتوى ولا ارتفاعَ نطاقه.
TemplateDocument resizeElement(
  TemplateDocument doc, {
  required BandId bandId,
  required String elementId,
  required double wMm,
  required double hMm,
  bool snap = true,
}) {
  final band = doc.bands.where((b) => b.id == bandId).firstOrNull;
  if (band == null) return doc;

  return _withElement(doc, bandId, elementId, (e) {
    final maxW = (doc.paper.contentWidthMm - e.xMm)
        .clamp(minElementWidthMm, double.infinity);
    final maxH =
        (band.heightMm - e.yMm).clamp(minElementHeightMm, double.infinity);
    return e.copyWith(
      wMm: _clamp(_snap(wMm, snap), minElementWidthMm, maxW),
      hMm: _clamp(_snap(hMm, snap), minElementHeightMm, maxH),
    );
  });
}

/// يعدّل خاصّةً واحدةً من خصائص العنصر.
///
/// `condition` تُمرَّر فارغةً لإزالة الشرط — و`null` تعني «لا تلمسه».
TemplateDocument editElement(
  TemplateDocument doc, {
  required BandId bandId,
  required String elementId,
  String? labelAr,
  String? labelEn,
  double? fontSize,
  bool? bold,
  bool? visible,
  TextAlignSpec? align,
  String? condition,
}) =>
    _withElement(
      doc,
      bandId,
      elementId,
      (e) => e.copyWith(
        labelAr: labelAr,
        labelEn: labelEn,
        fontSize: fontSize == null
            ? null
            : _clamp(fontSize, minFontSize, maxFontSize),
        bold: bold,
        visible: visible,
        align: align,
        condition: condition,
      ),
    );

/// يحذف عنصراً من نطاقه.
TemplateDocument removeElement(
  TemplateDocument doc, {
  required BandId bandId,
  required String elementId,
}) {
  for (final band in doc.bands) {
    if (band.id != bandId) continue;
    return _withBand(
      doc,
      band.copyWith(elements: [
        for (final e in band.elements)
          if (e.id != elementId) e,
      ]),
    );
  }
  return doc;
}

/// يضيف عنصراً جديداً في نطاقٍ — أسفلَ آخرِ عنصرٍ فيه كي لا يقع فوقه.
///
/// [id] يجب أن يكون فريداً في المستند كلِّه. والمحرّرُ يولّده بسابقةٍ لا
/// تصطدم بمعرِّفات الصفوف (‏`new:` + عدّاد) — فالصفُّ لم يُكتب بعد.
TemplateDocument addElement(
  TemplateDocument doc, {
  required BandId bandId,
  required String id,
  required String contentKey,
  ElementKind kind = ElementKind.text,
  String? labelAr,
  double wMm = 60,
  double hMm = 6,
}) {
  for (final band in doc.bands) {
    if (band.id != bandId) continue;

    var top = 0.0;
    for (final e in band.elements) {
      final bottom = e.yMm + e.hMm;
      if (bottom > top) top = bottom;
    }
    // لا يخرج عن النطاق: ما لم يسعه الارتفاعُ يُوضع في أعلاه ويراه المستخدم.
    if (top + hMm > band.heightMm) top = 0;

    return _withBand(
      doc,
      band.copyWith(elements: [
        ...band.elements,
        TemplateElement(
          id: id,
          contentKey: contentKey,
          xMm: 0,
          yMm: top,
          wMm: wMm.clamp(minElementWidthMm, doc.paper.contentWidthMm),
          hMm: hMm.clamp(minElementHeightMm, band.heightMm),
          labelAr: labelAr,
          kind: kind,
        ),
      ]),
    );
  }
  return doc;
}

/// يبدّل أعلامَ النطاق.
///
/// ⚠️ `growsWithData` **مقفلٌ على نطاق التفاصيل**: إيقافُه يكسر كلَّ قالبٍ
/// فيه جدول (عقدُ الأزرار — «الضغطُ يشرح لماذا»)، فلا يُمرَّر هنا أصلاً.
TemplateDocument editBand(
  TemplateDocument doc, {
  required BandId bandId,
  double? heightMm,
  bool? repeatEachPage,
  bool? autoHeight,
  bool? visible,
}) {
  for (final band in doc.bands) {
    if (band.id != bandId) continue;
    return _withBand(
      doc,
      band.copyWith(
        heightMm: heightMm,
        repeatEachPage: repeatEachPage,
        autoHeight: autoHeight,
        visible: visible,
      ),
    );
  }
  return doc;
}

// ═══════════════════════════════════════════════════════════════════════════
// الجدول
// ═══════════════════════════════════════════════════════════════════════════

TemplateDocument _withTable(TemplateDocument doc, TableSpec table) =>
    TemplateDocument(paper: doc.paper, bands: doc.bands, table: table);

/// يبدّل ظهورَ عمود.
///
/// ⚠️ **ولا يُطفَأ آخرُ عمودٍ ظاهر**: جدولٌ بلا أعمدةٍ يجعل `buildTable`
/// تُرجع `null`، فيختفي الجدولُ من الورقة بلا رسالةٍ ويظنّ المستخدمُ أنّ
/// القالبَ انكسر.
TemplateDocument toggleColumn(TemplateDocument doc, String key) {
  final table = doc.table;
  if (table == null) return doc;

  final target = table.columns.where((c) => c.key == key).firstOrNull;
  if (target == null) return doc;
  if (target.visible && table.visibleColumns.length <= 1) return doc;

  return _withTable(
    doc,
    table.copyWith(columns: [
      for (final c in table.columns)
        c.key == key ? c.copyWith(visible: !c.visible) : c,
    ]),
  );
}

/// ينقل عموداً خطوةً في الترتيب — الترتيبُ هو ما يظهر على الورق.
TemplateDocument moveColumn(TemplateDocument doc, String key, int delta) {
  final table = doc.table;
  if (table == null) return doc;

  final cols = [...table.columns];
  final i = cols.indexWhere((c) => c.key == key);
  if (i < 0) return doc;
  final j = i + delta;
  if (j < 0 || j >= cols.length) return doc;

  final moved = cols.removeAt(i);
  cols.insert(j, moved);
  return _withTable(doc, table.copyWith(columns: cols));
}

/// يعدّل خاصّةً من خصائص عمود.
TemplateDocument editColumn(
  TemplateDocument doc,
  String key, {
  String? labelAr,
  String? labelEn,
  double? flex,
  int? decimals,
  ColumnAlign? align,
  bool? wrap,
}) {
  final table = doc.table;
  if (table == null) return doc;

  return _withTable(
    doc,
    table.copyWith(columns: [
      for (final c in table.columns)
        if (c.key == key)
          c.copyWith(
            labelAr: labelAr,
            labelEn: labelEn,
            flex: flex == null
                ? null
                : _clamp(flex, minColumnFlex, maxColumnFlex),
            decimals: decimals?.clamp(0, 4),
            align: align,
            wrap: wrap,
          )
        else
          c,
    ]),
  );
}

/// يعدّل إعداداتِ الجدول العامّة.
TemplateDocument editTable(
  TemplateDocument doc, {
  double? fontSize,
  double? headerFontSize,
  bool? bilingualHeaders,
  bool? repeatHeader,
  bool? keepRowTogether,
}) {
  final table = doc.table;
  if (table == null) return doc;
  return _withTable(
    doc,
    table.copyWith(
      fontSize: fontSize == null
          ? null
          : _clamp(fontSize, minFontSize, maxFontSize),
      headerFontSize: headerFontSize == null
          ? null
          : _clamp(headerFontSize, minFontSize, maxFontSize),
      bilingualHeaders: bilingualHeaders,
      repeatHeader: repeatHeader,
      keepRowTogether: keepRowTogether,
    ),
  );
}

/// يبدّل الورقَ — ويُعيد قصَّ كلِّ عنصرٍ صار خارجَ العرض الجديد.
///
/// ⚠️ **والقصُّ هنا لا يُؤجَّل**: بلا هذا يبقى العنصرُ بإحداثيٍّ يتجاوز الورقةَ
/// حتى يُطبع فيُقصّ صامتاً. ونقلُ قالبِ A4 إلى ٥٨مم يُخرج نصفَ عناصره.
TemplateDocument setPaper(
  TemplateDocument doc, {
  required double widthMm,
  double? heightMm,
}) {
  final paper = PaperSpec(
    widthMm: widthMm,
    heightMm: heightMm,
    margins: doc.paper.margins,
  );
  final contentWidth = paper.contentWidthMm;

  TemplateElement fit(TemplateElement e) {
    final w = e.wMm > contentWidth ? contentWidth : e.wMm;
    final maxX = (contentWidth - w).clamp(0.0, double.infinity);
    return e.copyWith(wMm: w, xMm: e.xMm > maxX ? maxX : e.xMm);
  }

  return TemplateDocument(
    paper: paper,
    bands: [
      for (final band in doc.bands)
        band.copyWith(elements: [for (final e in band.elements) fit(e)]),
    ],
    table: doc.table,
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
