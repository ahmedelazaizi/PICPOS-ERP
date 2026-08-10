// ═══════════════════════════════════════════════════════════════════════════
// TEMPLATE-BASED PRINT RENDERER
// Renders PDF documents from user-designed invoice templates
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../generators/base_generator.dart' show BaseGenerator;
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart' as printing_pkg;
import '../../core/constants/app_constants.dart';
import '../../data/database/database.dart' hide Printer;
import '../../domain/repositories/printers_repository.dart';
import '../printer_resolver.dart';
import 'printing_models.dart';
import 'formula_evaluator.dart';

/// Renders a PDF document from a user-designed template.
///
/// This allows templates designed in the Invoice Designer to be used
/// for actual printing, replacing the hardcoded layout generators.
class TemplatePrintRenderer {
  static pw.Font? _arabicFont;

  /// الخطُّ من المصنع وحدَه — Noto Naskh، لا Cairo.
  ///
  /// كان هنا `PdfGoogleFonts.cairoRegular()`، وهي علّةٌ مزدوجة:
  ///
  /// ١) Cairo ينقصه **الياءُ المنفصلة U+FEF1**. والنمطُ المحلّيُّ
  ///    `TextStyle(font: …)` يدهس أساسَ الثيم ولا يدهس احتياطيَّه، والاحتياطيُّ
  ///    في الثيم هو Cairo نفسُه — فتصير السلسلةُ **Cairo ← Cairo** ولا مصدرَ
  ///    فيه الرسم. مقيس على إيصالٍ مطبوع: «صبري» بالياء راكبةً على الراء،
  ///    و«لوز ارباع» صارت «لوزارباع».
  ///
  /// ٢) `PdfGoogleFonts` **تنزّل من الشبكة** وقت الطباعة — ونقطةُ البيع قد
  ///    تكون بلا إنترنت. المصنعُ يقرأ الأصلَ المحزوم أولاً.
  static Future<void> _initFont() async {
    _arabicFont ??= await BaseGenerator.initFont();
  }

  /// Build a PDF document from a template and its data.
  ///
  /// [template] — The template entity (type, paper dimensions)
  /// [elements] — Ordered list of template elements
  /// [tableSettings] — Optional items table configuration
  /// [data] — Map of all variable values (invoice_number, date, items, totals, etc.)
  static Future<pw.Document> renderFromTemplate({
    required InvoiceTemplate template,
    required List<InvoiceTemplateElement> elements,
    InvoiceTableSetting? tableSettings,
    required Map<String, dynamic> data,
  }) async {
    await _initFont();

    final isThermal = template.type == 'thermal';
    final pageFormat = isThermal
        ? PdfPageFormat(
            template.paperWidth * PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    final doc = await BaseGenerator.newDocument();
    final baseStyle = pw.TextStyle(font: _arabicFont, fontSize: 12);

    if (isThermal) {
      // Thermal: single column, vertical flow based on element y-position
      final sortedElements = List<InvoiceTemplateElement>.from(elements)
        ..sort((a, b) => a.yPosition.compareTo(b.yPosition));

      final children = <pw.Widget>[];
      for (final el in sortedElements) {
        final widget = _buildElementWidget(el, data, baseStyle, tableSettings);
        if (widget != null) children.add(widget);
      }

      final lang = data['print_language'] as String? ?? 'ar';
      final pageTextDir = lang == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl;

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        textDirection: pageTextDir,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: children,
        ),
      ));
    } else {
      // A4: absolute-positioned elements on a fixed-size page
      final widgets = <pw.Widget>[];
      for (final el in elements) {
        final widget = _buildElementWidget(el, data, baseStyle, tableSettings);
        if (widget != null) {
          widgets.add(
            pw.Positioned(
              left: el.xPosition,
              top: el.yPosition,
              child: pw.SizedBox(
                width: el.width,
                height: el.height,
                child: widget,
              ),
            ),
          );
        }
      }

      // Add items table if configured
      if (tableSettings != null && data['items'] != null) {
        final lang = data['print_language'] as String? ?? 'ar';
        final table = _buildItemsTable(
          tableSettings,
          data['items'] as List<InvoiceItem>,
          baseStyle,
          lang: lang,
        );
        widgets.add(
          pw.Positioned(
            left: tableSettings.xPosition,
            top: tableSettings.yPosition,
            child: pw.SizedBox(width: tableSettings.width, child: table),
          ),
        );
      }

      final lang = data['print_language'] as String? ?? 'ar';
      final pageTextDir = lang == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl;

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        textDirection: pageTextDir,
        build: (_) => pw.Stack(children: widgets),
      ));
    }

    return doc;
  }

  /// Resolve the display label based on the print language.
  /// Returns `labelEn` when language is 'en', otherwise `labelAr`.
  static String _resolveLabel(InvoiceTemplateElement el, Map<String, dynamic> data) {
    final lang = data['print_language'] as String? ?? 'ar';
    if (lang == 'en') {
      return el.labelEn?.isNotEmpty == true ? el.labelEn! : (el.labelAr ?? '');
    }
    return el.labelAr?.isNotEmpty == true ? el.labelAr! : (el.labelEn ?? '');
  }

  /// Build a single element as a pw.Widget.
  static pw.Widget? _buildElementWidget(
    InvoiceTemplateElement el,
    Map<String, dynamic> data,
    pw.TextStyle baseStyle,
    InvoiceTableSetting? tableSettings,
  ) {
    final lang = data['print_language'] as String? ?? 'ar';
    final textDir = lang == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl;

    final style = baseStyle.copyWith(
      fontSize: el.fontSize,
      fontWeight: el.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: el.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
      color: _parseColor(el.fontColor),
    );

    final align = _textAlign(el.textAlign);

    // If element has a formula, evaluate it
    if (el.formula != null && el.formula!.isNotEmpty) {
      final result = FormulaEvaluator.evaluate(el.formula!, data);
      if (result != null) {
        final label = _resolveLabel(el, data);
        final prefix = label.isNotEmpty ? '$label: ' : '';
        return pw.Text('$prefix${result.toStringAsFixed(AppConstants.decimalPlaces)}',
            style: style, textAlign: align, textDirection: textDir);
      }
    }

    switch (el.elementType) {
      case 'company_name':
        return pw.Text(data['company_name'] ?? '', style: style, textAlign: align,
            textDirection: pw.TextDirection.rtl);
      case 'company_address':
        return pw.Text(data['company_address'] ?? '', style: style, textAlign: align,
            textDirection: pw.TextDirection.rtl);
      case 'company_phone':
        return pw.Text(data['company_phone'] ?? '', style: style, textAlign: align,
            textDirection: pw.TextDirection.rtl);
      case 'invoice_number':
      case 'order_number':
      case 'cashier_name':
      case 'customer':
      case 'customer_name':
      case 'customer_phone':
      case 'customer_address':
      case 'supplier_name':
      case 'payment_method':
      case 'notes':
        final label = _resolveLabel(el, data);
        final prefix = label.isNotEmpty ? '$label: ' : '';
        final key = el.elementType == 'customer' ? 'customer_name' : el.elementType;
        return pw.Text('$prefix${data[key] ?? ''}', style: style,
            textAlign: align, textDirection: textDir);
      case 'date':
        final date = data['date'];
        final formatted = date is DateTime
            ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
            : (date?.toString() ?? '');
        final label = _resolveLabel(el, data);
        final prefix = label.isNotEmpty ? '$label: ' : '';
        return pw.Text('$prefix$formatted', style: style, textAlign: align,
            textDirection: textDir);
      case 'time':
        final date = data['date'];
        final formatted = date is DateTime
            ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
            : '';
        return pw.Text(formatted, style: style, textAlign: align,
            textDirection: textDir);
      case 'adhoc_customer_name':
        return pw.Text(data['adhoc_customer_name'] ?? '', style: style,
            textAlign: align, textDirection: textDir);
      case 'adhoc_customer_phone':
        return pw.Text(data['adhoc_customer_phone'] ?? '', style: style,
            textAlign: align, textDirection: textDir);
      case 'subtotal':
        return _valueRow(el, data['subtotal'], style, align, data);
      case 'discount':
        return _valueRow(el, data['discount'], style, align, data);
      case 'tax':
        return _valueRow(el, data['tax'], style, align, data);
      case 'total':
        return _valueRow(el, data['total'], style, align, data);
      case 'paid':
        return _valueRow(el, data['paid'], style, align, data);
      case 'remaining':
        return _valueRow(el, data['remaining'], style, align, data);
      case 'text':
        return pw.Text(el.content ?? '', style: style, textAlign: align,
            textDirection: textDir);
      case 'divider':
      case 'line':
        return pw.Divider(thickness: el.height.clamp(0.5, 4));
      case 'rectangle':
        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: _parseColor(el.borderColor) ?? PdfColors.grey600,
              width: el.borderWidth > 0 ? el.borderWidth : 0.5,
            ),
          ),
        );
      case 'footer':
        return pw.Text(el.content ?? data['footer'] ?? '', style: style,
            textAlign: align, textDirection: textDir);
      case 'qr_code':
        final qrData = data['qr_data'] ?? data['invoice_number'] ?? '';
        if (qrData.toString().isEmpty) return null;
        return pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: qrData.toString(),
          width: el.width,
          height: el.height,
        );
      case 'barcode':
        final barcodeData = data['barcode_data'] ?? data['invoice_number'] ?? '';
        if (barcodeData.toString().isEmpty) return null;
        return pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: barcodeData.toString(),
          width: el.width,
          height: el.height,
        );
      case 'variable':
        // Generic variable resolution
        final varName = el.content ?? '';
        return _buildVariableWidget(varName, el, data, style, align, textDir);
      case 'spacer':
        return pw.SizedBox(height: el.height);
      case 'items_table':
        if (tableSettings != null && data['items'] != null) {
          return _buildItemsTable(
            tableSettings, data['items'] as List<InvoiceItem>, baseStyle,
            lang: lang);
        }
        return null;
      case 'logo':
        // Logo handled separately (needs image bytes)
        final logoBytes = data['logo_bytes'];
        if (logoBytes != null) {
          return pw.Image(pw.MemoryImage(logoBytes), width: el.width, height: el.height);
        }
        return null;
      default:
        if (data.containsKey(el.elementType)) {
          return pw.Text('${data[el.elementType]}', style: style,
              textAlign: align, textDirection: textDir);
        }
        return null;
    }
  }

  static pw.Widget _buildVariableWidget(
    String varName,
    InvoiceTemplateElement el,
    Map<String, dynamic> data,
    pw.TextStyle style,
    pw.TextAlign align,
    pw.TextDirection textDir,
  ) {
    final value = data[varName];
    final label = _resolveLabel(el, data);
    final prefix = label.isNotEmpty ? '$label: ' : '';

    if (varName == 'qr_code') {
      final qrData = data['qr_data'] ?? data['invoice_number'] ?? '';
      if (qrData.toString().isEmpty) return pw.SizedBox();
      return pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: qrData.toString(),
        width: el.width,
        height: el.height,
      );
    }

    if (value == null) {
      return pw.Text('$prefix—', style: style, textAlign: align,
        textDirection: textDir);
    }

    if (value is num) {
      return pw.Text('$prefix${value.toStringAsFixed(AppConstants.decimalPlaces)}', style: style,
          textAlign: align, textDirection: textDir);
    }

    return pw.Text('$prefix$value', style: style, textAlign: align,
        textDirection: textDir);
  }

  static pw.Widget _valueRow(
    InvoiceTemplateElement el,
    dynamic value,
    pw.TextStyle style,
    pw.TextAlign align,
    Map<String, dynamic> data,
  ) {
    final lang = data['print_language'] as String? ?? 'ar';
    final textDir = lang == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl;
    final label = _resolveLabel(el, data);
    final prefix = label.isNotEmpty ? '$label: ' : '';
    final formatted = value is num ? value.toStringAsFixed(AppConstants.decimalPlaces) : (value?.toString() ?? '0.00');
    return pw.Text('$prefix$formatted', style: style, textAlign: align,
        textDirection: textDir);
  }

  static pw.Widget _buildItemsTable(
    InvoiceTableSetting settings,
    List<InvoiceItem> items,
    pw.TextStyle baseStyle, {
    String lang = 'ar',
  }) {
    final isEn = lang == 'en';

    final textDir = isEn ? pw.TextDirection.ltr : pw.TextDirection.rtl;

    // Build column definitions: key → (header label, flex width)
    // Notes are NEVER a column — they render inside the product name cell
    final columns = <_ColDef>[];
    if (settings.showIndex) columns.add(_ColDef(isEn ? '#' : 'م', 1.0));
    if (settings.showBarcode) columns.add(_ColDef(isEn ? 'Barcode' : 'الباركود', 2.5));
    if (settings.showProductCode) columns.add(_ColDef(isEn ? 'Code' : 'الكود', 2.0));
    if (settings.showProductName) columns.add(_ColDef(isEn ? 'Item' : 'الصنف', 4.0));
    if (settings.showUnit) columns.add(_ColDef(isEn ? 'Unit' : 'الوحدة', 1.8));
    if (settings.showQuantity) columns.add(_ColDef(isEn ? 'Qty' : 'العدد', 2.0));
    if (settings.showUnitPrice) columns.add(_ColDef(isEn ? 'Price' : 'السعر', 2.0));
    if (settings.showDiscount) columns.add(_ColDef(isEn ? 'Disc.' : 'الخصم', 1.8));
    if (settings.showTax) columns.add(_ColDef(isEn ? 'Tax' : 'الضريبة', 1.8));
    if (settings.showTotal) columns.add(_ColDef(isEn ? 'Total' : 'الإجمالي', 2.5));

    if (columns.isEmpty) return pw.SizedBox();

    final headerBg = _parseColor(settings.headerBgColor) ?? PdfColors.grey800;
    final headerFg = _parseColor(settings.headerTextColor) ?? PdfColors.white;
    final headerFontSize = settings.headerFontSize > 0 ? settings.headerFontSize : 7.0;
    final itemFontSize = settings.fontSize > 0 ? settings.fontSize : 8.0;
    final colCount = columns.length;

    // Parse bold flags from columnWidths JSON
    bool headerBold = true;  // Default: header is bold
    bool bodyBold = false;   // Default: body is normal
    if (settings.columnWidths != null && settings.columnWidths!.isNotEmpty) {
      try {
        final decoded = jsonDecode(settings.columnWidths!) as Map<String, dynamic>;
        headerBold = (decoded['_headerBold'] as bool?) ?? true;
        bodyBold = (decoded['_bodyBold'] as bool?) ?? false;
      } catch (_) {}
    }

    // Column width map
    final columnWidths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < colCount; i++) {
      columnWidths[i] = pw.FlexColumnWidth(columns[i].flex);
    }

    // Header row
    final headerRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: headerBg),
      children: columns.map((col) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Text(
          col.label,
          style: baseStyle.copyWith(
            fontSize: headerFontSize,
            fontWeight: headerBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: headerFg,
          ),
          textAlign: pw.TextAlign.center,
          maxLines: 1,
          textDirection: textDir,
        ),
      )).toList(),
    );

    // Item rows
    final tableRows = <pw.TableRow>[headerRow];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final cells = <pw.Widget>[];
      final hasNote = item.note != null && item.note!.isNotEmpty;

      final bodyWeight = bodyBold ? pw.FontWeight.bold : pw.FontWeight.normal;
      if (settings.showIndex) cells.add(_tCell('${i + 1}', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showBarcode) cells.add(_tCell(item.barcode ?? '', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showProductCode) cells.add(_tCell(item.barcode ?? '', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showProductName) {
        // Embed notes directly inside the product name cell
        if (hasNote) {
          cells.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch, // Stretch ensures full cell width
              children: [
                pw.Text(
                  item.name,
                  style: baseStyle.copyWith(fontSize: itemFontSize, fontWeight: bodyWeight),
                  textAlign: isEn ? pw.TextAlign.left : pw.TextAlign.right,
                  textDirection: textDir,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  item.note!,
                  style: baseStyle.copyWith(
                    fontSize: itemFontSize >= 8.0 ? itemFontSize : 8.0,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: isEn ? pw.TextAlign.left : pw.TextAlign.right,
                  textDirection: textDir,
                ),
              ],
            ),
          ));
        } else {
          cells.add(_tCell(item.name, baseStyle, itemFontSize, textDir: textDir, align: isEn ? pw.TextAlign.left : pw.TextAlign.right, fontWeight: bodyWeight));
        }
      }
      if (settings.showUnit) cells.add(_tCell('', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showQuantity) cells.add(_tCell(item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 2), baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showUnitPrice) cells.add(_tCell(item.price.toStringAsFixed(AppConstants.decimalPlaces), baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showDiscount) cells.add(_tCell('0.00', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showTax) cells.add(_tCell('0.00', baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));
      if (settings.showTotal) cells.add(_tCell(item.total.toStringAsFixed(AppConstants.decimalPlaces), baseStyle, itemFontSize, textDir: textDir, fontWeight: bodyWeight));

      tableRows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3)),
        ),
        children: cells,
      ));
    }

    return pw.Table(
      columnWidths: columnWidths,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.2),
      ),
      children: tableRows,
    );
  }

  static pw.Widget _tCell(
    String text,
    pw.TextStyle baseStyle,
    double fontSize, {
    pw.TextDirection? textDir,
    pw.TextAlign align = pw.TextAlign.center,
    pw.FontWeight? fontWeight,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: pw.Text(
        text,
        style: baseStyle.copyWith(fontSize: fontSize, fontWeight: fontWeight),
        textAlign: align,
        textDirection: textDir,
      ),
    );
  }


  static pw.TextAlign _textAlign(String align) {
    switch (align) {
      case 'left': return pw.TextAlign.left;
      case 'right': return pw.TextAlign.right;
      case 'center': return pw.TextAlign.center;
      default: return pw.TextAlign.center;
    }
  }

  static PdfColor? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return PdfColor.fromInt(value);
  }

  /// Print directly using a template.
  ///
  /// Looks up the default template for [type] and [category],
  /// renders it, and sends to printer.
  static Future<bool> printWithTemplate({
    required AppDatabase db,
    required String type,
    required String category,
    required Map<String, dynamic> data,
    required List<InvoiceItem> items,
    bool directPrint = false,
    IPrintersRepository? printersRepo,
  }) async {
    try {
      final templateData = await db.getDefaultTemplateWithDataByCategory(type, category);
      if (templateData == null) return false; // No default template found

      final template = templateData.template;
      final elements = templateData.elements;
      final tableSettings = templateData.tableSettings;

      // Auto-inject print language from settings if not already present
      if (!data.containsKey('print_language')) {
        final langSetting = await db.getSettingValue('print_language');
        data['print_language'] = langSetting ?? 'ar';
      }

      // Add items to data
      data['items'] = items;

      final doc = await renderFromTemplate(
        template: template,
        elements: elements,
        tableSettings: tableSettings,
        data: data,
      );

      final bytes = await doc.save();

      if (directPrint && printersRepo != null) {
        final resolved = await PrinterResolver.resolveReceiptPrinter(printersRepo);
        if (resolved != null) {
          await printing_pkg.Printing.directPrintPdf(
            printer: resolved,
            onLayout: (_) => bytes,
          );
          return true;
        }
      }

      // Fallback: show print dialog
      await printing_pkg.Printing.layoutPdf(onLayout: (_) => bytes);
      return true;
    } catch (e) {
      debugPrint('[TemplatePrintRenderer] Error: $e');
      return false;
    }
  }
}

/// Helper class for column definitions in the items table
class _ColDef {
  final String label;
  final double flex;
  const _ColDef(this.label, this.flex);
}
