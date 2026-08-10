import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'base_generator.dart';
import '../cash_drawer_service.dart';
import '../printer_resolver.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/repositories/printers_repository.dart';
import 'thermal_voucher_generator.dart';
import '../../core/config/brand.dart';

/// Thermal Receipt Generator (80mm format)
///
/// Handles printing of thermal receipts for POS systems.
/// Supports delivery orders, tax, discounts, and multiple payment methods.
class ThermalReceiptGenerator extends BaseGenerator {
  /// Print thermal receipt (80mm format) - Elegant professional design
  /// Layout: Company Header → Invoice Title → Customer Info → Items Table → Totals Section → Footer
  static Future<void> print({
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    required double change,
    String? companyName,
    String? companyNameEn,
    String? companyPhone,
    String? companyAddress,
    String? taxId,
    String? employeeName,
    String? registerNumber,
    String? salesType,
    String? receiptCodeType, // 'barcode', 'qr_code', or 'none'
    String? footerText,
    // Delivery information
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? courierName,
    String? courierPhone,
    bool isDelivery = false,
    double? discount,
    double? tax,
    double? deliveryFee,
    IPrintersRepository? printersRepo, // For printer resolution
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();

    // 80mm thermal paper format
    const thermalFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    // Display invoice number
    final displayInvoiceNumber = invoiceNumber;

    // Receipt totals breakdown
    final double itemsSubtotal = total + (discount ?? 0) - (tax ?? 0);
    final double grandTotal = total + (deliveryFee ?? 0);
    final double actualChange = paid - grandTotal;
    final double remaining = grandTotal - paid;

    pdf.addPage(
      pw.Page(
        pageFormat: thermalFormat,
        // NOTE: Do NOT set textDirection on the Page — it causes entire-page mirroring
        // on some Windows thermal printer drivers. RTL is handled per-widget below.
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // ═══════════════════════════════════════════════════════════════════
            // COMPANY HEADER
            // ═══════════════════════════════════════════════════════════════════
            _buildHeader(
              arabicFont,
              companyName,
              companyNameEn,
              companyPhone,
              companyAddress,
              taxId,
            ),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),

            // ═══════════════════════════════════════════════════════════════════
            // INVOICE TITLE
            // ═══════════════════════════════════════════════════════════════════
            _buildInvoiceTitle(
              arabicFont,
              displayInvoiceNumber,
              date,
              salesType,
              employeeName,
              registerNumber,
            ),

            // Customer info
            if (customerName != null || isDelivery)
              _buildCustomerInfo(
                arabicFont,
                customerName,
                customerPhone,
                customerAddress,
                courierName,
                courierPhone,
                isDelivery,
              ),

            pw.Divider(thickness: 1),

            // ═══════════════════════════════════════════════════════════════════
            // ITEMS TABLE
            // ═══════════════════════════════════════════════════════════════════
            _buildItemsTable(arabicFont, items),

            pw.Divider(thickness: 1),

            // ═══════════════════════════════════════════════════════════════════
            // TOTALS SECTION
            // ═══════════════════════════════════════════════════════════════════
            _buildTotalsSection(
              arabicFont,
              itemsSubtotal,
              discount,
              tax,
              deliveryFee,
              grandTotal,
              paid,
              actualChange,
              remaining,
            ),

            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),

            // ═══════════════════════════════════════════════════════════════════
            // FOOTER
            // ═══════════════════════════════════════════════════════════════════
            _buildFooter(
              arabicFont,
              footerText,
              receiptCodeType,
              displayInvoiceNumber,
            ),
          ],
        ),
        ), // end Directionality
      ),
    );

    // Resolve printer from Repository config, fallback to system default
    Printer? resolvedPrinter;
    if (printersRepo != null) {
      resolvedPrinter = await PrinterResolver.resolveReceiptPrinter(printersRepo);
    }

    if (resolvedPrinter != null) {
      debugPrint('[ThermalReceipt] Printing to: ${resolvedPrinter.name}');
      await Printing.directPrintPdf(
        printer: resolvedPrinter,
        onLayout: (format) async => pdf.save(),
      );
      // Auto-open cash drawer after print
      await CashDrawerService().openDrawer(printerName: resolvedPrinter.name);
    } else {
      // No resolved printer — try system printers
      final printers = await Printing.listPrinters();
      if (printers.isNotEmpty) {
        final fallback =
            printers.where((p) => p.isDefault).firstOrNull ?? printers.first;
        debugPrint('[ThermalReceipt] Fallback to: ${fallback.name}');
        await Printing.directPrintPdf(
          printer: fallback,
          onLayout: (format) async => pdf.save(),
        );
        await CashDrawerService().openDrawer(printerName: fallback.name);
      } else {
        debugPrint('[ThermalReceipt] No printers, showing dialog');
        await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      }
    }
  }

  static pw.Widget _buildHeader(
    pw.Font font,
    String? companyName,
    String? companyNameEn,
    String? companyPhone,
    String? companyAddress,
    String? taxId,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          companyName ?? Brand.documentCompanyFallback,
          style: pw.TextStyle(
            font: font,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (companyNameEn != null)
          pw.Text(
            companyNameEn,
            style: pw.TextStyle(font: font, fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
        if (companyAddress != null)
          pw.Text(
            companyAddress,
            style: pw.TextStyle(font: font, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        if (companyPhone != null)
          pw.Text(
            'Tel: $companyPhone',
            style: pw.TextStyle(font: font, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        if (taxId != null)
          pw.Text(
            'Tax ID: $taxId',
            style: pw.TextStyle(font: font, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  static pw.Widget _buildInvoiceTitle(
    pw.Font font,
    String invoiceNumber,
    DateTime date,
    String? salesType,
    String? employeeName,
    String? registerNumber,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'فاتورة مبيعات',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Sales Invoice',
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        _thermalRow(font, invoiceNumber, 'رقم الفاتورة'),
        _thermalRow(
          font,
          '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          'التاريخ',
        ),
        if (salesType != null) _thermalRow(font, salesType, 'نوع البيع'),
        if (employeeName != null) _thermalRow(font, employeeName, 'الموظف'),
        if (registerNumber != null)
          _thermalRow(font, registerNumber, 'الكاشير'),
      ],
    );
  }

  static pw.Widget _buildCustomerInfo(
    pw.Font font,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? courierName,
    String? courierPhone,
    bool isDelivery,
  ) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5),
        if (customerName != null) _thermalRow(font, customerName, 'العميل'),
        if (customerPhone != null) _thermalRow(font, customerPhone, 'الهاتف'),
        if (customerAddress != null)
          _thermalRow(font, customerAddress, 'العنوان'),
        if (isDelivery && courierName != null)
          _thermalRow(font, courierName, 'المندوب'),
        if (isDelivery && courierPhone != null)
          _thermalRow(font, courierPhone, 'هاتف المندوب'),
      ],
    );
  }

  static pw.Widget _buildItemsTable(pw.Font font, List<InvoiceItem> items) {
    return pw.Table(
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.5),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2.5),
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'الصنف', isHeader: true),
            _tableCell(font, 'الكمية', isHeader: true),
            _tableCell(font, 'السعر', isHeader: true),
            _tableCell(font, 'الإجمالي', isHeader: true),
          ],
        ),
        // Item rows
        ...items.map(
          (item) => pw.TableRow(
            children: [
              _tableCell(font, item.name),
              _tableCell(
                font,
                item.quantity.toStringAsFixed(
                  item.quantity == item.quantity.toInt() ? 0 : 2,
                ),
              ),
              _tableCell(font, item.price.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, item.total.toStringAsFixed(AppConstants.decimalPlaces)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTotalsSection(
    pw.Font font,
    double itemsSubtotal,
    double? discount,
    double? tax,
    double? deliveryFee,
    double grandTotal,
    double paid,
    double actualChange,
    double remaining,
  ) {
    return pw.Column(
      children: [
        _totalRow(font, 'المجموع الفرعي', 'Subtotal', itemsSubtotal),
        if (discount != null && discount > 0)
          _totalRow(font, 'الخصم', 'Discount', discount, isSubtraction: true),
        if (tax != null && tax > 0)
          _totalRow(font, 'الضريبة', 'Tax', tax, isAddition: true),
        if (deliveryFee != null && deliveryFee > 0)
          _totalRow(font, 'التوصيل', 'Delivery', deliveryFee, isAddition: true),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: _totalRow(
            font,
            'الإجمالي',
            'Total',
            grandTotal,
            isBold: true,
            fontSize: 14,
          ),
        ),
        pw.SizedBox(height: 4),
        _totalRow(font, 'المدفوع', 'Paid', paid),
        if (actualChange > 0.01)
          _totalRow(font, 'الباقي', 'Change', actualChange)
        else if (remaining > 0.01)
          _totalRow(
            font,
            'المتبقي',
            'Remaining',
            remaining,
            isSubtraction: true,
          ),
      ],
    );
  }

  static pw.Widget _buildFooter(
    pw.Font font,
    String? footerText,
    String? receiptCodeType,
    String invoiceNumber,
  ) {
    return pw.Column(
      children: [
        // Receipt code (barcode or QR)
        if (receiptCodeType == 'barcode')
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoiceNumber,
            width: 150,
            height: 30,
            drawText: false,
          )
        else if (receiptCodeType == 'qr_code')
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: invoiceNumber,
            width: 60,
            height: 60,
          ),

        pw.SizedBox(height: 8),

        // Footer text
        pw.Text(
          footerText ?? 'شكراً لتسوقكم معنا - Thank you for shopping with us',
          style: pw.TextStyle(font: font, fontSize: 9),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  static pw.Widget _thermalRow(pw.Font font, String value, String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text(
            label,
            style: pw.TextStyle(
              font: font,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableCell(
    pw.Font font,
    String text, {
    bool isHeader = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 8 : 7.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 1,
      ),
    );
  }

  static pw.Widget _totalRow(
    pw.Font font,
    String labelAr,
    String labelEn,
    double amount, {
    bool isAddition = false,
    bool isSubtraction = false,
    bool isBold = false,
    double fontSize = 10,
  }) {
    String prefix = '';
    if (isAddition) prefix = '+';
    if (isSubtraction) prefix = '-';

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$prefix${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
            style: pw.TextStyle(
              font: font,
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Row(
            children: [
              pw.Text(
                labelEn,
                style: pw.TextStyle(font: font, fontSize: fontSize - 2),
              ),
              pw.Text(
                ' / ',
                style: pw.TextStyle(font: font, fontSize: fontSize - 2),
              ),
              pw.Text(
                labelAr,
                style: pw.TextStyle(
                  font: font,
                  fontSize: fontSize,
                  fontWeight: isBold
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =======================================================================
  // VOUCHER & RETURN PRINTING — Forwarded to ThermalVoucherGenerator
  // =======================================================================

  /// Forwarding: Print Voucher → ThermalVoucherGenerator.printVoucher
  static Future<void> printVoucher({
    required String voucherNumber,
    required String voucherType,
    required DateTime date,
    required double amount,
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? partyName,
    String? partyPhone,
    String? description,
    String? safeName,
    String? employeeName,
    IPrintersRepository? printersRepo,
  }) => ThermalVoucherGenerator.printVoucher(
    voucherNumber: voucherNumber,
    voucherType: voucherType,
    date: date,
    amount: amount,
    companyName: companyName,
    companyPhone: companyPhone,
    companyAddress: companyAddress,
    partyName: partyName,
    partyPhone: partyPhone,
    description: description,
    safeName: safeName,
    employeeName: employeeName,
    printersRepo: printersRepo,
  );

  /// Forwarding: Print Return Receipt → ThermalVoucherGenerator.printReturnReceipt
  static Future<void> printReturnReceipt({
    required String returnVoucherNumber,
    required String originalInvoiceNumber,
    required DateTime date,
    required List<InvoiceItem> items,
    required double returnTotal,
    required String paymentMethod,
    double cashRefund = 0,
    double bankRefund = 0,
    String? returnReason,
    String? customerName,
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? employeeName,
    IPrintersRepository? printersRepo,
  }) => ThermalVoucherGenerator.printReturnReceipt(
    returnVoucherNumber: returnVoucherNumber,
    originalInvoiceNumber: originalInvoiceNumber,
    date: date,
    items: items,
    returnTotal: returnTotal,
    paymentMethod: paymentMethod,
    cashRefund: cashRefund,
    bankRefund: bankRefund,
    returnReason: returnReason,
    customerName: customerName,
    companyName: companyName,
    companyPhone: companyPhone,
    companyAddress: companyAddress,
    employeeName: employeeName,
    printersRepo: printersRepo,
  );
}

