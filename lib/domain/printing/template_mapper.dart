/// اشتقاقُ [TemplateDocument] من قوالبِ التدفّق القديمة.
///
/// ── القاعدةُ الحاكمة ──────────────────────────────────────────────────────
/// القالبُ الذي لم يمسّه المستخدمُ يجب أن يطبع بعد الهجرة نفسَ ما كان يطبعه
/// قبلها. ولذلك هذا الملفُّ **لا يقرأ `xPosition`/`yPosition` إطلاقاً**:
/// الراسمُ القديمُ كان يتجاهلهما ويبني تدفّقاً من `sortOrder` + `flexWidth`،
/// فقراءتُهما الآن تعني تحريكَ عناصرَ لم تتحرّك يوماً على ورقِ عميل.
///
/// المواضعُ تُشتقّ من التدفّق نفسِه، فيُعاد إنتاجُ التخطيط التدفّقيِّ حرفيّاً
/// بإحداثيّات — المطبوعُ لا يتغيّر، والمستخدمُ يكتسب القدرةَ على التحريك من
/// اللحظة الأولى.
///
/// نقيٌّ كأخوَيه: لا `package:pdf` ولا `package:flutter` ولا قاعدةَ بيانات.
library;

import 'template_document.dart';

/// عنصرٌ بالصيغة القديمة — بنيةٌ محايدةٌ يملؤها الـDAO، فيبقى هذا الملفُّ
/// بلا تبعيّةٍ على `data/database`.
class LegacyElement {
  final String elementType;
  final String? content;
  final String section;
  final int sortOrder;
  final double flexWidth;
  final double fontSize;
  final bool isBold;
  final bool isVisible;
  final String? labelAr;
  final String? labelEn;
  final String textAlign;
  final String? fontColor;
  final String? condition;

  /// مُعرِّفُ الصفِّ الذي جاء منه — يعود به [TemplateElement.id].
  ///
  /// تحتاجه **الهجرة** وحدَها: تشتقّ المواضعَ بهذا المُخطِّط ثمّ تكتبها
  /// في الصفوف، فلا بدّ أن تعرف أيُّ صفٍّ يقابل أيَّ عنصرٍ محسوب. وبدونه
  /// كان لا بدّ من نسخِ حلقةِ الرصّ في الهجرة — نسخةٌ تنحرف عن الأصل عند
  /// أوّل تعديل، فتُهاجَر القوالبُ إلى تخطيطٍ يخالف ما كان يُطبع.
  final String? sourceId;

  const LegacyElement({
    required this.elementType,
    this.content,
    this.section = 'body',
    this.sortOrder = 0,
    this.flexWidth = 100,
    this.fontSize = 10,
    this.isBold = false,
    this.isVisible = true,
    this.labelAr,
    this.labelEn,
    this.textAlign = 'center',
    this.fontColor,
    this.condition,
    this.sourceId,
  });
}

/// مفاتيحُ الطرف — تفصل `party` عن `info` داخلَ `body` القديم.
const _partyKeys = <String>{
  'customer_name', 'customer_phone', 'customer_address', 'customer_tax_number',
  'customer_code', 'supplier_name', 'supplier_phone', 'supplier_address',
  'supplier_tax_number', 'supplier_code', 'party_name', 'party_code',
  'party_phone', 'party_address', 'party_tax_number', 'courier_name',
  'courier_phone',
};

/// مفاتيحُ المجاميع — تفصل `totals` عن `footer` داخلَ `footer` القديم.
const _totalsKeys = <String>{
  'subtotal', 'discount', 'tax', 'total', 'total_amount', 'grand_total',
  'paid', 'remaining', 'delivery_fee', 'cash_amount', 'bank_amount',
  'total_in_words', 'opening_balance', 'closing_balance', 'total_debit',
  'total_credit', 'overdue_amount', 'outstanding_papers', 'ageing_buckets',
  'change_amount', 'net_total',
};

/// أنواعُ النصِّ الحرّ — محتواها نصٌّ مكتوبٌ لا مفتاحُ حقل.
const _freeTextTypes = <String>{'text', 'footer', 'note', 'label'};

/// أنواعٌ لا تحمل نصّاً — لا تسقط بقاعدة «لا تسميةَ معلَّقة».
/// هل هذا العنصرُ شكلٌ على الورق لا حقلَ بيانات؟
///
/// ⚠️ **يُفحص النوعُ والمفتاحُ معاً**. المحرّرُ يخزّن كثيراً من الأشكال
/// نوعاً عامّاً ومحتوىً خاصّاً: مربّعُ QR في القوالب المشحونة
/// `{"type":"variable","content":"qr_code"}`، والشعارُ
/// `{"type":"image","content":"logo"}`. ففحصُ النوع وحدَه يمسك الشعارَ
/// ويُفلت مربّعَ QR — مقيسٌ على ملفّ الفاتورة الضريبيّة.
bool isStructuralElement(String elementType, String contentKey) =>
    elementKindFor(elementType, contentKey).isStructural;

/// نوعُ العنصر على الورق — من نوعه المخزَّن أو من مفتاحه.
///
/// ⚠️ **يُفحص الاثنان**. المحرّرُ يخزّن كثيراً من الأشكال نوعاً عامّاً
/// ومحتوىً خاصّاً: مربّعُ QR `{"type":"variable","content":"qr_code"}`،
/// والشعارُ `{"type":"image","content":"logo"}`. ففحصُ النوع وحدَه يمسك
/// الشعارَ ويُفلت مربّعَ QR — مقيسٌ على ملفّ الفاتورة الضريبيّة.
ElementKind elementKindFor(String elementType, String contentKey) {
  for (final key in [elementType, contentKey]) {
    switch (key) {
      case 'logo':
      case 'image':
        return ElementKind.image;
      case 'qr_code':
        return ElementKind.qrCode;
      case 'barcode':
      case 'barcode_image':
        return ElementKind.barcode;
      case 'line':
      case 'divider':
        return ElementKind.line;
      case 'rectangle':
        return ElementKind.rect;
      case 'spacer':
        return ElementKind.spacer;
      case 'items_table':
      case 'ledger_table':
      case 'report_table':
        // الجدولُ يرسمه النطاقُ لا العنصر — يبقى بنيويّاً كي يحجز مكانَه
        // ولا تُسقطه قاعدةُ الفراغ.
        return ElementKind.spacer;
    }
  }
  return ElementKind.text;
}

const _nonTextTypes = <String>{
  'logo', 'image', 'line', 'rectangle', 'qr_code', 'barcode', 'items_table',
  'ledger_table', 'report_table', 'spacer', 'divider',
};

/// المسافةُ بين صفَّين مشتقَّين — نفسُ ما كان التدفّقُ يتركه.
const double _rowGapMm = 1.0;

/// معاملُ تحويلِ حجمِ الخطّ إلى ارتفاعِ سطرٍ بالمليمتر.
///
/// النقطةُ ٠.٣٥٢٨مم، وارتفاعُ السطر ١.٤ من حجم الخطّ.
const double _lineHeightFactor = 0.3528 * 1.4;

class TemplateMapper {
  const TemplateMapper._();

  /// يبني مستنداً بنطاقاتٍ من عناصرَ بالصيغة القديمة.
  static TemplateDocument fromLegacy({
    required PaperSpec paper,
    required List<LegacyElement> elements,
    TableSpec? table,
  }) {
    final buckets = <BandId, List<LegacyElement>>{
      for (final id in BandId.values) id: <LegacyElement>[],
    };

    for (final el in elements) {
      buckets[_bandFor(el)]!.add(el);
    }

    final bands = <TemplateBand>[];
    for (final id in BandId.values) {
      bands.add(_buildBand(id, buckets[id]!, paper.contentWidthMm));
    }

    return TemplateDocument(paper: paper, bands: bands, table: table);
  }

  /// يُرجع مفتاحَ العنصر — وهو ما يطابقه المحرّرُ ويحلّه المُحلِّل.
  ///
  /// العنصرُ بلا `content` يستنتج مفتاحَه من `elementType`. **هذا وحدَه ما
  /// يجعل القوالبَ المبذورةَ الثمانيةَ مرئيّةً في المحرّر لأوّل مرّة**:
  /// `assets/invoice_templates/*.json` تكتب `{"type":"company_name"}` بلا
  /// `content`، ومحرّرُ الأقسام يفهرس بـ`content` — فالحقلُ يُطبع على الورق
  /// والمحرّرُ يعتبره مخفيّاً.
  static String contentKeyFor(LegacyElement el) {
    if (_freeTextTypes.contains(el.elementType)) return '';
    final c = el.content?.trim() ?? '';
    return c.isEmpty ? el.elementType : c;
  }

  static BandId _bandFor(LegacyElement el) {
    switch (el.section) {
      case 'header':
        return BandId.header;
      case 'details':
        return BandId.details;
      case 'footer':
        return _totalsKeys.contains(contentKeyFor(el))
            ? BandId.totals
            : BandId.footer;
      default:
        return _partyKeys.contains(contentKeyFor(el))
            ? BandId.party
            : BandId.info;
    }
  }

  /// يمشي صفّاً صفّاً على عناصرِ نطاقٍ ويحوّل النسبَ إلى مليمترات.
  ///
  /// الصفُّ يُغلَق حين يبلغ مجموعُ النسب مئة — وهو بالضبط ما كان يفعله
  /// التدفّقُ القديم.
  static TemplateBand _buildBand(
    BandId id,
    List<LegacyElement> raw,
    double contentWidth,
  ) {
    final items = [...raw]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final placed = <TemplateElement>[];
    var y = 0.0;
    var rowFlexUsed = 0.0;
    var rowX = 0.0;
    var rowHeight = 0.0;
    var seq = 0;

    void closeRow() {
      if (rowHeight <= 0) return;
      y += rowHeight + _rowGapMm;
      rowFlexUsed = 0;
      rowX = 0;
      rowHeight = 0;
    }

    for (final el in items) {
      final flex = el.flexWidth <= 0 ? 100.0 : el.flexWidth;

      // تجاوزُ المئة يعني صفّاً جديداً — نفسُ قاعدةِ التدفّق القديم.
      if (rowFlexUsed > 0 && rowFlexUsed + flex > 100) closeRow();

      final w = contentWidth * (flex.clamp(0, 100) / 100);
      final h = el.fontSize * _lineHeightFactor;

      placed.add(
        TemplateElement(
          id: el.sourceId ?? '${id.name}_${seq++}',
          contentKey: contentKeyFor(el),
          xMm: rowX,
          yMm: y,
          wMm: w,
          hMm: h,
          labelAr: _labelFor(el),
          labelEn: el.labelEn,
          fontSize: el.fontSize,
          bold: el.isBold,
          visible: el.isVisible,
          align: _alignFor(el.textAlign),
          colorHex: el.fontColor,
          condition: el.condition,
          kind: elementKindFor(el.elementType, contentKeyFor(el)),
        ),
      );

      rowX += w;
      rowFlexUsed += flex;
      if (h > rowHeight) rowHeight = h;
      if (rowFlexUsed >= 100) closeRow();
    }
    closeRow();

    // نطاقٌ فارغٌ يبقى بارتفاعٍ صفريّ — حذفُه يفقد المحرّرَ مكانَ الإفلات.
    final height = y > 0 ? y - _rowGapMm : 0.0;

    return TemplateBand(
      id: id,
      heightMm: height,
      repeatEachPage: id.repeatsByDefault,
      growsWithData: id.isDetails,
      elements: List.unmodifiable(placed),
    );
  }

  /// النصُّ الحرُّ يحمل نصَّه في `content` — يُنقل إلى [TemplateElement.labelAr]
  /// لأنّ `contentKey` صار فارغاً.
  ///
  /// وهذا هو إصلاحُ `footer_text`: المحرّرُ كان يخزّن **المفتاح** في
  /// `content`، والراسمُ يستبدل نوعَ العنصر بمحتواه فلا تُطابَق حالةٌ ويطبع
  /// حارسُ `default` السلسلةَ «footer_text» حرفيّاً على الورق.
  static String? _labelFor(LegacyElement el) {
    if (_freeTextTypes.contains(el.elementType)) {
      final c = el.content?.trim() ?? '';
      // المفتاحُ المخزَّنُ خطأً بدل النصّ — لا يُطبع حرفيّاً.
      if (c.isNotEmpty && c != el.elementType && c != 'footer_text') return c;
      return el.labelAr;
    }
    return el.labelAr;
  }

  static TextAlignSpec _alignFor(String v) {
    switch (v) {
      case 'left':
        return TextAlignSpec.start;
      case 'right':
        return TextAlignSpec.end;
      case 'center':
      default:
        return TextAlignSpec.center;
    }
  }

  /// هل هذا النوعُ يحمل نصّاً؟ يقرؤها الراسمُ ليعرف ما يسقط بقاعدة
  /// «لا تسميةَ معلَّقة» وما يبقى (شعارٌ · خطٌّ · باركود).
  static bool isTextBearing(String elementType) =>
      !_nonTextTypes.contains(elementType);
}
