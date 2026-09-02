// ignore_for_file: avoid_dynamic_calls
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'base_generator.dart';
import '../printing/pdf_compute_helper.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/brand.dart';

/// Report Generator (A4 format)
///
/// Handles printing of various business reports including:
/// - Inventory reports
/// - Treasury reports
/// - Sales reports
/// - Purchases reports
/// - Category reports
/// - Financial statements
class ReportGenerator extends BaseGenerator {
  /// Print inventory report
  static Future<bool> printInventoryReport({
    required List<dynamic> products,
    String? companyName,
    Map<int, String>? categoryMap,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    // Calculate totals
    double totalValue = 0;
    int totalProducts = products.length;
    int lowStockCount = 0;

    for (final p in products) {
      totalValue += (p.currentStock * p.costPrice);
      if (p.currentStock <= p.minStock && p.trackInventory) {
        lowStockCount++;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            arabicFont,
            'تقرير أرصدة المخزون',
            companyName,
            now,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Summary
          _buildSummaryBox(
            arabicFont,
            [
              SummaryItem('عدد الأصناف', '$totalProducts'),
              SummaryItem(
                'أصناف منخفضة',
                '$lowStockCount',
                color: PdfColors.red,
              ),
              SummaryItem(
                'قيمة المخزون',
                '${totalValue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
              ),
            ],
            PdfColors.blue50,
            PdfColors.blue,
          ),
          pw.SizedBox(height: 20),

          // Products Table
          _buildInventoryTable(arabicFont, products, categoryMap),
        ],
      ),
    );

    return PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print treasury report
  static Future<bool> printTreasuryReport({
    required List<dynamic> transactions,
    required double openingBalance,
    required double totalIn,
    required double totalOut,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeaderWithDateRange(
            arabicFont,
            'تقرير حركة الخزينة',
            companyName,
            now,
            fromDate,
            toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Summary
          _buildTreasurySummary(
            arabicFont,
            openingBalance,
            totalIn,
            totalOut,
            closingBalance,
          ),
          pw.SizedBox(height: 20),

          // Transactions Table
          _buildTreasuryTable(arabicFont, transactions),
        ],
      ),
    );

    return PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print sales report
  static Future<bool> printSalesReport({
    required List<dynamic> invoices,
    required double totalSales,
    required double totalProfit,
    required int invoiceCount,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeaderWithDateRange(
            arabicFont,
            'تقرير المبيعات التفصيلي',
            companyName,
            now,
            fromDate,
            toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Summary
          _buildSummaryBox(
            arabicFont,
            [
              SummaryItem(
                'إجمالي المبيعات',
                '${totalSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                isBold: true,
              ),
              SummaryItem(
                'صافي الأرباح',
                '${totalProfit.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                color: PdfColors.green,
              ),
              SummaryItem('عدد الفواتير', '$invoiceCount'),
            ],
            PdfColors.green50,
            PdfColors.green,
          ),
          pw.SizedBox(height: 20),

          // Invoices Table
          _buildSalesTable(arabicFont, invoices),
        ],
      ),
    );

    return PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print purchases report
  static Future<bool> printPurchasesReport({
    required List<dynamic> invoices,
    required double totalPurchases,
    required double totalOutstanding,
    required int invoiceCount,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeaderWithDateRange(
            arabicFont,
            'تقرير المشتريات التفصيلي',
            companyName,
            now,
            fromDate,
            toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Summary
          _buildSummaryBox(
            arabicFont,
            [
              SummaryItem(
                'إجمالي المشتريات',
                '${totalPurchases.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                isBold: true,
              ),
              SummaryItem(
                'المستحقات',
                '${totalOutstanding.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                color: PdfColors.red,
              ),
              SummaryItem('عدد الفواتير', '$invoiceCount'),
            ],
            PdfColors.orange50,
            PdfColors.orange,
          ),
          pw.SizedBox(height: 20),

          // Invoices Table (reuse sales table structure)
          _buildPurchasesTable(arabicFont, invoices),
        ],
      ),
    );

    return PdfComputeHelper.layoutPdf(pdf);
  }

  /// Print category report (sales by category or classification)
  static Future<bool> printCategoryReport({
    required List<Map<String, dynamic>> categories,
    required double totalSales,
    required bool isCategory,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeaderWithDateRange(
            arabicFont,
            isCategory
                ? 'تقرير المبيعات حسب التصنيف'
                : 'تقرير المبيعات حسب الفئة',
            companyName,
            now,
            fromDate,
            toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Total
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'إجمالي المبيعات:',
                  style: pw.TextStyle(font: arabicFont, fontSize: 14),
                ),
                pw.Text(
                  '${totalSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Categories Table
          _buildCategoryTable(arabicFont, categories, totalSales),
        ],
      ),
    );

    return PdfComputeHelper.layoutPdf(pdf);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  static pw.Widget _buildReportHeader(
    pw.Font font,
    String title,
    String? companyName,
    DateTime now,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'التاريخ: ${now.day}/${now.month}/${now.year}',
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
          ],
        ),
        pw.Text(
          companyName ?? Brand.documentCompanyFallback,
          style: pw.TextStyle(
            font: font,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildReportHeaderWithDateRange(
    pw.Font font,
    String title,
    String? companyName,
    DateTime now,
    DateTime? fromDate,
    DateTime? toDate,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (fromDate != null && toDate != null)
              pw.Text(
                'الفترة: ${fromDate.day}/${fromDate.month}/${fromDate.year} - ${toDate.day}/${toDate.month}/${toDate.year}',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            pw.Text(
              'تاريخ الطباعة: ${now.day}/${now.month}/${now.year}',
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ],
        ),
        pw.Text(
          companyName ?? Brand.documentCompanyFallback,
          style: pw.TextStyle(
            font: font,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryBox(
    pw.Font font,
    List<SummaryItem> items,
    PdfColor bgColor,
    PdfColor borderColor,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: items
            .map(
              (item) => pw.Column(
                children: [
                  pw.Text(
                    item.label,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10,
                      color: item.color,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    item.value,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 12,
                      fontWeight: item.isBold
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      color: item.color,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  static pw.Widget _buildTreasurySummary(
    pw.Font font,
    double opening,
    double totalIn,
    double totalOut,
    double closing,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryColumn(font, 'الرصيد الافتتاحي', opening),
          _summaryColumn(
            font,
            'إجمالي الإيرادات',
            totalIn,
            color: PdfColors.green,
          ),
          _summaryColumn(
            font,
            'إجمالي المصروفات',
            totalOut,
            color: PdfColors.red,
          ),
          _summaryColumn(font, 'الرصيد الختامي', closing, isBold: true),
        ],
      ),
    );
  }

  static pw.Widget _summaryColumn(
    pw.Font font,
    String label,
    double value, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
          style: pw.TextStyle(
            font: font,
            fontSize: 11,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInventoryTable(
    pw.Font font,
    List<dynamic> products,
    Map<int, String>? categoryMap,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
        5: pw.FlexColumnWidth(2),
        6: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'م', isHeader: true),
            _tableCell(font, 'الصنف', isHeader: true),
            _tableCell(font, 'التصنيف', isHeader: true),
            _tableCell(font, 'الرصيد', isHeader: true),
            _tableCell(font, 'الحد الأدنى', isHeader: true),
            _tableCell(font, 'سعر التكلفة', isHeader: true),
            _tableCell(font, 'القيمة', isHeader: true),
          ],
        ),
        ...products.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final isLowStock = p.currentStock <= p.minStock && p.trackInventory;
          final categoryName = categoryMap != null && p.categoryId != null
              ? categoryMap[p.categoryId] ?? '-'
              : '-';
          return pw.TableRow(
            decoration: isLowStock
                ? const pw.BoxDecoration(color: PdfColors.red50)
                : null,
            children: [
              _tableCell(font, '${i + 1}'),
              _tableCell(font, p.name),
              _tableCell(font, categoryName),
              _tableCell(font, p.currentStock.toStringAsFixed(0)),
              _tableCell(font, p.minStock.toStringAsFixed(0)),
              _tableCell(font, p.costPrice.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(
                font,
                (p.currentStock * p.costPrice).toStringAsFixed(AppConstants.decimalPlaces),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTreasuryTable(
    pw.Font font,
    List<dynamic> transactions,
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
            _tableCell(font, 'إيرادات', isHeader: true),
            _tableCell(font, 'مصروفات', isHeader: true),
            _tableCell(font, 'الرصيد', isHeader: true),
          ],
        ),
        ...transactions.map(
          (t) => pw.TableRow(
            children: [
              _tableCell(
                font,
                '${t.transactionDate.day}/${t.transactionDate.month}/${t.transactionDate.year}',
              ),
              _tableCell(font, t.description ?? t.category),
              _tableCell(
                font,
                t.transactionType == 'receipt'
                    ? t.amount.toStringAsFixed(AppConstants.decimalPlaces)
                    : '-',
              ),
              _tableCell(
                font,
                t.transactionType == 'payment'
                    ? t.amount.toStringAsFixed(AppConstants.decimalPlaces)
                    : '-',
              ),
              _tableCell(font, '-'), // Running balance - would need calculation
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSalesTable(pw.Font font, List<dynamic> invoices) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
        5: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'رقم الفاتورة', isHeader: true),
            _tableCell(font, 'التاريخ', isHeader: true),
            _tableCell(font, 'الإجمالي', isHeader: true),
            _tableCell(font, 'المدفوع', isHeader: true),
            _tableCell(font, 'المتبقي', isHeader: true),
            _tableCell(font, 'طريقة الدفع', isHeader: true),
          ],
        ),
        ...invoices.map((inv) {
          final remaining = inv.total - inv.paid;
          return pw.TableRow(
            children: [
              _tableCell(font, inv.invoiceNumber),
              _tableCell(
                font,
                '${inv.invoiceDate.day}/${inv.invoiceDate.month}/${inv.invoiceDate.year}',
              ),
              _tableCell(font, inv.total.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, inv.paid.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, remaining.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, inv.paymentMethod == 'cash' ? 'نقدي' : 'آجل'),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildPurchasesTable(pw.Font font, List<dynamic> invoices) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
        5: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'رقم الفاتورة', isHeader: true),
            _tableCell(font, 'المورد', isHeader: true),
            _tableCell(font, 'التاريخ', isHeader: true),
            _tableCell(font, 'الإجمالي', isHeader: true),
            _tableCell(font, 'المدفوع', isHeader: true),
            _tableCell(font, 'المتبقي', isHeader: true),
          ],
        ),
        ...invoices.map((inv) {
          final remaining = inv.total - inv.paid;
          return pw.TableRow(
            children: [
              _tableCell(font, inv.invoiceNumber),
              _tableCell(font, inv.supplierName ?? '-'),
              _tableCell(
                font,
                '${inv.invoiceDate.day}/${inv.invoiceDate.month}/${inv.invoiceDate.year}',
              ),
              _tableCell(font, inv.total.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, inv.paid.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, remaining.toStringAsFixed(AppConstants.decimalPlaces)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildCategoryTable(
    pw.Font font,
    List<Map<String, dynamic>> categories,
    double totalSales,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell(font, 'م', isHeader: true),
            _tableCell(font, 'التصنيف', isHeader: true),
            _tableCell(font, 'المبيعات', isHeader: true),
            _tableCell(font, 'النسبة', isHeader: true),
          ],
        ),
        ...categories.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          final sales = (cat['sales'] as num?)?.toDouble() ?? 0;
          final percentage = totalSales > 0 ? (sales / totalSales * 100) : 0;
          return pw.TableRow(
            children: [
              _tableCell(font, '${i + 1}'),
              _tableCell(font, cat['name'] ?? '-'),
              _tableCell(font, sales.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(font, '${percentage.toStringAsFixed(1)}%'),
            ],
          );
        }),
      ],
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
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}

/// Summary item for report boxes
class SummaryItem {
  final String label;
  final String value;
  final bool isBold;
  final PdfColor? color;

  SummaryItem(this.label, this.value, {this.isBold = false, this.color});
}
