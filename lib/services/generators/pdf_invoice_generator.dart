import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/constants/app_constants.dart';
import 'base_generator.dart';
import '../printing/pdf_compute_helper.dart';
import '../../core/config/brand.dart';

/// PDF Invoice Generator (A4 format)
///
/// Handles printing of A4 PDF invoices for sales, purchases, and party statements.
class PdfInvoiceGenerator extends BaseGenerator {
  /// Print sales invoice (A4)
  static Future<void> printSalesInvoice({
    required String invoiceNumber,
    required DateTime date,
    required String? customerName,
    required List<InvoiceItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxId,
    String? notes, // ADDED: pass notes through wrapper
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();
    final remaining = total - paid;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Header
            _buildInvoiceHeader(
              arabicFont,
              invoiceNumber,
              date,
              companyName,
              companyAddress,
              companyPhone,
              companyTaxId,
              total,
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),

            // Title
            pw.Center(
              child: pw.Text(
                'فاتورة مبيعات',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),

            // Customer
            if (customerName != null)
              pw.Text(
                'العميل: $customerName',
                style: pw.TextStyle(font: arabicFont, fontSize: 14),
              ),
            if (notes != null && notes.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                'ملاحظات: $notes',
                style: pw.TextStyle(font: arabicFont, fontSize: 12),
              ),
            ],
            pw.SizedBox(height: 20),

            // Items Table
            _buildItemsTable(arabicFont, items),
            pw.SizedBox(height: 20),

            // Totals
            _buildTotalsSection(
              arabicFont,
              subtotal,
              discount,
              tax,
              total,
              paid,
              remaining,
            ),
            pw.Spacer(),

            // Footer
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'شكراً لتعاملكم معنا',
                style: pw.TextStyle(font: arabicFont, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );

    await PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print purchase invoice (A4)
  static Future<void> printPurchaseInvoice({
    required String invoiceNumber,
    required DateTime date,
    required String supplierName,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'التاريخ: ${date.day}/${date.month}/${date.year}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 12),
                    ),
                    pw.Text(
                      'رقم الفاتورة: $invoiceNumber',
                      style: pw.TextStyle(font: arabicFont, fontSize: 12),
                    ),
                  ],
                ),
                pw.Text(
                  companyName ?? Brand.documentCompanyFallback,
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),

            // Title
            pw.Center(
              child: pw.Text(
                'فاتورة مشتريات',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),

            // Supplier
            pw.Text(
              'المورد: $supplierName',
              style: pw.TextStyle(font: arabicFont, fontSize: 14),
            ),
            pw.SizedBox(height: 20),

            // Items Table
            _buildItemsTable(arabicFont, items),
            pw.SizedBox(height: 20),

            // Totals
            pw.Container(
              alignment: pw.Alignment.centerLeft,
              width: 200,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _totalRow(arabicFont, 'الإجمالي', total, isBold: true),
                  _totalRow(arabicFont, 'المدفوع', paid),
                  if (total - paid > 0)
                    _totalRow(
                      arabicFont,
                      'المتبقي',
                      total - paid,
                      color: PdfColors.red,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    await PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print party statement (A4)
  static Future<void> printPartyStatement({
    required String partyName,
    required String partyType,
    required double currentBalance,
    required List<StatementItem> transactions,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'كشف حساب ${partyType == 'customer' ? 'عميل' : 'مورد'}',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'الاسم: $partyName',
                    style: pw.TextStyle(font: arabicFont, fontSize: 14),
                  ),
                  if (fromDate != null && toDate != null)
                    pw.Text(
                      'الفترة: ${fromDate.day}/${fromDate.month}/${fromDate.year} - ${toDate.day}/${toDate.month}/${toDate.year}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 11),
                    ),
                ],
              ),
              pw.Text(
                companyName ?? Brand.documentCompanyFallback,
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 20),

          // Current Balance
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: currentBalance > 0 ? PdfColors.red50 : PdfColors.green50,
              border: pw.Border.all(
                color: currentBalance > 0 ? PdfColors.red : PdfColors.green,
              ),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'الرصيد الحالي:',
                  style: pw.TextStyle(font: arabicFont, fontSize: 14),
                ),
                pw.Text(
                  '${currentBalance.toStringAsFixed(AppConstants.decimalPlaces)} JOD',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: currentBalance > 0 ? PdfColors.red : PdfColors.green,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Transactions Table
          _buildStatementTable(arabicFont, transactions),
        ],
      ),
    );

    await PdfComputeHelper.layoutPdf(pdf);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  static pw.Widget _buildInvoiceHeader(
    pw.Font font,
    String invoiceNumber,
    DateTime date,
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxId,
    double total,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'التاريخ: ${date.day}/${date.month}/${date.year}',
              style: pw.TextStyle(font: font, fontSize: 12),
            ),
            pw.Text(
              'رقم الفاتورة: $invoiceNumber',
              style: pw.TextStyle(font: font, fontSize: 12),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              companyName ?? Brand.documentCompanyFallback,
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (companyAddress != null)
              pw.Text(
                companyAddress,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            if (companyPhone != null)
              pw.Text(
                'هاتف: $companyPhone',
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            if (companyTaxId != null)
              pw.Text(
                'السجل الضريبي: $companyTaxId',
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
          ],
        ),
        // QR Code for invoice verification
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data:
              'INV:$invoiceNumber|DATE:${date.day}/${date.month}/${date.year}|TOTAL:$total',
          width: 60,
          height: 60,
        ),
      ],
    );
  }

  static pw.Widget _buildItemsTable(pw.Font font, List<InvoiceItem> items) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'م', isHeader: true),
            _tableCell(font, 'الصنف', isHeader: true),
            _tableCell(font, 'الكمية', isHeader: true),
            _tableCell(font, 'السعر', isHeader: true),
            _tableCell(font, 'الإجمالي', isHeader: true),
          ],
        ),
        // Items
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return pw.TableRow(
            children: [
              _tableCell(font, '${i + 1}'),
              _tableCell(font, item.name),
              _tableCell(font, item.quantity.toString()),
              _tableCell(font, item.price.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, item.total.toStringAsFixed(AppConstants.decimalPlaces)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildStatementTable(
    pw.Font font,
    List<StatementItem> transactions,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'التاريخ', isHeader: true),
            _tableCell(font, 'البيان', isHeader: true),
            _tableCell(font, 'مدين', isHeader: true),
            _tableCell(font, 'دائن', isHeader: true),
            _tableCell(font, 'الرصيد', isHeader: true),
          ],
        ),
        ...transactions.map(
          (t) => pw.TableRow(
            children: [
              _tableCell(font, '${t.date.day}/${t.date.month}/${t.date.year}'),
              _tableCell(font, t.description),
              _tableCell(font, t.debit > 0 ? t.debit.toStringAsFixed(AppConstants.decimalPlaces) : '-'),
              _tableCell(
                font,
                t.credit > 0 ? t.credit.toStringAsFixed(AppConstants.decimalPlaces) : '-',
              ),
              _tableCell(font, t.balance.toStringAsFixed(AppConstants.decimalPlaces)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTotalsSection(
    pw.Font font,
    double subtotal,
    double discount,
    double tax,
    double total,
    double paid,
    double remaining,
  ) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      width: 200,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _totalRow(font, 'المجموع', subtotal),
          if (discount > 0) _totalRow(font, 'الخصم', -discount),
          if (tax > 0) _totalRow(font, 'الضريبة', tax),
          pw.Divider(),
          _totalRow(font, 'الإجمالي', total, isBold: true),
          _totalRow(font, 'المدفوع', paid),
          if (remaining > 0)
            _totalRow(font, 'المتبقي', remaining, color: PdfColors.red),
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
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _totalRow(
    pw.Font font,
    String label,
    double amount, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: font,
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(AppConstants.decimalPlaces)} JOD',
            style: pw.TextStyle(
              font: font,
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
