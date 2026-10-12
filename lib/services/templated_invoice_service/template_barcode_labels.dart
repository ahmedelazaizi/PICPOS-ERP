// TemplatedInvoiceService - barcode label printing.
part of '../templated_invoice_service.dart';

/// Barcode label printing of [TemplatedInvoiceService].
abstract final class _TemplatedBarcodeLabels {
  static Future<bool> printBarcodeWithTemplate({
    required AppDatabase db,
    required String barcodeValue,
    required String productName,
    String? productCode,
    double? price,
    String? companyName,
    int copies = 1,
    bool directPrint = true,
    int? templateId,
  }) async {
    await _initFont();

    // Find template
    InvoiceTemplateWithData? templateData;
    if (templateId != null) {
      final t = await db.getTemplateById(templateId);
      if (t != null) {
        final elements = await db.getTemplateElements(templateId);
        templateData = InvoiceTemplateWithData(template: t, elements: elements);
      }
    }
    templateData ??= await db.getDefaultTemplateWithDataByCategory(
      'thermal',
      'barcode',
    );

    if (templateData == null) {
      debugPrint('[BarcodeTemplate] No barcode template found');
      return false;
    }

    final template = templateData.template;
    final elements = templateData.elements;

    // Label dimensions in mm → points
    final labelWidthMM = template.paperWidth;
    final labelHeightMM = template.paperHeight ?? 25.0;
    final labelWidth = labelWidthMM * PdfPageFormat.mm;
    final labelHeight = labelHeightMM * PdfPageFormat.mm;

    // Calculate grid layout on A4
    const pageMargin = 10.0;
    const a4Width = 210.0 * PdfPageFormat.mm;
    const a4Height = 297.0 * PdfPageFormat.mm;
    const usableWidth = a4Width - (2 * pageMargin);
    const usableHeight = a4Height - (2 * pageMargin);

    final labelsPerRow = (usableWidth / (labelWidth + 2)).floor().clamp(1, 20);
    final labelsPerCol = (usableHeight / (labelHeight + 2)).floor().clamp(
      1,
      40,
    );
    final labelsPerPage = labelsPerRow * labelsPerCol;
    final totalPages = (copies / labelsPerPage).ceil();

    final pdf = await BaseGenerator.newDocument();

    for (int page = 0; page < totalPages; page++) {
      final labelsOnThisPage = (page == totalPages - 1)
          ? copies - (page * labelsPerPage)
          : labelsPerPage;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(pageMargin),
          // بدونه تؤول الصفحةُ إلى LTR فلا تُشكَّل العربيةُ ولا يُعاد
          // ترتيبُها: اسمُ الصنف يخرج بحروفٍ منفصلةٍ ومقلوبِ الترتيب على
          // **كلّ ملصقِ باركود**. مقيسٌ بالرسم: «صبري» ⇒ «يربص».
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Wrap(
            spacing: 2,
            runSpacing: 2,
            children: List.generate(
              labelsOnThisPage,
              (_) => _buildSingleBarcodeLabel(
                elements: elements,
                labelWidth: labelWidth,
                labelHeight: labelHeight,
                labelWidthMM: labelWidthMM,
                labelHeightMM: labelHeightMM,
                barcodeValue: barcodeValue,
                productName: productName,
                productCode: productCode,
                price: price,
                companyName: companyName,
              ),
            ),
          ),
        ),
      );
    }

    if (directPrint) {
      final printerName = await PrinterResolver.resolveByPurpose(PrintersRepositoryImpl(db), 'barcode');
      await Printing.directPrintPdf(
        printer: printerName ?? (await Printing.listPrinters()).first,
        onLayout: (format) async => pdf.save(),
        name: 'Barcode_${barcodeValue}_x$copies',
      );
    } else {
      return PdfComputeHelper.layoutPdf(pdf, name: 'Barcode_${barcodeValue}_x$copies');
    }
    // الإرسالُ المباشرُ إلى طابعةٍ مضبوطةٍ لا يُلغى من حوار.
    return true;
  }

  /// Build a single barcode label from template elements
  static pw.Widget _buildSingleBarcodeLabel({
    required List<InvoiceTemplateElement> elements,
    required double labelWidth,
    required double labelHeight,
    required double labelWidthMM,
    required double labelHeightMM,
    required String barcodeValue,
    required String productName,
    String? productCode,
    double? price,
    String? companyName,
  }) {
    // Scale factor from mm units (template coords) to points
    final scaleX = labelWidth / labelWidthMM;
    final scaleY = labelHeight / labelHeightMM;

    final children = <pw.Widget>[];
    for (final el in elements) {
      final x = el.xPosition * scaleX;
      final y = el.yPosition * scaleY;
      final w = el.width * scaleX;
      final h = el.height * scaleY;

      // نفسُ فخّ `_getStyle`: الوجهُ يُنتقى صراحةً وإلا رُسم العريضُ عادياً.
      final style = pw.TextStyle(
        font: el.isBold ? (_arabicBoldFont ?? _arabicFont) : _arabicFont,
        fontSize: el.fontSize,
        fontWeight: el.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: el.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        color: _TemplatedItemsTable._parseColor(el.fontColor),
      );
      final align = _TemplatedItemsTable._getAlignment(el.textAlign);

      pw.Widget? contentWidget;
      final type = el.elementType;

      switch (type) {
        case 'product_name':
          final displayName = productName.length > 30
              ? '${productName.substring(0, 30)}...'
              : productName;
          contentWidget = pw.Text(
            displayName,
            style: style,
            textAlign: align,
            maxLines: 2,
          );
          break;
        case 'product_code':
          contentWidget = pw.Text(
            productCode ?? barcodeValue,
            style: style,
            textAlign: align,
          );
          break;
        case 'barcode_image':
          final barcodeType = _resolveBarcodeType(el.content);
          contentWidget = pw.BarcodeWidget(
            data: barcodeValue,
            barcode: barcodeType,
            width: w,
            height: h * 0.8,
            drawText: true,
            textStyle: pw.TextStyle(font: _arabicFont, fontSize: el.fontSize),
          );
          break;
        case 'product_price':
          if (price != null) {
            contentWidget = pw.Text(
              price.toStringAsFixed(_docDecimals),
              style: style,
              textAlign: align,
            );
          } else {
            contentWidget = pw.SizedBox();
          }
          break;
        case 'company_name':
          contentWidget = pw.Text(
            companyName ?? '',
            style: style,
            textAlign: align,
          );
          break;
        case 'text':
          contentWidget = pw.Text(
            el.content ?? '',
            style: style,
            textAlign: align,
          );
          break;
        case 'line':
        case 'divider':
          contentWidget = pw.Container(
            width: w,
            height: 0.5,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
          );
          break;
        case 'rectangle':
          contentWidget = pw.Container(
            width: w,
            height: h,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                width: el.borderWidth > 0 ? el.borderWidth : 0.5,
              ),
            ),
          );
          break;
        default:
          contentWidget = pw.Text(
            el.content ?? '',
            style: style,
            textAlign: align,
          );
      }

      children.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.SizedBox(width: w, child: contentWidget),
        ),
      );
    }

    return pw.Container(
      width: labelWidth,
      height: labelHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
      ),
      child: pw.Stack(children: children),
    );
  }

  /// Resolve barcode type from template content string
  static pw.Barcode _resolveBarcodeType(String? type) {
    switch (type) {
      case 'ean13':
        return pw.Barcode.ean13();
      case 'ean8':
        return pw.Barcode.ean8();
      case 'upcA':
        return pw.Barcode.upcA();
      case 'code39':
        return pw.Barcode.code39();
      case 'code93':
        return pw.Barcode.code93();
      case 'codabar':
        return pw.Barcode.codabar();
      case 'qrCode':
        return pw.Barcode.qrCode();
      case 'code128':
      default:
        return pw.Barcode.code128();
    }
  }
}
