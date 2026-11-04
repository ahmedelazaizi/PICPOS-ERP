// نموذجُ ملصق الباركود في المحرّر — **خالصٌ بلا واجهةٍ ولا قاعدة**.
//
// ── لماذا نموذجٌ مستقلٌّ لا [TemplateDocument] ─────────────────────────────
// راسمُ الملصقات (`template_barcode_labels.dart`) **لا يعرف النطاقات**: يقرأ
// `xPosition/yPosition/width/height` من `invoice_template_elements` على أنّها
// مليمتراتٌ من **حافّة اليسار** داخل الملصق، ولا ينظر إلى `layout_version`
// ولا `x_mm` ولا `band_id` ولا `is_visible`. فتحويلُ الملصق إلى نطاقاتٍ v2
// كان سيكتب أعمدةً لا يقرؤها الراسمُ ويترك التي يقرؤها — أي «ما يُحرَّك لا
// يُطبع» من جديد.
//
// فهذا النموذجُ **مرآةٌ حرفيّةٌ لما يقرؤه الراسم** لا أكثر: كلُّ حقلٍ هنا
// عمودٌ يستهلكه `_buildSingleBarcodeLabel`، بنفس وحدته ونفس أصله.

/// أنواعُ عناصر الملصق التي **يرسمها** راسمُ الملصقات فعلاً.
///
/// `image` غائبٌ عن قصد: الراسمُ لا يرسم صورةً للملصق (يسقط إلى `content`
/// نصّاً)، وعرضُه في اللوحة وعدٌ بشيءٍ لا يخرج على الورق.
abstract final class LabelElementTypes {
  static const productName = 'product_name';
  static const productCode = 'product_code';
  static const barcode = 'barcode_image';
  static const price = 'product_price';
  static const companyName = 'company_name';
  static const text = 'text';
  static const line = 'line';
  static const divider = 'divider';
  static const rectangle = 'rectangle';

  /// ما تعرضه لوحةُ الإضافة — بترتيبها.
  static const palette = <String>[
    productName,
    barcode,
    price,
    productCode,
    companyName,
    text,
    line,
    rectangle,
  ];
}

/// رموزُ الباركود التي يحلّها `_resolveBarcodeType` — بنفس مفاتيحه.
const kLabelSymbologies = <String>[
  'code128',
  'ean13',
  'ean8',
  'upcA',
  'code39',
  'code93',
  'codabar',
  'qrCode',
];

/// حدودُ مقاس الملصق بالمليمتر — أصغرُ من ١٠ لا يحمل باركوداً مقروءاً،
/// وأكبرُ من ٢٠٠ لا يسعه عرضُ A4 الذي يُرصَّف عليه.
const double kLabelMinMm = 10;
const double kLabelMaxMm = 200;

/// أصغرُ ضلعٍ لعنصر — الخطُّ وحدَه يرقّ إلى ما دونه.
const double kLabelElementMinMm = 1;
const double kLabelLineMinMm = 0.3;

class LabelElement {
  /// مفتاحٌ ثابتٌ في الجلسة — `e<id>` للمحفوظ و`n<seq>` للجديد.
  final String key;

  /// مُعرِّفُ الصفّ — `null` لعنصرٍ لم يُحفظ بعد.
  final int? id;

  /// `element_type` كما يقرؤه الراسم.
  final String type;

  /// مليمتراتٌ من **يسار** الملصق وأعلاه — `x_position`/`y_position`.
  final double xMm;
  final double yMm;
  final double wMm;
  final double hMm;

  final double fontSize;
  final bool bold;
  final bool italic;

  /// `left` · `center` · `right` — `text_align` حرفيّاً.
  final String align;

  /// `#RRGGBB` — `font_color`.
  final String color;

  /// النصُّ الثابت، أو رمزُ الباركود لـ`barcode_image`.
  final String? content;

  /// سُمكُ إطار المستطيل — صفرٌ يعني ٠٫٥ عند الراسم.
  final double borderWidth;

  /// التسميةُ المخزَّنة — لا يطبعها الراسم، وتُحفظ كما هي.
  final String? labelAr;

  const LabelElement({
    required this.key,
    this.id,
    required this.type,
    required this.xMm,
    required this.yMm,
    required this.wMm,
    required this.hMm,
    this.fontSize = 8,
    this.bold = false,
    this.italic = false,
    this.align = 'center',
    this.color = '#000000',
    this.content,
    this.borderWidth = 0,
    this.labelAr,
  });

  bool get isLine =>
      type == LabelElementTypes.line || type == LabelElementTypes.divider;
  bool get isBarcode => type == LabelElementTypes.barcode;
  bool get isQr => isBarcode && content == 'qrCode';
  bool get isRect => type == LabelElementTypes.rectangle;

  /// عنصرٌ يحمل نصّاً — فتعنيه خصائصُ الخطّ.
  bool get hasText => !isLine && !isRect;

  LabelElement copyWith({
    double? xMm,
    double? yMm,
    double? wMm,
    double? hMm,
    double? fontSize,
    bool? bold,
    bool? italic,
    String? align,
    String? color,
    String? content,
    double? borderWidth,
  }) =>
      LabelElement(
        key: key,
        id: id,
        type: type,
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        wMm: wMm ?? this.wMm,
        hMm: hMm ?? this.hMm,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        align: align ?? this.align,
        color: color ?? this.color,
        content: content ?? this.content,
        borderWidth: borderWidth ?? this.borderWidth,
        labelAr: labelAr,
      );

  @override
  bool operator ==(Object other) =>
      other is LabelElement &&
      other.key == key &&
      other.id == id &&
      other.type == type &&
      other.xMm == xMm &&
      other.yMm == yMm &&
      other.wMm == wMm &&
      other.hMm == hMm &&
      other.fontSize == fontSize &&
      other.bold == bold &&
      other.italic == italic &&
      other.align == align &&
      other.color == color &&
      other.content == content &&
      other.borderWidth == borderWidth &&
      other.labelAr == labelAr;

  @override
  int get hashCode => Object.hash(key, id, type, xMm, yMm, wMm, hMm, fontSize,
      bold, italic, align, color, content, borderWidth, labelAr);
}

class LabelDesign {
  final int templateId;
  final String name;
  final double widthMm;
  final double heightMm;
  final bool isDefault;

  /// بترتيب الرسم — يُكتب `sort_order` من موضعه هنا.
  final List<LabelElement> elements;

  const LabelDesign({
    required this.templateId,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.elements,
    this.isDefault = false,
  });

  /// `paper_size` كما يكتبه البذّار: «50x25».
  String get paperSize => '${_fmt(widthMm)}x${_fmt(heightMm)}';

  LabelElement? byKey(String? key) {
    if (key == null) return null;
    for (final e in elements) {
      if (e.key == key) return e;
    }
    return null;
  }

  LabelDesign copyWith({
    String? name,
    double? widthMm,
    double? heightMm,
    bool? isDefault,
    List<LabelElement>? elements,
  }) =>
      LabelDesign(
        templateId: templateId,
        name: name ?? this.name,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        isDefault: isDefault ?? this.isDefault,
        elements: elements ?? this.elements,
      );

  @override
  bool operator ==(Object other) {
    if (other is! LabelDesign) return false;
    if (other.templateId != templateId ||
        other.name != name ||
        other.widthMm != widthMm ||
        other.heightMm != heightMm ||
        other.elements.length != elements.length) {
      return false;
    }
    for (var i = 0; i < elements.length; i++) {
      if (other.elements[i] != elements[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(templateId, name, widthMm, heightMm, Object.hashAll(elements));
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// ═══════════════════════════════════════════════════════════════════════════
// التعديلات — دوالُّ خالصةٌ تُرجع تصميماً جديداً.
// ═══════════════════════════════════════════════════════════════════════════

double _snap(double v, bool snap) =>
    snap ? (v * 2).roundToDouble() / 2 : (v * 100).roundToDouble() / 100;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

LabelDesign _replace(LabelDesign d, String key, LabelElement Function(LabelElement) f) =>
    d.copyWith(elements: [
      for (final e in d.elements) e.key == key ? f(e) : e,
    ]);

/// يحرّك عنصراً — ويُبقيه **داخل الملصق**: ما يخرج عن حدوده يُقصّ على الورق.
LabelDesign moveLabelElement(LabelDesign d, String key, double xMm, double yMm,
        {bool snap = true}) =>
    _replace(d, key, (e) {
      final x = _clamp(_snap(xMm, snap), 0, (d.widthMm - e.wMm).clamp(0.0, d.widthMm));
      final y = _clamp(_snap(yMm, snap), 0, (d.heightMm - e.hMm).clamp(0.0, d.heightMm));
      return e.copyWith(xMm: x, yMm: y);
    });

/// يغيّر مقاسَ عنصرٍ — لا أصغرَ من [kLabelElementMinMm] ولا أبعدَ من الحافّة.
LabelDesign resizeLabelElement(LabelDesign d, String key, double wMm, double hMm,
        {bool snap = true}) =>
    _replace(d, key, (e) {
      final minH = e.isLine ? kLabelLineMinMm : kLabelElementMinMm;
      final w = _clamp(_snap(wMm, snap), kLabelElementMinMm,
          (d.widthMm - e.xMm).clamp(kLabelElementMinMm, d.widthMm));
      final h = e.isLine && hMm < kLabelElementMinMm
          ? _clamp(hMm, minH, kLabelElementMinMm)
          : _clamp(_snap(hMm, snap), minH,
              (d.heightMm - e.yMm).clamp(minH, d.heightMm));
      return e.copyWith(wMm: w, hMm: h);
    });

/// يعدّل خصائصَ عنصر.
LabelDesign editLabelElement(
  LabelDesign d,
  String key, {
  double? fontSize,
  bool? bold,
  bool? italic,
  String? align,
  String? color,
  String? content,
  double? borderWidth,
}) =>
    _replace(
      d,
      key,
      (e) => e.copyWith(
        fontSize: fontSize == null ? null : _clamp(fontSize, 3, 72),
        bold: bold,
        italic: italic,
        align: align,
        color: color,
        content: content,
        borderWidth: borderWidth == null ? null : _clamp(borderWidth, 0, 5),
      ),
    );

/// يحذف عنصراً.
LabelDesign removeLabelElement(LabelDesign d, String key) =>
    d.copyWith(elements: [for (final e in d.elements) if (e.key != key) e]);

/// يضيف عنصراً بمقاسٍ معقولٍ لنوعه ويُرجع مفتاحَه.
(LabelDesign, String) addLabelElement(LabelDesign d, String type,
    {String? content}) {
  var seq = 0;
  for (final e in d.elements) {
    if (!e.key.startsWith('n')) continue;
    final n = int.tryParse(e.key.substring(1));
    if (n != null && n >= seq) seq = n + 1;
  }
  final key = 'n$seq';
  final lw = d.widthMm;
  final lh = d.heightMm;
  final maxW = (lw - 4).clamp(kLabelElementMinMm, lw);

  final (double w, double h) = switch (type) {
    LabelElementTypes.barcode when content == 'qrCode' =>
      ((lh - 4).clamp(kLabelElementMinMm, maxW), (lh - 4).clamp(kLabelElementMinMm, lh)),
    LabelElementTypes.barcode => (maxW, (lh * 0.5).clamp(kLabelElementMinMm, lh)),
    LabelElementTypes.line || LabelElementTypes.divider => (maxW, 0.5),
    LabelElementTypes.rectangle => (maxW, (lh - 4).clamp(kLabelElementMinMm, lh)),
    _ => (maxW, (lh * 0.25).clamp(kLabelElementMinMm, lh)),
  };

  final (xMm, yMm) = _firstVacantLabelPosition(d, w, h);
  final el = LabelElement(
    key: key,
    type: type,
    xMm: xMm,
    yMm: yMm,
    wMm: w,
    hMm: h,
    fontSize: type == LabelElementTypes.price ? 9 : 7,
    bold: type == LabelElementTypes.productName ||
        type == LabelElementTypes.price,
    content: content ??
        (type == LabelElementTypes.barcode
            ? 'code128'
            : (type == LabelElementTypes.text ? '' : null)),
  );
  return (d.copyWith(elements: [...d.elements, el]), key);
}

(double, double) _firstVacantLabelPosition(
  LabelDesign design,
  double width,
  double height,
) {
  final maxX = design.widthMm - width;
  final maxY = design.heightMm - height;
  final candidates = _labelPositionCandidates(design, maxX, maxY);
  for (final y in candidates.y) {
    for (final x in candidates.x) {
      if (!_labelPositionOverlaps(design, x, y, width, height)) return (x, y);
    }
  }
  return (
    ((design.widthMm - width) / 2).clamp(0.0, maxX),
    maxY.clamp(0.0, design.heightMm),
  );
}

({List<double> x, List<double> y}) _labelPositionCandidates(
  LabelDesign design,
  double maxX,
  double maxY,
) {
  final x = <double>{0};
  final y = <double>{0};
  for (final element in design.elements) {
    final right = element.xMm + element.wMm;
    final bottom = element.yMm + element.hMm;
    if (right <= maxX) x.add(right);
    if (bottom <= maxY) y.add(bottom);
  }
  return (x: x.toList()..sort(), y: y.toList()..sort());
}

bool _labelPositionOverlaps(
  LabelDesign design,
  double x,
  double y,
  double width,
  double height,
) =>
    design.elements.any(
      (element) =>
          x < element.xMm + element.wMm &&
          x + width > element.xMm &&
          y < element.yMm + element.hMm &&
          y + height > element.yMm,
    );

/// يغيّر مقاسَ الملصق — والعناصرُ تُقصّ إلى الحدود الجديدة كي لا تقع خارجها.
LabelDesign resizeLabel(LabelDesign d, {double? widthMm, double? heightMm}) {
  final lw = _clamp(widthMm ?? d.widthMm, kLabelMinMm, kLabelMaxMm);
  final lh = _clamp(heightMm ?? d.heightMm, kLabelMinMm, kLabelMaxMm);
  return d.copyWith(
    widthMm: lw,
    heightMm: lh,
    elements: [
      for (final e in d.elements)
        () {
          final w = e.wMm > lw ? lw : e.wMm;
          final h = e.hMm > lh ? lh : e.hMm;
          return e.copyWith(
            wMm: w,
            hMm: h,
            xMm: e.xMm + w > lw ? lw - w : e.xMm,
            yMm: e.yMm + h > lh ? lh - h : e.yMm,
          );
        }(),
    ],
  );
}
