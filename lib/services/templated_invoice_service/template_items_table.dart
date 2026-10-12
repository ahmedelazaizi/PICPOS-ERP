// TemplatedInvoiceService - items table, element styles and measurement handles.
part of '../templated_invoice_service.dart';

/// Items table, style helpers and the measurement handles of [TemplatedInvoiceService].
abstract final class _TemplatedItemsTable {
  /// بايتاتُ جدولِ الأصناف كما يُرسَم فعلاً — **مِقبضٌ للقياس لا مسارُ إنتاج.**
  ///
  /// `printWithTemplate` يبني `pw.Document` ويدفعه إلى `Printing.*` مباشرةً،
  /// فلا تُرجع الوثيقةَ ولا البايتات. ولذلك كانت حراسُ المطبوع **بنيويةً**
  /// تمنع العودةَ ولا تثبت الخروج. وحين وصل بلاغُ «صفُّ عناوين الأعمدة لا
  /// يظهر في الطباعة» لم يكن ثمّة سبيلٌ لرسم المستند والنظر إليه — وهي
  /// الخطوةُ التي كشفت عطبَ الخطوط بعد ثلاث فرضياتٍ معقولةٍ خاطئة.
  ///
  /// فهذا يبني **نفسَ** الجدول بنفس الدالّة (`_buildItemsTable`) وبنفس هيئة
  /// الورق الحراريّ، ويعيد البايتات كي تُرسَّم وتُفحَص. لا يستنسخ منطقاً:
  /// أيُّ تغييرٍ في الجدول يظهر هنا فوراً.
  /// نمطُ عنصرٍ كما يصل الورقةَ — للقياس الآليّ لوجه الخطّ.
  ///
  /// النيّةُ (`fontWeight`) لم تكن يوماً هي المشكلة؛ **الوجهُ** هو الذي كان
  /// يخون. فيُقاس ما يُرسَم لا ما يُقصَد.
  static Future<pw.TextStyle> debugStyleFor({required bool isBold}) async {
    await _initFont();
    return _getStyle(InvoiceTemplateElement(
      id: 0,
      templateId: 0,
      elementType: 'variable',
      rowIndex: 0,
      sortOrder: 0,
      flexWidth: 100,
      xPosition: 0,
      yPosition: 0,
      width: 100,
      height: 20,
      textAlign: 'right',
      fontSize: 12,
      isBold: isBold,
      isItalic: false,
      fontColor: '#000000',
      borderWidth: 0,
      content: 'total_amount',
      isVisible: true,
      section: 'footer',
    ));
  }

  static Future<Uint8List> debugRenderItemsTable({
    required List<Map<String, dynamic>> items,
    InvoiceTableSetting? settings,
    double paperWidthMm = 79,
  }) async {
    await _initFont();
    const mmToPoints = 2.8346;
    final baseStyle = pw.TextStyle(font: _arabicFont, fontSize: 8);
    // `BaseGenerator.newDocument()` لا `pw.Document()` عارياً — وهو ما يستعمله
    // مسارُ الإنتاج في هذا الملفّ (‏السطران ٣٥٢ و١٥٩٣). المستندُ العاري بلا
    // ثيمٍ يرسم بخطٍّ واحدٍ لكلّ النصّ ويحذف الرسمَ الناقصَ بالسكوت، فمِقبضٌ
    // للقياس يبني بغير ما يبني به الإنتاجُ يقيس مستنداً آخر.
    // (‏حارسُ `no_bare_pdf_document_test` اصطاد هذا هنا فعلاً.)
    final pdf = await BaseGenerator.newDocument();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          paperWidthMm * mmToPoints,
          double.infinity,
          marginAll: 2.0 * mmToPoints,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (_) => _buildItemsTable(items, settings, baseStyle),
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    InvoiceTableSetting? settings,
    pw.TextStyle baseStyle,
  ) {
    final showIndex = settings?.showIndex ?? false;
    final showName = settings?.showProductName ?? true;
    final showCode = settings?.showProductCode ?? false;
    final showQty = settings?.showQuantity ?? true;
    final showPrice = settings?.showUnitPrice ?? true;
    final showDiscount = settings?.showDiscount ?? false;
    final showTax = settings?.showTax ?? false;
    final showTotalCol = settings?.showTotal ?? true;

    // Parse custom flex ratios and _decimalPlaces from JSON
    final defaultWidths = <String, double>{
      'index': 0.8,
      'product': 3.0,
      'code': 1.5,
      'quantity': 1.0,
      'price': 1.2,
      'discount': 1.0,
      'tax': 1.0,
      'total': 1.5,
    };
    // §٥-٣ — الدقّةُ محسومةٌ للمستند كلِّه في `_docDecimals` (انظر تعليقَه
    // فوق). كانت تُحسم هنا وحدَها فتفترق عن الإجماليات في نفس الورقة.
    int decimalPlaces = _docDecimals;
    bool headerBold = true;  // Default: header is bold
    bool bodyBold = false;   // Default: body is normal
    bool showHeader = true;  // Default: show header row
    // ⚠️ كان `try` واحدٌ يلفّ فكَّ المفاتيح كلَّها مع `value as bool?` —
    // فقيمةٌ مخزَّنةٌ `1` بدل `true` ترمي، فتُبتلع الرميةُ وتضيع معها
    // **عروضُ الأعمدة والدقّةُ وكلُّ الأعلام** دفعةً واحدة: تصميمٌ مسطَّحٌ
    // بلا رسالةِ خطأٍ واحدة. `parseTableFlags` تعزل كلَّ مفتاحٍ وتتسامح مع
    // الأرقام والنصوص. اقرأ `core/utils/template_json_flags.dart`.
    final flags = parseTableFlags(settings?.columnWidths);
    defaultWidths.addAll(flags.columnWidths);
    decimalPlaces = flags.decimalPlaces ?? decimalPlaces;
    headerBold = flags.headerBold ?? headerBold;
    bodyBold = flags.bodyBold ?? bodyBold;
    showHeader = flags.showHeader ?? showHeader;

    // Number formatter helper
    String fmt(num val) => val.toStringAsFixed(decimalPlaces);

    // Build column widths using Flex ratios — proportional to content importance.
    // Product name gets the most space. Numbers get less.
    // Columns are ordered RTL (reversed) in the cell builders below,
    // so column indices map naturally: 0 = rightmost (last visual column).
    int colIdx = 0;
    final Map<int, pw.TableColumnWidth> colWidths = {};
    // Order: Total | Tax | Discount | Price | Qty | Code | Name | Index
    // (cells already reversed for RTL in the builders below)
    if (showTotalCol) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['total']!);
    if (showTax) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['tax']!);
    if (showDiscount) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['discount']!);
    if (showPrice) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['price']!);
    if (showQty) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['quantity']!);
    if (showCode) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['code']!);
    if (showName) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['product']!);
    if (showIndex) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['index']!);

    // final totalCols = colIdx;

    // Count enabled columns — auto-reduce header font for cramped layouts
    int enabledCols = 0;
    if (showIndex) enabledCols++;
    if (showName) enabledCols++;
    if (showCode) enabledCols++;
    if (showQty) enabledCols++;
    if (showPrice) enabledCols++;
    if (showDiscount) enabledCols++;
    if (showTax) enabledCols++;
    if (showTotalCol) enabledCols++;

    // Use font sizes from settings — clamp to reasonable range for thermal paper
    // Auto-reduce header font when many columns are enabled
    // ⚠️ الحدُّ الأدنى كان `1.0` — أي أن مقاساً فاسداً يُقبل كما هو فيصير
    // صفُّ العناوين موجوداً في الوثيقة وغيرَ مرئيٍّ على الورق. قِيس في
    // قاعدة المالك 2026-08-12: `header_font_size = 1.0` والمحرّرُ يعرض 9.
    final headerFontSize =
        resolveHeaderFontSize(settings?.headerFontSize, enabledColumns: enabledCols);
    final bodyFontSize = (settings?.fontSize ?? 8.0).clamp(1.0, 24.0);
    // ── صفُّ العناوين: حبرٌ لا تعبئة ──────────────────────────────────────
    //
    // البلاغ الميدانيّ (2026-08-11): «صفُّ عناوين أعمدة الجدول لا يظهر في
    // الطباعة». ورسمُ المستند بـ`Windows.Data.Pdf` أثبت أن **الصفَّ موجودٌ
    // في الوثيقة وواضح** — فنفى كلَّ فرضيات الكود (‏`_showHeader` معطَّل ·
    // `headerFontSize` مقصورٌ إلى ١pt · القالبُ بلا صفّ). بقي تفسيرٌ واحد:
    // النصُّ كان **أبيضَ** يتّكئ على تعبئةٍ سوداء، والطابعةُ الحرارية تُسقط
    // تعبئةَ الخلفية ⇒ أبيضُ على ورقٍ أبيض.
    //
    // فالعناوينُ الآن سوداءُ عريضة، والفصلُ من حدود الجدول القائمة لا من
    // مساحةٍ ملوّنة. يُطبع على كلّ جهازٍ سواءٌ رسم التعبئةَ أم أسقطها —
    // **لا يُعتمد على ما قد لا يصل إلى الورق.**
    final headerStyle = baseStyle.copyWith(
      font: _arabicBoldFont ?? baseStyle.font,
      fontWeight: pw.FontWeight.bold,
      fontSize: headerFontSize,
      color: PdfColors.black,
    );
    final bodyStyle = baseStyle.copyWith(
      fontWeight: bodyBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bodyFontSize,
    );

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: colWidths,
      children: [
        // Header (cells in RTL order — rightmost visual column first)
        if (showHeader)
        pw.TableRow(
          // `repeat: true` — الجدولُ ينقسم على صفحات A4، وبلا التكرار تخرج
          // الصفحةُ الثانيةُ أرقاماً بلا رؤوسٍ لا يُعرف أيُّها الكمّيةُ وأيُّها
          // السعر. ولا أثرَ له على الحراريّ: لفّةٌ لا تنقسم أصلاً.
          repeat: true,
          // بلا تعبئة — انظر `headerStyle` فوق. و`headerBold` صار لا يُقرأ
          // هنا قصداً: العناوينُ عريضةٌ دائماً لأن العَرْضَ هو ما يفصلها عن
          // البدن بعد زوال المساحة الملوّنة.
          children: [
            if (showTotalCol)
              _tableCell(
                '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a',
                headerStyle,
              ),
            if (showTax)
              _tableCell(
                '\u0627\u0644\u0636\u0631\u064a\u0628\u0629',
                headerStyle,
              ),
            if (showDiscount)
              _tableCell('\u0627\u0644\u062e\u0635\u0645', headerStyle),
            if (showPrice)
              _tableCell('\u0627\u0644\u0633\u0639\u0631', headerStyle),
            if (showQty)
              _tableCell('العدد', headerStyle),
            if (showCode)
              _tableCell('\u0627\u0644\u0643\u0648\u062f', headerStyle),
            if (showName)
              _tableCell('\u0627\u0644\u0635\u0646\u0641', headerStyle),
            if (showIndex) _tableCell('\u0645', headerStyle),
          ],
        ),
        ...items.asMap().entries.expand((entry) {
          final idx = entry.key + 1;
          final item = entry.value;
          final itemNote = item['note']?.toString() ?? '';
          
          final formattedNote = itemNote.replaceAll(' | ', '\n').replaceAll('📝 ', '\nملاحظة: ').trim();

          pw.Widget productNameWidget() {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: formattedNote.isNotEmpty
                ? pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        item['name']?.toString() ?? '',
                        style: bodyStyle,
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        formattedNote,
                        style: bodyStyle.copyWith(
                          fontSize: (bodyStyle.fontSize ?? 10) >= 8.0 ? (bodyStyle.fontSize ?? 10) - 2.0 : 6.0,
                          fontWeight: pw.FontWeight.normal,
                          color: PdfColors.black,
                          lineSpacing: 0.5,
                        ),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  )
                : pw.Text(
                    item['name']?.toString() ?? '',
                    style: bodyStyle,
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
            );
          }

          // فاصلُ تصنيفٍ لا صنف: سطرٌ واحدٌ بعرض الجدول، عنوانُه في الوسط —
          // كما يرسمه المسارُ الحراريُّ تماماً (`— الاسم —`). وبلا هذا كان
          // يُطبع صنفاً بكمّية صفرٍ وسعرٍ صفر.
          if (TemplatedInvoiceService.isCategoryHeaderRow(item)) {
            // العنوانُ يقع في **عمود الصنف** — أعرضُ الأعمدة وموضعُ الاسم —
            // وبقيةُ الخلايا فارغة. و`pw.Table` لا يدعم دمجَ الأعمدة، فهذا
            // أقربُ ما يُطابق المسارَ الحراريّ بلا كسر الشبكة.
            // ⚠️ وعددُ الخلايا يجب أن يساوي عددَ الأعمدة تماماً.
            final nameCell = pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              alignment: pw.Alignment.center,
              child: pw.Text(
                '— ${item['name'] ?? ''} —',
                style: headerStyle,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            );
            return [
              pw.TableRow(
                children: [
                  if (showTotalCol) pw.SizedBox(),
                  if (showTax) pw.SizedBox(),
                  if (showDiscount) pw.SizedBox(),
                  if (showPrice) pw.SizedBox(),
                  if (showQty) pw.SizedBox(),
                  if (showCode) pw.SizedBox(),
                  if (showName) nameCell,
                  if (showIndex) pw.SizedBox(),
                ],
              ),
            ];
          }

          final rows = <pw.TableRow>[
            pw.TableRow(
              children: [
                if (showTotalCol) _tableCell(fmt(item['total'] ?? 0), bodyStyle),
                if (showTax) _tableCell(fmt(item['tax'] ?? 0), bodyStyle),
                if (showDiscount)
                  _tableCell(fmt(item['discount'] ?? 0), bodyStyle),
                if (showPrice) _tableCell(fmt(item['price'] ?? 0), bodyStyle),
                if (showQty) _tableCell(fmt(item['quantity'] ?? 1), bodyStyle),
                if (showCode)
                  _tableCell(item['code']?.toString() ?? '', bodyStyle),
                if (showName) productNameWidget(),
                if (showIndex) _tableCell('$idx', bodyStyle),
              ],
            ),
          ];

          return rows;
        }),
      ],
    );
  }

  static pw.Widget _tableCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _totalRow(
    String label,
    double value,
    pw.TextStyle style,
    pw.TextAlign align, {
    bool isSubtraction = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Flexible(
            child: pw.Text(label, style: style),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            '${isSubtraction ? "-" : ""}${value.toStringAsFixed(_docDecimals)}',
            style: style,
          ),
        ],
      ),
    );
  }

  static pw.TextStyle _getStyle(InvoiceTemplateElement element) {
    // Clamp font size for thermal-safe rendering (max 12pt).
    // The designer may allow larger sizes for preview, but 79mm paper
    // can't fit long Arabic labels at 14-18pt without overflow.
    final fontSize = element.fontSize.clamp(1.0, 24.0);
    // ⚠️ `font:` مع `fontWeight: bold` فخّ: الحزمةُ تُركّب الخطَّ الممرَّر في
    // **خانة العريض** (`text_style.dart:150-153`)، فيدهس الدمجُ وجهَ الثيم
    // العريضَ الحقيقيّ ويُرسم كلُّ «عريض» عادياً. الوجهُ يُنتقى صراحةً.
    return pw.TextStyle(
      font: element.isBold ? (_arabicBoldFont ?? _arabicFont) : _arabicFont,
      fontSize: fontSize,
      fontWeight: element.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: _parseColor(element.fontColor),
    );
  }

  static pw.TextAlign _getAlignment(String? alignment) {
    switch (alignment) {
      case 'left':
        return pw.TextAlign.left;
      case 'center':
        return pw.TextAlign.center;
      case 'right':
      default:
        return pw.TextAlign.right;
    }
  }

  static PdfColor _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return PdfColor.fromInt(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return PdfColors.black;
    }
  }
}
