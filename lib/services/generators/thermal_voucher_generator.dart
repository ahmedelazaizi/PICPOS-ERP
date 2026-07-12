import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'base_generator.dart';
import '../printer_resolver.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/repositories/printers_repository.dart';

/// Thermal Voucher & Return Generator
///
/// Handles printing of payment/receipt vouchers and sales return credit notes.
/// Extracted from ThermalReceiptGenerator for maintainability.
class ThermalVoucherGenerator {
  // Helper: thermal row with label-value layout
  static pw.Widget _thermalRow(pw.Font font, String value, String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // Helper: company header
  static pw.Widget _buildHeader(pw.Font font, String? companyName, String? companyNameEn, String? companyPhone, String? companyAddress, String? taxId) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(companyName ?? 'UralCash Market', style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        if (companyNameEn != null) pw.Text(companyNameEn, style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center),
        if (companyAddress != null) pw.Text(companyAddress, style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.center),
        if (companyPhone != null) pw.Text('Tel: $companyPhone', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.center),
        if (taxId != null) pw.Text('Tax ID: $taxId', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.center),
      ],
    );
  }

  // Helper: items table
  static pw.Widget _buildItemsTable(pw.Font font, List<InvoiceItem> items) {
    return pw.Table(
      border: pw.TableBorder.symmetric(inside: const pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
      columnWidths: const {0: pw.FlexColumnWidth(3.5), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2.5)},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text('الصنف', style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 1)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text('الكمية', style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 1)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text('السعر', style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 1)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text('الإجمالي', style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 1)),
          ],
        ),
        ...items.map((item) => pw.TableRow(
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text(item.name, style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text(item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 2), style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text(item.price.toStringAsFixed(AppConstants.decimalPlaces), style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3), child: pw.Text(item.total.toStringAsFixed(AppConstants.decimalPlaces), style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
          ],
        )),
      ],
    );
  }
  /// Print Voucher (Receipt/Payment) - 80mm thermal format (#5)
  /// Layout: Company Header → Voucher Title → Party Info → Amount → Description → Footer
  static Future<void> printVoucher({
    required String voucherNumber,
    required String voucherType, // 'receipt' or 'payment'
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
    IPrintersRepository? printersRepo, // For printer resolution
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();

    // 80mm thermal paper format
    const thermalFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final isReceipt = voucherType == 'receipt';
    final voucherTitle = isReceipt ? 'سند قبض' : 'سند صرف';
    final voucherTitleEn = isReceipt ? 'Receipt Voucher' : 'Payment Voucher';

    pdf.addPage(
      pw.Page(
        pageFormat: thermalFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // ═══════════════════════════════════════════════════════════════════
            // COMPANY HEADER
            // ═══════════════════════════════════════════════════════════════════
            pw.Text(
              companyName ?? 'UralCash Market',
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            if (companyAddress != null)
              pw.Text(
                companyAddress,
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            if (companyPhone != null)
              pw.Text(
                'Tel: $companyPhone',
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 4),

            // ═══════════════════════════════════════════════════════════════════
            // VOUCHER TITLE
            // ═══════════════════════════════════════════════════════════════════
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                color: isReceipt ? PdfColors.green100 : PdfColors.red100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    voucherTitle,
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    voucherTitleEn,
                    style: pw.TextStyle(font: arabicFont, fontSize: 10),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 8),

            // Voucher details
            _thermalRow(arabicFont, voucherNumber, 'رقم السند'),
            _thermalRow(
              arabicFont,
              '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              'التاريخ',
            ),
            if (safeName != null) _thermalRow(arabicFont, safeName, 'الخزينة'),
            if (employeeName != null)
              _thermalRow(arabicFont, employeeName, 'الموظف'),

            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),

            // ═══════════════════════════════════════════════════════════════════
            // PARTY INFO
            // ═══════════════════════════════════════════════════════════════════
            if (partyName != null) ...[
              pw.Text(
                isReceipt ? 'استلمنا من' : 'صرفنا إلى',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                partyName,
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (partyPhone != null)
                pw.Text(
                  partyPhone,
                  style: pw.TextStyle(font: arabicFont, fontSize: 9),
                ),
              pw.SizedBox(height: 8),
            ],

            // ═══════════════════════════════════════════════════════════════════
            // AMOUNT (Big and Bold)
            // ═══════════════════════════════════════════════════════════════════
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(
                  color: isReceipt ? PdfColors.green : PdfColors.red,
                  width: 2,
                ),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'المبلغ / Amount',
                    style: pw.TextStyle(font: arabicFont, fontSize: 10),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 8),

            // ═══════════════════════════════════════════════════════════════════
            // DESCRIPTION
            // ═══════════════════════════════════════════════════════════════════
            if (description != null && description.isNotEmpty) ...[
              pw.Text(
                'البيان:',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                description,
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
            ],

            pw.Divider(thickness: 1),
            pw.SizedBox(height: 12),

            // ═══════════════════════════════════════════════════════════════════
            // SIGNATURES
            // ═══════════════════════════════════════════════════════════════════
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'المستلم',
                      style: pw.TextStyle(font: arabicFont, fontSize: 9),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(width: 60, child: pw.Divider(thickness: 0.5)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'المسلم',
                      style: pw.TextStyle(font: arabicFont, fontSize: 9),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(width: 60, child: pw.Divider(thickness: 0.5)),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 12),

            // Footer
            pw.Text(
              'تم الطباعة بواسطة UralCash POS',
              style: pw.TextStyle(font: arabicFont, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    // Resolve printer from repository config, fallback to system default
    Printer? resolvedPrinter;
    if (printersRepo != null) {
      final dbPrinter = await printersRepo.getActivePrinterByPurpose('pos_receipt');
      if (dbPrinter != null) {
        resolvedPrinter = await PrinterResolver.resolveByPrinter(dbPrinter);
      }
    }

    if (resolvedPrinter != null) {
      await Printing.directPrintPdf(
        printer: resolvedPrinter,
        onLayout: (format) async => pdf.save(),
      );
    } else {
      final printers = await Printing.listPrinters();
      if (printers.isNotEmpty) {
        final fallback =
            printers.where((p) => p.isDefault).firstOrNull ?? printers.first;
        await Printing.directPrintPdf(
          printer: fallback,
          onLayout: (format) async => pdf.save(),
        );
      } else {
        await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      }
    }
  }

  /// Print Return Credit Note - 80mm thermal format
  /// Layout: Company Header → Return Title → Original Invoice Ref → Items Table → Refund Amount → Reason → Footer
  static Future<void> printReturnReceipt({
    required String returnVoucherNumber,
    required String originalInvoiceNumber,
    required DateTime date,
    required List<InvoiceItem> items,
    required double returnTotal,
    required String paymentMethod, // cash, card, transfer, multiple
    double cashRefund = 0,
    double bankRefund = 0,
    String? returnReason,
    String? customerName,
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? employeeName,
    IPrintersRepository? printersRepo,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();

    const thermalFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    // Payment method display
    String paymentText = paymentMethod == 'cash'
        ? 'نقدي'
        : (paymentMethod == 'card' || paymentMethod == 'transfer')
        ? 'تحويل'
        : (paymentMethod == 'multiple' || paymentMethod == 'mixed')
        ? 'متعدد'
        : 'نقدي';

    pdf.addPage(
      pw.Page(
        pageFormat: thermalFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // COMPANY HEADER
            _buildHeader(
              arabicFont,
              companyName,
              null,
              companyPhone,
              companyAddress,
              null,
            ),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 4),

            // RETURN TITLE (red-highlighted)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.red100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'إشعار مرتجع مبيعات',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'Sales Return Credit Note',
                    style: pw.TextStyle(font: arabicFont, fontSize: 10),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 8),

            // RETURN DETAILS
            _thermalRow(arabicFont, returnVoucherNumber, 'رقم المرتجع'),
            _thermalRow(arabicFont, originalInvoiceNumber, 'الفاتورة الأصلية'),
            _thermalRow(
              arabicFont,
              '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              'التاريخ',
            ),
            if (customerName != null)
              _thermalRow(arabicFont, customerName, 'العميل'),
            if (employeeName != null)
              _thermalRow(arabicFont, employeeName, 'الموظف'),

            pw.Divider(thickness: 1),

            // RETURNED ITEMS TABLE
            _buildItemsTable(arabicFont, items),

            pw.Divider(thickness: 1),

            // REFUND AMOUNT (Big & Bold with red border)
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.red, width: 2),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'إجمالي المرتجع / Refund Total',
                    style: pw.TextStyle(font: arabicFont, fontSize: 10),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${returnTotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 4),

            // REFUND METHOD BREAKDOWN
            _thermalRow(arabicFont, paymentText, 'طريقة الاسترداد'),
            if (paymentMethod == 'multiple' || paymentMethod == 'mixed') ...[
              if (cashRefund > 0)
                _thermalRow(
                  arabicFont,
                  '${cashRefund.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  'استرداد نقدي',
                ),
              if (bankRefund > 0)
                _thermalRow(
                  arabicFont,
                  '${bankRefund.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  'استرداد تحويل',
                ),
            ],

            // RETURN REASON
            if (returnReason != null && returnReason.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'السبب:',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                returnReason,
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ],

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 12),

            // SIGNATURES
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'المستلم',
                      style: pw.TextStyle(font: arabicFont, fontSize: 9),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(width: 60, child: pw.Divider(thickness: 0.5)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'المسلم',
                      style: pw.TextStyle(font: arabicFont, fontSize: 9),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(width: 60, child: pw.Divider(thickness: 0.5)),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 8),

            // Footer
            pw.Text(
              'تم الطباعة بواسطة UralCash POS',
              style: pw.TextStyle(font: arabicFont, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    // Resolve printer
    Printer? resolvedPrinter;
    if (printersRepo != null) {
      final dbPrinter = await printersRepo.getActivePrinterByPurpose('pos_receipt');
      if (dbPrinter != null) {
        resolvedPrinter = await PrinterResolver.resolveByPrinter(dbPrinter);
      }
    }

    if (resolvedPrinter != null) {
      await Printing.directPrintPdf(
        printer: resolvedPrinter,
        onLayout: (format) async => pdf.save(),
      );
    } else {
      final printers = await Printing.listPrinters();
      if (printers.isNotEmpty) {
        final fallback =
            printers.where((p) => p.isDefault).firstOrNull ?? printers.first;
        await Printing.directPrintPdf(
          printer: fallback,
          onLayout: (format) async => pdf.save(),
        );
      } else {
        await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      }
    }
  }
}
