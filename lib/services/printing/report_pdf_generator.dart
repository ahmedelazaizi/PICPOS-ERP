// ignore_for_file: avoid_dynamic_calls
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import 'printing_models.dart';
import '../../core/constants/app_constants.dart';
import 'pdf_compute_helper.dart';
import 'package:intl/intl.dart';
import '../generators/base_generator.dart' hide InvoiceItem, StatementItem;
import '../../core/config/brand.dart';

class ReportPdfGenerator {
  static pw.Font? _arabicFont;

  static Future<void> _initFont() async {
    _arabicFont ??= await BaseGenerator.initFont();
  }

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
    String? notes,
    String title = 'فاتورة مبيعات',
    String? printedBy,
  }) async {
    await PdfComputeHelper.layoutPdf(await buildSalesInvoiceDocument(
      invoiceNumber: invoiceNumber,
      date: date,
      customerName: customerName,
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      companyName: companyName,
      companyAddress: companyAddress,
      companyPhone: companyPhone,
      companyTaxId: companyTaxId,
      notes: notes,
      title: title,
      printedBy: printedBy,
    ));
  }

  /// Builds the A4 sales-invoice document. Split out of [printSalesInvoice] so
  /// the real widget tree can be asserted on without a platform channel —
  /// PdfComputeHelper.layoutPdf needs one, which previously forced the PDF
  /// tests to re-implement the layout instead of exercising it.
  ///
  /// ⚠️ MultiPage, not Page. `pw.Table` is a SpanningWidget (pdf-3.12.0
  /// table.dart:250) but only a MultiPage drives the spanning protocol; inside
  /// a plain Page it truncates at `if (totalHeight + lineHeight >
  /// constraints.maxHeight) { index--; break; }` (table.dart:473) and the
  /// totals block that follows lays out beyond the page bounds and never
  /// prints. A 35-line wholesale invoice printed ~20 lines with NO totals,
  /// no exception and no log — a commercial document silently handed to a
  /// customer with data missing.
  static Future<pw.Document> buildSalesInvoiceDocument({
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
    String? notes,
    String title = 'فاتورة مبيعات',
    String? printedBy,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final remaining = total - paid;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        // Repeated per page so page 2+ still identifies the invoice.
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _buildA4Header(
              date,
              invoiceNumber,
              companyName,
              companyAddress,
              companyPhone,
              companyTaxId,
              total,
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
          ],
        ),
        footer: (context) => _buildA4Footer(
          printedBy: printedBy,
          pageNumber: context.pageNumber,
          pagesCount: context.pagesCount,
        ),
        build: (context) => [
          if (customerName != null)
            pw.Text(
              'العميل: $customerName',
              style: pw.TextStyle(font: _arabicFont, fontSize: 14),
            ),
          if (notes != null && notes.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'ملاحظات: $notes',
              style: pw.TextStyle(font: _arabicFont, fontSize: 12),
            ),
          ],
          pw.SizedBox(height: 20),
          _buildItemsTable(items),
          pw.SizedBox(height: 20),
          // Last element in `build`, so it flows onto whatever page the table
          // ends on (or its own) instead of being laid out off-page.
          _buildTotalsSection(
            subtotal,
            discount,
            tax,
            total,
            paid,
            remaining,
          ),
        ],
      ),
    );
    return pdf;
  }

  static pw.Widget _buildA4Footer({
    String? printedBy,
    int? pageNumber,
    int? pagesCount,
  }) {
    final now = DateTime.now();
    final dateStr = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return pw.Column(
      children: [
        pw.Divider(),
        if (printedBy != null && printedBy.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'طبع بواسطة: $printedBy',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                ),
                pw.Text(
                  'تاريخ الطباعة: $dateStr',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                ),
              ],
            ),
          ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'شكراً لتعاملكم معنا',
              style: pw.TextStyle(font: _arabicFont, fontSize: 10),
            ),
            // Page marker — on a multi-page invoice the recipient must be able
            // to tell a short print from a missing page.
            if (pageNumber != null && pagesCount != null)
              pw.Text(
                'صفحة $pageNumber من $pagesCount',
                style: pw.TextStyle(font: _arabicFont, fontSize: 9),
              ),
            pw.Text(
              'نظام ${Brand.name}',
              style: pw.TextStyle(font: _arabicFont, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> printPurchaseInvoice({
    required String invoiceNumber,
    required DateTime date,
    required String supplierName,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    String? companyName,
    bool isReturn = false,
  }) async {
    await PdfComputeHelper.layoutPdf(await buildPurchaseInvoiceDocument(
      invoiceNumber: invoiceNumber,
      date: date,
      supplierName: supplierName,
      items: items,
      total: total,
      paid: paid,
      companyName: companyName,
      isReturn: isReturn,
    ));
  }

  /// Builds the A4 purchase-invoice document. Same MultiPage rationale as
  /// [buildSalesInvoiceDocument] — a plain Page silently dropped every line
  /// past the first page along with the totals block.
  static Future<pw.Document> buildPurchaseInvoiceDocument({
    required String invoiceNumber,
    required DateTime date,
    required String supplierName,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    String? companyName,
    bool isReturn = false,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _buildA4Header(
              date,
              invoiceNumber,
              companyName,
              null,
              null,
              null,
              total,
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
          ],
        ),
        footer: (context) => _buildA4Footer(
          pageNumber: context.pageNumber,
          pagesCount: context.pagesCount,
        ),
        build: (context) => [
          pw.Text(
            'المورد: $supplierName',
            style: pw.TextStyle(font: _arabicFont, fontSize: 14),
          ),
          pw.SizedBox(height: 20),
          _buildItemsTable(items, showBarcode: true),
          pw.SizedBox(height: 20),
          _buildTotalsSection(total, 0, 0, total, paid, total - paid),
        ],
      ),
    );
    return pdf;
  }

  static Future<void> printPartyStatement({
    required String partyName,
    required String partyType,
    required double currentBalance,
    required List<StatementItem> transactions,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
    DocumentCompanyHeader? company,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();

    // The registered company identity. `company` is the full record read from
    // settings; `companyName` stays for older callers that only had a name.
    // DocumentCompanyHeader supplies its own fallback for a blank name, so this
    // deliberately does not reach for a brand constant — the header must depend
    // only on what the operator registered in settings.
    final header = company ?? DocumentCompanyHeader(name: companyName ?? '');
    final layout = StatementColumnLayout.forItems(transactions);
    final totals = StatementTotals.from(transactions);
    final printedAt = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
        // رأس الصفحة يتكرّر على **كل** صفحة — كشف من عدة صفحات كانت صفحاته
        // التالية تخرج بلا أي هوية للشركة.
        header: (context) => _buildCompanyLetterhead(header),
        footer: (context) => _buildDocumentFooter(header, context, printedAt),
        build: (context) => [
          _buildStatementHeader(partyName, partyType, fromDate, toDate),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 12),
          _buildBalanceBox(currentBalance),
          pw.SizedBox(height: 12),
          _buildStatementTable(transactions, layout, totals),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  /// ترويسة الشركة: الاسم ثم الهاتف والعنوان ثم الرقم الضريبي.
  ///
  /// Rendered as a page `header` so it repeats on every page of a multi-page
  /// statement. Only present fields are drawn — no blank lines, no dangling
  /// separators.
  static pw.Widget _buildCompanyLetterhead(DocumentCompanyHeader c) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey600, width: 1.2),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            c.displayName,
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (c.hasContactInfo)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                c.contactLine,
                style: pw.TextStyle(
                    font: _arabicFont, fontSize: 9, color: PdfColors.grey800),
              ),
            ),
          if (c.taxLine.isNotEmpty)
            pw.Text(
              c.taxLine,
              style: pw.TextStyle(
                  font: _arabicFont, fontSize: 9, color: PdfColors.grey800),
            ),
        ],
      ),
    );
  }

  /// تذييل الصفحة: هوية الشركة مختصرة + تاريخ الطباعة + ترقيم الصفحات.
  static pw.Widget _buildDocumentFooter(
    DocumentCompanyHeader c,
    pw.Context context,
    DateTime printedAt,
  ) {
    final stamp = '${printedAt.year}/${printedAt.month}/${printedAt.day} '
        '${printedAt.hour.toString().padLeft(2, '0')}:'
        '${printedAt.minute.toString().padLeft(2, '0')}';
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(
                font: _arabicFont, fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            c.hasContactInfo ? '${c.displayName}  ·  ${c.contactLine}' : c.displayName,
            style: pw.TextStyle(
                font: _arabicFont, fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            'طُبع في $stamp',
            style: pw.TextStyle(
                font: _arabicFont, fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static Future<void> printInventoryReport({
    required List<dynamic> products,
    String? companyName,
    Map<int, String>? categoryMap,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();
    double totalValue = 0;
    int lowStockCount = 0;
    for (final p in products) {
      totalValue += (p.currentStock * p.costPrice);
      if (p.currentStock <= p.minStock && p.trackInventory) lowStockCount++;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader('تقرير أرصدة المخزون', now, companyName),
          pw.SizedBox(height: 10),
          pw.Divider(),
          _buildInventorySummary(products.length, lowStockCount, totalValue),
          pw.SizedBox(height: 20),
          _buildInventoryTable(products, categoryMap),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printTreasuryReport({
    required List<dynamic> transactions,
    required double openingBalance,
    required double totalIn,
    required double totalOut,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            'تقرير حركة الخزينة',
            now,
            companyName,
            from: fromDate,
            to: toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          _buildFinanceSummary(
            openingBalance,
            totalIn,
            totalOut,
            closingBalance,
          ),
          pw.SizedBox(height: 20),
          _buildTreasuryTable(transactions),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printSalesReport({
    required List<dynamic> invoices,
    required double totalSales,
    required double totalProfit,
    required int invoiceCount,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
    String? printedBy,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            'تقرير المبيعات التفصيلي',
            now,
            companyName,
            from: fromDate,
            to: toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          _buildSalesSummary(totalSales, totalProfit, invoiceCount),
          pw.SizedBox(height: 20),
          _buildSalesTable(invoices),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printFixedAssetsRegister({
    required List<dynamic> assets,
    required double totalCost,
    required double totalDepreciation,
    required double totalBookValue,
    String? companyName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader('سجل الأصول الثابتة', now, companyName),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sumCol('إجمالي التكلفة', totalCost.toStringAsFixed(AppConstants.decimalPlaces)),
              _sumCol('مجمع الإهلاك', totalDepreciation.toStringAsFixed(AppConstants.decimalPlaces)),
              _sumCol('صافي القيمة الدفترية', totalBookValue.toStringAsFixed(AppConstants.decimalPlaces)),
              _sumCol('عدد الأصول', assets.length.toString()),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(2),
              6: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('الكود', isHeader: true),
                  _tableCell('الاسم', isHeader: true),
                  _tableCell('تاريخ الشراء', isHeader: true),
                  _tableCell('تكلفة الشراء', isHeader: true),
                  _tableCell('مجمع الإهلاك', isHeader: true),
                  _tableCell('القيمة الدفترية', isHeader: true),
                  _tableCell('الحالة', isHeader: true),
                ],
              ),
              ...assets.map((asset) {
                final cost = asset.purchasePrice as double;
                final accDep = asset.accumulatedDepreciation as double;
                final bookVal = cost - accDep;
                return pw.TableRow(
                  children: [
                    _tableCell(asset.code),
                    _tableCell(asset.name),
                    _tableCell(DateFormat('yyyy/MM/dd').format(asset.purchaseDate)),
                    _tableCell(cost.toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell(accDep.toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell(bookVal.toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell(asset.status == 'active' ? 'نشط' : 'مستبعد'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printGeneralLedger({
    required String accountName,
    required List<Map<String, dynamic>> data,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader('دفتر الأستاذ التحليلي', now, companyName, from: fromDate, to: toDate),
          pw.SizedBox(height: 10),
          pw.Text('الحساب: $accountName', style: pw.TextStyle(font: _arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.5),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('التاريخ', isHeader: true),
                  _tableCell('القيد', isHeader: true),
                  _tableCell('البيان', isHeader: true),
                  _tableCell('مدين', isHeader: true),
                  _tableCell('دائن', isHeader: true),
                  _tableCell('الرصيد', isHeader: true),
                ],
              ),
              ...data.map((row) {
                final isOpening = row['is_opening'] == true;
                final date = row['entry_date'];
                final dateStr = date is DateTime ? DateFormat('yyyy/MM/dd').format(date) : '';
                return pw.TableRow(
                  decoration: isOpening ? const pw.BoxDecoration(color: PdfColors.blue50) : null,
                  children: [
                    _tableCell(dateStr),
                    _tableCell(row['entry_number']?.toString() ?? ''),
                    _tableCell(row['description']?.toString() ?? ''),
                    _tableCell((row['debit'] as double? ?? 0).toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell((row['credit'] as double? ?? 0).toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell((row['balance'] as double? ?? 0).toStringAsFixed(AppConstants.decimalPlaces)),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  // --- Helper Widgets ---

  static pw.Widget _buildA4Header(
    DateTime date,
    String invNum,
    String? comp,
    String? addr,
    String? phone,
    String? taxId,
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
              style: pw.TextStyle(font: _arabicFont, fontSize: 12),
            ),
            pw.Text(
              'رقم الفاتورة: $invNum',
              style: pw.TextStyle(font: _arabicFont, fontSize: 12),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              comp ?? Brand.documentCompanyFallback,
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (addr != null)
              pw.Text(
                addr,
                style: pw.TextStyle(font: _arabicFont, fontSize: 10),
              ),
            if (phone != null)
              pw.Text(
                'هاتف: $phone',
                style: pw.TextStyle(font: _arabicFont, fontSize: 10),
              ),
            if (taxId != null)
              pw.Text(
                'السجل الضريبي: $taxId',
                style: pw.TextStyle(font: _arabicFont, fontSize: 10),
              ),
          ],
        ),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: 'INV:$invNum|TOTAL:$total',
          width: 60,
          height: 60,
        ),
      ],
    );
  }

  static pw.Widget _buildItemsTable(
    List<InvoiceItem> items, {
    bool showBarcode = false,
  }) {
    // Field-report 2026-05-14: operator asked for the product barcode to
    // appear on purchase invoice & purchase return prints (it helps
    // staff reconcile the printed sheet against shelved stock). Gated
    // behind `showBarcode` so sales A4 prints keep their existing layout.
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(4),
      if (showBarcode) 2: const pw.FlexColumnWidth(2),
      (showBarcode ? 3 : 2): const pw.FlexColumnWidth(1),
      (showBarcode ? 4 : 3): const pw.FlexColumnWidth(2),
      (showBarcode ? 5 : 4): const pw.FlexColumnWidth(2),
    };
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: colWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('م', isHeader: true),
            _tableCell('الصنف', isHeader: true),
            if (showBarcode) _tableCell('الباركود', isHeader: true),
            _tableCell('الكمية', isHeader: true),
            _tableCell('السعر', isHeader: true),
            _tableCell('الإجمالي', isHeader: true),
          ],
          // Repeated on every page of a multi-page invoice — otherwise page 2
          // is a wall of unlabelled numbers.
          repeat: true,
        ),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return pw.TableRow(
            children: [
              _tableCell('${i + 1}'),
              _tableCell(item.name),
              if (showBarcode) _tableCell(item.barcode ?? ''),
              _tableCell(item.quantity.toString()),
              _tableCell(
                item.price.toStringAsFixed(AppConstants.decimalPlaces),
              ),
              _tableCell(
                item.total.toStringAsFixed(AppConstants.decimalPlaces),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTotalsSection(
    double sub,
    double disc,
    double tax,
    double total,
    double paid,
    double rem,
  ) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      width: 200,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _totalRow('المجموع', sub),
          if (disc > 0) _totalRow('الخصم', -disc),
          if (tax > 0) _totalRow('الضريبة', tax),
          pw.Divider(),
          _totalRow('الإجمالي', total, isBold: true),
          _totalRow('المدفوع', paid),
          if (rem > 0) _totalRow('المتبقي', rem, color: PdfColors.red),
        ],
      ),
    );
  }

  static Future<void> printCategoryReport({
    required List<Map<String, dynamic>> categories,
    required double totalSales,
    required bool isCategory,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();
    final title = isCategory
        ? 'تقرير المبيعات حسب التصنيف'
        : 'تقرير المبيعات حسب نوع البيع';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            title,
            now,
            companyName,
            from: fromDate,
            to: toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _sumCol(
                  'إجمالي المبيعات',
                  totalSales.toStringAsFixed(AppConstants.decimalPlaces),
                  isBold: true,
                ),
                _sumCol(
                  isCategory ? 'عدد التصنيفات' : 'عدد الأنواع',
                  '${categories.length}',
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('م', isHeader: true),
                  _tableCell(
                    isCategory ? 'التصنيف' : 'نوع البيع',
                    isHeader: true,
                  ),
                  _tableCell(isCategory ? 'الكمية' : 'العدد', isHeader: true),
                  _tableCell('القيمة', isHeader: true),
                  _tableCell('النسبة', isHeader: true),
                ],
              ),
              ...categories.asMap().entries.map((entry) {
                final val = entry.value['total'] as double;
                final pct = totalSales > 0 ? (val / totalSales) * 100 : 0;
                return pw.TableRow(
                  children: [
                    _tableCell('${entry.key + 1}'),
                    _tableCell(
                      isCategory
                          ? (entry.value['category'] ?? '-')
                          : (entry.value['type'] ?? '-'),
                    ),
                    _tableCell(
                      isCategory
                          ? (entry.value['quantity'] as double).toStringAsFixed(
                              1,
                            )
                          : (entry.value['count'] as int).toString(),
                    ),
                    _tableCell(val.toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell('${pct.toStringAsFixed(1)}%'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printFinancialStatement({
    required String title,
    required List<dynamic> data,
    required String statementType,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            title,
            now,
            companyName,
            from: fromDate,
            to: toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 15),
          if (statementType == 'trial_balance')
            _buildTrialBalanceContent(data.cast<Map<String, dynamic>>()),
          if (statementType == 'income_statement')
            _buildIncomeStatementContent(data[0] as Map<String, dynamic>),
          if (statementType == 'balance_sheet')
            _buildBalanceSheetContent(data[0] as Map<String, dynamic>),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printTreasuryClosingReport({
    required List<Map<String, dynamic>> safeData,
    required double totalSystem,
    required double totalActual,
    required double totalVariance,
    String? companyName,
    String? employeeName,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader('محضر جرد وإقفال الخزينة', now, companyName),
          if (employeeName != null)
            pw.Text(
              'الموظف: $employeeName',
              style: pw.TextStyle(font: _arabicFont, fontSize: 11),
            ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _sumCol('رصيد النظام', totalSystem.toStringAsFixed(AppConstants.decimalPlaces)),
                _sumCol('الرصيد الفعلي', totalActual.toStringAsFixed(AppConstants.decimalPlaces)),
                _sumCol(
                  'الفارق',
                  totalVariance.toStringAsFixed(AppConstants.decimalPlaces),
                  color: totalVariance == 0 ? PdfColors.green : PdfColors.red,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('الخزينة', isHeader: true),
                  _tableCell('النظام', isHeader: true),
                  _tableCell('الفعلي', isHeader: true),
                  _tableCell('الفارق', isHeader: true),
                ],
              ),
              ...safeData.map(
                (safe) => pw.TableRow(
                  children: [
                    _tableCell(safe['name']),
                    _tableCell((safe['system'] as double).toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell((safe['actual'] as double).toStringAsFixed(AppConstants.decimalPlaces)),
                    _tableCell(
                      (safe['variance'] as double).toStringAsFixed(AppConstants.decimalPlaces),
                      color: (safe['variance'] as double) < 0
                          ? PdfColors.red
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static Future<void> printBarcodeLabel({
    required String barcodeValue,
    required String productName,
    double? price,
    int copies = 1,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    const labelWidth = 50.0 * PdfPageFormat.mm;
    const labelHeight = 25.0 * PdfPageFormat.mm;
    const labelFormat = PdfPageFormat(
      labelWidth,
      labelHeight,
      marginAll: 2 * PdfPageFormat.mm,
    );

    for (int i = 0; i < copies; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: labelFormat,
          // The only page in this file that omitted textDirection, so Arabic
          // product names printed as disconnected, reversed glyphs on shelf
          // labels — the one print an operator reads dozens of times a day.
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                productName,
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
                maxLines: 1,
              ),
              pw.SizedBox(height: 2),
              pw.BarcodeWidget(
                data: barcodeValue,
                barcode: pw.Barcode.code128(),
                width: labelWidth - 10,
                height: 15,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 5),
              ),
              if (price != null)
                pw.Text(
                  // Was the literal 'JOD'. The label ignored the company's
                  // configured currency, so every non-Jordanian install
                  // printed the wrong unit on its shelf tags.
                  '${price.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static String _fmtNum(dynamic val) {
    if (val == null) return '-';
    final d = (val is num) ? val.toDouble() : 0.0;
    if (d == 0) return '-';
    return d.toStringAsFixed(AppConstants.decimalPlaces);
  }

  static pw.Widget _buildTrialBalanceContent(List<Map<String, dynamic>> data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('كود', isHeader: true),
            _tableCell('الحساب', isHeader: true),
            _tableCell('حركة مدين', isHeader: true),
            _tableCell('حركة دائن', isHeader: true),
            _tableCell('رصيد مدين', isHeader: true),
            _tableCell('رصيد دائن', isHeader: true),
          ],
        ),
        ...data.map(
          (row) => pw.TableRow(
            decoration: row['type'] == 'total'
                ? const pw.BoxDecoration(color: PdfColors.grey100)
                : null,
            children: [
              _tableCell(row['code']?.toString() ?? '-'),
              _tableCell(row['name']?.toString() ?? '-'),
              _tableCell(_fmtNum(row['movementDebit'])),
              _tableCell(_fmtNum(row['movementCredit'])),
              _tableCell(_fmtNum(row['closingDebit'])),
              _tableCell(_fmtNum(row['closingCredit'])),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildIncomeStatementContent(Map<String, dynamic> data) {
    final revenueDetails = (data['revenueDetails'] as List?) ?? [];
    final expenseDetails = (data['expenseDetails'] as List?) ?? [];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('الإيرادات', style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        ...revenueDetails.map((item) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_fmtNum(item['amount']), style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
            pw.Text(item['name']?.toString() ?? '-', style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
          ],
        )),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_fmtNum(data['totalRevenue']), style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('إجمالي الإيرادات', style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 15),
        pw.Text('المصروفات', style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        ...expenseDetails.map((item) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_fmtNum(item['amount']), style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
            pw.Text(item['name']?.toString() ?? '-', style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
          ],
        )),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_fmtNum(data['totalExpenses']), style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('إجمالي المصروفات', style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 15),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(_fmtNum(data['netProfit']), style: pw.TextStyle(font: _arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('صافي الربح', style: pw.TextStyle(font: _arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      ],
    );
  }

  static pw.Widget _buildBalanceSheetContent(Map<String, dynamic> data) {
    final assetDetails = (data['assetDetails'] as List?) ?? [];
    final liabilityDetails = (data['liabilityDetails'] as List?) ?? [];
    final equityDetails = (data['equityDetails'] as List?) ?? [];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('الأصول', style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        ...assetDetails.map((item) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_fmtNum(item['balance']), style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
            pw.Text(item['name']?.toString() ?? '-', style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
          ],
        )),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_fmtNum(data['totalAssets']), style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('إجمالي الأصول', style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 15),
        pw.Text('الخصوم', style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        ...liabilityDetails.map((item) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_fmtNum(item['balance']), style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
            pw.Text(item['name']?.toString() ?? '-', style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
          ],
        )),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_fmtNum(data['totalLiabilities']), style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('إجمالي الخصوم', style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 15),
        pw.Text('حقوق الملكية', style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        ...equityDetails.map((item) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_fmtNum(item['balance']), style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
            pw.Text(item['name']?.toString() ?? '-', style: pw.TextStyle(font: _arabicFont, fontSize: 11)),
          ],
        )),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_fmtNum(data['totalEquity']), style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('إجمالي حقوق الملكية', style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
      ],
    );
  }

  /// عنوان الكشف نفسه. هوية الشركة انتقلت إلى ترويسة الصفحة المتكرّرة
  /// (`_buildCompanyLetterhead`) فلم تعد تُمرَّر هنا.
  static pw.Widget _buildStatementHeader(
    String name,
    String type,
    DateTime? from,
    DateTime? to,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'كشف حساب ${type == 'customer' ? 'عميل' : 'مورد'}',
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'الاسم: $name',
              style: pw.TextStyle(font: _arabicFont, fontSize: 14),
            ),
            if (from != null && to != null)
              pw.Text(
                'الفترة: ${from.day}/${from.month}/${from.year} - ${to.day}/${to.month}/${to.year}',
                style: pw.TextStyle(font: _arabicFont, fontSize: 11),
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildBalanceBox(double bal) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bal > 0 ? PdfColors.red50 : PdfColors.green50,
        border: pw.Border.all(color: bal > 0 ? PdfColors.red : PdfColors.green),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'الرصيد الحالي:',
            style: pw.TextStyle(font: _arabicFont, fontSize: 14),
          ),
          pw.Text(
            '${bal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: bal > 0 ? PdfColors.red : PdfColors.green,
            ),
          ),
        ],
      ),
    );
  }

  /// جدول كشف الحساب بأعمدة مقيسة على المحتوى وصف إجماليات.
  ///
  /// Previously: five fixed-width columns, the document number crammed into the
  /// description, and NO totals row — so a printed statement gave no debit or
  /// credit total and no closing balance, while the Excel export from the same
  /// screen did. Column widths and the font now come from
  /// [StatementColumnLayout], which shrinks the type rather than clipping data.
  static pw.Widget _buildStatementTable(
    List<StatementItem> items,
    StatementColumnLayout layout,
    StatementTotals totals,
  ) {
    final showDoc = layout.showDocumentColumn;
    final fs = layout.fontSize;

    final widths = <int, pw.TableColumnWidth>{};
    var col = 0;
    widths[col++] = pw.FlexColumnWidth(layout.dateFlex.toDouble());
    if (showDoc) {
      widths[col++] = pw.FlexColumnWidth(layout.documentFlex.toDouble());
    }
    widths[col++] = pw.FlexColumnWidth(layout.descriptionFlex.toDouble());
    for (var i = 0; i < 3; i++) {
      widths[col++] = pw.FlexColumnWidth(layout.amountFlex.toDouble());
    }

    String money(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _statementCell('التاريخ', fs, isHeader: true),
            if (showDoc) _statementCell('رقم المستند', fs, isHeader: true),
            _statementCell('البيان', fs, isHeader: true),
            _statementCell('مدين', fs, isHeader: true),
            _statementCell('دائن', fs, isHeader: true),
            _statementCell('الرصيد', fs, isHeader: true),
          ],
        ),
        ...items.map(
          (t) => pw.TableRow(
            children: [
              _statementCell(
                  '${t.date.day}/${t.date.month}/${t.date.year}', fs),
              if (showDoc) _statementCell(t.documentNumber ?? '-', fs),
              _statementCell(t.description, fs),
              _statementCell(t.debit > 0 ? money(t.debit) : '-', fs),
              _statementCell(t.credit > 0 ? money(t.credit) : '-', fs),
              _statementCell(money(t.balance), fs),
            ],
          ),
        ),
        // صف الإجماليات — محسوب على كل الحركات لا على الصفحة الظاهرة.
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _statementCell('', fs),
            if (showDoc) _statementCell('', fs),
            _statementCell('الإجمالي', fs, isHeader: true),
            _statementCell(money(totals.totalDebit), fs, isHeader: true),
            _statementCell(money(totals.totalCredit), fs, isHeader: true),
            _statementCell(money(totals.closingBalance), fs, isHeader: true),
          ],
        ),
      ],
    );
  }

  /// خلية كشف الحساب بحجم خط مُمرَّر — `_tableCell` يثبّت الحجم، فلا يسمح
  /// بالتصغير النسبي الذي يجعل الأعمدة الطويلة تتّسع بدل أن تُبتر.
  static pw.Widget _statementCell(
    String text,
    double fontSize, {
    bool isHeader = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: _arabicFont,
          fontSize: fontSize,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Print detailed purchases report
  static Future<void> printPurchasesReport({
    required List<dynamic> invoices,
    required double totalPurchases,
    required int invoiceCount,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
    String? printedBy,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          _buildReportHeader(
            'تقرير المشتريات التفصيلي',
            now,
            companyName,
            from: fromDate,
            to: toDate,
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          _buildPurchasesSummary(totalPurchases, invoiceCount),
          pw.SizedBox(height: 20),
          _buildPurchasesTable(invoices),
        ],
      ),
    );
    await printing_pkg.Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  static pw.Widget _buildPurchasesSummary(double total, int count) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.orange),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _sumCol('إجمالي المشتريات', total.toStringAsFixed(AppConstants.decimalPlaces), isBold: true),
          _sumCol('عدد الفواتير', '$count'),
        ],
      ),
    );
  }

  static pw.Widget _buildPurchasesTable(List<dynamic> invoices) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('الفاتورة', isHeader: true),
            _tableCell('التاريخ', isHeader: true),
            _tableCell('المورد', isHeader: true),
            _tableCell('الإجمالي', isHeader: true),
            _tableCell('المدفوع', isHeader: true),
            _tableCell('الحالة', isHeader: true),
          ],
        ),
        ...invoices.map(
          (item) {
            final inv = item.invoice;
            return pw.TableRow(
              children: [
                _tableCell(inv.invoiceNumber),
                _tableCell('${inv.invoiceDate.day}/${inv.invoiceDate.month}'),
                _tableCell(item.supplierName ?? '-'),
                _tableCell(inv.total.toStringAsFixed(AppConstants.decimalPlaces)),
                _tableCell(inv.paid.toStringAsFixed(AppConstants.decimalPlaces)),
                _tableCell((inv.total - inv.paid) <= 0 ? 'مسددة' : 'آجلة'),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Print a journal entry with its lines.
  ///
  /// [branchName] / [branchColorHex] (Feature 004) — when supplied, render a
  /// coloured branch pill in the header. The colour comes from the same
  /// [BranchChip.colorFor] palette used on-screen so the PDF matches what the
  /// auditor saw when they triggered the print.
  static Future<void> printJournalEntry({
    required String entryNumber,
    required DateTime entryDate,
    required String? description,
    required String? referenceType,
    required bool isAutoPosted,
    required List<Map<String, dynamic>> lines,
    String? companyName,
    String? printedBy,
    String? branchName,
    int? branchColorHex,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();

    double totalDebit = 0, totalCredit = 0;
    for (final line in lines) {
      totalDebit += (line['debit'] as double? ?? 0);
      totalCredit += (line['credit'] as double? ?? 0);
    }

    final typeLabel = isAutoPosted ? 'تلقائي' : 'يدوي';
    String refLabel = '';
    switch (referenceType) {
      case 'sale': refLabel = 'مبيعات'; break;
      case 'purchase': case 'purchase_invoice': refLabel = 'مشتريات'; break;
      case 'receipt': refLabel = 'تحصيل'; break;
      case 'payment': refLabel = 'سداد'; break;
      case 'return': refLabel = 'مرتجع'; break;
      case 'fiscal_close': refLabel = 'إقفال'; break;
      case 'manufacturing': refLabel = 'تصنيع'; break;
      case 'daily': refLabel = 'يومية'; break;
      case 'adjustment': refLabel = 'تسوية'; break;
      case 'salary': refLabel = 'رواتب'; break;
    }

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
                      'رقم القيد: $entryNumber',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 12),
                    ),
                    pw.Text(
                      'التاريخ: ${entryDate.day}/${entryDate.month}/${entryDate.year}',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 12),
                    ),
                    pw.Text(
                      'النوع: $typeLabel ${refLabel.isNotEmpty ? "($refLabel)" : ""}',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 11),
                    ),
                    // Feature 004 — branch pill in the PDF header (when the
                    // entry has a branch link). Same colour as the on-screen
                    // chip so the printout is recognisable as belonging to
                    // the same branch.
                    if (branchName != null && branchName.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: branchColorHex != null
                              ? PdfColor.fromInt(
                                  // 12% alpha on the supplied colour.
                                  (branchColorHex & 0x00FFFFFF) | 0x1F000000,
                                )
                              : PdfColors.grey200,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(8)),
                          border: pw.Border.all(
                            color: branchColorHex != null
                                ? PdfColor.fromInt(branchColorHex)
                                : PdfColors.grey600,
                            width: 0.5,
                          ),
                        ),
                        child: pw.Text(
                          'الفرع: $branchName',
                          style: pw.TextStyle(
                            font: _arabicFont,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: branchColorHex != null
                                ? PdfColor.fromInt(branchColorHex)
                                : PdfColors.grey800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName ?? Brand.documentCompanyFallback,
                      style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'تاريخ الطباعة: ${now.day}/${now.month}/${now.year}',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'قيد يومية',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            if (description != null && description.isNotEmpty)
              pw.Text(
                'البيان: $description',
                style: pw.TextStyle(font: _arabicFont, fontSize: 13),
              ),
            pw.SizedBox(height: 20),

            // Lines table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(60),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('رمز الحساب', isHeader: true),
                    _tableCell('اسم الحساب', isHeader: true),
                    _tableCell('البيان', isHeader: true),
                    _tableCell('مدين', isHeader: true),
                    _tableCell('دائن', isHeader: true),
                  ],
                ),
                ...lines.map((line) => pw.TableRow(
                  children: [
                    _tableCell(line['account_code']?.toString() ?? ''),
                    _tableCell(line['account_name']?.toString() ?? ''),
                    _tableCell(line['description']?.toString() ?? ''),
                    _tableCell(
                      (line['debit'] as double? ?? 0) > 0
                          ? (line['debit'] as double).toStringAsFixed(AppConstants.decimalPlaces)
                          : '',
                    ),
                    _tableCell(
                      (line['credit'] as double? ?? 0) > 0
                          ? (line['credit'] as double).toStringAsFixed(AppConstants.decimalPlaces)
                          : '',
                    ),
                  ],
                )),
                // Totals row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('', isHeader: true),
                    _tableCell('الإجمالي', isHeader: true),
                    _tableCell(''),
                    _tableCell(totalDebit.toStringAsFixed(AppConstants.decimalPlaces), isHeader: true),
                    _tableCell(totalCredit.toStringAsFixed(AppConstants.decimalPlaces), isHeader: true),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 20),
            // Balance check
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                border: pw.Border.all(color: PdfColors.green),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: pw.Text(
                  'القيد متوازن ✓  |  المدين = الدائن = ${totalDebit.toStringAsFixed(AppConstants.decimalPlaces)}',
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green800,
                  ),
                ),
              ),
            ),

            pw.Spacer(),
            _buildA4Footer(printedBy: printedBy),
          ],
        ),
      ),
    );
    await printing_pkg.Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  static pw.Widget _buildReportHeader(
    String title,
    DateTime now,
    String? comp, {
    DateTime? from,
    DateTime? to,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (from != null)
              pw.Text(
                'الفترة: ${from.day}/${from.month}/${from.year} - ${to!.day}/${to.month}/${to.year}',
                style: pw.TextStyle(font: _arabicFont, fontSize: 11),
              ),
            pw.Text(
              'تاريخ الطباعة: ${now.day}/${now.month}/${now.year}',
              style: pw.TextStyle(font: _arabicFont, fontSize: 10),
            ),
          ],
        ),
        pw.Text(
          comp ?? Brand.documentCompanyFallback,
          style: pw.TextStyle(
            font: _arabicFont,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInventorySummary(int total, int low, double value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _sumCol('عدد الأصناف', '$total'),
          _sumCol('أصناف منخفضة', '$low', color: PdfColors.red),
          _sumCol('قيمة المخزون', '${value.toStringAsFixed(AppConstants.decimalPlaces)} JOD'),
        ],
      ),
    );
  }

  static pw.Widget _buildInventoryTable(
    List<dynamic> products,
    Map<int, String>? catMap,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2),
        5: const pw.FlexColumnWidth(2),
        6: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('م', isHeader: true),
            _tableCell('الصنف', isHeader: true),
            _tableCell('التصنيف', isHeader: true),
            _tableCell('الرصيد', isHeader: true),
            _tableCell('الحد الأدنى', isHeader: true),
            _tableCell('التكلفة', isHeader: true),
            _tableCell('القيمة', isHeader: true),
          ],
        ),
        ...products.asMap().entries.map((entry) {
          final p = entry.value;
          final cat = catMap != null && p.categoryId != null
              ? catMap[p.categoryId] ?? '-'
              : '-';
          return pw.TableRow(
            children: [
              _tableCell('${entry.key + 1}'),
              _tableCell(p.name),
              _tableCell(cat),
              _tableCell(p.currentStock.toStringAsFixed(0)),
              _tableCell(p.minStock.toStringAsFixed(0)),
              _tableCell(p.costPrice.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell((p.currentStock * p.costPrice).toStringAsFixed(AppConstants.decimalPlaces)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildFinanceSummary(
    double open,
    double inVal,
    double outVal,
    double close,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _sumCol('رصيد افتتاحي', open.toStringAsFixed(AppConstants.decimalPlaces)),
          _sumCol('مقبوضات', inVal.toStringAsFixed(AppConstants.decimalPlaces), color: PdfColors.green),
          _sumCol('مدفوعات', outVal.toStringAsFixed(AppConstants.decimalPlaces), color: PdfColors.red),
          _sumCol('رصيد ختامي', close.toStringAsFixed(AppConstants.decimalPlaces), isBold: true),
        ],
      ),
    );
  }

  static pw.Widget _buildTreasuryTable(List<dynamic> txs) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('التاريخ', isHeader: true),
            _tableCell('النوع', isHeader: true),
            _tableCell('المبلغ', isHeader: true),
            _tableCell('الرصيد', isHeader: true),
            _tableCell('البيان', isHeader: true),
          ],
        ),
        ...txs.map(
          (t) => pw.TableRow(
            children: [
              _tableCell('${t.createdAt.day}/${t.createdAt.month}'),
              _tableCell(t.transactionType == 'receipt' ? 'قبض' : 'صرف'),
              _tableCell(t.amount.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(t.balanceAfter.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(t.description ?? '-'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSalesSummary(double sales, double profit, int count) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.green),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _sumCol('إجمالي المبيعات', sales.toStringAsFixed(AppConstants.decimalPlaces), isBold: true),
          // B11 REP-1 (spec 149): mirrors the on-screen relabel in
          // sales_report_screen.dart — this is the sales-level profit
          // (revenue − discount − COGS − tax), not the GL-sourced company
          // net profit. Kept the same value, just no longer called it that.
          _sumCol(
            'ربح المبيعات (قبل المصروفات)',
            profit.toStringAsFixed(AppConstants.decimalPlaces),
            color: PdfColors.green,
          ),
          _sumCol('عدد الفواتير', '$count'),
        ],
      ),
    );
  }

  static pw.Widget _buildSalesTable(List<dynamic> invoices) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('الفاتورة', isHeader: true),
            _tableCell('التاريخ', isHeader: true),
            _tableCell('الإجمالي', isHeader: true),
            _tableCell('المدفوع', isHeader: true),
            _tableCell('الحالة', isHeader: true),
          ],
        ),
        ...invoices.map(
          (inv) => pw.TableRow(
            children: [
              _tableCell(inv.invoiceNumber),
              _tableCell('${inv.invoiceDate.day}/${inv.invoiceDate.month}'),
              _tableCell(inv.total.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(inv.paid.toStringAsFixed(AppConstants.decimalPlaces)),
              _tableCell(inv.paymentMethod == 'cash' ? 'نقدي' : 'آجل'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableCell(
    String text, {
    bool isHeader = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: _arabicFont,
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  static pw.Widget _totalRow(
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
              font: _arabicFont,
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(AppConstants.decimalPlaces)} JOD',
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sumCol(
    String label,
    String value, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(font: _arabicFont, fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: _arabicFont,
            fontSize: 12,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Print Check Receipt/Disbursement Voucher — سند قبض/صرف شيك (Item #13)
  static Future<void> printCheckVoucher({
    required String checkNumber,
    required double amount,
    required DateTime checkDate,
    required DateTime? dueDate,
    required String drawerName,
    required String? bankName,
    required String direction, // 'received' or 'issued'
    required String status,
    String? notes,
    String? companyName,
    String? printedBy,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    final now = DateTime.now();
    final isReceived = direction == 'received';
    final titleAr = isReceived ? 'سند قبض شيك' : 'سند صرف شيك';
    final partyLabel = isReceived ? 'المستلم من' : 'المدفوع إلى';
    final df = DateFormat('yyyy/MM/dd');

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
                      'تاريخ الطباعة: ${df.format(now)}',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                    ),
                    pw.Text(
                      'رقم الشيك: $checkNumber',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 12),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName ?? Brand.documentCompanyFallback,
                      style: pw.TextStyle(
                        font: _arabicFont,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'CHK:$checkNumber|AMT:$amount|DATE:${df.format(checkDate)}',
                  width: 60,
                  height: 60,
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 15),

            // Title
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: isReceived ? PdfColors.green50 : PdfColors.red50,
                  border: pw.Border.all(
                    color: isReceived ? PdfColors.green : PdfColors.red,
                  ),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  titleAr,
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: isReceived ? PdfColors.green900 : PdfColors.red900,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 25),

            // Details table
            _voucherRow('$partyLabel:', drawerName),
            _voucherRow('المبلغ:', '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}'),
            _voucherRow('تاريخ الشيك:', df.format(checkDate)),
            if (dueDate != null)
              _voucherRow('تاريخ الاستحقاق:', df.format(dueDate)),
            if (bankName != null && bankName.isNotEmpty)
              _voucherRow('البنك:', bankName),
            _voucherRow('الحالة:', _getCheckStatusLabel(status)),
            if (notes != null && notes.isNotEmpty)
              _voucherRow('ملاحظات:', notes),
            pw.SizedBox(height: 30),

            // Amount box
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Center(
                child: pw.Text(
                  'المبلغ: ${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),

            pw.Spacer(),

            // Signature lines
            pw.Divider(),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide()),
                      ),
                      child: pw.SizedBox(height: 40),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('توقيع المسلِّم',
                        style: pw.TextStyle(font: _arabicFont, fontSize: 10)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide()),
                      ),
                      child: pw.SizedBox(height: 40),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('توقيع المستلِم',
                        style: pw.TextStyle(font: _arabicFont, fontSize: 10)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide()),
                      ),
                      child: pw.SizedBox(height: 40),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('المدير المالي',
                        style: pw.TextStyle(font: _arabicFont, fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            _buildA4Footer(printedBy: printedBy),
          ],
        ),
      ),
    );
    await PdfComputeHelper.layoutPdf(pdf);
  }

  static pw.Widget _voucherRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(label,
                style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(font: _arabicFont, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  static String _getCheckStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'معلق';
      case 'in_portfolio': return 'في الحافظة';
      case 'deposited': return 'مودع';
      case 'deposited_for_collection': return 'برسم التحصيل';
      case 'cashed': return 'محصّل';
      case 'bounced': return 'مرتد';
      case 'endorsed': return 'مظهّر';
      case 'cancelled': return 'ملغي';
      default: return status;
    }
  }
}
