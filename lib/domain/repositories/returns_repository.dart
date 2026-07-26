import '../../services/generators/base_generator.dart' show InvoiceItem;
import '../../data/database/database.dart';
import '../../domain/entities/product_entity.dart';

/// Data structure for return receipt printing
class ReturnPrintData {
  final ReceiptSettingData receiptSettings;
  final List<InvoiceItem> items;
  final String paymentMethod;
  final double cashRefund;
  final double bankRefund;
  final String? customerName;

  /// The actual SRET-N voucher number produced by this return — looked up
  /// from the ledger rows written during `processSalesReturn`. When a
  /// print is triggered from history this still resolves correctly to the
  /// latest voucher for the invoice. Falls back to `'SRET-<invoice>'` if
  /// no voucher row exists yet (shouldn't happen in normal flows).
  final String? returnVoucherNumber;

  ReturnPrintData({
    required this.receiptSettings,
    required this.items,
    required this.paymentMethod,
    required this.cashRefund,
    required this.bankRefund,
    this.customerName,
    this.returnVoucherNumber,
  });
}

/// Interface for Sales and Purchase Returns repository
abstract class IReturnsRepository {
  /// Load sales invoices for return with filters
  Future<List<SalesInvoiceData>> getInvoicesForReturn({
    required DateTime fromDate,
    required DateTime toDate,
  });

  /// Load purchase invoices for return with filters.
  ///
  /// البند 7 — [supplierId] / [productId] / [invoiceNumberLike] are applied in
  /// SQL, not over an already-truncated page (see PurchaseDao docs).
  Future<List<PurchaseInvoiceData>> getInvoicesForPurchaseReturn({
    required DateTime fromDate,
    required DateTime toDate,
    int? supplierId,
    int? productId,
    String? invoiceNumberLike,
  });

  /// Get items for a specific sales invoice
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId);

  /// Get items for a specific purchase invoice
  Future<List<PurchaseInvoiceItem>> getPurchaseInvoiceItems(int invoiceId);

  /// Get already returned quantity for an invoice item
  Future<double> getReturnedQuantityForInvoiceItem({
    required int invoiceId,
    required int productId,
  });

  /// Batch version — returns `{productId: totalReturnedQty}` for ALL items of
  /// the invoice in a single query. Use this when loading the sales-returns
  /// invoice picker to avoid the N+1 freeze.
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(int invoiceId);

  Future<bool> processSalesReturn({
    required SalesInvoiceData invoice,
    required Map<int, double> returnQuantities,
    required Map<int, ProductEntity> productCache,
    String? reason,
    required int userId,
    required String userName,
    bool isFullReturn = false,
    bool isDamaged = false,
  });

  /// Cancel an existing sales return
  Future<void> cancelSalesReturn({
    required SalesInvoiceData invoice,
    required int userId,
    required String userName,
  });

  /// Get sales return history (invoices with return status)
  ///
  /// [allowedBranchIds] — authoritative branch-scope cap (Spec 151 Track-3):
  /// null = full access, {} = fail-closed (no rows), {ids} = those branches
  /// OR NULL-branch (shared/head-office) rows.
  Future<List<SalesInvoiceData>> getSalesReturnHistory({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  });

  /// Sales return history for the «سجل المرتجعات» dialog — normalised over
  /// BOTH persisted return shapes (separate `sale_type='return'` document, or
  /// a flipped original + `safe_transactions`), so a return processed on a
  /// standalone/server install shows up the same way a purchase return does.
  ///
  /// [getSalesReturnHistory] above only sees the return-document shape and is
  /// therefore empty on standalone installs; prefer this method for any
  /// user-facing "list the returns" view.
  Future<List<SalesReturnHistoryEntry>> getSalesReturnHistoryEntries({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  });

  /// Get purchase return history
  ///
  /// [allowedBranchIds] — authoritative branch-scope cap (Spec 151 Track-3):
  /// null = full access, {} = fail-closed (no rows), {ids} = those branches
  /// OR NULL-branch (shared/head-office) rows.
  Future<List<PurchaseInvoiceData>> getPurchaseReturnHistory({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  });

  /// Get print data for a sales return
  Future<ReturnPrintData?> getSalesReturnPrintData({
    required String invoiceNumber,
    required double returnTotal,
    SalesInvoiceData? selectedInvoice,
    List<SalesInvoiceItem>? invoiceItems,
    Map<int, ProductEntity>? productCache,
    Map<int, double>? returnQuantities,
  });
}
