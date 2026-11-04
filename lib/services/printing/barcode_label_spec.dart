// مواصفات ملصق الباركود وحساب التخطيط (منطق صرف بلا Flutter/PDF).
//
// نوعان: رول (ملصق واحد أو أكثر بعرض الصفحة) وورقة A4 (شبكة أعمدة × صفوف).
// يُستهلك من المولّد `barcode_label_printer.dart` ومن معاينة الحوار.

/// نوع تنسيق الملصقات.
enum LabelKind { roll, sheet }

/// عنصر للطباعة: صنف + عدد نسخه.
class BarcodeLabelItem {
  final String name;
  final String barcode;
  final double? price;
  final int copies;

  /// معرّف الصنف (اختياري) لاحتساب النسخ الافتراضية من آخر استلام.
  final int? productId;
  final int? scalePluNumber;
  final bool isSoldByWeight;
  final double? scaleWeight;
  final String? scaleBarcode;

  const BarcodeLabelItem({
    required this.name,
    required this.barcode,
    this.price,
    this.copies = 1,
    this.productId,
    this.scalePluNumber,
    this.isSoldByWeight = false,
    this.scaleWeight,
    this.scaleBarcode,
  });

  BarcodeLabelItem withCopies(int value) => BarcodeLabelItem(
    name: name,
    barcode: barcode,
    price: price,
    copies: value,
    productId: productId,
    scalePluNumber: scalePluNumber,
    isSoldByWeight: isSoldByWeight,
    scaleWeight: scaleWeight,
    scaleBarcode: scaleBarcode,
  );

  BarcodeLabelItem withScaleData({
    required double weight,
    required String value,
  }) => BarcodeLabelItem(
    name: name,
    barcode: barcode,
    price: price,
    copies: copies,
    productId: productId,
    scalePluNumber: scalePluNumber,
    isSoldByWeight: isSoldByWeight,
    scaleWeight: weight,
    scaleBarcode: value,
  );
}

/// تنسيق ملصق (مقاس جاهز أو مخصص).
class LabelSpec {
  static const double a4WidthMm = 210;
  static const double a4HeightMm = 297;

  /// أقصى عدد ملصقات في عملية واحدة (حماية من خطأ إدخال).
  static const int maxTotalLabels = 5000;
  static const int maxCopiesPerItem = 999;

  final String id;
  final String name;
  final LabelKind kind;

  /// رول: مقاس الملصق الواحد. ورقة: يُهمل (يُحسب من الشبكة).
  final double widthMm;
  final double heightMm;

  /// رول: هامش داخلي حول محتوى كل ملصق. ورقة: هامش الصفحة الخارجي.
  final double marginMm;

  /// عدد الأعمدة (رول متعدد الأعمدة أو أعمدة الورقة).
  final int columns;

  /// عدد الصفوف في الصفحة (ورقة فقط؛ الرول صف واحد).
  final int rows;

  /// المسافة بين الملصقات أفقياً/عمودياً.
  final double gapMm;

  final bool isCustom;

  const LabelSpec({
    required this.id,
    required this.name,
    this.kind = LabelKind.roll,
    this.widthMm = 50,
    this.heightMm = 25,
    this.marginMm = 2,
    this.columns = 1,
    this.rows = 1,
    this.gapMm = 0,
    this.isCustom = false,
  });

  /// رول بمقاس محدد.
  const LabelSpec.roll({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    this.marginMm = 2,
    this.columns = 1,
    this.gapMm = 0,
    this.isCustom = false,
  }) : kind = LabelKind.roll,
       rows = 1;

  /// ورقة A4 بشبكة أعمدة × صفوف.
  const LabelSpec.a4Sheet({
    required this.id,
    required this.name,
    required this.columns,
    required this.rows,
    this.marginMm = 8,
    this.gapMm = 0,
  }) : kind = LabelKind.sheet,
       widthMm = 0,
       heightMm = 0,
       isCustom = false;

  bool get isSheet => kind == LabelKind.sheet;

  double get pageWidthMm =>
      isSheet ? a4WidthMm : columns * widthMm + (columns - 1) * gapMm;
  double get pageHeightMm => isSheet ? a4HeightMm : heightMm;

  /// هامش الصفحة الخارجي (ورقة فقط؛ الرول بلا هامش صفحة).
  double get pageMarginMm => isSheet ? marginMm : 0;

  double get cellWidthMm => isSheet
      ? (a4WidthMm - 2 * marginMm - (columns - 1) * gapMm) / columns
      : widthMm;
  double get cellHeightMm => isSheet
      ? (a4HeightMm - 2 * marginMm - (rows - 1) * gapMm) / rows
      : heightMm;

  /// الهامش الداخلي حول محتوى الملصق.
  double get innerPaddingMm => isSheet ? 1 : marginMm;

  int get labelsPerPage => isSheet ? columns * rows : columns;

  /// `null` إن كان التنسيق صالحاً، وإلا وصف الخطأ (لا يُترجم؛ للسجل/الاختبار).
  String? validate() {
    if (name.trim().isEmpty) return 'name';
    if (columns < 1 || columns > 12) return 'columns';
    if (rows < 1 || rows > 40) return 'rows';
    if (gapMm < 0 || gapMm > 20) return 'gap';
    if (marginMm < 0 || marginMm > 30) return 'margin';
    if (!isSheet) {
      if (widthMm < 15 || widthMm > 300) return 'width';
      if (heightMm < 10 || heightMm > 300) return 'height';
    }
    if (cellWidthMm < 15 || cellHeightMm < 10) return 'cell';
    if (cellWidthMm - 2 * innerPaddingMm < 10 ||
        cellHeightMm - 2 * innerPaddingMm < 8) {
      return 'margin';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'w': widthMm,
    'h': heightMm,
    'margin': marginMm,
    'cols': columns,
    'rows': rows,
    'gap': gapMm,
  };

  /// يُرجع `null` لمدخل تالف بدل رمي استثناء (إعدادات محفوظة قديمة/معطوبة).
  static LabelSpec? fromJson(Object? raw, {bool isCustom = true}) {
    if (raw is! Map) return null;
    try {
      final spec = LabelSpec(
        id: raw['id'] as String,
        name: raw['name'] as String,
        kind: raw['kind'] == 'sheet' ? LabelKind.sheet : LabelKind.roll,
        widthMm: (raw['w'] as num).toDouble(),
        heightMm: (raw['h'] as num).toDouble(),
        marginMm: (raw['margin'] as num).toDouble(),
        columns: (raw['cols'] as num).toInt(),
        rows: (raw['rows'] as num).toInt(),
        gapMm: (raw['gap'] as num).toDouble(),
        isCustom: isCustom,
      );
      return spec.validate() == null ? spec : null;
    } catch (_) {
      return null;
    }
  }

  /// المقاس الافتراضي التاريخي (50×25 مم، هامش 2) — يطابق السلوك السابق.
  static const LabelSpec defaultSpec = LabelSpec.roll(
    id: 'roll_50x25',
    name: '50×25 mm',
    widthMm: 50,
    heightMm: 25,
  );

  /// المقاسات الجاهزة.
  static const List<LabelSpec> presets = [
    defaultSpec,
    LabelSpec.roll(
      id: 'roll_40x25',
      name: '40×25 mm',
      widthMm: 40,
      heightMm: 25,
    ),
    LabelSpec.roll(
      id: 'roll_38x25',
      name: '38×25 mm',
      widthMm: 38,
      heightMm: 25,
      marginMm: 1.5,
    ),
    LabelSpec.roll(
      id: 'roll_58x40',
      name: '58×40 mm',
      widthMm: 58,
      heightMm: 40,
      marginMm: 3,
    ),
    LabelSpec.roll(
      id: 'roll_100x50',
      name: '100×50 mm',
      widthMm: 100,
      heightMm: 50,
      marginMm: 4,
    ),
    LabelSpec.a4Sheet(id: 'a4_2x7', name: 'A4 2×7', columns: 2, rows: 7),
    LabelSpec.a4Sheet(id: 'a4_3x8', name: 'A4 3×8', columns: 3, rows: 8),
    LabelSpec.a4Sheet(
      id: 'a4_4x12',
      name: 'A4 4×12',
      columns: 4,
      rows: 12,
      marginMm: 5,
    ),
  ];
}

/// ملصق واحد ناتج عن توسيع النسخ.
class LabelJob {
  final BarcodeLabelItem item;
  const LabelJob(this.item);
}

/// حسابات التخطيط والصفحات.
abstract final class LabelLayout {
  /// تقييد عدد النسخ في [0, maxCopiesPerItem].
  static int clampCopies(int copies) => copies < 0
      ? 0
      : (copies > LabelSpec.maxCopiesPerItem
            ? LabelSpec.maxCopiesPerItem
            : copies);

  /// يوسّع كل صنف إلى `copies` ملصق بالترتيب. الأصناف بلا باركود أو بنسخ 0
  /// تُتجاهل.
  static List<LabelJob> expand(List<BarcodeLabelItem> items) {
    final jobs = <LabelJob>[];
    for (final it in items) {
      if (it.barcode.trim().isEmpty) continue;
      final n = clampCopies(it.copies);
      for (var i = 0; i < n; i++) {
        jobs.add(LabelJob(it));
      }
    }
    return jobs;
  }

  static int totalLabels(List<BarcodeLabelItem> items) => expand(items).length;

  /// يقسّم الملصقات على صفحات، كل صفحة بحد أقصى `spec.labelsPerPage`.
  static List<List<LabelJob>> paginate(
    LabelSpec spec,
    List<BarcodeLabelItem> items,
  ) {
    final jobs = expand(items);
    final per = spec.labelsPerPage;
    final pages = <List<LabelJob>>[];
    for (var i = 0; i < jobs.length; i += per) {
      pages.add(jobs.sublist(i, i + per > jobs.length ? jobs.length : i + per));
    }
    return pages;
  }

  /// أكثر النسخ المسموحة إجمالاً؟
  static bool exceedsLimit(List<BarcodeLabelItem> items) =>
      totalLabels(items) > LabelSpec.maxTotalLabels;
}
