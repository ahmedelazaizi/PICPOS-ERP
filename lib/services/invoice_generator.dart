import 'package:flutter/foundation.dart';
import '../data/database/database.dart' hide Printer;
import '../domain/repositories/printers_repository.dart';
import '../domain/printing/party_statement_snapshot.dart';
import 'printing/thermal_receipt_generator.dart';
// ⚠️ صنفان بنفس الاسم `ThermalReceiptGenerator`: واحدٌ في `printing/` وآخرُ
// في `generators/`، و`printReturnReceipt` في الثاني وحدَه. والشاشتان تستوردان
// الثاني — فالاسمُ وحدَه لا يكفي هنا.
// ونظيرُها في النموذج: `InvoiceItem` مُعرَّفٌ مرّتَين كذلك — في
// `printing/printing_models.dart` وفي `generators/base_generator.dart`.
// وشاشتا المرتجع تمرّران الثاني.
import 'generators/thermal_receipt_generator.dart' as gen;
import 'generators/base_generator.dart' as gen_base;
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
            documentType: 'sales_invoice',
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

  /// طباعةُ إيصال مرتجع مبيعات — بقالب المستخدم إن وُجد.
  ///
  /// كانت الشاشتان تناديان `ThermalReceiptGenerator.printReturnReceipt`
  /// مباشرةً — مولّدٌ مكتوبٌ في الكود **لا يسأل عن قالبٍ أصلاً**. فقالبُ
  /// `sales_return` مبذورٌ منذ البداية وقابلٌ للتصميم، ولا مسارَ طباعةٍ
  /// يستدعيه: يصمّمه المالكُ ويخرج المطبوعُ كما كتبه الكود.
  ///
  /// والتوجيهُ هنا لا في الشاشتَين: توأمان ينسخان النداءَ نفسَه، ومنطقٌ
  /// مكرَّرٌ في موضعَين يفترق (‏حصل في عنوان قناةٍ يومَ 2026-08-12).
  static Future<void> printSalesReturnReceipt({
    required String returnVoucherNumber,
    required String originalInvoiceNumber,
    required DateTime date,
    required List<gen_base.InvoiceItem> items,
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
    AppDatabase? db,
  }) async {
    if (db != null) {
      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db, 'thermal', category: 'sales_return',
      );
      if (hasTemplate) {
        try {
          await TemplatedInvoiceService.printWithTemplate(
            db: db,
            // رقمُ المستند هو سندُ المرتجع SRET-N، والفاتورةُ الأصليةُ تُحمل
            // في `orderNumber` — وتسميتُها في القالب `labelAr` («رقم الفاتورة
            // الأصلية») فلا تُقرأ «رقم الطلب».
            invoiceNumber: returnVoucherNumber,
            orderNumber: originalInvoiceNumber,
            date: date,
            customerName: customerName,
            customerPhone: null,
            customerAddress: null,
            items: items
                .map((i) => <String, dynamic>{
                      'name': i.name,
                      'quantity': i.quantity,
                      'price': i.price,
                      'total': i.total,
                      'note': i.note ?? '',
                    })
                .toList(),
            subtotal: returnTotal,
            discount: 0,
            tax: 0,
            deliveryFee: 0,
            total: returnTotal,
            paid: returnTotal, // مرتجعٌ مسدَّدٌ بالكامل
            companyName: companyName ?? '',
            companyAddress: companyAddress ?? '',
            companyPhone: companyPhone ?? '',
            companyTaxId: null,
            paymentMethod: paymentMethod,
            cashierName: employeeName,
            notes: returnReason,
            cashAmount: cashRefund,
            bankAmount: bankRefund,
            type: 'thermal',
            category: 'sales_return',
            documentType: 'sales_return',
            directPrint: true,
          );
          return;
        } catch (e) {
          debugPrint(
              '[InvoiceGenerator] Sales return template failed, falling back: $e');
        }
      }
    }

    // Fallback to hardcoded thermal generator
    return gen.ThermalReceiptGenerator.printReturnReceipt(
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
    );
  }

  /// Print A4 purchase invoice — uses user template if available.
  ///
  /// [isReturn]=true ⇒ قالبُ `purchase_return` بعنوانه، لا تخطّي القوالب.
  ///
  /// كان المرتجعُ يتخطّى القوالبَ كلَّها بحجّة أن «قوالبَ المستخدم تكتب عنوان
  /// *فاتورة مشتريات* ثابتاً». والحجّةُ صحيحةٌ والعلاجُ خطأ: للمرتجع قالبُه
  /// المبذورُ منذ البداية (`purchase_return`) بعنوانه الخاصّ في عنصرِ نصٍّ
  /// داخله. فالتخطّي كان يحرم المالكَ من تصميم مرتجعاته بلا سبب.
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
    // Try template-based rendering first — لكلٍّ قالبُه
    final category = isReturn ? 'purchase_return' : 'purchase';
    if (db != null) {
      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db, 'a4', category: category,
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
            category: category,
            documentType:
                isReturn ? 'purchase_return' : 'purchase_invoice',
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
            // رايةُ **عرضٍ** لا بيانات — وكانت تسقط هنا صامتةً فيُطبع اسمُ
            // التصنيف صنفاً بكمّية صفر. البلاغ: «*عرايس* بدل الصنف».
            'isCategoryHeader': i.isCategoryHeader,
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
            documentType: 'kitchen_order',
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
  /// ── امتدادُ الكشف (‏`EXTENSION-SPEC.md` §٣) ───────────────────────────
  ///
  /// كشفُ الحساب كان يُطبع من مولّدٍ ثابتٍ لا يقرأ جدولَ القوالب إطلاقاً —
  /// فتغييرُ عمودٍ فيه يعني تعديلَ Dart وإعادةَ بناءِ التطبيق. وقالبا الكشف
  /// (‏`a4_customer_statement.json` و`a4_supplier_statement.json`) مكتوبان
  /// ومبذوران منذ حينها ولا يصلان ورقة.
  ///
  /// و[db] هي البوّابة: بدونها — أو حين لا قالبَ محسوماً — يبقى المولّدُ
  /// الثابتُ كما هو بحرفه، فلا يتغيّر مطبوعُ أحد.
  static Future<void> printPartyStatement({
    required String partyName,
    required String partyType,
    required double currentBalance,
    required List<StatementItem> transactions,
    DateTime? fromDate,
    DateTime? toDate,
    String? companyName,
    DocumentCompanyHeader? company,
    AppDatabase? db,
    String? partyCode,
    double openingBalance = 0,
  }) async {
    final isSupplier = partyType == 'supplier' || partyType == 'مورد';

    if (db != null) {
      try {
        final from = fromDate ??
            (transactions.isEmpty ? DateTime.now() : transactions.first.date);
        final to = toDate ??
            (transactions.isEmpty ? DateTime.now() : transactions.last.date);

        final snapshot = PartyStatementSnapshot(
          partyName: partyName,
          partyCode: partyCode ?? '',
          isSupplier: isSupplier,
          periodFrom: from,
          periodTo: to,
          openingBalance: openingBalance,
          closingBalance: currentBalance,
          totalDebit: transactions.fold(0.0, (a, t) => a + t.debit),
          totalCredit: transactions.fold(0.0, (a, t) => a + t.credit),
          lines: [
            for (final t in transactions)
              PartyStatementLine(
                date: t.date,
                documentNumber: t.documentNumber ?? '',
                description: t.description,
                debit: t.debit,
                credit: t.credit,
                runningBalance: t.balance,
              ),
          ],
        );

        await TemplatedInvoiceService.printWithTemplate(
          db: db,
          invoiceNumber: '',
          date: to,
          customerName: partyName,
          customerPhone: null,
          customerAddress: null,
          items: snapshot.rowMaps,
          subtotal: snapshot.totalDebit,
          discount: 0,
          tax: 0,
          deliveryFee: 0,
          total: currentBalance,
          paid: snapshot.totalCredit,
          companyName: company?.name ?? companyName ?? '',
          companyAddress: company?.address ?? '',
          companyPhone: company?.phone ?? '',
          companyTaxId: company?.taxId,
          type: 'statement',
          category: 'party_statement',
          documentType: 'party_statement',
          statement: snapshot,
        );
        return;
      } catch (e) {
        // كشفٌ لا يُطبع أسوأُ من كشفٍ بالشكل القديم.
        debugPrint('[InvoiceGenerator] statement template failed, '
            'falling back: $e');
      }
    }

    return ReportPdfGenerator.printPartyStatement(
      partyName: partyName,
      partyType: partyType,
      currentBalance: currentBalance,
      transactions: transactions,
      fromDate: fromDate,
      toDate: toDate,
      companyName: companyName,
      company: company,
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

    /// `{معرّفُ الفاتورة: ما رُدَّ عنها}` — [totalSales] صافٍ من المرتجعات.
    Map<int, double> returnedAmounts = const {},
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
      returnedAmounts: returnedAmounts,
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
      systemClick: systemClick,
      actualClick: actualClick,
      clickVariance: clickVariance,
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
