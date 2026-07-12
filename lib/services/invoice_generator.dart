import 'package:flutter/foundation.dart';
import '../data/database/database.dart' hide Printer;
import '../domain/repositories/printers_repository.dart';
import 'printing/thermal_receipt_generator.dart';
import 'printing/template_pdf_renderer.dart';
import 'templated_invoice_service.dart';
import 'printing/report_pdf_generator.dart';
import 'printing/printing_models.dart';

// Re-export models for backward compatibility if needed,
// though direct imports are preferred in new code.
export 'printing/printing_models.dart';

/// Facade for all printing and PDF generation services.
/// Decomposed into specialized services in lib/services/printing/
class InvoiceGenerator {
  /// Print thermal receipt for sales invoice.
  ///
  /// If [db] is provided and a default thermal receipt template exists,
  /// uses the user's custom template design. Otherwise falls back to
  /// the hardcoded receipt layout.
  static Future<void> printThermalReceipt({
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    required double change,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? employeeName,
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? taxId,
    String? registerNumber,
    String? salesType,
    String? receiptCodeType,
    String? footerText,
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
    AppDatabase? db,
    String locale = 'ar',
  }) async {
    // ── Try template-driven rendering ──
    if (db != null) {
      try {
        final templateData = await db.getDefaultTemplateWithDataByCategory(
          'thermal',
          'receipt',
        );
        if (templateData != null && templateData.elements.isNotEmpty) {
          final subtotal = total + (discount ?? 0) - (tax ?? 0);
          final grandTotal = total + (deliveryFee ?? 0);
          final remaining = grandTotal - paid;

          await TemplatePdfRenderer.printFromTemplate(
            templateData: templateData,
            invoiceData: TemplateInvoiceData(
              invoiceNumber: invoiceNumber,
              date: date,
              items: items,
              subtotal: subtotal,
              discount: discount ?? 0,
              tax: tax ?? 0,
              total: grandTotal,
              paid: paid,
              remaining: remaining > 0 ? remaining : 0,
              deliveryFee: deliveryFee ?? 0,
              companyName: companyName,
              companyPhone: companyPhone,
              companyAddress: companyAddress,
              taxId: taxId,
              customerName: customerName,
              customerPhone: customerPhone,
              customerAddress: customerAddress,
              employeeName: employeeName,
              salesType: salesType,
              paymentMethod: salesType,
              footerText: footerText,
              receiptCodeType: receiptCodeType,
              notes: notes,
              courierName: courierName,
              courierPhone: courierPhone,
              isDelivery: isDelivery,
              orderNumber: orderNumber,
              locale: locale,
            ),
            directPrint: directPrint,
            printersRepo: printersRepo,
          );
          return; // Done — template used successfully
        }
      } catch (e) {
        debugPrint('[InvoiceGenerator] Template rendering failed, falling back: $e');
      }
    }

    // ── Fallback: hardcoded generator ──
    return ThermalReceiptGenerator.printThermalReceipt(
      invoiceNumber: invoiceNumber,
      date: date,
      items: items,
      total: total,
      paid: paid,
      change: change,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      employeeName: employeeName,
      companyName: companyName,
      companyPhone: companyPhone,
      companyAddress: companyAddress,
      taxId: taxId,
      registerNumber: registerNumber,
      salesType: salesType,
      receiptCodeType: receiptCodeType,
      footerText: footerText,
      courierName: courierName,
      courierPhone: courierPhone,
      isDelivery: isDelivery,
      discount: discount,
      tax: tax,
      deliveryFee: deliveryFee,
      directPrint: directPrint,
      orderNumber: orderNumber,
      printersRepo: printersRepo,
      notes: notes,
      locale: locale,
    );
  }

  /// Print A4 sales invoice — uses user template if available
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
    String? notes, // NEW: Support passing order notes to A4 invoices
    String title = 'فاتورة مبيعات',
    AppDatabase? db,
  }) async {
    // Try template-based rendering first
    if (db != null) {
      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db, 'a4', category: 'invoice',
      );
      if (hasTemplate) {
        try {
          final itemsMaps = items.map((i) => <String, dynamic>{
            'name': i.name, 'quantity': i.quantity,
            'price': i.price, 'total': i.total, 'note': i.note ?? '',
          }).toList();
          await TemplatedInvoiceService.printWithTemplate(
            db: db,
            invoiceNumber: invoiceNumber,
            date: date,
            customerName: customerName,
            customerPhone: null,
            customerAddress: null,
            items: itemsMaps,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            deliveryFee: 0,
            total: total,
            paid: paid,
            companyName: companyName ?? '',
            companyAddress: companyAddress ?? '',
            companyPhone: companyPhone ?? '',
            companyTaxId: companyTaxId,
            notes: notes, // ADDED: Pass notes to template engine
            type: 'a4',
            category: 'invoice',
          );
          return;
        } catch (e) {
          debugPrint('[InvoiceGenerator] A4 template failed, falling back: $e');
        }
      }
    }
    // Fallback to hardcoded A4 generator
    return ReportPdfGenerator.printSalesInvoice(
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
      notes: notes, // ADDED: Pass notes to fallback non-templated PDF
      title: title,
    );
  }

  /// Print A4 purchase invoice — uses user template if available.
  ///
  /// Pass [isReturn]=true for purchase return printouts. Templates are skipped
  /// in that case (user templates hard-code the "فاتورة مشتريات" title), so
  /// the fallback generator renders with the correct "مرتجع مشتريات" title.
  static Future<void> printPurchaseInvoice({
    required String invoiceNumber,
    required DateTime date,
    required String supplierName,
    required List<InvoiceItem> items,
    required double total,
    required double paid,
    String? companyName,
    AppDatabase? db,
    bool isReturn = false,
  }) async {
    // Try template-based rendering first (skipped for returns — see doc above)
    if (db != null && !isReturn) {
      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db, 'a4', category: 'purchase',
      );
      if (hasTemplate) {
        try {
          final itemsMaps = items.map((i) => <String, dynamic>{
            'name': i.name, 'quantity': i.quantity,
            'price': i.price, 'total': i.total, 'note': i.note ?? '',
          }).toList();
          await TemplatedInvoiceService.printWithTemplate(
            db: db,
            invoiceNumber: invoiceNumber,
            date: date,
            customerName: supplierName,
            customerPhone: null,
            customerAddress: null,
            items: itemsMaps,
            subtotal: total,
            discount: 0,
            tax: 0,
            deliveryFee: 0,
            total: total,
            paid: paid,
            companyName: companyName ?? '',
            companyAddress: '',
            companyPhone: '',
            companyTaxId: null,
            type: 'a4',
            category: 'purchase',
          );
          return;
        } catch (e) {
          debugPrint('[InvoiceGenerator] Purchase template failed, falling back: $e');
        }
      }
    }

    // Fallback to hardcoded A4 generator
    return ReportPdfGenerator.printPurchaseInvoice(
      invoiceNumber: invoiceNumber,
      date: date,
      supplierName: supplierName,
      items: items,
      total: total,
      paid: paid,
      companyName: companyName,
      isReturn: isReturn,
    );
  }

  /// Print thermal work order for the kitchen/preparation — uses user template if available
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
    AppDatabase? db,
  }) async {
    // Try template-based rendering first
    if (db != null) {
      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db, 'kitchen',
      );
      if (hasTemplate) {
        try {
          final itemsMaps = items.map((i) => <String, dynamic>{
            'name': i.name, 'quantity': i.quantity,
            'price': i.price, 'total': i.total, 'note': i.note ?? '',
          }).toList();
          await TemplatedInvoiceService.printWithTemplate(
            db: db,
            invoiceNumber: invoiceNumber ?? orderNumber,
            date: date,
            // Kitchen receipts: NO customer info — only order number
            customerName: null,
            customerPhone: null,
            customerAddress: null,
            items: itemsMaps,
            subtotal: 0,
            discount: 0,
            tax: 0,
            deliveryFee: 0,
            total: 0,
            paid: 0,
            companyName: categoryName,
            companyAddress: '',
            companyPhone: '',
            companyTaxId: null,
            type: 'kitchen',
            category: 'kitchen',
            notes: orderNotes,  // RESTORED: User still wants general cart notes on kitchen receipt
            adhocCustomerName: null,
            adhocCustomerPhone: null,
            directPrint: true,
            orderNumber: orderNumber,
            salesType: orderType,
          );
          return;
        } catch (e) {
          debugPrint('[InvoiceGenerator] Kitchen template failed, falling back: $e');
        }
      }
    }
    // Fallback to hardcoded kitchen generator
    return ThermalReceiptGenerator.printWorkOrderReceipt(
      orderNumber: orderNumber,
      date: date,
      categoryName: categoryName,
      items: items,
      invoiceNumber: invoiceNumber,
      dailyOrderNumber: dailyOrderNumber,
      orderType: orderType,
      // Kitchen receipts: NO customer info, but keep general order notes
      orderNotes: orderNotes,
      customerName: null,
      printersRepo: printersRepo,
    );
  }

  /// Print party (customer/supplier) account statement
  static Future<void> printPartyStatement({
    required String partyName,
    required String partyType,
    required double currentBalance,
    required List<StatementItem> transactions,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) {
    return ReportPdfGenerator.printPartyStatement(
      partyName: partyName,
      partyType: partyType,
      currentBalance: currentBalance,
      transactions: transactions,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
    );
  }

  /// Print inventory stock report
  static Future<void> printInventoryReport({
    required List<dynamic> products,
    String? companyName,
    Map<int, String>? categoryMap,
  }) {
    return ReportPdfGenerator.printInventoryReport(
      products: products,
      companyName: companyName,
      categoryMap: categoryMap,
    );
  }

  /// Print treasury/safe transaction report
  static Future<void> printTreasuryReport({
    required List<dynamic> transactions,
    required double openingBalance,
    required double totalIn,
    required double totalOut,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) {
    return ReportPdfGenerator.printTreasuryReport(
      transactions: transactions,
      openingBalance: openingBalance,
      totalIn: totalIn,
      totalOut: totalOut,
      closingBalance: closingBalance,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
    );
  }

  /// Print detailed sales report
  static Future<void> printSalesReport({
    required List<dynamic> invoices,
    required double totalSales,
    required double totalProfit,
    required int invoiceCount,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
    String? printedBy,
  }) {
    return ReportPdfGenerator.printSalesReport(
      invoices: invoices,
      totalSales: totalSales,
      totalProfit: totalProfit,
      invoiceCount: invoiceCount,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
      printedBy: printedBy,
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
  }) {
    return ReportPdfGenerator.printPurchasesReport(
      invoices: invoices,
      totalPurchases: totalPurchases,
      invoiceCount: invoiceCount,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
      printedBy: printedBy,
    );
  }

  /// Print category/sales-type report
  static Future<void> printCategoryReport({
    required List<Map<String, dynamic>> categories,
    required double totalSales,
    required bool isCategory,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) {
    return ReportPdfGenerator.printCategoryReport(
      categories: categories,
      totalSales: totalSales,
      isCategory: isCategory,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
    );
  }

  /// Print financial statements (Trial Balance, Income Statement, Balance Sheet)
  static Future<void> printFinancialStatement({
    required String title,
    required List<dynamic> data,
    required String statementType,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
  }) {
    return ReportPdfGenerator.printFinancialStatement(
      title: title,
      data: data,
      statementType: statementType,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
    );
  }

  /// Print treasury closing/audit report
  static Future<void> printTreasuryClosingReport({
    required List<Map<String, dynamic>> safeData,
    required double totalSystem,
    required double totalActual,
    required double totalVariance,
    String? companyName,
    String? employeeName,
  }) {
    return ReportPdfGenerator.printTreasuryClosingReport(
      safeData: safeData,
      totalSystem: totalSystem,
      totalActual: totalActual,
      totalVariance: totalVariance,
      companyName: companyName,
      employeeName: employeeName,
    );
  }

  /// Print barcode labels for products
  static Future<void> printBarcodeLabel({
    required String barcodeValue,
    required String productName,
    double? price,
    int copies = 1,
  }) {
    return ReportPdfGenerator.printBarcodeLabel(
      barcodeValue: barcodeValue,
      productName: productName,
      price: price,
      copies: copies,
    );
  }

  /// Print shift closing report (thermal)
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
  }) {
    return ThermalReceiptGenerator.printShiftClosingReport(
      invoiceCount: invoiceCount,
      totalSales: totalSales,
      systemCash: systemCash,
      systemCard: systemCard,
      actualCash: actualCash,
      actualCard: actualCard,
      cashVariance: cashVariance,
      cardVariance: cardVariance,
      totalVariance: totalVariance,
      totalExpenses: totalExpenses,
      cashRefunds: cashRefunds,
      cashIncome: cashIncome,
      creditSales: creditSales,
      creditSalesCount: creditSalesCount,
      openingBalance: openingBalance,
      fontScale: fontScale,
      employeeName: employeeName,
      companyName: companyName,
      printersRepo: printersRepo,
    );
  }
}
