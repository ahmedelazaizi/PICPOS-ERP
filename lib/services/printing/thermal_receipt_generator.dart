import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import '../printer_resolver.dart';
import '../license_service.dart';
import '../generators/base_generator.dart' hide InvoiceItem;
import '../../core/constants/app_constants.dart';
import '../../domain/repositories/printers_repository.dart';
import 'printing_models.dart';
import '../../core/config/brand.dart';

/// حساب أرقام ذيل الإيصال — مستخرَج من باني الـPDF عشان يبقى **قابلاً للاختبار**.
///
/// ── العطل اللي بيقفله ──────────────────────────────────────────────────────
/// `salesInvoices.total` المخزَّن **بيشمل رسوم التوصيل بالفعل**:
///
///   finalTotal = subtotal − discount + tax + deliveryFee
///   (sales_transaction_orchestrator.dart:635-636)
///
/// وطبقة الطباعة كانت بتجمعها تاني: `grandTotal = total + deliveryFee`.
/// فعلى فاتورة توصيل أصنافها ١٠٠ ورسومها ٥ ومدفوعة ١٠٥ بالكامل:
///
///   المجموع الفرعي المطبوع = ١٠٥ (والصح ١٠٠)
///   الإجمالي المطبوع       = ١١٠ (والصح ١٠٥)
///   «المتبقي ٥٫٠٠٠» بالأحمر على فاتورة **مقفولة ومدفوعة**
///
/// يعني الورقة بتقول العميل مديون والقاعدة بتقول صفر.
///
/// `total` هو الإجمالي النهائي — ما بيتجمعش عليه حاجة. والمجموع الفرعي
/// بيترجع بالعكس: `subtotal = total + discount − tax − deliveryFee`.
@immutable
class ReceiptTotals {
  const ReceiptTotals({
    required this.itemsSubtotal,
    required this.grandTotal,
    required this.change,
    required this.remaining,
  });

  /// مجموع الأصناف قبل الخصم والضريبة والتوصيل.
  final double itemsSubtotal;

  /// الإجمالي النهائي المستحق — نفس `total` المخزَّن.
  final double grandTotal;

  /// الباقي للعميل (صفر لو مفيش).
  final double change;

  /// المتبقي على العميل (صفر لو مفيش).
  final double remaining;

  factory ReceiptTotals.from({
    required double total,
    required double paid,
    double? discount,
    double? tax,
    double? deliveryFee,
  }) {
    final fee = deliveryFee ?? 0;
    final disc = discount ?? 0;
    final t = tax ?? 0;
    final diff = paid - total;
    return ReceiptTotals(
      itemsSubtotal: total + disc - t - fee,
      grandTotal: total,
      change: diff > 0 ? diff : 0,
      remaining: diff < 0 ? -diff : 0,
    );
  }
}

class ThermalReceiptGenerator {
  static pw.Font? _arabicFont;

  static Future<void> _initFont() async {
    // Always delegate to BaseGenerator — it only caches Cairo (never Helvetica)
    // so if previous call got Helvetica fallback, this retries the real font.
    _arabicFont = await BaseGenerator.initFont();
  }

  static Future<void> printThermalReceipt({
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
    String? receiptCodeType,
    String? footerText,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? courierName,
    String? courierPhone,
    bool isDelivery = false,
    double? discount,
    double? tax,
    double? deliveryFee,
    bool directPrint = false,
    int? orderNumber,
    IPrintersRepository? printersRepo,
    String? notes,
    String locale = 'ar',
  }) async {
    await _initFont();
    final pdf = pw.Document();
    const thermalFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final displayInvoiceNumber = invoiceNumber;
    final totals = ReceiptTotals.from(
      total: total,
      paid: paid,
      discount: discount,
      tax: tax,
      deliveryFee: deliveryFee,
    );
    final double itemsSubtotal = totals.itemsSubtotal;
    final double grandTotal = totals.grandTotal;
    final double actualChange = totals.change;
    final double remaining = totals.remaining;

    pdf.addPage(
      pw.Page(
        pageFormat: thermalFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildHeader(companyName, companyAddress, companyPhone, taxId),
            _buildSeparator(locale == 'en' ? 'Invoice' : 'فاتورة'),
            _buildMetadata(
              date,
              displayInvoiceNumber,
              employeeName,
              orderNumber,
            ),
            if (salesType != null && salesType.isNotEmpty && salesType != 'default')
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  _mapSaleTypeLabel(salesType),
                  style: pw.TextStyle(font: _arabicFont, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
            if (customerName != null || isDelivery)
              _buildCustomerSection(
                customerName,
                customerPhone,
                customerAddress,
                isDelivery,
              ),
            _buildItemsTable(items),
            pw.SizedBox(height: 8),
            _buildTotalsSection(
              itemsSubtotal,
              tax,
              discount,
              deliveryFee,
              grandTotal,
              paid,
              actualChange,
              remaining,
            ),
            if (isDelivery && (courierName != null || courierPhone != null))
              _buildCourierSection(courierName, courierPhone),
            if (notes != null && notes.isNotEmpty)
              pw.Container(
                width: double.infinity,
                margin: const pw.EdgeInsets.only(top: 4),
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(
                  notes,
                  style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                ),
              ),
            pw.SizedBox(height: 8),
            _buildCodes(receiptCodeType, invoiceNumber),
            pw.SizedBox(height: 8),
            _buildFooter(footerText),
            pw.SizedBox(height: 15),
          ],
        ),
      ),
    );

    if (directPrint) {
      printing_pkg.Printer? resolvedPrinter;
      if (printersRepo != null) {
        resolvedPrinter = await PrinterResolver.resolveReceiptPrinter(printersRepo);
      }
      if (resolvedPrinter != null) {
        await printing_pkg.Printing.directPrintPdf(
          printer: resolvedPrinter,
          onLayout: (format) async => pdf.save(),
        );
        return;
      }
    }
    await printing_pkg.Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  /// Print thermal work order for the kitchen/preparation
  static Future<void> printWorkOrderReceipt({
    required String orderNumber,
    required DateTime date,
    required String categoryName,
    required List<InvoiceItem> items,
    String? invoiceNumber,
    int? dailyOrderNumber,
    String? orderType,
    String? orderNotes,
    String? customerName, // NEW: Table Name or Guest Name
    IPrintersRepository? printersRepo,
  }) async {
    await _initFont();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 2 * PdfPageFormat.mm,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'طلب تحضير / مطبخ',
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              categoryName,
              style: pw.TextStyle(font: _arabicFont, fontSize: 16),
            ),
            pw.Divider(),
            // Order Type Badge (e.g., Takeaway, Dine-in)
            if (orderType != null && orderType.isNotEmpty && orderType != 'default')
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  _mapSaleTypeLabel(orderType),
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            
            // Customer Name removed from kitchen receipt — only order number is shown

            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'التاريخ: ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                ),
                pw.Text(
                  'الوقت: ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'رقم الطلب: $orderNumber',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            if (invoiceNumber != null)
              pw.Text(
                'فاتورة: $invoiceNumber',
                style: pw.TextStyle(font: _arabicFont, fontSize: 11),
              ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(
                        'الكمية',
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(
                        'الصنف',
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                ...items.expand(
                  (item) => [
                    if (item.isCategoryHeader)
                      // Issue 2 (Feature 019): category section divider —
                      // spans both columns with a centered, bold label so
                      // the kitchen / barista can fast-scan their section.
                      pw.TableRow(
                        children: [
                          pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            child: pw.Text(
                              '— ${item.name} —',
                              style: pw.TextStyle(
                                font: _arabicFont,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(
                              '${item.quantity}',
                              style: pw.TextStyle(font: _arabicFont),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(
                              item.name,
                              style: pw.TextStyle(font: _arabicFont),
                            ),
                          ),
                        ],
                      ),
                      if (item.note != null && item.note!.isNotEmpty)
                        pw.TableRow(
                          children: [
                            pw.SizedBox(),
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(right: 4, bottom: 2),
                              child: pw.Text(
                                item.note!,
                                style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            // Phase 3: Order notes
            if (orderNotes != null && orderNotes.trim().isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.5),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('\u0645\u0644\u0627\u062d\u0638\u0627\u062a:', style: pw.TextStyle(font: _arabicFont, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(orderNotes, style: pw.TextStyle(font: _arabicFont, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),
            ],
            pw.Text('*********************', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );

    printing_pkg.Printer? resolvedPrinter;
    if (printersRepo != null) {
      resolvedPrinter = await PrinterResolver.resolveByPurpose(printersRepo, 'kitchen');
    }

    if (resolvedPrinter != null) {
      await printing_pkg.Printing.directPrintPdf(
        printer: resolvedPrinter,
        onLayout: (format) async => pdf.save(),
      );
    } else {
      await printing_pkg.Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );
    }
  }

  /// Map sale type codes to human-readable Arabic labels (with platform hashtags)
  static String _mapSaleTypeLabel(String saleType) {
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
        return saleType;
    }
  }

  static pw.Widget _buildHeader(
    String? name,
    String? address,
    String? phone,
    String? taxId,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Column(
        children: [
          pw.Text(
            name ?? Brand.documentCompanyFallback,
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          if (address?.isNotEmpty ?? false)
            pw.Text(
              address!,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          if (phone?.isNotEmpty ?? false)
            pw.Text(
              phone!,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          if (taxId?.isNotEmpty ?? false)
            pw.Text(
              'الرقم الضريبي: $taxId',
              style: pw.TextStyle(font: _arabicFont, fontSize: 7),
              textAlign: pw.TextAlign.center,
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildSeparator(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Container(height: 1, color: PdfColors.grey600)),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(child: pw.Container(height: 1, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  static pw.Widget _buildMetadata(
    DateTime date,
    String invNum,
    String? empName,
    int? orderNum,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'التاريخ: ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              ),
              pw.Text(
                'رقم: $invNum',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          if (empName?.isNotEmpty ?? false)
            pw.Row(
              children: [
                pw.Text(
                  'الكاشير: $empName',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                ),
              ],
            ),
          if (orderNum != null)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey800,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    'طلب رقم: $orderNum',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ],
            ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'الوقت: ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(List<InvoiceItem> items) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
            decoration: const pw.BoxDecoration(color: PdfColors.grey800),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 32,
                  child: pw.Text(
                    'الإجمالي',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(
                  width: 24,
                  child: pw.Text(
                    'العدد',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(
                  width: 24,
                  child: pw.Text(
                    'السعر',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'الوصف',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.SizedBox(
                  width: 14,
                  child: pw.Text(
                    'م',
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final item = entry.value;
            final hasNote = item.note != null && item.note!.isNotEmpty;
            
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 3,
                horizontal: 3,
              ),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 32,
                        child: pw.Text(
                          item.total.toStringAsFixed(AppConstants.decimalPlaces),
                          style: pw.TextStyle(
                            font: _arabicFont,
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.SizedBox(
                        width: 24,
                        child: pw.Text(
                          '${item.quantity}',
                          style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.SizedBox(
                        width: 24,
                        child: pw.Text(
                          item.price.toStringAsFixed(AppConstants.decimalPlaces),
                          style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          item.name,
                          style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.SizedBox(
                        width: 14,
                        child: pw.Text(
                          '$index.',
                          style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  if (hasNote)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 14, top: 1),
                      child: pw.Text(
                        item.note!.replaceAll(' | ', '\n').replaceAll('📝 ', '').trim(),
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.normal,
                          color: PdfColors.grey700,
                        ),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _buildTotalsSection(
    double sub,
    double? tax,
    double? disc,
    double? del,
    double grand,
    double paid,
    double change,
    double rem,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          _receiptTotalRow('SUBTOTAL', 'المجموع الفرعي', sub),
          if (tax != null && tax > 0)
            _receiptTotalRow('TAX', 'الضريبة', tax, isAddition: true),
          if (disc != null && disc > 0)
            _receiptTotalRow('DISCOUNT', 'الخصم', disc, isSubtraction: true),
          if (del != null && del > 0)
            _receiptTotalRow('DELIVERY', 'التوصيل', del, isAddition: true),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
            height: 1,
            color: PdfColors.grey600,
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${grand.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'TOTAL  الإجمالي',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                paid.toStringAsFixed(AppConstants.decimalPlaces),
                style: pw.TextStyle(font: _arabicFont, fontSize: 9),
              ),
              pw.Text(
                'المدفوع',
                style: pw.TextStyle(font: _arabicFont, fontSize: 9),
              ),
            ],
          ),
          if (change > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  change.toStringAsFixed(AppConstants.decimalPlaces),
                  style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                ),
                pw.Text(
                  'الباقي',
                  style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                ),
              ],
            )
          else if (rem > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  rem.toStringAsFixed(AppConstants.decimalPlaces),
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 9,
                    color: PdfColors.red,
                  ),
                ),
                pw.Text(
                  'المتبقي',
                  style: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 9,
                    color: PdfColors.red,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _receiptTotalRow(
    String labelEn,
    String labelAr,
    double amount, {
    bool isAddition = false,
    bool isSubtraction = false,
  }) {
    final prefix = isSubtraction ? '-' : (isAddition ? '+' : '');
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(labelAr, style: pw.TextStyle(font: _arabicFont, fontSize: 8)), // Label on RIGHT
          pw.Text(
            '$prefix${amount.toStringAsFixed(AppConstants.decimalPlaces)}',
            style: pw.TextStyle(font: _arabicFont, fontSize: 9),
          ), // Amount on LEFT
        ],

      ),
    );
  }

  static pw.Widget _buildCustomerSection(
    String? name,
    String? phone,
    String? address,
    bool isDel,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (name?.isNotEmpty ?? false)
            pw.Text(
              'العميل: $name',
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          if (phone?.isNotEmpty ?? false)
            pw.Text(
              'الهاتف: $phone',
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
            ),
          if (address?.isNotEmpty ?? false)
            pw.Text(
              'العنوان: $address',
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
            ),
          if (isDel)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 2),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey800,
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Text(
                'توصيل',
                style: pw.TextStyle(
                  font: _arabicFont,
                  fontSize: 7,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildCourierSection(String? name, String? phone) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'معلومات المندوب',
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (name != null)
            pw.Text(name, style: pw.TextStyle(font: _arabicFont, fontSize: 8)),
          if (phone != null)
            pw.Text(phone, style: pw.TextStyle(font: _arabicFont, fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _buildCodes(String? type, String data) {
    if (type == 'barcode') {
      return pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: data,
        width: 140,
        height: 30,
        textStyle: const pw.TextStyle(fontSize: 6),
      );
    } else if (type == 'qr_code') {
      return pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: data,
        width: 50,
        height: 50,
      );
    }
    return pw.SizedBox();
  }

  static pw.Widget _buildFooter(String? text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Column(
        children: [
          // Trial watermark
          if (LicenseService.showWatermark) ...[
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
                  font: _arabicFont,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 4),
          ],
          if (text?.isNotEmpty ?? false)
            pw.Text(
              text!,
              style: pw.TextStyle(font: _arabicFont, fontSize: 7),
              textAlign: pw.TextAlign.center,
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            '~ شكراً لزيارتكم ~',
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.Text(
            'Thank You',
            style: pw.TextStyle(font: _arabicFont, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Future<void> printShiftClosingReport({
    required int invoiceCount,
    required double totalSales,
    required double systemCash,
    required double systemCard,
    required double actualCash,
    required double actualCard,
    required double cashVariance,
    required double cardVariance,
    required double totalVariance,
    double systemClick = 0.0,
    double actualClick = 0.0,
    double clickVariance = 0.0,
    double totalExpenses = 0,
    double cashRefunds = 0,
    double cashIncome = 0,
    double creditSales = 0,
    int creditSalesCount = 0,
    double openingBalance = 0,
    double fontScale = 1.0,
    String? employeeName,
    String? companyName,
    IPrintersRepository? printersRepo,
  }) async {
    await _initFont();
    final pdf = pw.Document();
    final now = DateTime.now();
    const thermalWidth = 80.0 * PdfPageFormat.mm;
    // marginRight is intentionally larger than marginLeft: Arabic labels start
    // from the right edge, and many thermal printers have a wider non-printable
    // dead zone on the right side. 8mm ensures labels don't get physically cut.
    const pageFormat = PdfPageFormat(
      thermalWidth,
      double.infinity,
      marginLeft: 4 * PdfPageFormat.mm,
      marginRight: 8 * PdfPageFormat.mm,
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 2 * PdfPageFormat.mm,
    );

    final fs = fontScale.clamp(0.5, 2.0);
    // Font sizes reduced slightly so label + value fit comfortably on one line.
    final bold = pw.TextStyle(
      font: _arabicFont,
      fontSize: 8 * fs,
      fontWeight: pw.FontWeight.bold,
    );
    final normal = pw.TextStyle(font: _arabicFont, fontSize: 7 * fs);
    final small = pw.TextStyle(font: _arabicFont, fontSize: 6.5 * fs);
    final headerStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 10 * fs,
      fontWeight: pw.FontWeight.bold,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(companyName ?? Brand.documentCompanyFallback, style: headerStyle),
              pw.Divider(thickness: 0.5),
              pw.Text('تقرير إغلاق الوردية', style: bold),
              pw.Text(
                '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}',
                style: small,
              ),
              if (employeeName != null)
                pw.Text('الكاشير: $employeeName', style: small),
              pw.Divider(thickness: 0.5),
              if (openingBalance > 0)
                _labelValue('الرصيد الافتتاحي', openingBalance.toStringAsFixed(AppConstants.decimalPlaces), normal, bold),
              _labelValue('عدد الفواتير', '$invoiceCount', normal, bold),
              _labelValue(
                'إجمالي المبيعات',
                '${totalSales.toStringAsFixed(AppConstants.decimalPlaces)} JOD',
                normal,
                bold,
              ),
              if (creditSales > 0 || creditSalesCount > 0)
                _labelValue(
                  creditSalesCount > 0
                      ? 'المبيعات الآجلة ($creditSalesCount)'
                      : 'المبيعات الآجلة',
                  '${creditSales.toStringAsFixed(AppConstants.decimalPlaces)} JOD',
                  normal,
                  bold,
                ),
              if (totalExpenses > 0 || cashRefunds > 0) ...[
                pw.SizedBox(height: 2),
                if (cashIncome > 0)
                  _labelValue(
                    'دخل النقد',
                    cashIncome.toStringAsFixed(AppConstants.decimalPlaces),
                    normal,
                    bold,
                  ),
                if (totalExpenses > 0)
                  _labelValue(
                    'المصروفات',
                    '- ${totalExpenses.toStringAsFixed(AppConstants.decimalPlaces)}',
                    normal,
                    bold.copyWith(color: PdfColors.red),
                  ),
                if (cashRefunds > 0)
                  _labelValue(
                    'المرتجعات',
                    '- ${cashRefunds.toStringAsFixed(AppConstants.decimalPlaces)}',
                    normal,
                    bold.copyWith(color: PdfColors.red),
                  ),
              ],
              pw.Divider(thickness: 0.5),
              pw.Text('تفاصيل التسوية', style: bold),
              _labelValue(
                'النقد - نظام',
                systemCash.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'النقد - فعلي',
                actualCash.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'الفارق',
                cashVariance.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold.copyWith(
                  color: cashVariance < 0 ? PdfColors.red : PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 4),
              _labelValue(
                'البطاقة - نظام',
                systemCard.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'البطاقة - فعلي',
                actualCard.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'الفارق',
                cardVariance.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold.copyWith(
                  color: cardVariance < 0 ? PdfColors.red : PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 4),
              _labelValue(
                'كليك - النظام',
                systemClick.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'كليك - الفعلي',
                actualClick.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold,
              ),
              _labelValue(
                'كليك - الفارق',
                clickVariance.toStringAsFixed(AppConstants.decimalPlaces),
                normal,
                bold.copyWith(
                  color: clickVariance < 0 ? PdfColors.red : PdfColors.black,
                ),
              ),
              pw.Divider(thickness: 0.5),
              _labelValue(
                'إجمالي الفارق',
                totalVariance.toStringAsFixed(AppConstants.decimalPlaces),
                bold,
                bold.copyWith(
                  color: totalVariance < 0 ? PdfColors.red : PdfColors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    printing_pkg.Printer? resolvedPrinter;
    if (printersRepo != null) {
      resolvedPrinter = await PrinterResolver.resolveReceiptPrinter(printersRepo);
    }

    if (resolvedPrinter != null) {
      await printing_pkg.Printing.directPrintPdf(
        printer: resolvedPrinter,
        onLayout: (format) async => pdf.save(),
      );
    } else {
      await printing_pkg.Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );
    }
  }

  static pw.Widget _labelValue(
    String label,
    String value,
    pw.TextStyle labelStyle,
    pw.TextStyle valueStyle,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Flexible allows the label to shrink/wrap rather than overflow
          pw.Flexible(
            child: pw.Text(
              label,
              style: labelStyle,
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 6), // guaranteed gap between label and value
          pw.Text(value, style: valueStyle), // Value on the LEFT in RTL
        ],
      ),
    );
  }
}
