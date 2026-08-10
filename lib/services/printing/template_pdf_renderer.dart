import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../generators/base_generator.dart' show BaseGenerator;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import '../../data/database/database.dart' hide Printer;
import '../../domain/repositories/printers_repository.dart';
import '../../core/constants/app_constants.dart';
import '../printer_resolver.dart';
import '../license_service.dart';
import 'printing_models.dart';

/// Invoice data container passed to the template renderer.
class TemplateInvoiceData {
  final String invoiceNumber;
  final DateTime date;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final double remaining;
  final double deliveryFee;
  final String? companyName;
  final String? companyNameEn;
  final String? companyPhone;
  final String? companyAddress;
  final String? taxId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? employeeName;
  final String? salesType;
  final String? paymentMethod;
  final String? footerText;
  final String? receiptCodeType;
  final String? notes;
  final String? courierName;
  final String? courierPhone;
  final bool isDelivery;
  final int? orderNumber;
  final String locale; // 'ar' or 'en'

  const TemplateInvoiceData({
    required this.invoiceNumber,
    required this.date,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    required this.total,
    required this.paid,
    this.remaining = 0,
    this.deliveryFee = 0,
    this.companyName,
    this.companyNameEn,
    this.companyPhone,
    this.companyAddress,
    this.taxId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.employeeName,
    this.salesType,
    this.paymentMethod,
    this.footerText,
    this.receiptCodeType,
    this.notes,
    this.courierName,
    this.courierPhone,
    this.isDelivery = false,
    this.orderNumber,
    this.locale = 'ar',
  });
}

/// Renders a PDF from a user-designed invoice template.
///
/// Reads [InvoiceTemplateWithData] (template + elements + table settings)
/// and generates a matching PDF, using the absolute positions and styles
/// the user configured in the visual editor.
class TemplatePdfRenderer {
  static pw.Font? _arabicFont;

  static Future<pw.Font> _initFont() async {
    if (_arabicFont != null) return _arabicFont!;

    // ① Load from bundled asset (works offline)
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _arabicFont = pw.Font.ttf(fontData);
      return _arabicFont!;
    } catch (_) {}

    // ② Fallback: Google Fonts (requires internet)
    try {
      _arabicFont = await printing_pkg.PdfGoogleFonts.cairoRegular();
      return _arabicFont!;
    } catch (_) {}

    // ③ Last resort: Helvetica — NOT cached so next call retries
    debugPrint('[TemplatePDF] WARNING: Arabic font unavailable');
    return pw.Font.helvetica();
  }

  /// Main entry: print using template + real data.
  static Future<void> printFromTemplate({
    required InvoiceTemplateWithData templateData,
    required TemplateInvoiceData invoiceData,
    bool directPrint = false,
    IPrintersRepository? printersRepo,
  }) async {
    final pdfBytes = await generatePdf(
      templateData: templateData,
      invoiceData: invoiceData,
    );

    if (directPrint || printersRepo != null) {
      printing_pkg.Printer? resolvedPrinter;
      if (printersRepo != null) {
        resolvedPrinter =
            await PrinterResolver.resolveReceiptPrinter(printersRepo);
      }
      if (resolvedPrinter != null) {
        await printing_pkg.Printing.directPrintPdf(
          printer: resolvedPrinter,
          onLayout: (format) async => pdfBytes,
        );
        return;
      }
    }
    await printing_pkg.Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
    );
  }

  /// Generate PDF bytes from template.
  static Future<Uint8List> generatePdf({
    required InvoiceTemplateWithData templateData,
    required TemplateInvoiceData invoiceData,
  }) async {
    final font = await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final template = templateData.template;

    // Paper dimensions (mm to points)
    const mmToPt = 72.0 / 25.4;
    final paperWidth = (template.paperWidth) * mmToPt;
    final margins = _parseMargins(template.margins);

    final pageFormat = PdfPageFormat(
      paperWidth,
      double.infinity,
      marginTop: margins['top']! * mmToPt,
      marginRight: margins['right']! * mmToPt,
      marginBottom: margins['bottom']! * mmToPt,
      marginLeft: margins['left']! * mmToPt,
    );

    // Sort elements by Y, then X
    final sortedElements = List<InvoiceTemplateElement>.from(
      templateData.elements.where((e) => e.isVisible),
    )..sort((a, b) {
        final dy = a.yPosition.compareTo(b.yPosition);
        return dy != 0 ? dy : a.xPosition.compareTo(b.xPosition);
      });

    // Render each element sequentially (no row-grouping)
    // Avoids pw.Row+Expanded squeezing that garbles Arabic text
    final contentWidgets = <pw.Widget>[];

    for (final el in sortedElements) {
      contentWidgets.add(_buildFlowElement(el, font, invoiceData));
    }

    // Insert the items table at its relative position
    if (templateData.tableSettings != null) {
      _insertItemsTable(
        contentWidgets,
        templateData.tableSettings!,
        font,
        invoiceData,
        sortedElements,
      );
    }

    // Trial watermark
    if (LicenseService.showWatermark) {
      contentWidgets.add(pw.SizedBox(height: 4));
      contentWidgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.red, width: 1),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            'نسخة تجريبية — TRIAL VERSION',
            style: pw.TextStyle(
              font: font,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: contentWidgets,
        ),
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ELEMENT RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Render a single element as a flow widget (not absolute positioned).
  static pw.Widget _buildFlowElement(
    InvoiceTemplateElement el,
    pw.Font font,
    TemplateInvoiceData data,
  ) {
    final style = pw.TextStyle(
      font: font,
      fontSize: el.fontSize,
      fontWeight: el.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: el.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
      color: _parseColor(el.fontColor),
    );

    final align = _textAlign(el.textAlign);

    switch (el.elementType) {
      // ── Visual elements ──
      case 'divider':
      case 'line':
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Divider(thickness: 0.5),
        );

      case 'rectangle':
        return pw.Container(
          height: el.height,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1),
          ),
        );

      case 'logo':
      case 'image':
        return pw.Container(
          height: el.height,
          alignment: pw.Alignment.center,
          child: pw.Text('LOGO', style: pw.TextStyle(font: font, fontSize: 14)),
        );

      case 'barcode':
        final barcodeData = _resolveValue(el, data) ?? data.invoiceNumber;
        return pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: barcodeData,
            width: el.width.clamp(80, 200),
            height: el.height.clamp(20, 40),
            textStyle: pw.TextStyle(font: font, fontSize: 6),
          ),
        );

      case 'qr_code':
        final qrData = _resolveValue(el, data) ?? data.invoiceNumber;
        return pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            width: el.width.clamp(40, 80),
            height: el.height.clamp(40, 80),
          ),
        );

      // ── All text-based elements ──
      default:
        final text = _resolveValue(el, data) ?? '';
        if (text.isEmpty) return pw.SizedBox.shrink();
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Text(
            text,
            style: style,
            textAlign: align,
          ),
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA RESOLUTION — Maps element types to actual invoice values
  // ═══════════════════════════════════════════════════════════════════════════

  static String? _resolveValue(
    InvoiceTemplateElement el,
    TemplateInvoiceData data,
  ) {
    final isEn = data.locale == 'en';
    final label = isEn ? (el.labelEn ?? el.labelAr ?? '') : (el.labelAr ?? el.labelEn ?? '');
    final formatter = intl.NumberFormat('#,##0.00');
    final dateStr = '${data.date.day}/${data.date.month}/${data.date.year}';
    final timeStr =
        '${data.date.hour.toString().padLeft(2, '0')}:${data.date.minute.toString().padLeft(2, '0')}';

    String withLabel(String value) =>
        label.isNotEmpty ? '$label: $value' : value;

    switch (el.elementType) {
      case 'company_name':
        return isEn ? (data.companyNameEn ?? data.companyName ?? 'Company Name') : (data.companyName ?? 'اسم الشركة');
      case 'company_address':
        return data.companyAddress ?? '';
      case 'company_phone':
        return data.companyPhone ?? '';
      case 'invoice_number':
        return withLabel(data.invoiceNumber);
      case 'date':
        return withLabel(dateStr);
      case 'time':
        return withLabel(timeStr);
      case 'customer':
        final name = data.customerName ?? (isEn ? 'Cash Customer' : 'عميل نقدي');
        return withLabel(name);
      case 'cashier_name':
        return data.employeeName != null ? withLabel(data.employeeName!) : null;
      case 'subtotal':
        return withLabel(formatter.format(data.subtotal));
      case 'discount':
        return data.discount > 0
            ? withLabel(formatter.format(data.discount))
            : null;
      case 'tax':
        return data.tax > 0 ? withLabel(formatter.format(data.tax)) : null;
      case 'total':
        return withLabel(formatter.format(data.total));
      case 'paid':
        return withLabel(formatter.format(data.paid));
      case 'remaining':
        return data.remaining > 0
            ? withLabel(formatter.format(data.remaining))
            : withLabel('0.00');
      case 'sale_type':
        return data.salesType != null && data.salesType!.isNotEmpty && data.salesType != 'default'
            ? withLabel(_mapOrderTypeLabel(data.salesType))
            : null;
      case 'order_type':
        return data.salesType != null && data.salesType!.isNotEmpty
            ? withLabel(_mapOrderTypeLabel(data.salesType))
            : null;
      case 'payment_method':
        return data.paymentMethod != null
            ? withLabel(data.paymentMethod!)
            : null;
      case 'notes':
        return data.notes != null && data.notes!.isNotEmpty
            ? withLabel(data.notes!)
            : null;
      case 'footer':
        return el.content ?? data.footerText ?? (isEn ? 'Thank you for your visit' : 'شكراً لزيارتكم');
      case 'order_number':
        return data.orderNumber != null
            ? withLabel('${data.orderNumber}')
            : null;
      case 'supplier_name':
        return null; // Only for purchase invoices
      case 'text':
        return el.content ?? '';
      case 'variable':
        return _resolveVariable(el.content ?? '', data, formatter);
      case 'adhoc_customer_name':
        return data.customerName != null ? withLabel(data.customerName!) : null;
      case 'adhoc_customer_phone':
        return data.customerPhone != null
            ? withLabel(data.customerPhone!)
            : null;
      default:
        return el.content;
    }
  }

  static String _resolveVariable(
    String key,
    TemplateInvoiceData data,
    intl.NumberFormat fmt,
  ) {
    switch (key) {
      case 'invoice_number':
        return data.invoiceNumber;
      case 'date':
        return '${data.date.day}/${data.date.month}/${data.date.year}';
      case 'time':
        return '${data.date.hour.toString().padLeft(2, '0')}:${data.date.minute.toString().padLeft(2, '0')}';
      case 'customer_name':
        return data.customerName ?? 'عميل نقدي';
      case 'customer_phone':
        return data.customerPhone ?? '';
      case 'customer_address':
        return data.customerAddress ?? '';
      case 'company_name':
        return data.companyName ?? '';
      case 'company_address':
        return data.companyAddress ?? '';
      case 'company_phone':
        return data.companyPhone ?? '';
      case 'company_tax_number':
        return data.taxId ?? '';
      case 'subtotal':
        return fmt.format(data.subtotal);
      case 'discount':
        return fmt.format(data.discount);
      case 'tax':
        return fmt.format(data.tax);
      case 'total_amount':
      case 'net_amount':
        return fmt.format(data.total);
      case 'paid':
        return fmt.format(data.paid);
      case 'remaining':
        return fmt.format(data.remaining);
      case 'delivery_fee':
        return fmt.format(data.deliveryFee);
      case 'sale_type':
        return data.salesType ?? 'نقدي';
      case 'order_type':
        return _mapOrderTypeLabel(data.salesType);
      case 'payment_method':
        return data.paymentMethod ?? 'نقدي';
      case 'cashier_name':
        return data.employeeName ?? '';
      case 'notes':
      case 'footer_text':
        return data.footerText ?? 'شكراً لزيارتكم';
      case 'order_number':
        return data.orderNumber?.toString() ?? '';
      default:
        return key;
    }
  }

  /// Map sale type / order type codes to human-readable Arabic labels
  static String _mapOrderTypeLabel(String? saleType) {
    if (saleType == null || saleType.isEmpty) return '';
    switch (saleType.toLowerCase()) {
      case 'delivery':
        return 'توصيل';
      case 'internal':
      case 'default':
        return 'محلي';
      case 'dine_in':
      case 'صالة':
        return 'صالة';
      case 'takeaway':
      case 'سفري':
        return 'سفري';
      case 'talabat':
      case 'طلبات':
        return '#طلبات';
      case 'careem':
      case 'كريم':
        return '#كريم';
      case 'marsool':
      case 'مرسول':
        return '#مرسول';
      case 'jahez':
      case 'جاهز':
        return '#جاهز';
      case 'hungerstation':
        return '#هنقرستيشن';
      case 'toyo':
      case 'toyou':
        return '#ToYou';
      default:
        // If it already looks like an Arabic label or hashtag, return as-is
        return saleType;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS TABLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get per-column font size from column settings, with fallback to default
  static double _getColumnFontSize(String key, Map<String, dynamic> widths, double defaultSize) {
    final val = widths[key];
    if (val is Map) return (val['fontSize'] as num?)?.toDouble() ?? defaultSize;
    return defaultSize;
  }

  /// Get per-column decimal places from column settings, with fallback to default
  static int _getColumnDecimals(String key, Map<String, dynamic> widths, int defaultDecimals) {
    final val = widths[key];
    if (val is Map) return (val['decimals'] as num?)?.toInt() ?? defaultDecimals;
    return defaultDecimals;
  }

  /// Get per-column text wrap setting from column settings
  static bool _getColumnWrap(String key, Map<String, dynamic> widths) {
    final val = widths[key];
    if (val is Map) return (val['wrap'] as bool?) ?? false;
    return false;
  }

  /// Get column width from either old format (plain number) or new format (map with 'width')
  static double _getColumnWidth(String key, Map<String, dynamic> widths, double defaultWidth) {
    final val = widths[key];
    if (val is num) return val.toDouble();
    if (val is Map) return (val['width'] as num?)?.toDouble() ?? defaultWidth;
    return defaultWidth;
  }

  /// Insert items table widget at the appropriate position in the flow list.
  static void _insertItemsTable(
    List<pw.Widget> widgets,
    InvoiceTableSetting settings,
    pw.Font font,
    TemplateInvoiceData data,
    List<InvoiceTemplateElement> sortedElements,
  ) {
    // Parse column widths (supports both old and new formats)
    final defaultWidths = <String, double>{
      'index': 0.8,
      'product': 3.0,
      'code': 1.5,
      'quantity': 1.0,
      'price': 1.2,
      'discount': 1.0,
      'tax': 1.0,
      'total': 1.5,
      'unit': 1.0,
      'barcode': 1.5,
      'notes': 2.0,
    };
    int decimalPlaces = AppConstants.decimalPlaces;
    final customLabels = <String, String>{};
    // Keep raw decoded JSON for per-column settings lookup
    Map<String, dynamic> rawColumnSettings = {};

    try {
      if (settings.columnWidths != null) {
        final Map<String, dynamic> decoded = jsonDecode(settings.columnWidths!);
        rawColumnSettings = decoded;
        decoded.forEach((key, value) {
          if (key == '_decimalPlaces') {
            decimalPlaces = (value as num).toInt();
          } else if (key.startsWith('_label_') && value is String) {
            // Custom header labels: _label_product -> 'Item', etc.
            customLabels[key.replaceFirst('_label_', '')] = value;
          } else if (key.startsWith('_')) {
            // Skip other meta keys
          } else if (value is num) {
            // Old format: plain number
            defaultWidths[key] = value.toDouble();
          } else if (value is Map) {
            // New format: map with 'width' and other settings
            final map = value as Map<String, dynamic>;
            defaultWidths[key] = (map['width'] as num?)?.toDouble() ?? defaultWidths[key]!;
          }
        });
      }
    } catch (_) {}

    String fmt(num val) => val.toStringAsFixed(decimalPlaces);
    /// Format a numeric value using per-column decimal places
    String fmtCol(num val, String colKey) {
      final colDecimals = _getColumnDecimals(colKey, rawColumnSettings, decimalPlaces);
      return val.toStringAsFixed(colDecimals);
    }
    int getFlex(String key) => (defaultWidths[key]! * 10).round();

    // Default labels based on locale
    final isEnLocale = data.locale == 'en';
    final defaultLabels = <String, String>{
      'index': isEnLocale ? '#' : 'م',
      'product': isEnLocale ? 'Item' : 'الصنف',
      'code': isEnLocale ? 'Code' : 'الكود',
      'quantity': isEnLocale ? 'Qty' : 'العدد',
      'price': isEnLocale ? 'Price' : 'السعر',
      'discount': isEnLocale ? 'Disc.' : 'الخصم',
      'tax': isEnLocale ? 'Tax' : 'الضريبة',
      'total': isEnLocale ? 'Total' : 'الإجمالي',
      'unit': isEnLocale ? 'Unit' : 'الوحدة',
      'barcode': isEnLocale ? 'Barcode' : 'الباركود',
    };
    String getLabel(String key) => customLabels[key] ?? defaultLabels[key] ?? key;

    final headerFontSize = settings.headerFontSize;
    final bodyFontSize = settings.fontSize;
    final headerBg = _parseColor(settings.headerBgColor);
    final headerFg = _parseColor(settings.headerTextColor);

    pw.Widget headerCell(String text, String key) => pw.Expanded(
          flex: getFlex(key),
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: font,
                fontSize: headerFontSize,
                fontWeight: pw.FontWeight.bold,
                color: headerFg,
              ),
            ),
          ),
        );

    pw.Widget bodyCell(String text, String key) {
      final colFontSize = _getColumnFontSize(key, rawColumnSettings, bodyFontSize);
      final colWrap = _getColumnWrap(key, rawColumnSettings);
      return pw.Expanded(
        flex: getFlex(key),
        child: pw.Padding(
          padding: const pw.EdgeInsets.all(2),
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            softWrap: colWrap,
            maxLines: colWrap ? 3 : 1,
            style: pw.TextStyle(font: font, fontSize: colFontSize),
          ),
        ),
      );
    }

    final table = pw.Column(
      children: [
        // Header row
        pw.Container(
          color: headerBg,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: [
              if (settings.showIndex) headerCell(getLabel('index'), 'index'),
              if (settings.showProductName) headerCell(getLabel('product'), 'product'),
              if (settings.showProductCode) headerCell(getLabel('code'), 'code'),
              if (settings.showQuantity) headerCell(getLabel('quantity'), 'quantity'),
              if (settings.showUnitPrice) headerCell(getLabel('price'), 'price'),
              if (settings.showDiscount) headerCell(getLabel('discount'), 'discount'),
              if (settings.showTax) headerCell(getLabel('tax'), 'tax'),
              if (settings.showTotal) headerCell(getLabel('total'), 'total'),
              if (settings.showUnit) headerCell(getLabel('unit'), 'unit'),
              if (settings.showBarcode) headerCell(getLabel('barcode'), 'barcode'),
            ],
          ),
        ),
        // Data rows
        ...data.items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final isAlt = idx.isOdd && settings.altRowBgColor != null;
          final rowBg = isAlt ? _parseColor(settings.altRowBgColor!) : null;
          final hasNote = item.note != null && item.note!.isNotEmpty;

          // Per-column font size for product column
          final productFontSize = _getColumnFontSize('product', rawColumnSettings, bodyFontSize);
          final productWrap = _getColumnWrap('product', rawColumnSettings);

          // Special cell for product name + notes
          pw.Widget productNameCell() => pw.Expanded(
            flex: getFlex('product'),
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: hasNote
                  ? pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(
                          item.name,
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                          softWrap: productWrap,
                          maxLines: productWrap ? 3 : 1,
                          style: pw.TextStyle(font: font, fontSize: productFontSize),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          item.note!,
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            font: font,
                            fontSize: productFontSize >= 8.0 ? productFontSize : 8.0,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    )
                  : pw.Text(
                      item.name,
                      textAlign: pw.TextAlign.right,
                      textDirection: pw.TextDirection.rtl,
                      softWrap: productWrap,
                      maxLines: productWrap ? 3 : 1,
                      style: pw.TextStyle(font: font, fontSize: productFontSize),
                    ),
            ),
          );

          return pw.Container(
            color: rowBg,
            constraints: pw.BoxConstraints(minHeight: settings.rowHeight),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
              ),
            ),
            child: pw.Row(
              children: [
                if (settings.showIndex) bodyCell('${idx + 1}', 'index'),
                if (settings.showProductName) productNameCell(),
                if (settings.showProductCode)
                  bodyCell(item.barcode ?? '', 'code'),
                if (settings.showQuantity)
                  bodyCell(
                    item.quantity == item.quantity.toInt()
                        ? '${item.quantity.toInt()}'
                        : fmtCol(item.quantity, 'quantity'),
                    'quantity',
                  ),
                if (settings.showUnitPrice)
                  bodyCell(fmtCol(item.price, 'price'), 'price'),
                if (settings.showDiscount) bodyCell('', 'discount'),
                if (settings.showTax) bodyCell('', 'tax'),
                if (settings.showTotal) bodyCell(fmtCol(item.total, 'total'), 'total'),
                if (settings.showUnit) bodyCell('', 'unit'),
                if (settings.showBarcode)
                  bodyCell(item.barcode ?? '', 'barcode'),
              ],
            ),
          );
        }),
      ],
    );

    // Find the right insertion point based on Y position of the table
    // relative to the sorted elements. Insert after the last element
    // that has yPosition < table yPosition.
    int insertIdx = 0;
    for (int i = 0; i < sortedElements.length; i++) {
      if (sortedElements[i].yPosition < settings.yPosition) {
        insertIdx = i + 1;
      }
    }
    // Clamp to widgets size
    if (insertIdx > widgets.length) insertIdx = widgets.length;

    widgets.insert(insertIdx, table);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Map<String, double> _parseMargins(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return {
        'top': (m['top'] as num?)?.toDouble() ?? 5,
        'right': (m['right'] as num?)?.toDouble() ?? 5,
        'bottom': (m['bottom'] as num?)?.toDouble() ?? 5,
        'left': (m['left'] as num?)?.toDouble() ?? 5,
      };
    } catch (_) {
      return {'top': 5, 'right': 5, 'bottom': 5, 'left': 5};
    }
  }

  static PdfColor _parseColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      if (clean.length == 6) {
        return PdfColor.fromHex('FF$clean');
      } else if (clean.length == 8) {
        return PdfColor.fromHex(clean);
      }
    } catch (_) {}
    return PdfColors.black;
  }

  static pw.TextAlign _textAlign(String align) {
    switch (align) {
      case 'left':
        return pw.TextAlign.left;
      case 'center':
        return pw.TextAlign.center;
      case 'right':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.right;
    }
  }
}

