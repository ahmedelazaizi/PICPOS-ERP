/// إعدادُ باركود الميزان كما يقرؤه `ScaleBarcodeHandler` (نقطة البيع)
/// ويكتبه `ScaleBarcodeEncoder` (ملصق الميزان) — **مصدرٌ واحدٌ** لمفاتيح
/// الإعداد وافتراضاتها وقواعد صلاحيتها.
///
/// ── المفاتيح (حصرٌ من الكود) ───────────────────────────────────────────────
/// يقرؤها المحلّل `scale_barcode_handler.dart`:
///   `scale_price_prefix` (افتراضي 20) · `scale_weight_prefix` (21) ·
///   `scale_fallback_prefix` (22، بادئة وزنٍ بديلة) ·
///   `scale_price_item_code_len` / `scale_weight_item_code_len` (5) ·
///   `scale_price_divider` (100) / `scale_weight_divider` (1000).
/// تكتبها شاشةُ الإعداد: `scale_weight_enabled` / `scale_price_enabled`.
/// عند غياب مؤشر التفعيل، يُعدّ النوع مفعّلاً فقط إذا وُجدت بادئته مخزّنة
/// (بما فيها المفاتيح القديمة)، حفاظاً على إعدادات الميزان السابقة؛ أما الإعداد
/// الجديد بلا بادئة محفوظة فيبقى معطّلاً. القيمة الصريحة `false` لها الأولوية.
///
/// عدد خانات القيمة **لا مفتاح له**: المحلّل يأخذ ما بين نهاية PLU والخانة
/// ١٢، فهو مشتقٌّ = 12 − طول البادئة − خانات PLU. وخانةُ التحقّق (الثالثة
/// عشرة) إلزاميةٌ دائماً: المحلّل يرفض EAN-13 بخانة تحقّقٍ خاطئة.
///
/// نقيّ: لا Flutter ولا قاعدة بيانات ولا `tr()` — الرسائلُ تُترجم في الواجهة.
library;

import 'scale_barcode_encoder.dart';

enum ScaleBarcodeIssue {
  weightPrefixInvalid,
  pricePrefixInvalid,
  fallbackPrefixInvalid,
  weightCodeLenInvalid,
  priceCodeLenInvalid,
  weightDividerInvalid,
  priceDividerInvalid,
  prefixConflict,
  fallbackConflict,
}

/// نتيجة معاينة المثال: [barcode] أو [error]، مع [plu]/[value] الفعليّين بعد
/// القصّ/التقريب (يقارنهما العرضُ بالمثال الأصلي).
class ScaleBarcodeSample {
  const ScaleBarcodeSample({
    this.barcode,
    this.error,
    this.plu = '',
    this.value = 0,
  });
  final String? barcode;
  final ScaleSampleError? error;
  final String plu;
  final double value;
}

enum ScaleSampleError { profileInvalid, valueOverflow }

class ScaleBarcodeConfig {
  static const weightEnabledKey = 'scale_weight_enabled';
  static const priceEnabledKey = 'scale_price_enabled';
  static const weightPrefixKey = 'scale_weight_prefix';
  static const pricePrefixKey = 'scale_price_prefix';
  static const fallbackPrefixKey = 'scale_fallback_prefix';
  static const weightCodeLenKey = 'scale_weight_item_code_len';
  static const priceCodeLenKey = 'scale_price_item_code_len';
  static const weightDividerKey = 'scale_weight_divider';
  static const priceDividerKey = 'scale_price_divider';

  /// مفاتيحُ قديمة تقرؤها شاشة الإعداد احتياطاً (نُقلت حرفياً من
  /// `scale_barcode_settings.dart`) — تُقرأ فقط، ولا تُكتب.
  static const legacyFallbacks = <String, List<String>>{
    priceEnabledKey: ['scale_qty_enabled'],
    weightPrefixKey: ['scale_barcode_prefix'],
    weightCodeLenKey: ['scale_barcode_code_length'],
    weightDividerKey: ['scale_barcode_divider'],
    pricePrefixKey: ['scale_qty_prefix'],
    priceCodeLenKey: ['scale_price_code_length', 'scale_qty_code_length'],
    priceDividerKey: ['scale_qty_divider'],
  };

  static const canonicalKeys = [
    weightEnabledKey,
    priceEnabledKey,
    weightPrefixKey,
    pricePrefixKey,
    fallbackPrefixKey,
    weightCodeLenKey,
    priceCodeLenKey,
    weightDividerKey,
    priceDividerKey,
  ];

  /// كلُّ مفتاحٍ يلزم قراءته (الأساسية + القديمة).
  static List<String> get readKeys => [
    ...canonicalKeys,
    for (final l in legacyFallbacks.values) ...l,
  ];

  /// أمثلةُ المعاينة: صنف PLU 12345 بوزن 1.234 كجم وسعر كيلو 10.
  static const samplePlu = '12345';
  static const sampleWeight = 1.234;
  static const sampleUnitPrice = 10.0;

  const ScaleBarcodeConfig({
    this.weightEnabled = false,
    this.priceEnabled = false,
    this.weightPrefix = '21',
    // كانت شاشةُ الإعداد تفترض 22 للسعر بينما المحلّل يفترض 20 ويجعل 22
    // بادئةَ وزنٍ بديلة — فحفظُ الشاشة يقلب ملصقات 22 إلى «سعر». المحلّلُ مرجع.
    this.pricePrefix = '20',
    this.fallbackPrefix = '22',
    this.weightCodeLen = '5',
    this.priceCodeLen = '5',
    this.weightDivider = '1000',
    this.priceDivider = '100',
  });

  final bool weightEnabled;
  final bool priceEnabled;
  final String weightPrefix;
  final String pricePrefix;
  final String fallbackPrefix;
  final String weightCodeLen;
  final String priceCodeLen;
  final String weightDivider;
  final String priceDivider;

  /// يبني الإعداد من قيم مخزّنة (مفتاح ← قيمة)؛ المفقود ⇒ مفتاحٌ قديم ⇒ افتراضي.
  factory ScaleBarcodeConfig.fromSettings(Map<String, String?> s) {
    String? read(String key) {
      final v = s[key];
      if (v != null && v.trim().isNotEmpty) return v.trim();
      for (final old in legacyFallbacks[key] ?? const <String>[]) {
        final o = s[old];
        if (o != null && o.trim().isNotEmpty) return o.trim();
      }
      return null;
    }

    const d = ScaleBarcodeConfig();
    // Missing toggle preserves previously saved scale profiles; explicit false
    // always disables that mode, and no saved prefix means opt-in is required.
    final savedWeightPrefix = read(weightPrefixKey) != null;
    final savedPricePrefix = read(pricePrefixKey) != null;
    final weightToggle = read(weightEnabledKey);
    final priceToggle = read(priceEnabledKey);
    return ScaleBarcodeConfig(
      weightEnabled:
          weightToggle == 'true' || (weightToggle == null && savedWeightPrefix),
      priceEnabled:
          priceToggle == 'true' || (priceToggle == null && savedPricePrefix),
      weightPrefix: read(weightPrefixKey) ?? d.weightPrefix,
      pricePrefix: read(pricePrefixKey) ?? d.pricePrefix,
      fallbackPrefix: read(fallbackPrefixKey) ?? d.fallbackPrefix,
      weightCodeLen: read(weightCodeLenKey) ?? d.weightCodeLen,
      priceCodeLen: read(priceCodeLenKey) ?? d.priceCodeLen,
      weightDivider: read(weightDividerKey) ?? d.weightDivider,
      priceDivider: read(priceDividerKey) ?? d.priceDivider,
    );
  }

  ScaleBarcodeConfig copyWith({
    bool? weightEnabled,
    bool? priceEnabled,
    String? weightPrefix,
    String? pricePrefix,
    String? fallbackPrefix,
    String? weightCodeLen,
    String? priceCodeLen,
    String? weightDivider,
    String? priceDivider,
  }) => ScaleBarcodeConfig(
    weightEnabled: weightEnabled ?? this.weightEnabled,
    priceEnabled: priceEnabled ?? this.priceEnabled,
    weightPrefix: weightPrefix ?? this.weightPrefix,
    pricePrefix: pricePrefix ?? this.pricePrefix,
    fallbackPrefix: fallbackPrefix ?? this.fallbackPrefix,
    weightCodeLen: weightCodeLen ?? this.weightCodeLen,
    priceCodeLen: priceCodeLen ?? this.priceCodeLen,
    weightDivider: weightDivider ?? this.weightDivider,
    priceDivider: priceDivider ?? this.priceDivider,
  );

  /// القيمُ المكتوبة عند الحفظ — المفاتيح الأساسية وحدها.
  Map<String, String> toSettings() => {
    weightEnabledKey: '$weightEnabled',
    priceEnabledKey: '$priceEnabled',
    weightPrefixKey: weightPrefix.trim(),
    pricePrefixKey: pricePrefix.trim(),
    fallbackPrefixKey: fallbackPrefix.trim(),
    weightCodeLenKey: weightCodeLen.trim(),
    priceCodeLenKey: priceCodeLen.trim(),
    weightDividerKey: weightDivider.trim(),
    priceDividerKey: priceDivider.trim(),
  };

  bool get anyEnabled => weightEnabled || priceEnabled;

  /// Mirrors the parser's configured modes and its legacy weight auto-detect.
  bool isEnabledScaleBarcode(String barcode) {
    if (barcode.startsWith(pricePrefix.trim())) return priceEnabled;
    return weightEnabled;
  }

  /// True only for a 13-digit scale-prefix candidate explicitly disabled.
  bool isDisabledScaleBarcode(String barcode) =>
      barcode.length == 13 &&
      barcode.startsWith('2') &&
      ((barcode.startsWith(pricePrefix.trim()) && !priceEnabled) ||
          ((barcode.startsWith(weightPrefix.trim()) ||
                  barcode.startsWith(fallbackPrefix.trim())) &&
              !weightEnabled));

  String prefixOf(ScaleBarcodeValueKind k) =>
      (k == ScaleBarcodeValueKind.weight ? weightPrefix : pricePrefix).trim();

  int? codeLenOf(ScaleBarcodeValueKind k) => int.tryParse(
    (k == ScaleBarcodeValueKind.weight ? weightCodeLen : priceCodeLen).trim(),
  );

  /// المحلّل يقرأ المعامل بـ`double.tryParse` — فـ«1000.0» مقبولة كـ1000.
  int? dividerOf(ScaleBarcodeValueKind k) {
    final d = double.tryParse(
      (k == ScaleBarcodeValueKind.weight ? weightDivider : priceDivider).trim(),
    );
    if (d == null || !d.isFinite || d != d.roundToDouble()) return null;
    return d.toInt();
  }

  /// خاناتُ القيمة المشتقّة (12 − البادئة − PLU)؛ `null` إن لم تُحسب.
  int? valueDigitsOf(ScaleBarcodeValueKind k) {
    final len = codeLenOf(k);
    if (len == null || !_prefixOk(prefixOf(k))) return null;
    return 12 - prefixOf(k).length - len;
  }

  /// المنازلُ العشرية التي يمثّلها المعامل (1000 ⇒ 3)؛ `null` لغير قوى العشرة.
  int? decimalsOf(ScaleBarcodeValueKind k) => _decimals(dividerOf(k));

  static bool _prefixOk(String p) => RegExp(r'^2\d{0,3}$').hasMatch(p);

  static int? _decimals(int? divider) {
    if (divider == null) return null;
    const powers = [1, 10, 100, 1000, 10000, 100000];
    final i = powers.indexOf(divider);
    return i < 0 ? null : i;
  }

  static bool _overlaps(String a, String b) =>
      a.isNotEmpty && b.isNotEmpty && (a.startsWith(b) || b.startsWith(a));

  /// أخطاءُ الإعداد. المحلّل يجرّب بادئة السعر **قبل** الوزن، فتداخلهما
  /// (تساوٍ أو بادئةٌ أوّلُ الأخرى) يقلب ملصقات الوزن إلى سعر حتى لو كان ملف
  /// السعر غير مفعّل — لذلك يُفحص التداخل دائماً.
  List<ScaleBarcodeIssue> validate() {
    final issues = <ScaleBarcodeIssue>[];
    void profile(
      ScaleBarcodeValueKind k,
      ScaleBarcodeIssue prefixIssue,
      ScaleBarcodeIssue lenIssue,
      ScaleBarcodeIssue divIssue,
    ) {
      final prefixValid = _prefixOk(prefixOf(k));
      if (!prefixValid) issues.add(prefixIssue);
      final len = codeLenOf(k);
      final maxLen = 11 - (prefixValid ? prefixOf(k).length : 1);
      if (len == null || len < 1 || len > maxLen) issues.add(lenIssue);
      if (decimalsOf(k) == null) issues.add(divIssue);
    }

    profile(
      ScaleBarcodeValueKind.weight,
      ScaleBarcodeIssue.weightPrefixInvalid,
      ScaleBarcodeIssue.weightCodeLenInvalid,
      ScaleBarcodeIssue.weightDividerInvalid,
    );
    profile(
      ScaleBarcodeValueKind.price,
      ScaleBarcodeIssue.pricePrefixInvalid,
      ScaleBarcodeIssue.priceCodeLenInvalid,
      ScaleBarcodeIssue.priceDividerInvalid,
    );
    final fb = fallbackPrefix.trim();
    if (!_prefixOk(fb)) issues.add(ScaleBarcodeIssue.fallbackPrefixInvalid);
    if (_overlaps(weightPrefix.trim(), pricePrefix.trim())) {
      issues.add(ScaleBarcodeIssue.prefixConflict);
    }
    if (_overlaps(fb, pricePrefix.trim())) {
      issues.add(ScaleBarcodeIssue.fallbackConflict);
    }
    return issues;
  }

  bool profileValid(ScaleBarcodeValueKind k) {
    final bad = validate();
    final own = k == ScaleBarcodeValueKind.weight
        ? const [
            ScaleBarcodeIssue.weightPrefixInvalid,
            ScaleBarcodeIssue.weightCodeLenInvalid,
            ScaleBarcodeIssue.weightDividerInvalid,
          ]
        : const [
            ScaleBarcodeIssue.pricePrefixInvalid,
            ScaleBarcodeIssue.priceCodeLenInvalid,
            ScaleBarcodeIssue.priceDividerInvalid,
          ];
    return !bad.any(own.contains) &&
        !bad.contains(ScaleBarcodeIssue.prefixConflict);
  }

  /// يشفّر قيمةً بهذا الإعداد (نفس ما يقرؤه المحلّل). يرمي `ArgumentError`
  /// (و`RangeError`) كالمشفّر.
  String encode({
    required ScaleBarcodeValueKind kind,
    required String plu,
    required double value,
  }) => ScaleBarcodeEncoder.encode(
    plu: plu,
    value: value,
    kind: kind,
    prefix: prefixOf(kind),
    codeLength: codeLenOf(kind) ?? 5,
    divider: (dividerOf(kind) ?? 0).toDouble(),
  );

  /// باركود المثال (PLU 12345، وزن 1.234 أو إجمالي 12.34). PLU أطول من
  /// الخانات يُقصّ لأوّلها، والقيمة تُقرّب لدقّة المعامل — فيرى المستخدم
  /// أثر إعداده بدل خطأ.
  ScaleBarcodeSample sample(ScaleBarcodeValueKind kind) {
    final len = codeLenOf(kind);
    final div = dividerOf(kind);
    if (!profileValid(kind) || len == null || div == null) {
      return const ScaleBarcodeSample(error: ScaleSampleError.profileInvalid);
    }
    final plu = samplePlu.length > len
        ? samplePlu.substring(0, len)
        : samplePlu;
    final raw = kind == ScaleBarcodeValueKind.weight
        ? sampleWeight
        : sampleWeight * sampleUnitPrice;
    final value = (raw * div).round() / div;
    try {
      return ScaleBarcodeSample(
        barcode: encode(kind: kind, plu: plu, value: value),
        plu: plu,
        value: value,
      );
    } on ArgumentError {
      return ScaleBarcodeSample(
        error: ScaleSampleError.valueOverflow,
        plu: plu,
        value: value,
      );
    }
  }
}
