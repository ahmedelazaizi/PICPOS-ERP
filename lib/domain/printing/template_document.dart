/// بنيةُ مستندِ الطباعة — **نطاقاتٌ بإحداثيّاتٍ داخليّة**.
///
/// ── قاعدةٌ صارمة ───────────────────────────────────────────────────────────
/// هذا الملفُّ **لا يستورد `package:pdf` ولا `package:flutter`**. وهذا ما يجعل
/// نفسَ البنية قابلةً للرسم على قماشين مختلفين (ورقٌ ومعاينة) وللاختبار بلا
/// واجهةٍ ولا قاعدةِ بيانات. حارسٌ بنيويٌّ يمنع عودةَ التبعيّة:
/// `test/structural/template_document_has_no_ui_deps_test.dart`.
///
/// ── لماذا نطاقاتٌ لا إحداثيّاتٌ مطلقةٌ على الورقة ─────────────────────────
/// المستندُ نطاقاتٌ تتراصّ رأسيّاً، وداخلَ كلِّ نطاقٍ العناصرُ بإحداثيّاتٍ
/// مطلقةٍ بالمليمتر من حافّة النطاق. نطاقُ `details` وحدَه يتمدّد بالبيانات
/// فيدفع ما بعده.
///
///   · الإحداثيّاتُ المطلقةُ على الورقة كلِّها تنكسر: جدولٌ بـ٣٠ صنفاً بدل
///     خمسةٍ يدهس المجاميع.
///   · والتدفّقُ الخالصُ يمنع حرّيةَ الموضع التي طلبها المالك.
///
/// النطاقُ يحلّ الاثنين: حرّيةٌ كاملةٌ داخلَه، وأمانٌ كاملٌ بينها. وهو نمطٌ
/// قياسيّ — Crystal Reports و JasperReports و RDLC كلُّها bands.
library;

/// النطاقاتُ الستّةُ بترتيبها الرأسيِّ على الورقة.
///
/// الترتيبُ هنا **هو** ترتيبُ الرصّ — `LayoutEngine` يعتمد على `index`.
enum BandId {
  header,
  info,
  party,
  details,
  totals,
  footer;

  /// `details` وحدَه يتمدّد بالبيانات. مقفلٌ في الواجهة: إيقافُه يكسر كلَّ
  /// قالبٍ فيه جدول.
  bool get isDetails => this == BandId.details;

  /// الرأسُ والتذييلُ وحدَهما يتكرّران على كلِّ صفحةٍ افتراضيّاً.
  bool get repeatsByDefault => this == BandId.header || this == BandId.footer;
}

enum TextAlignSpec { start, center, end }

enum ColumnAlign { start, center, end }

/// نوعُ الجدول — يحدّد أيَّ حمولةٍ يقرأ الرابطُ.
///
/// `items` بنودُ الفاتورة · `ledger` حركةُ كشف الحساب · `report` أعمدةٌ متغيّرة.
enum TableKind { items, ledger, report }

/// هوامشُ الورقة بالمليمتر.
class MarginsMm {
  final double top;
  final double right;
  final double bottom;
  final double left;

  const MarginsMm({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  const MarginsMm.all(double v)
      : top = v,
        right = v,
        bottom = v,
        left = v;

  double get horizontal => left + right;
  double get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is MarginsMm &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// مواصفةُ الورق.
///
/// `heightMm == null` تعني ورقاً متّصلاً (الطابعةُ الحراريّة) — لا ترقيمَ
/// صفحاتٍ ولا قطع؛ الورقةُ تطول بقدر المحتوى.
class PaperSpec {
  final double widthMm;
  final double? heightMm;
  final MarginsMm margins;

  const PaperSpec({
    required this.widthMm,
    required this.heightMm,
    required this.margins,
  });

  /// ورقٌ متّصلٌ بلا ارتفاعٍ محدّد — الحراريّ.
  const PaperSpec.continuous({
    required this.widthMm,
    required this.margins,
  }) : heightMm = null;

  bool get isContinuous => heightMm == null;

  /// العرضُ الصالحُ للمحتوى بعد الهوامش.
  double get contentWidthMm => widthMm - margins.horizontal;

  /// الارتفاعُ الصالحُ للمحتوى، أو `null` للورق المتّصل.
  double? get contentHeightMm =>
      heightMm == null ? null : heightMm! - margins.vertical;
}

/// عنصرٌ واحدٌ داخلَ نطاق — بإحداثيّاتٍ **من حافّة النطاق** بالمليمتر.
class TemplateElement {
  final String id;

  /// مفتاحُ المتغيّر — هو ما يطابقه المحرّرُ وما يحلّه المُحلِّل.
  /// فارغٌ يعني نصّاً ثابتاً محمولاً في [labelAr]/[labelEn].
  final String contentKey;

  final double xMm;
  final double yMm;
  final double wMm;
  final double hMm;

  final String? labelAr;
  final String? labelEn;

  final double fontSize;
  final bool bold;
  final bool visible;
  final TextAlignSpec align;
  final String? colorHex;

  /// `field op value` — فارغٌ يعني «يظهر دائماً».
  /// العنصرُ الذي لا يتحقّق شرطُه **لا يُطبع ولا يترك فراغاً**.
  final String? condition;

  /// شكلٌ على الورق لا حقلُ بيانات — فاصلٌ أو شعارٌ أو مربّعُ QR.
  ///
  /// ⚠️ **وهذا الوسمُ هو ما يُنجّيه من قاعدة «لا تسميةَ معلَّقة»**: تلك
  /// القاعدةُ تُسقط كلَّ عنصرٍ ذي مفتاحٍ بقيمةٍ فارغة، وهي صوابٌ لحقلِ
  /// بيانات — «الكاشير:» بلا اسمٍ يُوهم القارئَ أنّ البيانَ ناقص. لكنّ
  /// الفاصلَ **لا قيمةَ له أصلاً**، فكان يسقط معها.
  ///
  /// مقيسٌ قبل هذا الوسم: قالبُ الفاتورة الضريبيّة يضع ١٤ عنصراً من ٣٠
  /// على الورق — تسقط منه أربعةُ فواصلَ والشعارُ ومربّعُ QR. والنيّةُ
  /// كانت مكتوبةً في `_nonTextTypes` ولم يكن يحملها شيءٌ إلى المحرّك.
  final bool structural;

  const TemplateElement({
    required this.id,
    required this.contentKey,
    required this.xMm,
    required this.yMm,
    required this.wMm,
    required this.hMm,
    this.labelAr,
    this.labelEn,
    this.fontSize = 10,
    this.bold = false,
    this.visible = true,
    this.align = TextAlignSpec.start,
    this.colorHex,
    this.condition,
    this.structural = false,
  });

  TemplateElement copyWith({
    double? xMm,
    double? yMm,
    double? wMm,
    double? hMm,
    String? labelAr,
    String? labelEn,
    double? fontSize,
    bool? bold,
    bool? visible,
    TextAlignSpec? align,
    String? colorHex,
    String? condition,
  }) =>
      TemplateElement(
        id: id,
        contentKey: contentKey,
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        wMm: wMm ?? this.wMm,
        hMm: hMm ?? this.hMm,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        visible: visible ?? this.visible,
        align: align ?? this.align,
        colorHex: colorHex ?? this.colorHex,
        condition: condition ?? this.condition,
      );
}

/// عمودٌ في الجدول.
///
/// [labelAr]/[labelEn] هما ما يحلّ محلَّ عناوينِ الأعمدة **الحرفيّة** المكتوبةِ
/// في الكود اليوم. وبدونهما لا تعمل ثنائيّةُ اللغة في رؤوس الجدول أصلاً.
class TableColumn {
  final String key;
  final String labelAr;
  final String labelEn;

  /// نسبيٌّ لا مليمترات — فالعمودُ يتوزّع مع تغيّر عرض الورق.
  final double flex;

  final int decimals;
  final ColumnAlign align;
  final bool visible;
  final bool wrap;

  /// `[price] * [quantity]` — فارغٌ يعني عموداً من البيانات لا محسوباً.
  final String? formula;

  const TableColumn({
    required this.key,
    required this.labelAr,
    this.labelEn = '',
    this.flex = 1,
    this.decimals = 2,
    this.align = ColumnAlign.center,
    this.visible = true,
    this.wrap = false,
    this.formula,
  });

  TableColumn copyWith({
    String? labelAr,
    String? labelEn,
    double? flex,
    int? decimals,
    ColumnAlign? align,
    bool? visible,
    bool? wrap,
    String? formula,
  }) =>
      TableColumn(
        key: key,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        flex: flex ?? this.flex,
        decimals: decimals ?? this.decimals,
        align: align ?? this.align,
        visible: visible ?? this.visible,
        wrap: wrap ?? this.wrap,
        formula: formula ?? this.formula,
      );
}

/// مواصفةُ الجدول الذي يسكن نطاقَ `details`.
class TableSpec {
  final TableKind kind;

  /// بالترتيب المعروض. المخفيّةُ تبقى في القائمة ليحفظها المحرّر.
  final List<TableColumn> columns;

  final double fontSize;
  final double headerFontSize;
  final double rowHeightMm;

  /// سطرٌ إنجليزيٌّ تحتَ العربيِّ في رأس الجدول.
  /// **يُطفأ تلقائيّاً على الحراريّ** — لا مكانَ لسطرين في ٥٨مم.
  final bool bilingualHeaders;

  /// رؤوسُ الأعمدة تُعاد على كلِّ صفحة.
  final bool repeatHeader;

  /// الصفُّ لا ينقسم بين صفحتين.
  final bool keepRowTogether;

  final int decimalPlaces;

  const TableSpec({
    this.kind = TableKind.items,
    required this.columns,
    this.fontSize = 9,
    this.headerFontSize = 9,
    this.rowHeightMm = 6,
    this.bilingualHeaders = false,
    this.repeatHeader = true,
    this.keepRowTogether = true,
    this.decimalPlaces = 2,
  });

  /// الأعمدةُ الظاهرةُ فقط — وهي وحدَها ما يُرسم ويقتسم العرض.
  List<TableColumn> get visibleColumns =>
      columns.where((c) => c.visible).toList(growable: false);

  TableSpec copyWith({
    List<TableColumn>? columns,
    double? fontSize,
    double? headerFontSize,
    double? rowHeightMm,
    bool? bilingualHeaders,
    bool? repeatHeader,
    bool? keepRowTogether,
    int? decimalPlaces,
  }) =>
      TableSpec(
        kind: kind,
        columns: columns ?? this.columns,
        fontSize: fontSize ?? this.fontSize,
        headerFontSize: headerFontSize ?? this.headerFontSize,
        rowHeightMm: rowHeightMm ?? this.rowHeightMm,
        bilingualHeaders: bilingualHeaders ?? this.bilingualHeaders,
        repeatHeader: repeatHeader ?? this.repeatHeader,
        keepRowTogether: keepRowTogether ?? this.keepRowTogether,
        decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      );
}

/// نطاقٌ واحد — شريحةٌ أفقيّةٌ من المستند تحمل عناصرَها.
class TemplateBand {
  final BandId id;

  /// الارتفاعُ المعلَن. مع [autoHeight] يتقلّص لأصغرِ ارتفاعٍ يسع عناصرَه.
  final double heightMm;

  final bool repeatEachPage;

  /// `details` وحدَه. إيقافُه يكسر كلَّ قالبٍ فيه جدول.
  final bool growsWithData;

  final bool autoHeight;
  final bool visible;

  final List<TemplateElement> elements;

  const TemplateBand({
    required this.id,
    required this.heightMm,
    this.repeatEachPage = false,
    this.growsWithData = false,
    this.autoHeight = false,
    this.visible = true,
    this.elements = const [],
  });

  TemplateBand copyWith({
    double? heightMm,
    bool? repeatEachPage,
    bool? growsWithData,
    bool? autoHeight,
    bool? visible,
    List<TemplateElement>? elements,
  }) =>
      TemplateBand(
        id: id,
        heightMm: heightMm ?? this.heightMm,
        repeatEachPage: repeatEachPage ?? this.repeatEachPage,
        growsWithData: growsWithData ?? this.growsWithData,
        autoHeight: autoHeight ?? this.autoHeight,
        visible: visible ?? this.visible,
        elements: elements ?? this.elements,
      );
}

/// المستندُ كامِلاً — ما يُخزَّن، ويُحرَّر، ويُخطَّط، ويُرسم.
class TemplateDocument {
  final PaperSpec paper;

  /// بالترتيب الرأسيّ.
  final List<TemplateBand> bands;

  /// `null` يعني قالباً بلا جدول (إيصالُ استلامٍ مثلاً).
  final TableSpec? table;

  const TemplateDocument({
    required this.paper,
    required this.bands,
    this.table,
  });

  /// النطاقاتُ الظاهرةُ مرتّبةً بترتيب [BandId] لا بترتيب الإدخال.
  ///
  /// الترتيبُ يُفرَض هنا لا يُفترَض: قالبٌ مستوردٌ قد تأتي نطاقاتُه بأيِّ
  /// ترتيب، ورصُّها بترتيب الإدخال يضع التذييلَ فوقَ الرأس.
  List<TemplateBand> get orderedVisibleBands {
    final visible = bands.where((b) => b.visible).toList()
      ..sort((a, b) => a.id.index.compareTo(b.id.index));
    return List.unmodifiable(visible);
  }

  TemplateBand? bandById(BandId id) {
    for (final b in bands) {
      if (b.id == id) return b;
    }
    return null;
  }

  TemplateDocument copyWith({
    PaperSpec? paper,
    List<TemplateBand>? bands,
    TableSpec? table,
  }) =>
      TemplateDocument(
        paper: paper ?? this.paper,
        bands: bands ?? this.bands,
        table: table ?? this.table,
      );
}
