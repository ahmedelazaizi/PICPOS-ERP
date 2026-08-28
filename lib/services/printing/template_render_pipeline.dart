// وصلُ الراسم بالمحرّك — صفُّ القالب في القاعدة ⇐ بايتاتُ الـPDF.
//
// ── الحلقةُ التي كانت مفقودة ─────────────────────────────────────────────
// المحرّكُ كاملٌ ومشحونٌ منذ تسعةِ كوميتات: `TemplateMapper` و`LayoutEngine`
// و`planPage` و`PdfPainter`، ومعها الأعمدةُ في المخطَّط (`layout_version` ·
// `band_id` · `x_mm`…`h_mm` · `table_kind` · `columns_json`). لكنّ **لا سطرَ
// في `lib/` كان يقرأ أيّاً من هذه الأعمدة** — مقيسٌ بالبحث: مطابقاتُها كلُّها
// في تعريف الجداول وملفّ الهجرة وحدَهما.
//
// فالمحرّكُ كان جزيرةً: مُختبَراً بثمانيةِ اختباراتِ منعِ انتكاسٍ، ولا يصل
// ورقةً واحدة. وهذا الملفُّ هو الجسر.
//
// ── والبوّابةُ تحفظ القديم ────────────────────────────────────────────────
// `layout_version == 1` ⇒ المسارُ التدفّقيُّ القديم كما هو بحرفه. و`== 2` ⇒
// هذا. وكلُّ قالبٍ في المستودع اليومَ عند ١، فالملفّاتُ الذهبيّةُ السبعةُ
// والعشرون هي البرهانُ على أنّ شيئاً لم يتحرّك.
//
// ── ولماذا مساران داخلَ v2 ──────────────────────────────────────────────
// القالبُ المهاجَرُ يحمل `band_id` وإحداثيّاتٍ بالمليمتر، فيُبنى منها مباشرةً
// — وهذا وحدَه ما يجعل سحبَ عنصرٍ في المصمّم يصل الورقةَ. والقالبُ المرقَّى
// إلى ٢ قبل أن يكتب المحرّرُ إحداثيّاته يُشتقّ بالمُخطِّط من التدفّق، فلا
// يخرج فارغاً. والهجرةُ كسولةٌ عند أوّل فتحٍ في المحرّر — لا دفعةً واحدةً على
// ورقِ عميل.

import 'dart:convert';
import 'dart:typed_data';

import '../../data/database/database.dart';
import '../../domain/printing/print_values.dart';
import '../../domain/printing/template_document.dart';
import '../../domain/printing/template_mapper.dart';
import 'layout_engine.dart';
import 'paint_plan.dart';
import 'pdf_painter.dart';

/// نسخةُ التخطيط التي يخدمها هذا المسار.
const int kBandLayoutVersion = 2;

class TemplateRenderPipeline {
  const TemplateRenderPipeline._();

  /// يرسم المستندَ بالمحرّك الجديد ويُرجع البايتات.
  ///
  /// [orderedElements] مرتَّبةٌ ومنقّاةٌ سلفاً بنفس ما يفعله المسارُ القديم
  /// (`orderElementsForPrint`) — كي لا يفترق الترتيبُ بين النسختين لسببٍ لا
  /// علاقةَ له بالتخطيط.
  static Future<Uint8List> render({
    required InvoiceTemplate template,
    required List<InvoiceTemplateElement> orderedElements,
    required InvoiceTableSetting? tableSettings,
    required PrintPayload payload,
    required List<Map<String, dynamic>> items,
    PaintDirection direction = PaintDirection.rtl,
  }) async {
    final document = buildDocument(
      template: template,
      orderedElements: orderedElements,
      tableSettings: tableSettings,
    );

    final pages = LayoutEngine.paginate(
      document: document,
      rows: buildRows(items, document.table, payload.decimals),
      values: buildValues(document, payload),
    );

    return PdfPainter.paint(pages: pages, direction: direction);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // المستند
  // ═════════════════════════════════════════════════════════════════════════

  static TemplateDocument buildDocument({
    required InvoiceTemplate template,
    required List<InvoiceTemplateElement> orderedElements,
    required InvoiceTableSetting? tableSettings,
  }) {
    final paper = buildPaper(template);
    final table = buildTable(tableSettings, paper);
    final visible = orderedElements.where((e) => e.isVisible).toList();

    if (visible.isNotEmpty && visible.every(_isPositioned)) {
      return _fromBands(paper, visible, table);
    }

    // لا إحداثيّاتٍ بعد ⇒ يُشتقّ من التدفّق. مستندٌ مشتقٌّ خيرٌ من ورقةٍ
    // فارغة، والمحرّرُ يكتب الإحداثيّاتِ عند أوّل فتح.
    return TemplateMapper.fromLegacy(
      paper: paper,
      elements: [for (final e in visible) _legacyOf(e)],
      table: table,
    );
  }

  static bool _isPositioned(InvoiceTemplateElement e) =>
      e.bandId != null &&
      e.xMm != null &&
      e.yMm != null &&
      e.wMm != null &&
      e.hMm != null;

  static TemplateDocument _fromBands(
    PaperSpec paper,
    List<InvoiceTemplateElement> elements,
    TableSpec? table,
  ) {
    final buckets = <BandId, List<InvoiceTemplateElement>>{
      for (final id in BandId.values) id: <InvoiceTemplateElement>[],
    };
    for (final e in elements) {
      buckets[_bandOf(e.bandId!)]!.add(e);
    }

    final bands = <TemplateBand>[];
    for (final id in BandId.values) {
      final own = buckets[id]!;
      // ارتفاعُ النطاق = أبعدُ قاعِ عنصرٍ فيه. صفرٌ لنطاقٍ فارغ — يبقى
      // موجوداً كي يجد المحرّرُ مكانَ الإفلات.
      var height = 0.0;
      for (final e in own) {
        final bottom = e.yMm! + e.hMm!;
        if (bottom > height) height = bottom;
      }
      bands.add(
        TemplateBand(
          id: id,
          heightMm: height,
          repeatEachPage: id.repeatsByDefault,
          growsWithData: id.isDetails,
          elements: [
            for (final e in own)
              TemplateElement(
                id: 'el_${e.id}',
                contentKey: contentKeyOf(e),
                xMm: e.xMm!,
                yMm: e.yMm!,
                wMm: e.wMm!,
                hMm: e.hMm!,
                labelAr: _labelOf(e),
                labelEn: e.labelEn,
                fontSize: e.fontSize,
                bold: e.isBold,
                visible: e.isVisible,
                align: _alignOf(e.textAlign),
                colorHex: e.fontColor,
                condition: e.condition,
                structural:
                    isStructuralElement(e.elementType, contentKeyOf(e)),
              ),
          ],
        ),
      );
    }

    return TemplateDocument(paper: paper, bands: bands, table: table);
  }

  static BandId _bandOf(String raw) {
    for (final id in BandId.values) {
      if (id.name == raw) return id;
    }
    // قيمةٌ لا يعرفها البناءُ الحاليّ — تُوضع في البدن لا تُرمى.
    return BandId.info;
  }

  static TextAlignSpec _alignOf(String v) {
    switch (v) {
      case 'left':
      case 'start':
        return TextAlignSpec.start;
      case 'right':
      case 'end':
        return TextAlignSpec.end;
      default:
        return TextAlignSpec.center;
    }
  }

  /// نفسُ اشتقاقِ المفتاح الذي يستعمله المُخطِّط — كي يتطابق المساران.
  static String contentKeyOf(InvoiceTemplateElement e) =>
      TemplateMapper.contentKeyFor(_legacyOf(e));

  static String? _labelOf(InvoiceTemplateElement e) {
    const freeText = {'text', 'footer', 'note', 'label'};
    if (freeText.contains(e.elementType)) {
      final c = e.content?.trim() ?? '';
      if (c.isNotEmpty && c != e.elementType && c != 'footer_text') return c;
    }
    return e.labelAr;
  }

  static LegacyElement _legacyOf(InvoiceTemplateElement e) => LegacyElement(
        elementType: e.elementType,
        content: e.content,
        section: e.section,
        sortOrder: e.sortOrder,
        flexWidth: e.flexWidth,
        fontSize: e.fontSize,
        isBold: e.isBold,
        isVisible: e.isVisible,
        labelAr: e.labelAr,
        labelEn: e.labelEn,
        textAlign: e.textAlign,
        fontColor: e.fontColor,
        condition: e.condition,
      );

  // ═════════════════════════════════════════════════════════════════════════
  // الورق
  // ═════════════════════════════════════════════════════════════════════════

  /// ⚠️ الهامشُ يطابق المسارَ القديمَ عن قصد: ٢ مم للحراريِّ و٤ لغيره
  /// (`templated_invoice_service.dart`). فالفرقُ بين النسختين يبقى في
  /// **التخطيط** وحدَه، لا في هامشٍ لا علاقةَ له بالموضوع.
  static PaperSpec buildPaper(InvoiceTemplate template) {
    final isThermal = template.paperWidth <= 80;

    // العرضُ الصالحُ للطباعة على الحراريّ أقلُّ من عرض الورق: رأسُ الطباعة
    // ~٧٢مم من ٨٠، والباقي هامشٌ عتاديٌّ لا يُطبع فيه.
    final widthMm =
        isThermal ? template.paperWidth - 8 : template.paperWidth;

    final margins = _marginsOf(template.margins, isThermal);
    final h = template.paperHeight;

    // الحراريُّ لفّةٌ تُقصّ عند آخر سطر، و`paperHeight` غيرُ مكتوبٍ في كثيرٍ
    // من ملفّات الأصول — وكلاهما «بلا قاع».
    if (isThermal || h == null || h <= 0) {
      return PaperSpec.continuous(widthMm: widthMm, margins: margins);
    }
    return PaperSpec(widthMm: widthMm, heightMm: h, margins: margins);
  }

  static MarginsMm _marginsOf(String json, bool isThermal) {
    final fallback = isThermal ? 2.0 : 4.0;
    try {
      final m = jsonDecode(json);
      if (m is Map) {
        double v(String k) => (m[k] as num?)?.toDouble() ?? fallback;
        return MarginsMm(
          top: v('top'),
          right: v('right'),
          bottom: v('bottom'),
          left: v('left'),
        );
      }
    } catch (_) {
      // هوامشُ غيرُ صالحةٍ لا تُسقط مطبوعاً — تعود إلى الافتراض.
    }
    return MarginsMm.all(fallback);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // الجدول
  // ═════════════════════════════════════════════════════════════════════════

  /// أعمدةُ الجدول — من `columns_json` إن وُجد، وإلّا من أعلام `show*`.
  ///
  /// و`columns_json == null` تعني «كما كان» بالضبط: نفسُ الأعمدة الثمانية
  /// بنفس نِسَبها وبنفس ترتيبها المقيس على الورق (‏م · الصنف · الكود ·
  /// العدد · السعر · الخصم · الضريبة · الإجمالي، من اليمين).
  static TableSpec? buildTable(InvoiceTableSetting? s, PaperSpec paper) {
    final kind = _kindOf(s?.tableKind);

    final columns = _columnsFrom(s);
    if (columns.isEmpty) return null;

    // العناوينُ الثنائيّةُ تُطفأ على الورق الضيّق — لا مكانَ لسطرين في ٥٨مم.
    final bilingual = paper.widthMm >= narrowPaperMm &&
        columns.any((c) => c.labelEn.isNotEmpty);

    // ⚠️ قيمةٌ واحدةٌ تُحسب مرّةً — لا `s!` بعد فحصٍ على تعبيرٍ آخر.
    //
    // كان هنا `(s?.headerFontSize ?? 9) > 1 ? s!.headerFontSize : 9`: الفحصُ
    // يمرّ بالبديل `9` بينما `s` نفسُها `null`، فينفجر عند `s!`. وقالبٌ بلا
    // إعداداتِ جدولٍ ليس حالةً نادرة — أسقط اثنَي عشرَ ملفَّ أصولٍ في أوّل
    // تشغيل.
    //
    // و`1.0` قيمةٌ مخزَّنةٌ معروفةٌ تعني «غيرُ مضبوط» (قاعدةُ المالك
    // 2026-08-12: المحرّرُ يعرض ٩ وتُخزَّن ١)، فتُعامَل كغياب.
    final stored = s?.headerFontSize;
    final headerSize = (stored == null || stored <= 1) ? 9.0 : stored;

    return TableSpec(
      kind: kind,
      columns: columns,
      fontSize: headerSize,
      headerFontSize: headerSize,
      rowHeightMm: 6,
      bilingualHeaders: bilingual,
      decimalPlaces: 2,
    );
  }

  static TableKind _kindOf(String? raw) {
    switch (raw) {
      case 'ledger':
        return TableKind.ledger;
      case 'report':
        return TableKind.report;
      default:
        return TableKind.items;
    }
  }

  static List<TableColumn> _columnsFrom(InvoiceTableSetting? s) {
    final custom = _columnsFromJson(s?.columnsJson);
    if (custom != null) return custom;

    // ترتيبُ القراءة (‏من حافّة البداية) — مقيسٌ من الورق لا مفترَض.
    return [
      TableColumn(
          key: 'index',
          labelAr: 'م',
          flex: 0.8,
          decimals: 0,
          visible: s?.showIndex ?? false),
      TableColumn(
          key: 'name',
          labelAr: 'الصنف',
          flex: 3.0,
          align: ColumnAlign.start,
          wrap: true,
          visible: s?.showProductName ?? true),
      TableColumn(
          key: 'code',
          labelAr: 'الكود',
          flex: 1.5,
          visible: s?.showProductCode ?? false),
      TableColumn(
          key: 'quantity',
          labelAr: 'العدد',
          flex: 1.0,
          visible: s?.showQuantity ?? true),
      TableColumn(
          key: 'price',
          labelAr: 'السعر',
          flex: 1.2,
          visible: s?.showUnitPrice ?? true),
      TableColumn(
          key: 'discount',
          labelAr: 'الخصم',
          flex: 1.0,
          visible: s?.showDiscount ?? false),
      TableColumn(
          key: 'tax',
          labelAr: 'الضريبة',
          flex: 1.0,
          visible: s?.showTax ?? false),
      TableColumn(
          key: 'total',
          labelAr: 'الإجمالي',
          flex: 1.5,
          visible: s?.showTotal ?? true),
    ];
  }

  static List<TableColumn>? _columnsFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final out = <TableColumn>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final key = e['key'] as String?;
        if (key == null || key.isEmpty) continue;
        out.add(
          TableColumn(
            key: key,
            labelAr: e['labelAr'] as String? ?? '',
            labelEn: e['labelEn'] as String? ?? '',
            flex: (e['flex'] as num?)?.toDouble() ?? 1,
            decimals: (e['decimals'] as num?)?.toInt() ?? 2,
            align: _colAlignOf(e['align'] as String?),
            visible: e['visible'] as bool? ?? true,
            wrap: e['wrap'] as bool? ?? false,
            formula: e['formula'] as String?,
          ),
        );
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      // JSON معطوبٌ لا يُفرِغ الجدول — يعود إلى الأعلام القديمة.
      return null;
    }
  }

  static ColumnAlign _colAlignOf(String? v) {
    switch (v) {
      case 'start':
      case 'left':
        return ColumnAlign.start;
      case 'end':
      case 'right':
        return ColumnAlign.end;
      default:
        return ColumnAlign.center;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // القيمُ والصفوف
  // ═════════════════════════════════════════════════════════════════════════

  /// خريطةُ «مفتاح ⇒ نصّ» لكلِّ مفتاحٍ يستعمله المستندُ فعلاً.
  ///
  /// تُبنى من مفاتيح المستند لا من قائمةٍ مكتوبةٍ في الكود: مفتاحٌ جديدٌ في
  /// قالبٍ جديدٍ يُحَلّ من يومه، ولا تنمو قائمةٌ يُنسى تحديثُها.
  static Map<String, String> buildValues(
    TemplateDocument document,
    PrintPayload payload,
  ) {
    final out = <String, String>{};
    for (final band in document.bands) {
      for (final el in band.elements) {
        if (el.contentKey.isEmpty) continue;
        out[el.contentKey] = resolveContentValue(el.contentKey, payload);
      }
    }
    return out;
  }

  /// صفوفُ الجدول نصّاً — طولُ كلِّ صفٍّ يطابق [TableSpec.visibleColumns].
  static List<List<String>> buildRows(
    List<Map<String, dynamic>> items,
    TableSpec? table,
    int decimals,
  ) {
    if (table == null) return const [];
    final cols = table.visibleColumns;

    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add([
        for (final c in cols) _cell(c, item, i, decimals),
      ]);
    }
    return rows;
  }

  static String _cell(
    TableColumn c,
    Map<String, dynamic> item,
    int index,
    int decimals,
  ) {
    double num0(String k) => (item[k] as num?)?.toDouble() ?? 0;
    String fmt(double v) => v.toStringAsFixed(c.decimals);

    switch (c.key) {
      case 'index':
        return '${index + 1}';
      case 'name':
      case 'product':
        // الملاحظةُ تلحق الاسمَ كما في المسار القديم. وإسقاطُها ليس تفصيلاً
        // تجميليّاً: «بدون ثلج» و«زيادة صوص» تعليماتُ تحضيرٍ يقرؤها المطبخُ
        // من الورقة — وقياسُ الهجرة أظهر ضياعَها في **كلِّ** قالبٍ فيه جدول.
        final name = item['name'] as String? ?? '';
        final note = (item['note'] as String?)?.trim() ?? '';
        return note.isEmpty ? name : '$name\n$note';
      case 'code':
      case 'barcode':
        return item['code'] as String? ?? '';
      case 'quantity':
        // ⚠️ بمنازل العمود لا بالاختصار إلى صحيح.
        //
        // كان هنا «الكميّةُ الصحيحةُ تُكتب ٢ لا ٢٫٠٠» — وهو تحسينٌ معقولٌ في
        // ذاته، لكنّ المسارَ القديم يكتب `2.00`. فكان كلُّ قالبٍ فيه جدولٌ
        // يخرج بعد الهجرة بكميّاتٍ مختلفةِ الشكل عمّا اعتاده المالك. وقاعدةُ
        // الهجرة: **يطبع بعدها نفسَ ما كان يطبعه**، لا ما نراه أجمل.
        return fmt(num0('quantity'));
      case 'price':
        return fmt(num0('price'));
      case 'discount':
        return fmt(num0('discount'));
      case 'tax':
        return fmt(num0('tax'));
      case 'total':
        return fmt(num0('total'));
      case 'note':
        return item['note'] as String? ?? '';
      default:
        final v = item[c.key];
        if (v == null) return '';
        if (v is num) return v.toDouble().toStringAsFixed(c.decimals);
        return '$v';
    }
  }
}
