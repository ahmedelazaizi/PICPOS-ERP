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
    double? weight,
    double? total,
    DateTime? packDate,
    String? companyName,
    int copies = 1,
    bool directPrint = true,
    int? templateId,
    @visibleForTesting bool debugBuildOnly = false,
    @visibleForTesting void Function(Uint8List bytes)? onDebugBytes,
    @visibleForTesting
    Future<bool> Function(Uint8List bytes, String name)? pdfSender,
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

    final pdf = await BaseGenerator.newDocument();
    final labelFormat = PdfPageFormat(labelWidth, labelHeight);

    for (var copy = 0; copy < copies; copy++) {
      pdf.addPage(
        pw.Page(
          pageFormat: labelFormat,
          margin: pw.EdgeInsets.zero,
          // طابعة الملصق تتلقى صفحةً واحدةً بمقاس الورق الفعلي لكل نسخة.
          textDirection: pw.TextDirection.rtl,
          build: (context) => _buildSingleBarcodeLabel(
            elements: elements,
            labelWidth: labelWidth,
            labelHeight: labelHeight,
            labelWidthMM: labelWidthMM,
            labelHeightMM: labelHeightMM,
            barcodeValue: barcodeValue,
            productName: productName,
            productCode: productCode,
            price: price,
            weight: weight,
            total: total,
            packDate: packDate,
            companyName: companyName,
          ),
        ),
      );
    }

    final bytes = await PdfComputeHelper.saveToBytes(pdf);
    if (debugBuildOnly) {
      onDebugBytes?.call(bytes);
      return false;
    }
    final sender = pdfSender;
    if (sender != null) {
      return sender(bytes, 'Barcode_${barcodeValue}_x$copies');
    }
    // ⚠️ **مقاسُ الورقة يُمرَّر للسائق صراحةً** — الصفحةُ بمقاس الملصق لا
    // تكفي. حزمةُ `printing` على Windows تبني `DEVMODE` من `format` وحده
    // (‏الافتراضُ `PdfPageFormat.standard` = A4)، ثم ترسم صفحةَ الـPDF بمقاسها
    // الأصليّ في ركن تلك الورقة. فكان ملصقُ ٥٨×٤٠ يخرج صغيراً أعلى يسار
    // صفحة A4 مع أنّ MediaBox الملف سليم (‏التحقّق الحيّ 2026-11-03).
    if (directPrint) {
      final printerName = await PrinterResolver.resolveByPurpose(
        PrintersRepositoryImpl(db),
        'barcode',
      );
      return PdfComputeHelper.directPrintBytes(
        printer: printerName ?? (await Printing.listPrinters()).first,
        bytes: bytes,
        name: 'Barcode_${barcodeValue}_x$copies',
        format: labelFormat,
      );
    }
    return PdfComputeHelper.layoutBytes(
      bytes,
      name: 'Barcode_${barcodeValue}_x$copies',
      format: labelFormat,
    );
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
    double? weight,
    double? total,
    DateTime? packDate,
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
          if (el.content == 'ean13') {
            contentWidget = pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.BarcodeWidget(
                  data: barcodeValue,
                  barcode: barcodeType,
                  width: w,
                  height: h * 0.68,
                  drawText: false,
                ),
                pw.Text(
                  barcodeValue,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(font: _arabicFont, fontSize: el.fontSize),
                ),
              ],
            );
          } else {
            contentWidget = pw.BarcodeWidget(
              data: barcodeValue,
              barcode: barcodeType,
              width: w,
              height: h * 0.8,
              drawText: true,
              textStyle: pw.TextStyle(font: _arabicFont, fontSize: el.fontSize),
            );
          }
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
        case 'scale_weight':
          contentWidget = pw.Text(
            '${el.labelAr ?? 'الوزن'}: ${weight?.toStringAsFixed(3) ?? ''} kg',
            style: style,
            textAlign: align,
          );
          break;
        case 'scale_unit_price':
          contentWidget = pw.Text(
            '${el.labelAr ?? 'سعر الوحدة / كجم'}: ${price?.toStringAsFixed(_docDecimals) ?? ''}',
            style: style,
            textAlign: align,
          );
          break;
        case 'scale_total':
          contentWidget = pw.Text(
            '${el.labelAr ?? 'الإجمالي'}: ${total?.toStringAsFixed(_docDecimals) ?? ''}',
            style: style,
            textAlign: align,
          );
          break;
        case 'scale_pack_date':
          final date = packDate ?? DateTime.now();
          contentWidget = pw.Text(
            '${el.labelAr ?? 'تاريخ التعبئة'}: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
            style: style,
            textAlign: align,
          );
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
