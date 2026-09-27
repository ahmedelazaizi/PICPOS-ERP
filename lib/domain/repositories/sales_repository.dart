import '../entities/invoice_entity.dart';
import '../entities/cart_item_entity.dart';
import '../../data/database/database.dart'; // Drift classes for repository contract
import '../../services/generators/base_generator.dart' show InvoiceItem;

/// Payload returned by [SalesRepository.getDiagnosticSample].
/// Only used in debug builds — keeps Drift types out of the presentation layer.
class DiagnosticSample {
  final int totalCount;
  final List<InvoiceEntity> undeletedSample;
  final String sampleText;

  const DiagnosticSample({
    required this.totalCount,
    required this.undeletedSample,
    required this.sampleText,
  });
}

/// Sales repository interface
///
/// Defines contract for sales operations. Implementations in data layer.
abstract class SalesRepository {
  /// Create a new sales invoice with full parameters (Orchestrated)
  Future<int> createSalesInvoice({
    required int? customerId,
    required int warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    required List<CartItemEntity> items,
    double? cashAmount,
    double? bankAmount,
    double? clickAmount,
    int? cashSafeId,
    int? bankSafeId,
    int? clickSafeId,
    double deliveryFee,
    int? deliveryCompanyId,
    int? courierId,
    String? deliveryStatus,
    String? notes,
    String? platformOrderNumber, // #Phase4: External platform order ID
    String? adhocCustomerName,
    String? adhocCustomerPhone,
  });

  /// Complete a sales transaction (High-level orchestration)
  ///
  /// Handles validation, persistence, stock, accounting, and client sync.
  Future<SaleResult> completeSalesTransaction(SaleRequest request);

  /// Get invoice by ID
  Future<InvoiceEntity?> getInvoiceById(int id);

  /// Get invoice by number
  Future<InvoiceEntity?> getInvoiceByNumber(String invoiceNumber);

  /// Watch all sales invoices
  Stream<List<InvoiceEntity>> watchInvoices();

  /// Get invoices (one-shot) with pagination — always returns fresh data.
  Future<List<InvoiceEntity>> getInvoicesPaged({int limit = 500, int offset = 0});

  /// Raw local-DB fallback: returns up to [limit] non-deleted invoices directly
  /// from the local store without any server/client routing. Used only as a
  /// last-resort diagnostic fallback when [getInvoicesPaged] fails. Keeps Drift
  /// types out of the presentation layer (Day 6B refactor).
  Future<List<InvoiceEntity>> getRawInvoices({int limit = 500});

  /// Debug-only: samples the raw sales_invoices table to diagnose empty-list
  /// issues. Returns total row count, undeleted rows as entities, and a
  /// formatted summary string. Callers must gate behind [kDebugMode].
  Future<DiagnosticSample> getDiagnosticSample({int limit = 20});

  /// Watch invoices with pagination support (server-side filtering).
  Stream<List<InvoiceEntity>> watchPaginatedInvoices({
    int limit = 50,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  });

  /// Watch invoices by date range
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(
    DateTime start,
    DateTime end,
  );

  /// Record payment for invoice. [amount] is the ABSOLUTE new paid total (the
  /// delta collected is `amount - invoice.paid`). [userId] attributes the
  /// collection's receipt voucher (Spec 151 C-05).
  Future<void> recordPayment(int invoiceId, double amount, {int? userId});

  /// Cancel invoice (Legacy - redirects to void)
  Future<void> cancelInvoice(int invoiceId, {int? userId});

  /// Void invoice (ISS-05)
  Future<void> voidInvoice(int invoiceId, {String? reason, int? userId});

  /// Get all data needed for printing an invoice
  Future<SalesPrintData?> getSalesPrintData(int invoiceId);

  // ═══════════════════════════════════════════════════════════════════════════
  // INVOICE NUMBERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch today's sales (real-time stream)
  Stream<List<SalesInvoiceData>> watchTodaySales();

  /// Watch today's sales for a specific user (shift-scoped, real-time stream)
  Stream<List<SalesInvoiceData>> watchTodaySalesForUser(int userId);

  /// Watch sales since [from] (open upper bound). Used for shift-window
  /// scoping so a shift crossing midnight keeps its pre-midnight sales.
  Stream<List<SalesInvoiceData>> watchSalesSince(DateTime from, {int? userId});

  /// Watch the single most recent NON-RETURN sale belonging to [userId],
  /// optionally bounded below by [since] (the open shift's start).
  ///
  /// Scoped to one user on purpose: the POS "last invoice" affordance must show
  /// the cashier THEIR OWN last sale, not one another till or another user
  /// synced in. Emits `null` when they have not sold anything in the window.
  Stream<SalesInvoiceData?> watchLastInvoiceForUser(
    int userId, {
    DateTime? since,
  });

  /// Get sales invoice items
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId);

  /// Get raw sales invoice by ID (drift type, for UI that consumes SalesInvoiceData directly)
  Future<SalesInvoiceData?> getRawInvoiceById(int id);

  /// Generate next sequential invoice number with given prefix
  Future<String> generateInvoiceNumber(String prefix);

  /// Get invoices since date
  Future<List<SalesInvoiceData>> getInvoicesSince(DateTime since);

  /// Update invoice status (PIR Architecture)
  Future<void> updateInvoiceStatus(int invoiceId, String status);

  /// Search invoices by number
  Future<List<SalesInvoiceData>> searchInvoicesByNumber(String query);

  /// Update sale type (e.g. mark as 'table' sale for shift-closing breakdown)
  Future<void> updateSaleType(int invoiceId, String saleType);

  /// Update sales invoice payment details
  Future<void> updateSalesInvoicePayment(
    int invoiceId,
    String paymentMethod,
    String? notes, {
    double? newCashAmount,
    double? newBankAmount,
  });

  /// Get sales invoice items with full product details
  Future<List<SalesInvoiceItemWithProduct>> getInvoiceItemsWithProduct(
    int invoiceId,
  );

  /// Full sales invoice update — reverses old accounting, updates items/totals, re-posts
  Future<void> updateFullSalesInvoice({
    required int invoiceId,
    required int? userId,
    int? customerId,
    int warehouseId,
    required double paid,
    required String paymentMethod,
    String? notes,
    required List<CartItemEntity> items,
    int? costCenterId,
  });

  /// Watch all raw sales invoices (Drift type)
  Stream<List<SalesInvoiceData>> watchAllRawInvoices();

}

/// Sales summary data
class SalesSummary {
  final int invoiceCount;
  final double totalSales;
  final double totalCash;
  final double totalCredit;
  final double totalProfit;

  const SalesSummary({
    required this.invoiceCount,
    required this.totalSales,
    required this.totalCash,
    required this.totalCredit,
    required this.totalProfit,
  });
}

/// Held order data for suspended orders
class HeldOrderData {
  final int id;
  final String holdNumber;
  final double subtotal;
  final double discount;
  final bool discountIsPercent;
  final int? customerId;
  final String? customerName;
  final DateTime createdAt;
  final List<CartItemEntity> items;

  const HeldOrderData({
    required this.id,
    required this.holdNumber,
    required this.subtotal,
    required this.discount,
    required this.discountIsPercent,
    this.customerId,
    this.customerName,
    required this.createdAt,
    this.items = const [],
  });
}

/// Data structure for invoice receipt printing
class SalesPrintData {
  final String invoiceNumber;
  final DateTime date;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double deliveryFee;
  final double total;
  final double paid;
  final String paymentMethod;
  final String? cashierName;
  final int? orderNumber;
  final String? courierName;
  final String? courierPhone;
  final bool isDelivery;
  final String salesTypeText;
  final String? saleType; // raw sale type: 'default', 'delivery', 'table', etc.
  final ReceiptSettingData receiptSettings;
  final String? codeType; // 'qr_code', 'barcode'
  final String? notes; // invoice notes (adhoc customer info etc.)
  final String? adhocCustomerName; // ad-hoc (text) customer name from POS
  final String? adhocCustomerPhone; // ad-hoc (text) customer phone from POS
  final String? platformOrderNumber; // #Phase4: External platform order ID

  SalesPrintData({
    required this.invoiceNumber,
    required this.date,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.deliveryFee,
    required this.total,
    required this.paid,
    required this.paymentMethod,
    this.cashierName,
    this.orderNumber,
    this.courierName,
    this.courierPhone,
    required this.isDelivery,
    required this.salesTypeText,
    this.saleType,
    required this.receiptSettings,
    this.codeType,
    this.notes,
    this.adhocCustomerName,
    this.adhocCustomerPhone,
    this.platformOrderNumber,
  });
}

/// Sale request data (moved from UseCase to Repository for centralization)
class SaleRequest {
  /// Spec 151 E-06 — NAMED fallback VAT rate (percent) applied ONLY when a
  /// caller does not thread the configured system `tax_rate` setting. Callers
  /// SHOULD pass the resolved system rate (POS does, via cart; the sales-invoice
  /// form does after E-06). This named constant replaces the bare `14` literal
  /// so the Egyptian default can't silently apply in another jurisdiction as an
  /// un-audited magic number scattered across the code.
  static const double kDefaultTaxPercent = 14;

  final List<CartItemEntity> items;
  final int? customerId;
  final int warehouseId;
  final int userId;
  final String paymentMethod;
  final double paidAmount;
  final double? cashAmount;
  final double? bankAmount;
  final double? clickAmount;
  final int? cashSafeId; // Target cash safe
  final int? bankSafeId; // Target bank safe
  final int? clickSafeId; // Target click safe

  final double discountPercent;
  final double taxPercent;
  final bool taxEnabled;
  /// Whether entered unit prices are gross prices including VAT.
  final bool pricesIncludeTax;
  final double deliveryFee;
  final int? deliveryCompanyId;
  final int? courierId;
  final String? deliveryStatus;
  final String? notes;
  final String? invoiceNumber;
  final int? quotationId;
  final bool isReturn;
  final String saleType; // default, talabat, careem, ashyae, delivery
  final String? adhocCustomerName; // ad-hoc customer name (not from DB)
  final String? adhocCustomerPhone; // ad-hoc customer phone
  final String? adhocCustomerNote; // ad-hoc customer note
  final int? costCenterId; // auto-resolved from branch
  final int? branchId; // auto-resolved from active branch
  final String? platformOrderNumber; // #Phase4: External platform order ID

  const SaleRequest({
    required this.items,
    this.customerId,
    this.warehouseId = 1,
    this.userId = 1,
    required this.paymentMethod,
    required this.paidAmount,
    this.cashAmount,
    this.bankAmount,
    this.clickAmount,
    this.cashSafeId,
    this.bankSafeId,
    this.clickSafeId,
    this.discountPercent = 0,
    this.taxPercent = kDefaultTaxPercent, // Spec 151 E-06 — named fallback, not a bare 14
    this.taxEnabled = true,
    this.pricesIncludeTax = false,
    this.deliveryFee = 0,
    this.deliveryCompanyId,
    this.courierId,
    this.deliveryStatus,
    this.notes,
    this.invoiceNumber,
    this.quotationId,
    this.isReturn = false,
    this.saleType = 'default',
    this.adhocCustomerName,
    this.adhocCustomerPhone,
    this.adhocCustomerNote,
    this.costCenterId,
    this.branchId,
    this.platformOrderNumber,
  });
}

/// Sale result
sealed class SaleResult {
  const SaleResult();

  factory SaleResult.success({
    required int invoiceId,
    required String invoiceNumber,
    required dynamic totals, // dynamic to avoid tight coupling with UseCase totals
  }) = SaleSuccess;

  factory SaleResult.failure(String error) = SaleFailure;

  bool get isSuccess => this is SaleSuccess;
  bool get isFailure => this is SaleFailure;

  int? get invoiceId =>
      this is SaleSuccess ? (this as SaleSuccess).invoiceId : null;
  String? get errorMessage =>
      this is SaleFailure ? (this as SaleFailure).error : null;
}

class SaleSuccess extends SaleResult {
  @override
  final int invoiceId;
  final String invoiceNumber;
  final dynamic totals;

  const SaleSuccess({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.totals,
  });
}

class SaleFailure extends SaleResult {
  final String error;
  const SaleFailure(this.error);
}
